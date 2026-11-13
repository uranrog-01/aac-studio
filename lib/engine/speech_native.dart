import 'voice_clips.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_tts/flutter_tts.dart';
import '../models/domain.dart';
import 'piper_voice.dart';
import 'piper_worker.dart' show piperPacks;
import 'i18n.dart';
import 'storage.dart' show AppSettings;

/// One installed platform voice (flutter_tts getVoices entry).
class DeviceVoice {
  final String name;
  final String locale;
  final String quality;
  final bool network;

  /// 'female' / 'male' when the device says so (iPhone, iPad), else ''.
  final String gender;
  const DeviceVoice(this.name, this.locale,
      {this.quality = '', this.network = false, this.gender = ''});

  VoiceInfo get info =>
      (name: name, locale: locale, quality: quality, network: network);

  bool get isEnglish => locale.toLowerCase().startsWith('en');

  /// Android lists cloud voices that only speak with internet access.
  bool get needsInternet => network || name.toLowerCase().contains('network');
}

/// Shared initialization and serialized requests keep first and rapid taps reliable.
class SpeechEngine {
  SpeechEngine(
      {OfflineSpeechVoice? offlineVoice,
      Map<String, OfflineSpeechVoice>? packVoices})
      : _offlineVoice = offlineVoice ?? PiperVoice() {
    if (packVoices != null) _packVoices.addAll(packVoices);
  }

  final FlutterTts _tts = FlutterTts();

  /// Plays recorded words (VoiceClips) for a language the device cannot
  /// speak itself, e.g. Albanian.
  AudioPlayer? _clipPlayer;
  Completer<void>? _clipCompletion;

  Future<void> _speakClips(List<String> clips, double rate, double volume,
      bool Function() isCurrent) async {
    final player = _clipPlayer ??= AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setVolume(volume);
    await player.setPlaybackRate((rate / .45).clamp(.5, 2.0));
    for (final clip in clips) {
      if (!isCurrent()) return;
      final done = _clipCompletion = Completer<void>();
      final completion = player.onPlayerComplete.listen((_) {
        if (!done.isCompleted) done.complete();
      });
      try {
        await player.play(AssetSource(clip));
        if (!isCurrent() && done.isCompleted) await player.stop();
        await done.future.timeout(const Duration(seconds: 12));
      } finally {
        if (identical(_clipCompletion, done)) _clipCompletion = null;
        await completion.cancel();
      }
    }
  }

  final OfflineSpeechVoice _offlineVoice;
  final Map<String, OfflineSpeechVoice> _packVoices = {};

  /// The offline voice for the current language: the built-in English one,
  /// or a downloaded pack (e.g. Albanian, which phones do not have).
  OfflineSpeechVoice get _offline => language.code == 'en'
      ? _offlineVoice
      : _packVoices.putIfAbsent(
          language.code, () => PiperVoice(piperPacks[language.code]!));

  /// Whether this app has an offline voice for [code].
  static bool hasOfflineVoice(String code) => piperPacks.containsKey(code);

  /// Downloads the offline voice for [code] once; afterwards it works
  /// without internet. [onProgress] gets 0..1.
  Future<void> downloadOfflineVoice(String code,
      {void Function(double)? onProgress}) async {
    final pack = piperPacks[code];
    if (pack == null) return;
    await PiperVoice.download(pack, onProgress: onProgress);
    if (language.code == code) {
      _offlineReady = false;
      _warming = null;
      await warmOfflineVoice();
    }
  }

  /// Whether the offline voice for [code] is bundled or already downloaded.
  static Future<bool> offlineVoiceReady(String code) async {
    final pack = piperPacks[code];
    return pack != null && await PiperVoice.isReady(pack);
  }

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
      final code = language.code;
      await _offline.prepare();
      if (code != language.code) return; // language changed meanwhile
      _offlineReady = true;
      if (_usePiper) {
        status.value =
            '${I18n.t('Offline voice')}: ${piperPacks[code]?.name ?? code}';
      }
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
  Future<void> _stopping = Future.value();
  int _generation = 0;
  double rate = 0.45;
  double pitch = 1.0;
  double volume = 1.0;

  /// Chosen device voice (null = platform default). Applied before the next
  /// device utterance.
  DeviceVoice? voice;

  /// iOS: speak through the call-capable voice (see ios/Runner/CallSpeech.swift).
  bool callSpeech = false;
  static const _callChannel = MethodChannel('aac/call_speech');

  Future<bool> _speakIntoCalls(String text, double rate, double pitch,
      double volume, bool interrupt) async {
    try {
      final result = await _callChannel.invokeMethod('speak', {
        'text': text,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'voiceName': _resolved?.name ?? '',
        'locale': _resolved?.locale ?? language.voiceLocales.first,
        'interrupt': interrupt,
      });
      return result == 1;
    } catch (_) {
      return false; // fall back to the normal voice
    }
  }

  /// Language the device voice speaks when no voice is chosen.
  AppLanguage language = kLanguages.first;

  Future<void> ensure() => _initializing ??= _initialize();

