import 'package:flutter_tts/flutter_tts.dart';

import '../models/domain.dart';

/// M3 speech engine — platform TTS abstraction with per-utterance overrides.
class SpeechEngine {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;
  double rate = 0.45;
  double pitch = 1.0;
  double volume = 1.0;

  Future<void> ensure() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
      await _tts.setQueueMode(0);
    } catch (_) {}
    _ready = true;
  }

  Future<void> applyDefaults() async {
    await ensure();
    try {
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
    } catch (_) {}
  }

  /// Speak [text]; [style] temporarily overrides rate/pitch/volume (M3).
  Future<void> speak(String text, {VoiceStyle? style}) async {
    if (text.trim().isEmpty) return;
    await ensure();
    try {
      await _tts.setSpeechRate(style?.rate ?? rate);
      await _tts.setPitch(style?.pitch ?? pitch);
      await _tts.setVolume(style?.volume ?? volume);
      await _tts.speak(text);
      // restore defaults for the next utterance
      await _tts.setSpeechRate(rate);
      await _tts.setPitch(pitch);
      await _tts.setVolume(volume);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
