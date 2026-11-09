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

  /// Notifies the app to redraw after a language change.
  static final ValueNotifier<String> changes = ValueNotifier('en');

  static Future<void> load(String code) async {
    final lang = languageFor(code);
    var ui = <String, String>{};
    var words = <String, String>{};
    if (lang.code != 'en') {
      try {
        final data = jsonDecode(
                await rootBundle.loadString('assets/i18n/${lang.code}.json'))
            as Map<String, dynamic>;
        ui = (data['ui'] as Map? ?? const {}).cast<String, String>();
        words = {
          for (final e in (data['words'] as Map? ?? const {}).entries)
            (e.key as String).toLowerCase(): e.value as String
        };
      } catch (_) {
        // A missing or damaged file keeps the app usable in English.
      }
    }
    language = lang;
    _ui = ui;
    _words = words;
    changes.value = lang.code;
  }

  /// App text (buttons, hints, messages), keyed by its English wording.
  static String t(String english) => _ui[english] ?? english;

  /// A board word or category name in the chosen language.
  static String word(String english) =>
      _words[english.toLowerCase()] ?? english;

  static bool hasWord(String english) =>
      _words.containsKey(english.toLowerCase());

  /// How many of [labels] have a translation (for Settings).
  static int translatedCount(Iterable<String> labels) =>
      labels.where(hasWord).length;
}