  /// Copies the saved speech settings onto the engine.
  void configure(AppSettings s) {
    final wanted = s.voiceGender == 'female'
        ? VoiceGender.female
        : s.voiceGender == 'male'
            ? VoiceGender.male
            : VoiceGender.unknown;
    final previous = language;
    final next = languageFor(s.language);
    if (wanted != gender ||
        previous.code != next.code ||
        voice?.name != s.voiceName ||
        voice?.locale != s.voiceLocale) {
      unawaited(stop());
      gender = wanted;
      _appliedKey = null;
      error.value = null;
    }
    // iPhone/iPad only: speech also goes into phone and FaceTime calls.
    callSpeech =
        s.callSpeech && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    // Offline voices exist for English (built in) and Albanian
    // (downloaded). Albanian always prefers its own voice: phones have none.
    if (previous.code != next.code) {
      _offlineReady = false;
      _warming = null;
    }
    language = next;
    final wantsOffline = hasOfflineVoice(language.code) &&
        (language.code == 'en' ? s.usePiper : !_femaleAlbanian);
    if (wantsOffline && previous.code != language.code && _usePiper) {
      unawaited(warmOfflineVoice());
    }
    usePiper = wantsOffline;
    rate = s.rate;
    pitch = s.pitch;
    volume = s.volume;
    voice = s.voiceName == null
        ? null
        : DeviceVoice(s.voiceName!, s.voiceLocale ?? '');
    if (_femaleAlbanian) status.value = 'Shqip · Arta';
  }

  /// Installed device voices, English first, sorted by language then name.
  Future<List<DeviceVoice>> deviceVoices() async {
    try {
      await ensure();
      final raw = await _tts.getVoices;
      final voices = <DeviceVoice>[
        for (final v in (raw as List? ?? const []))
          if (v is Map && v['name'] != null)
            DeviceVoice('${v['name']}', '${v['locale'] ?? ''}',
                quality: '${v['quality'] ?? ''}',
                network: '${v['network_required'] ?? '0'}' == '1',
                gender: '${v['gender'] ?? ''}'),
      ];
      voices.sort((a, b) {
        // The chosen language's voices first, then English, then the rest.
        final aMine = voiceSpeaks(language, a.locale);
        final bMine = voiceSpeaks(language, b.locale);
        if (aMine != bMine) return aMine ? -1 : 1;
        if (a.isEnglish != b.isEnglish) return a.isEnglish ? -1 : 1;
        final byLocale = a.locale.compareTo(b.locale);
        return byLocale != 0 ? byLocale : a.name.compareTo(b.name);
      });
      return voices;
    } catch (_) {
      return const [];
    }
  }

  /// The voice actually speaking (chosen in Settings, or the best one for
  /// the language); null = the device default for the language.
  /// The kind of voice wanted (Settings > Voice).
  VoiceGender gender = VoiceGender.unknown;

  DeviceVoice? _resolved;
  String? _appliedKey;
  String? _bestFor;
  DeviceVoice? _best;

  bool get _femaleAlbanian =>
      language.code == 'sq' && gender == VoiceGender.female;

  Future<DeviceVoice?> _bestVoice() async {
    if (_bestFor == '${language.code}|${gender.name}') return _best;
    final voices = await deviceVoices();
    // Female or male, when asked for and the device has such a voice.
    var pool = voices;
    if (gender != VoiceGender.unknown) {
      final wanted = [
        for (final v in voices)
          if (voiceSpeaks(language, v.locale) &&
              voiceGender(v.name, hint: v.gender) == gender)
            v
      ];
      if (wanted.isNotEmpty || _femaleAlbanian) pool = wanted;
    }
    final pick = bestVoice(language, pool.map((v) => v.info));
    _best = pick == null
        ? null
        : voices
            .firstWhere((v) => v.name == pick.name && v.locale == pick.locale);
    _bestFor = '${language.code}|${gender.name}';
    return _best;
  }

  /// Uses the voice chosen in Settings if it speaks the current language;
  /// otherwise the most natural installed voice for the language (so French
  /// words are never read by an English voice). Falls back to the device's
  /// default for the language, e.g. Albanian on iPhone.
  Future<bool> _applyVoice() async {
    var wanted = voice;
    if (wanted != null && !voiceSpeaks(language, wanted.locale)) wanted = null;
    if (_femaleAlbanian &&
        wanted != null &&
        voiceGender(wanted.name, hint: wanted.gender) != VoiceGender.female) {
      wanted = null;
    }
    wanted ??= await _bestVoice();
    if (_femaleAlbanian && wanted == null) return false;
    final key = '${language.code}|${wanted?.name}|${wanted?.locale}';
    if (key == _appliedKey) return true;
    if (wanted == null) {
      try {
        await _tts.clearVoice();
      } catch (_) {/* Not every platform implements clearVoice. */}
      for (final locale in language.voiceLocales) {
        try {
          if (await _tts.isLanguageAvailable(locale) == true) {
            await _tts.setLanguage(locale);
            break;
          }
        } catch (_) {/* Windows: keep its default. */}
      }
    } else {
      try {
        final result =
            await _tts.setVoice({'name': wanted.name, 'locale': wanted.locale});
        if (_femaleAlbanian && (result == false || result == 0)) return false;
      } catch (_) {
        if (_femaleAlbanian) return false;
        // An uninstalled voice must not silence the app: keep the default.
      }
    }
    _resolved = wanted;
    _appliedKey = key;
    return true;
  }

