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
  static Map<String, String> _wordsF = const {};
  static Map<String, String> _formsF = const {};

  /// The person speaking is a girl or woman: words and phrases that
  /// differ ("e lodhur" for "i lodhur") use their feminine form.
  static bool female = false;

  /// Whether the chosen language has feminine forms to offer.
  static bool get hasFeminine => _wordsF.isNotEmpty || _formsF.isNotEmpty;

  static void setFemale(bool value) {
    if (female == value) return;
    female = value;
    changes.value = _state;
  }

  static String get _state => '${language.code}${female ? '-f' : ''}';

  /// Every board word in the chosen language (typing suggestions).
  static Iterable<String> get boardWords => _words.values;

  /// Notifies the app to redraw after a language change.
  static final ValueNotifier<String> changes = ValueNotifier('en');

  static Future<void> load(String code) async {
    final lang = languageFor(code);
    var ui = <String, String>{};
    var words = <String, String>{};
    var forms = <String, String>{};
    var wordsF = <String, String>{};
    var formsF = <String, String>{};
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
        wordsF = {
          for (final e in (data['words_f'] as Map? ?? const {}).entries)
            (e.key as String).toLowerCase(): e.value as String
        };
        formsF = {
          for (final e in (data['forms_f'] as Map? ?? const {}).entries)
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
    _wordsF = wordsF;
    _formsF = formsF;
    changes.value = _state;
  }

  /// App text (buttons, hints, messages), keyed by its English wording.
  static String t(String english) => _ui[english] ?? english;

  /// A board word or category name in the chosen language.
  ///
  /// A word with several meanings ("sink" the basin, "sink" in water) can
  /// be translated per button or category: `@id` wins over the word.
  static String word(String english, {String? id}) {
    final key = english.toLowerCase();
    final own = id == null ? null : '@${id.toLowerCase()}';
    if (female) {
      final f = (own == null ? null : _wordsF[own]) ?? _wordsF[key];
      if (f != null && (own == null || !_words.containsKey(own))) return f;
    }
    return (own == null ? null : _words[own]) ?? _words[key] ?? english;
  }

  /// Pronoun + word as one natural phrase ("I" + "want" → "je veux",
  /// "I" + "hungry" → "j'ai faim"), or null when there is none.
  static String? form(String pronoun, String word) {
    final key = '${pronoun.toLowerCase()}+${word.toLowerCase()}';
    return (female ? _formsF[key] : null) ?? _forms[key];
  }

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

enum VoiceGender { female, male, unknown }

const _femaleNames = {
  'samantha', 'victoria', 'karen', 'moira', 'tessa', 'fiona', 'allison', 'ava',
  'susan', 'zoe', 'nicky', 'kate', 'serena', 'veena', 'alice', 'amelie',
  'amélie', 'anna', 'ellen', 'joana', 'luciana', 'monica', 'mónica',
  'paulina', 'sara', 'satu', 'kyoko', 'yuna', 'mei-jia', 'sin-ji',
  'ting-ting', 'milena', 'zuzana', 'ioana', 'melina', 'yelda', 'damayanti',
  'lekha', 'laura', 'marie', 'audrey', 'aurelie', 'aurélie', 'alva', 'nora',
  'helena', 'petra', 'carmit', 'kanya', 'lana', 'zira', 'hazel', 'heera',
  'catherine', 'linda', 'eva', 'hortense', 'julie', 'katja', 'hedda', 'elsa',
  'cosima', 'lucia', 'paola', 'ayumi', 'haruka', 'sayaka', 'heami', 'huihui',
  'yaoyao', 'tracy', 'hanhan', 'irina', 'maria', 'helia', 'sabina', 'zosia',
  'filiz', 'seda', 'salma', 'hoda', 'kalpana', 'anila', 'jenny', 'aria',
  'michelle', 'emma', 'sonia', 'libby', 'natasha', 'clara', 'denise', 'elvira',
  'isabella', 'nanami', 'sun-hi', 'xiaoxiao', 'swara', 'emel', 'svetlana',
  'polina', 'gabrijela', 'athina', 'alina', 'colette', 'fenna', 'zofia',
};

const _maleNames = {
  'daniel', 'alex', 'tom', 'oliver', 'aaron', 'arthur', 'gordon', 'lee',
  'rishi', 'thomas', 'jorge', 'juan', 'diego', 'luca', 'xander', 'maged',
  'tarik', 'otoya', 'hattori', 'yuri', 'markus', 'yannick', 'martin', 'david',
  'mark', 'george', 'james', 'richard', 'ravi', 'hemant', 'sean', 'guillaume',
  'paul', 'claude', 'stefan', 'michael', 'karsten', 'pablo', 'raul', 'raúl',
  'cosimo', 'ichiro', 'pavel', 'adam', 'jakub', 'tolga', 'naayf', 'andrei',
  'filip', 'matej', 'lado', 'guy', 'ryan', 'william', 'liam', 'henri',
  'conrad', 'alvaro', 'álvaro', 'keita', 'injoon', 'yunxi', 'madhur', 'ahmet',
  'dmitry', 'ostap', 'srecko', 'srećko', 'nestoras', 'emil', 'maarten', 'marek',
  'ilir', 'edon', 'asad', 'hamed', 'antonio', 'eddy', 'reed', 'rocko',
};

/// Whether a device voice is a woman's or a man's. The device says so on
/// iPhone and iPad ([hint]); elsewhere it is read from the voice's name
/// (Android "…#female_1", Windows "Zira" / "David"). Unknown voices are
/// listed separately rather than guessed.
VoiceGender voiceGender(String name, {String hint = ''}) {
  final h = hint.toLowerCase();
  if (h.contains('female')) return VoiceGender.female;
  if (h.contains('male')) return VoiceGender.male;
  final n = name.toLowerCase();
  if (n.contains('female') || n.contains('woman')) return VoiceGender.female;
  if (RegExp(r'(^|[^a-z])(male|man)([^a-z]|$)').hasMatch(n)) {
    return VoiceGender.male;
  }
  for (final word in n.split(RegExp(r"[^a-zà-ÿ'-]+"))) {
    if (_femaleNames.contains(word)) return VoiceGender.female;
    if (_maleNames.contains(word)) return VoiceGender.male;
  }
  return VoiceGender.unknown;
}

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
