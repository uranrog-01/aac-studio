import 'package:flutter_tts/flutter_tts.dart';

/// M2 speech engine — platform TTS abstraction (Windows SAPI voices on the
/// desktop preview, AVSpeechSynthesizer on iOS, engine TTS on Android).
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

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    await ensure();
    await _tts.setSpeechRate(rate);
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
