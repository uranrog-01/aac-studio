import 'storage_native.dart' if (dart.library.js_interop) 'storage_web.dart';
export 'storage_native.dart' if (dart.library.js_interop) 'storage_web.dart';
import 'prediction.dart';

/// AppStorage as the Predictor's storage contract (M4 auto-learn).
class StorageProviderAdapter implements AppStorageProvider {
  final AppStorage storage;
  StorageProviderAdapter(this.storage);

  @override
  Future<Map<String, int>> readLearned() async {
    final m = await storage.readJson(storage.learnedFile);
    return m?.map((k, v) => MapEntry(k, (v as num).toInt())) ?? {};
  }

  @override
  Future<void> writeLearned(Map<String, int> words) =>
      storage.writeJson(storage.learnedFile, words);
}

/// App settings persisted as JSON: M3 speech defaults + M5 restrictions.
/// View mode for grid buttons (P0 accessibility set).
enum ButtonView { symbolText, symbolOnly, textOnly }

/// Label position on grid buttons.
enum LabelPosition { below, above, hidden }

class AppSettings {
  double rate, pitch, volume;
  bool usePiper;
  String? voiceName, voiceLocale; // chosen device voice (null = default)
  bool restrictionsEnabled;
  String pin;
  bool editMode;

  // P0 accessibility / behavior settings
  bool quietBuilder; // build silently; tap banner to speak
  bool vocalizeFolders; // speak folder name when entering
  int inputDebounceMs; // ignore taps faster than this (0 = off)
  bool preventExit; // quick-exit guard (3 backs within 2s)
  bool clearOnSpeak; // clear message after speaking it
  bool goHomeOnPress; // return home after a spoken sentence
  ButtonView buttonView; // symbol/text/both
  LabelPosition labelPosition; // below/above/hidden
  bool messageWindowTop; // message window top vs bottom

  // P2 scanning / dwell / CVI / feedback
  bool scanningEnabled;
  int scanDelayMs; // auto-advance delay
  bool dwellEnabled;
  double dwellSeconds;
  bool cviMode; // high-contrast cortical-visual-impairment theme
  String skinTone; // people pictures: '' default or a SymbolLibrary.skinTones value
  bool haptics;
  bool audioCues;
  String language; // app and board language code (see kLanguages)
  bool fullScreen; // hide system bars / browser bars where possible
  bool callSpeech; // iPhone/iPad: speech also goes into phone/FaceTime calls
  List<String> phrases; // saved messages (Type > Save)
  String typingSpeech; // Type screen: 'letters' (and words), 'words' or 'off'

  /// The person speaking is a girl or woman (languages where words such
  /// as "tired" or "happy" differ: Albanian "i lodhur" / "e lodhur").
  bool speakerFemale;

  /// The voice the person wants: '' (automatic), 'female' or 'male'. The
  /// best installed voice of that kind is used; where the device has
  /// none, the best voice of any kind speaks.
  String voiceGender;

  /// Start small and grow: how many Home words are shown. 0 = all,
  /// 1 = the first 10 (no categories), 2 = 25, 3 = 45. Words never move;
  /// more rows appear below as the person learns.
  int homeLevel;

  /// Caregiver lock. The device's screen pinning state is checked separately.
  bool lockApp;

  // P2 ARASAAC online symbols
  bool arasaacEnabled;
  int arasaacSkin; // 0 none..3 dark
  int arasaacHair; // 0 none..4 dark? (API: none/blond/brown/dark/red/gray)

  AppSettings({
    this.usePiper = true,
    this.voiceName,
    this.voiceLocale,
    this.rate = 0.45,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.restrictionsEnabled = false,
    this.pin = '1234',
    this.editMode = false,
    this.quietBuilder = false,
    this.vocalizeFolders = true,
    this.inputDebounceMs = 0,
    this.preventExit = false,
    this.clearOnSpeak = false,
    this.goHomeOnPress = false,
    this.buttonView = ButtonView.symbolText,
    this.labelPosition = LabelPosition.below,
    this.messageWindowTop = true,
    this.scanningEnabled = false,
    this.scanDelayMs = 1200,
    this.dwellEnabled = false,
    this.dwellSeconds = 1.0,
    this.cviMode = false,
    this.skinTone = '',
    this.haptics = true,
    this.audioCues = false,
    this.language = 'en',
    this.fullScreen = true,
    this.callSpeech = false,
    List<String>? phrases,
    this.typingSpeech = 'letters',
    this.arasaacEnabled = true,
    this.arasaacSkin = 0,
    this.arasaacHair = 0,
    this.speakerFemale = false,
    this.voiceGender = '',
    this.homeLevel = 0,
    this.lockApp = false,
  }) : phrases = phrases ?? [];

