import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// One language the app can show and speak.
class AppLanguage {
  final String code;
  final String name; // in English, for caregivers
  final String nativeName; // in the language itself
  /// Voice languages to try, best first (BCP-47).
  final List<String> voiceLocales;

  /// Extra letters for the Type keyboard (accents), or null when the
  /// language is typed with the device's own keyboard (Chinese, Japanese,
  /// Hindi).
  final String? extraLetters;
  final bool rightToLeft;
  const AppLanguage(this.code, this.name, this.nativeName, this.voiceLocales,
      {this.extraLetters = '', this.rightToLeft = false});

  bool get usesOwnKeyboard => extraLetters != null;
}

const kLanguages = <AppLanguage>[
  AppLanguage('en', 'English', 'English', ['en-US', 'en-GB', 'en']),
  AppLanguage('sq', 'Albanian', 'Shqip', ['sq-AL', 'sq-XK', 'sq'],
      extraLetters: 'ëç'),
  AppLanguage('fr', 'French', 'Français', ['fr-FR', 'fr-CA', 'fr'],
      extraLetters: 'éèêàâçùûôîïœ'),
  AppLanguage('de', 'German', 'Deutsch', ['de-DE', 'de-AT', 'de-CH', 'de'],
      extraLetters: 'äöüß'),
  AppLanguage('es', 'Spanish', 'Español', ['es-ES', 'es-MX', 'es-US', 'es'],
      extraLetters: 'ñáéíóúü¿¡'),
  AppLanguage('it', 'Italian', 'Italiano', ['it-IT', 'it'],
      extraLetters: 'àèéìòù'),
  AppLanguage('zh', 'Chinese (Mandarin)', '中文', ['zh-CN', 'zh-TW', 'zh'],
      extraLetters: null),
  AppLanguage('ja', 'Japanese', '日本語', ['ja-JP', 'ja'], extraLetters: null),
  AppLanguage('hi', 'Hindi', 'हिन्दी', ['hi-IN', 'hi'], extraLetters: null),
  AppLanguage('tr', 'Turkish', 'Türkçe', ['tr-TR', 'tr'],
      extraLetters: 'çğıöşü'),
  AppLanguage('el', 'Greek', 'Ελληνικά', ['el-GR', 'el'], extraLetters: null),
  AppLanguage('hr', 'Croatian / Bosnian', 'Hrvatski / Bosanski',
      ['hr-HR', 'bs-BA', 'sr-Latn-RS', 'hr', 'bs'],
      extraLetters: 'čćđšž'),
  AppLanguage('ar', 'Arabic', 'العربية', ['ar-SA', 'ar-EG', 'ar'],
      extraLetters: null, rightToLeft: true),
  AppLanguage('ur', 'Urdu', 'اردو', ['ur-PK', 'ur-IN', 'ur'],
      extraLetters: null, rightToLeft: true),
  AppLanguage('pt', 'Portuguese (Brazil)', 'Português', ['pt-BR', 'pt-PT', 'pt'],
      extraLetters: 'ãáâàçéêíóôõú'),
  AppLanguage('ru', 'Russian', 'Русский', ['ru-RU', 'ru'], extraLetters: null),
  AppLanguage('uk', 'Ukrainian', 'Українська', ['uk-UA', 'uk'],
      extraLetters: null),
  AppLanguage('pl', 'Polish', 'Polski', ['pl-PL', 'pl'],
      extraLetters: 'ąćęłńóśźż'),
  AppLanguage('ro', 'Romanian', 'Română', ['ro-RO', 'ro'],
      extraLetters: 'ăâîșț'),
  AppLanguage('nl', 'Dutch', 'Nederlands', ['nl-NL', 'nl-BE', 'nl'],
      extraLetters: 'éëïóöü'),
  AppLanguage('ko', 'Korean', '한국어', ['ko-KR', 'ko'], extraLetters: null),
];

AppLanguage languageFor(String code) =>
    kLanguages.firstWhere((l) => l.code == code, orElse: () => kLanguages.first);

/// Translations for the app's own text and the board's words. The saved
/// board always keeps its English words; they are translated when shown
/// and spoken, so switching language never changes or damages a board.
/// Words without a translation yet stay in English.
class I18n {
  static AppLanguage language = kLanguages.first;
  static Map<String, String> _ui = const {};
  static Map<String, String> _words = const {};
  static Map<String, String> _forms = const {};

  /// Notifies the app to redraw after a language change.
  static final ValueNotifier<String> changes = ValueNotifier('en');

