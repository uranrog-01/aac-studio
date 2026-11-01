import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/domain.dart';

/// Shared initialization and serialized requests keep first and rapid taps reliable.
class SpeechEngine {
  final FlutterTts _tts = FlutterTts();
  final ValueNotifier<String?> error = ValueNotifier(null);
  Future<void>? _initializing;
  Future<void> _pending = Future.value();
  int _generation = 0;
  double rate = 0.45;
  double pitch = 1.0;
  double volume = 1.0;

  Future<void> ensure() => _initializing ??= _initialize();

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
    final generation = _generation;
    _pending = _pending.then((_) async {
      if (generation != _generation) return;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await ensure();
          if (generation != _generation) return;
          await _tts.setSpeechRate((style?.rate ?? rate).clamp(0.0, 1.0));
          await _tts.setPitch((style?.pitch ?? pitch).clamp(0.5, 2.0));
          await _tts.setVolume((style?.volume ?? volume).clamp(0.0, 1.0));
          if (generation != _generation) return;
          final result = await _tts.speak(text.trim());
          if (result == false || (result is num && result != 1)) {
            throw StateError('Speech engine rejected request');
          }
          error.value = null;
          return;
        } catch (_) {
          _initializing = null;
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
      await _tts.stop();
    } catch (_) {}
  }
}
