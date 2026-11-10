import 'dart:js_interop';
import 'package:flutter/foundation.dart';
import '../models/domain.dart';
import 'i18n.dart';
import 'storage.dart' show AppSettings;

@JS('aacSpeech.available')
external bool get _available;
@JS('aacSpeech.voices')
external JSArray<_BrowserVoice> _voices();
@JS('aacSpeech.speak')
external void _speak(JSString text, double rate, double pitch, double volume,
    JSString name, JSString locale);
@JS('aacSpeech.stop')
external void _stop();
@JS('aacSpeech.onError')
external set _onError(JSFunction callback);

extension type _BrowserVoice(JSObject _) implements JSObject {
  external String get name;
  external String get lang;
  external bool get localService;
}

class DeviceVoice {
  final String name;
  final String locale;
  final bool needsInternet;
  const DeviceVoice(this.name, this.locale, {this.needsInternet = false});
  bool get isEnglish => locale.toLowerCase().startsWith('en');
}

/// Call speechSynthesis synchronously from the tap handler. In particular,
/// Safari must retain the user's activation when starting the utterance.
class SpeechEngine {
  final ValueNotifier<String?> error = ValueNotifier(null);
  final ValueNotifier<String> status = ValueNotifier('Browser voice');
  double rate = .45, pitch = 1, volume = 1;
  DeviceVoice? voice;
  bool get usePiper => false;
  set usePiper(bool value) {}

  Future<void> ensure() async {
    if (!_available) {
      error.value = 'Speech is unavailable in this browser. Open in Safari.';
      return;
    }
    _onError = ((JSString message) {
      error.value = 'Speech unavailable. Check your device voices and volume.';
    }).toJS;
  }

  /// Language spoken when no voice is chosen (the browser picks a voice).
  AppLanguage language = kLanguages.first;

  void configure(AppSettings settings) {
    language = languageFor(settings.language);
    rate = settings.rate;
    pitch = settings.pitch;
    volume = settings.volume;
    voice = settings.voiceName == null
        ? null
        : DeviceVoice(settings.voiceName!, settings.voiceLocale ?? '');
  }

  Future<void> warmOfflineVoice() async {}
  Future<void> applyDefaults() async {}
  Future<List<DeviceVoice>> deviceVoices() async {
    final voices = _voices()
        .toDart
        .map((v) => DeviceVoice(v.name, v.lang, needsInternet: !v.localService))
        .toList();
    voices.sort((a, b) => voiceSpeaks(language, a.locale) !=
            voiceSpeaks(language, b.locale)
        ? (voiceSpeaks(language, a.locale) ? -1 : 1)
        : a.isEnglish != b.isEnglish
        ? (a.isEnglish ? -1 : 1)
        : a.name.compareTo(b.name));
    return voices;
  }

  /// The browser always cuts off what is playing (Safari's speech queue can
  /// stall), so [interrupt] is the behaviour here either way.
  Future<void> speak(String text, {VoiceStyle? style, bool interrupt = false}) {
    text = speechText(text);
    if (text.isEmpty) return Future.value();
    try {
      if (!_available) throw StateError('No browser speech');
      // The chosen voice if it speaks this language, else the most natural
      // browser voice for the language (never an English voice for French).
      var use = voice;
      if (use == null || !voiceSpeaks(language, use.locale)) {
        final pick = bestVoice(language, [
          for (final v in _voices().toDart)
            (name: v.name, locale: v.lang, quality: '', network: !v.localService)
        ]);
        use = pick == null ? null : DeviceVoice(pick.name, pick.locale);
      }
      _speak(
          text.trim().toJS,
          (style?.rate ?? rate).clamp(0, 1),
          (style?.pitch ?? pitch).clamp(.5, 2),
          (style?.volume ?? volume).clamp(0, 1),
          (use?.name ?? '').toJS,
          (use?.locale ?? language.voiceLocales.first).toJS);
      error.value = null;
    } catch (_) {
      error.value =
          'Speech unavailable. Open in Safari and check device voices.';
    }
    return Future.value();
  }

  Future<void> stop() async {
    if (_available) _stop();
  }

  Future<void> dispose() async {
    await stop();
    error.dispose();
    status.dispose();
  }
}
