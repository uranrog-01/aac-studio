import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/domain.dart';
import 'piper_voice.dart';
import 'storage.dart' show AppSettings;

/// One installed platform voice (flutter_tts getVoices entry).
class DeviceVoice {
  final String name;
  final String locale;
  const DeviceVoice(this.name, this.locale);

  bool get isEnglish => locale.toLowerCase().startsWith('en');

  /// Android lists cloud voices that only speak with internet access.
  bool get needsInternet => name.toLowerCase().contains('network');
}

/// Shared initialization and serialized requests keep first and rapid taps reliable.
class SpeechEngine {
  SpeechEngine({OfflineSpeechVoice? offlineVoice})
      : _offlineVoice = offlineVoice ?? PiperVoice();

  final FlutterTts _tts = FlutterTts();
  final OfflineSpeechVoice _offlineVoice;
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<String> status = ValueNotifier('Device voice');
  bool _usePiper = false;
  bool _offlineReady = false;
  Future<void>? _warming;

  bool get usePiper => _usePiper;
  set usePiper(bool value) {
    if (_usePiper == value) return;
    _usePiper = value;
    unawaited(stop());
    if (value) {
      unawaited(warmOfflineVoice());
    } else {
      status.value = 'Device voice';
    }
  }

  Future<void> warmOfflineVoice() {
    if (!_usePiper) return Future.value();
    return _warming ??= _warmOfflineVoice();
  }

  Future<void> _warmOfflineVoice() async {
    status.value = 'Preparing offline voice. Device voice is available.';
    try {
      await _offlineVoice.prepare();
      _offlineReady = true;
      if (_usePiper) status.value = 'Piper: US English, LJ Speech (offline)';
    } catch (_) {
      _offlineReady = false;
      if (_usePiper) {
        status.value = 'Offline voice unavailable. Using device voice.';
      }
    } finally {
      _warming = null;
    }
  }

  Future<void>? _initializing;
  Future<void> _pending = Future.value();
  int _generation = 0;
  double rate = 0.45;
  double pitch = 1.0;
  double volume = 1.0;

  /// Chosen device voice (null = platform default). Applied before the next
  /// device utterance.
  DeviceVoice? voice;
  DeviceVoice? _appliedVoice;

  Future<void> ensure() => _initializing ??= _initialize();

  /// Copies the saved speech settings onto the engine.
  void configure(AppSettings s) {
    usePiper = s.usePiper;
    rate = s.rate;
    pitch = s.pitch;
    volume = s.volume;
    voice = s.voiceName == null
        ? null
        : DeviceVoice(s.voiceName!, s.voiceLocale ?? '');
  }

  /// Installed device voices, English first, sorted by language then name.
  Future<List<DeviceVoice>> deviceVoices() async {
    try {
      await ensure();
      final raw = await _tts.getVoices;
      final voices = <DeviceVoice>[
        for (final v in (raw as List? ?? const []))
          if (v is Map && v['name'] != null)
            DeviceVoice('${v['name']}', '${v['locale'] ?? ''}'),
      ];
      voices.sort((a, b) {
        if (a.isEnglish != b.isEnglish) return a.isEnglish ? -1 : 1;
        final byLocale = a.locale.compareTo(b.locale);
        return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
      });
      return voices;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _applyVoice() async {
    final wanted = voice;
    if (wanted?.name == _appliedVoice?.name &&
        wanted?.locale == _appliedVoice?.locale) {
      return;
    }
    if (wanted == null) {
      try {
        await _tts.clearVoice();
      } catch (_) {/* Not every platform implements clearVoice. */}
    } else {
      try {
        await _tts.setVoice({'name': wanted.name, 'locale': wanted.locale});
      } catch (_) {
        // An uninstalled voice must not silence the app: keep the default.
      }
    }
    _appliedVoice = wanted;
  }

  Future<void> _initialize() async {
    _tts.setErrorHandler((message) {
      error.value =
          'Speech unavailable. Check media volume and installed English voices in device settings.';
      _initializing = null;
    });
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await _tts.setQueueMode(0);
      }
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await _tts.setSharedInstance(true);
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.playback,
          [IosTextToSpeechAudioCategoryOptions.duckOthers],
          IosTextToSpeechAudioMode.defaultMode,
        );
      }
      for (final language in ['en-US', 'en-GB', 'en']) {
        try {
          if (await _tts.isLanguageAvailable(language) == true) {
            await _tts.setLanguage(language);
            break;
          }
        } catch (_) {
          // Windows does not implement language availability; retain its default.
        }
      }
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  Future<void> applyDefaults() async {
    // Applied with each utterance, so updates cannot race a button voice style.
  }

  Future<void> speak(String text, {VoiceStyle? style}) {
    if (text.trim().isEmpty) return Future.value();
    // Piper synthesis takes time: a newer tap replaces queued/stale speech.
    if (_usePiper) _generation++;
    final generation = _generation;
    final requestedRate = (style?.rate ?? rate).clamp(0.0, 1.0);
    final requestedPitch = (style?.pitch ?? pitch).clamp(0.5, 2.0);
    final requestedVolume = (style?.volume ?? volume).clamp(0.0, 1.0);
    _pending = _pending.then((_) async {
      if (generation != _generation) return;
      if (_usePiper && _offlineReady && requestedPitch == 1.0) {
        try {
          // Native speech may still be playing from setup/fallback.
          try {
            await _tts.stop();
          } catch (_) {/* Piper works independently. */}
          await _offlineVoice.speak(text.trim(),
              rate: requestedRate,
              volume: requestedVolume,
              isCurrent: () => generation == _generation);
          if (generation == _generation) {
            status.value = 'Piper: US English, LJ Speech (offline)';
            error.value = null;
          }
          return;
        } catch (_) {
          _offlineReady = false;
          status.value = 'Offline voice unavailable. Using device voice.';
          // Continue with native speech for this same utterance.
        }
      }
      if (generation != _generation) return;
      try {
        await _offlineVoice.stop();
      } catch (_) {/* Continue with device speech. */}
      if (_usePiper && _offlineReady && requestedPitch != 1.0) {
        status.value = 'Using device voice for pitch adjustment.';
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await ensure();
          if (generation != _generation) return;
          await _applyVoice();
          await _tts.setSpeechRate(requestedRate);
          await _tts.setPitch(requestedPitch);
          await _tts.setVolume(requestedVolume);
          if (generation != _generation) return;
          final result = await _tts.speak(text.trim());
          if (result == false || (result is num && result != 1)) {
            throw StateError('Speech engine rejected request');
          }
          error.value = null;
          return;
        } catch (_) {
          _initializing = null;
          _appliedVoice = null;
        }
      }
      error.value =
          'Speech unavailable. Check media volume and installed English voices in device settings.';
    });
    return _pending;
  }

  Future<void> stop() async {
    _generation++;
    try {
      await _offlineVoice.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _warming;
    await _pending;
    await _offlineVoice.dispose();
    error.dispose();
    status.dispose();
  }
}