  static Future<void> load(String code) async {
    final lang = languageFor(code);
    var ui = <String, String>{};
    var words = <String, String>{};
    var forms = <String, String>{};
    // English has no word list but does have sentence forms (en.json).
    {
      try {
        final data = jsonDecode(
                await rootBundle.loadString('assets/i18n/${lang.code}.json'))
            as Map<String, dynamic>;
        ui = (data['ui'] as Map? ?? const {}).cast<String, String>();
        words = {
          for (final e in (data['words'] as Map? ?? const {}).entries)
            (e.key as String).toLowerCase(): e.value as String
        };
        forms = {
          for (final e in (data['forms'] as Map? ?? const {}).entries)
            (e.key as String).toLowerCase(): e.value as String
        };
      } catch (_) {
        // A missing or damaged file keeps the app usable in English.
      }
    }
    language = lang;
    _ui = ui;
    _words = words;
    _forms = forms;
    changes.value = lang.code;
  }

  /// App text (buttons, hints, messages), keyed by its English wording.
  static String t(String english) => _ui[english] ?? english;

  /// A board word or category name in the chosen language.
  static String word(String english) =>
      _words[english.toLowerCase()] ?? english;

  /// Pronoun + word as one natural phrase ("I" + "want" → "je veux",
  /// "I" + "hungry" → "j'ai faim"), or null when there is none.
  static String? form(String pronoun, String word) =>
      _forms['${pronoun.toLowerCase()}+${word.toLowerCase()}'];

  static bool hasWord(String english) =>
      _words.containsKey(english.toLowerCase());

  /// How many of [labels] have a translation (for Settings).
  static int translatedCount(Iterable<String> labels) =>
      labels.where(hasWord).length;
}

/// Text as it should be spoken. A single capital letter is lower-cased:
/// iPhone/iPad voices otherwise say "capital A" instead of "A".
String speechText(String text) {
  final t = text.trim();
  if (t.length == 1 && t.toUpperCase() != t.toLowerCase()) {
    return t.toLowerCase();
  }
  return t;
}

/// A voice as the device reports it (iOS/Android via flutter_tts, browsers
/// via speechSynthesis).
typedef VoiceInfo = ({String name, String locale, String quality, bool network});

/// iPhone joke/effect voices: never chosen automatically.
const _noveltyVoices = {
  'albert', 'bad news', 'bahh', 'bells', 'boing', 'bubbles', 'cellos',
  'good news', 'jester', 'organ', 'superstar', 'trinoids', 'whisper',
  'wobble', 'zarvox', 'fred', 'junior', 'kathy', 'ralph', 'grandma',
  'grandpa', 'rocko', 'shelley', 'eddy', 'flo', 'reed', 'sandy',
};

String _localeKey(String locale) => locale.toLowerCase().replaceAll('_', '-');

/// Whether a voice speaks [lang] (Croatian/Bosnian also accept Serbian
/// Latin voices, which read the same words correctly).
bool voiceSpeaks(AppLanguage lang, String locale) {
  final base = _localeKey(locale).split('-').first;
  return lang.voiceLocales.any((l) => _localeKey(l).split('-').first == base);
}

/// The most natural installed voice for [lang]: the language's main region
/// first (e.g. pt-BR before pt-PT), then the best quality (premium /
/// enhanced / neural), preferring voices that work offline. Null when the
/// device has no voice for the language.
VoiceInfo? bestVoice(AppLanguage lang, Iterable<VoiceInfo> voices) {
  VoiceInfo? best;
  var bestScore = -1;
  for (final v in voices) {
    if (!voiceSpeaks(lang, v.locale)) continue;
    final name = v.name.toLowerCase();
    if (_noveltyVoices.contains(name.split(' (').first)) continue;
    final loc = _localeKey(v.locale);
    var score = 100;
    final region = lang.voiceLocales.indexWhere((l) => _localeKey(l) == loc);
    score -= region < 0 ? 30 : region * 8;
    final q = v.quality.toLowerCase();
    score += q.contains('premium') || q.contains('very high')
        ? 40
        : q.contains('enhanced') || q == 'high'
            ? 25
            : q.contains('low')
                ? -10
                : 0;
    if (name.contains('natural') || name.contains('neural')) score += 30;
    if (name.contains('enhanced') || name.contains('premium')) score += 25;
    if (name.contains('google')) score += 15;
    if (v.network) score -= 15; // works offline is better
    if (score > bestScore) {
      bestScore = score;
      best = v;
    }
  }
  return best;
}