  Map<String, dynamic> toJson() => {
        'usePiper': usePiper,
        if (voiceName != null) 'voiceName': voiceName,
        if (voiceLocale != null) 'voiceLocale': voiceLocale,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'restrictionsEnabled': restrictionsEnabled,
        'pin': pin,
        'editMode': editMode,
        'quietBuilder': quietBuilder,
        'vocalizeFolders': vocalizeFolders,
        'inputDebounceMs': inputDebounceMs,
        'preventExit': preventExit,
        'clearOnSpeak': clearOnSpeak,
        'goHomeOnPress': goHomeOnPress,
        'buttonView': buttonView.name,
        'labelPosition': labelPosition.name,
        'messageWindowTop': messageWindowTop,
        'scanningEnabled': scanningEnabled,
        'scanDelayMs': scanDelayMs,
        'dwellEnabled': dwellEnabled,
        'dwellSeconds': dwellSeconds,
        'cviMode': cviMode,
        'skinTone': skinTone,
        'haptics': haptics,
        'audioCues': audioCues,
        'language': language,
        'fullScreen': fullScreen,
        'callSpeech': callSpeech,
        'phrases': phrases,
        // Saved under a new name: v10 saved 'words' as the default, and
        // typing now speaks each letter unless a caregiver turns it down.
        'typingSpeak': typingSpeech,
        'arasaacEnabled': arasaacEnabled,
        'arasaacSkin': arasaacSkin,
        'arasaacHair': arasaacHair,
        'speakerFemale': speakerFemale,
        'voiceGender': voiceGender,
        'homeLevel': homeLevel,
        'lockApp': lockApp,
      };

  // A wrong type in one saved value falls back to that value's default
  // instead of stopping the app from opening.
  static bool _b(Map<String, dynamic>? j, String k, bool d) {
    final v = j?[k];
    return v is bool ? v : d;
  }

  static double _d(Map<String, dynamic>? j, String k, double d) {
    final v = j?[k];
    return v is num && v.isFinite ? v.toDouble() : d;
  }

  static int _i(Map<String, dynamic>? j, String k, int d) {
    final v = j?[k];
    return v is num && v.isFinite ? v.toInt() : d;
  }

  static String _s(Map<String, dynamic>? j, String k, String d) {
    final v = j?[k];
    return v is String ? v : d;
  }

  static String? _sn(Map<String, dynamic>? j, String k) {
    final v = j?[k];
    return v is String ? v : null;
  }

  static AppSettings fromJson(Map<String, dynamic>? j) => AppSettings(
        usePiper: _b(j, 'usePiper', true),
        voiceName: _sn(j, 'voiceName'),
        voiceLocale: _sn(j, 'voiceLocale'),
        rate: _d(j, 'rate', 0.45),
        pitch: _d(j, 'pitch', 1.0),
        volume: _d(j, 'volume', 1.0),
        restrictionsEnabled: _b(j, 'restrictionsEnabled', false),
        pin: _s(j, 'pin', '1234'),
        editMode: _b(j, 'editMode', false),
        quietBuilder: _b(j, 'quietBuilder', false),
        vocalizeFolders: _b(j, 'vocalizeFolders', true),
        inputDebounceMs: _i(j, 'inputDebounceMs', 0),
        preventExit: _b(j, 'preventExit', false),
        clearOnSpeak: _b(j, 'clearOnSpeak', false),
        goHomeOnPress: _b(j, 'goHomeOnPress', false),
        buttonView: ButtonView.values.firstWhere(
            (v) => v.name == j?['buttonView'],
            orElse: () => ButtonView.symbolText),
        labelPosition: LabelPosition.values.firstWhere(
            (v) => v.name == j?['labelPosition'],
            orElse: () => LabelPosition.below),
        messageWindowTop: _b(j, 'messageWindowTop', true),
        scanningEnabled: _b(j, 'scanningEnabled', false),
        scanDelayMs: _i(j, 'scanDelayMs', 1200),
        dwellEnabled: _b(j, 'dwellEnabled', false),
        dwellSeconds: _d(j, 'dwellSeconds', 1.0),
        cviMode: _b(j, 'cviMode', false),
        skinTone: _s(j, 'skinTone', ''),
        haptics: _b(j, 'haptics', true),
        audioCues: _b(j, 'audioCues', false),
        language: _s(j, 'language', 'en'),
        fullScreen: _b(j, 'fullScreen', true),
        callSpeech: _b(j, 'callSpeech', false),
        phrases: [
          for (final p in (j?['phrases'] is List ? j!['phrases'] as List : const []))
            if (p is String && p.trim().isNotEmpty) p
        ],
        typingSpeech: const ['words', 'letters', 'off']
                .contains(j?['typingSpeak'])
            ? j!['typingSpeak'] as String
            : 'letters',
        arasaacEnabled: _b(j, 'arasaacEnabled', true),
        arasaacSkin: _i(j, 'arasaacSkin', 0),
        arasaacHair: _i(j, 'arasaacHair', 0),
        speakerFemale: _b(j, 'speakerFemale', false),
        voiceGender: const ['female', 'male'].contains(j?['voiceGender'])
            ? j!['voiceGender'] as String
            : '',
        homeLevel: _i(j, 'homeLevel', 0).clamp(0, 3),
        lockApp: _b(j, 'lockApp', false),
      );
}

AppStorage? _defaultStorage;
AppStorageProvider get defaultAppStorageProvider =>
    StorageProviderAdapter(_defaultStorage!);

Future<AppStorage> initDefaultStorage() async {
  _defaultStorage ??= await AppStorage.instance();
  return _defaultStorage!;
}
