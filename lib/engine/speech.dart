import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models/domain.dart';

/// M3 speech engine — platform TTS abstraction, hardened for Android/Fire:
/// - warm-up at app start (engine init is slow; first-tap silence otherwise)
/// - language availability fallback (some engines reject 'en-US')
/// - one retry on failure
class SpeechEngine {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  bool _speaking = false;
  double rate = 0.45;
  double pitch = 1.0;
  double volume = 1.0;

  Future<void> ensure() async {
    if (_ready) return;
    _ready = true; // guard re-entry; failures retried per-speak
    try {
      _tts.setStartHandler(() {});
      _tts.setCancelHandler(() {});
      _tts.setErrorHandler((m) {
        if (kDebugMode) debugPrint('TTS error: $m');
      });
      await _tts.setLanguage(await _bestLanguage());
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
      await _tts.setQueueMode(0);
    } catch (e) {
      if (kDebugMode) debugPrint('TTS init failed: $e');
      _ready = false;
    }
  }

  /// Some Android engines (Fire OS variants) reject 'en-US'; probe a few
  /// candidates and pick the first available.
  Future<String> _bestLanguage() async {
    const candidates = ['en-US', 'en_US', 'eng', 'en'];
    for (final l in candidates) {
      try {
        final ok = await _tts.isLanguageAvailable(l);
        if (ok == true) return l;
      } catch (_) {}
    }
    return 'en-US';
  }

  Future<void> applyDefaults() async {
    await ensure();
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
    } catch (_) {}
  }

  /// Speak [text] with optional per-button [style]; one retry on failure.
  Future<void> speak(String text, {VoiceStyle? style}) async {
    final t = text.trim();
    if (t.isEmpty || _speaking) return;
    _speaking = true;
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await ensure();
          await _tts.setSpeechRate(style?.rate ?? rate);
          await _tts.setPitch(style?.pitch ?? pitch);
          await _tts.setVolume(style?.volume ?? volume);
          final res = await _tts.speak(t);
          final failed = (res is num && res != 1) || res == false;
          if (!failed) break;
          if (attempt == 0) {
            _ready = false;
            await Future.delayed(const Duration(milliseconds: 120));
          }
        } catch (e) {
          if (kDebugMode) debugPrint('TTS speak failed: $e');
          if (attempt == 0) {
            _ready = false;
            await Future.delayed(const Duration(milliseconds: 120));
          }
        }
      }
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