  Future<void> _initialize() async {
    _tts.setErrorHandler((message) {
      error.value = 'Speech unavailable. Check your device voices and volume.';
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

  /// Picture taps queue, so two quick taps ("I", "want") are both heard.
  /// [interrupt] (typing) cuts off what is playing instead, so letters
  /// typed quickly do not pile up and fall behind.
  Future<void> speak(String text, {VoiceStyle? style, bool interrupt = false}) {
    text = speechText(text);
    if (text.isEmpty) return Future.value();
    // Piper synthesis takes time: a newer tap replaces queued/stale speech.
    if (interrupt) {
      unawaited(stop());
    } else if (_usePiper || VoiceClips.languages.contains(language.code)) {
      _generation++;
    }
    final generation = _generation;
    final requestedRate = (style?.rate ?? rate).clamp(0.0, 1.0);
    final requestedPitch = (style?.pitch ?? pitch).clamp(0.5, 2.0);
    final requestedVolume = (style?.volume ?? volume).clamp(0.0, 1.0);
    _pending = _pending.then((_) async {
      await _stopping;
      if (generation != _generation) return;
      if (callSpeech &&
          !VoiceClips.languages.contains(language.code) &&
          await _speakIntoCalls(text.trim(), requestedRate, requestedPitch,
              requestedVolume, interrupt)) {
        error.value = null;
        return;
      }
      // Board words in a language with recordings (Albanian) play the
      // recordings: made with the reference Piper program, they say each
      // word completely. The live voice covers typed text.
      final code = language.code;
      final female = gender == VoiceGender.female;
      await VoiceClips.load(code, female: female);
      if (generation != _generation) return;
      final clips = VoiceClips.clipsFor(text, code, female: female);
      if (clips != null) {
        try {
          await _stopOutputs(
              stopCalls: false, stopClips: false, offline: _packVoices[code]);
          if (generation != _generation) return;
          await _speakClips(clips, requestedRate, requestedVolume,
              () => generation == _generation);
          if (generation == _generation) error.value = null;
        } catch (_) {
          if (generation == _generation) {
            error.value =
                'Speech unavailable. Check your device voices and volume.';
          }
        }
        return;
      }
      if (_usePiper && _offlineReady && requestedPitch == 1.0) {
        try {
          // Native speech may still be playing from setup/fallback.
          try {
            await _tts.stop();
          } catch (_) {/* Piper works independently. */}
          await _offline.speak(text.trim(),
              rate: requestedRate,
              volume: requestedVolume,
              isCurrent: () => generation == _generation);
          if (generation == _generation) {
            status.value =
                '${I18n.t('Offline voice')}: ${piperPacks[code]?.name ?? code}';
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
        await _offline.stop();
      } catch (_) {/* Continue with device speech. */}
      if (_usePiper && _offlineReady && requestedPitch != 1.0) {
        status.value = 'Using device voice for pitch adjustment.';
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await ensure();
          if (generation != _generation) return;
          if (!await _applyVoice()) {
            if (generation == _generation) {
              error.value = femaleAlbanianUnavailable;
            }
            return;
          }
          await _tts.setSpeechRate(requestedRate);
          await _tts.setPitch(requestedPitch);
          await _tts.setVolume(requestedVolume);
          if (generation != _generation) return;
          if (interrupt) {
            try {
              await _tts.stop(); // cut off the previous letter
            } catch (_) {/* Nothing playing. */}
            if (generation != _generation) return;
          }
          final result = await _tts.speak(text.trim());
          if (result == false || (result is num && result != 1)) {
            throw StateError('Speech engine rejected request');
          }
          error.value = null;
          return;
        } catch (_) {
          _initializing = null;
          _appliedKey = null;
        }
      }
      error.value = 'Speech unavailable. Check your device voices and volume.';
    });
    return _pending;
  }

  Future<void> stop() {
    _generation++;
    final clip = _clipCompletion;
    if (clip != null && !clip.isCompleted) clip.complete();
    final stopCalls = callSpeech;
    final offline =
        language.code == 'en' ? _offlineVoice : _packVoices[language.code];
    return _stopping = _stopping
        .then((_) => _stopOutputs(stopCalls: stopCalls, offline: offline));
  }

  Future<void> _stopOutputs(
      {required bool stopCalls,
      bool stopClips = true,
      OfflineSpeechVoice? offline}) async {
    if (stopCalls) {
      try {
        await _callChannel.invokeMethod('stop');
      } catch (_) {}
    }
    try {
      await offline?.stop();
    } catch (_) {}
    try {
      if (stopClips) await _clipPlayer?.stop();
    } catch (_) {}
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _warming;
    await _pending;
    await _clipPlayer?.dispose();
    for (final voice in {_offlineVoice, ..._packVoices.values}) {
      await voice.dispose();
    }
    error.dispose();
    status.dispose();
  }
}
