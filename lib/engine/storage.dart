import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'prediction.dart';

/// M5 persistence: packs, settings and learned words under the app's
/// application-support directory (Windows + Android + iOS).
class AppStorage {
  late final Directory root;
  late final Directory packsDir;

  AppStorage._();
  static AppStorage? _instance;

  static Future<AppStorage> instance() async {
    if (_instance != null) return _instance!;
    final s = AppStorage._();
    if (Platform.isAndroid || Platform.isIOS) {
      final base = await getApplicationSupportDirectory();
      s.root = Directory(p.join(base.path, 'data'));
    } else {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '.';
      s.root = Directory(p.join(home, '.aac_studio'));
    }
    s.packsDir = Directory(p.join(s.root.path, 'packs'));
    await s.packsDir.create(recursive: true);
    _instance = s;
    return s;
  }

  File packFile(String id) => File(p.join(packsDir.path, '$id.json'));
  File get settingsFile => File(p.join(root.path, 'settings.json'));
  File get learnedFile => File(p.join(root.path, 'learned_words.json'));

  Future<void> writeJson(File f, Object json) async =>
      f.writeAsString(const JsonEncoder.withIndent('  ').convert(json));

  Future<Map<String, dynamic>?> readJson(File f) async {
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}

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
  bool haptics;
  bool audioCues;

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
    this.haptics = true,
    this.audioCues = false,
    this.arasaacEnabled = true,
    this.arasaacSkin = 0,
    this.arasaacHair = 0,
  });

  Map<String, dynamic> toJson() => {
        'usePiper': usePiper,
        if (voiceName != null) 'voiceName': voiceName,
        if (voiceLocale != null) 'voiceLocale': voiceLocale,
        'rate': rate, 'pitch': pitch, 'volume': volume,
        'restrictionsEnabled': restrictionsEnabled, 'pin': pin,
        'editMode': editMode, 'quietBuilder': quietBuilder,
        'vocalizeFolders': vocalizeFolders,
        'inputDebounceMs': inputDebounceMs, 'preventExit': preventExit,
        'clearOnSpeak': clearOnSpeak, 'goHomeOnPress': goHomeOnPress,
        'buttonView': buttonView.name, 'labelPosition': labelPosition.name,
        'messageWindowTop': messageWindowTop,
        'scanningEnabled': scanningEnabled, 'scanDelayMs': scanDelayMs,
        'dwellEnabled': dwellEnabled, 'dwellSeconds': dwellSeconds,
        'cviMode': cviMode, 'haptics': haptics, 'audioCues': audioCues,
        'arasaacEnabled': arasaacEnabled, 'arasaacSkin': arasaacSkin,
        'arasaacHair': arasaacHair,
      };

  static AppSettings fromJson(Map<String, dynamic>? j) => AppSettings(
        usePiper: j?['usePiper'] as bool? ?? true,
        voiceName: j?['voiceName'] as String?,
        voiceLocale: j?['voiceLocale'] as String?,
        rate: (j?['rate'] as num?)?.toDouble() ?? 0.45,
        pitch: (j?['pitch'] as num?)?.toDouble() ?? 1.0,
        volume: (j?['volume'] as num?)?.toDouble() ?? 1.0,
        restrictionsEnabled: j?['restrictionsEnabled'] as bool? ?? false,
        pin: (j?['pin'] as String?) ?? '1234',
        editMode: j?['editMode'] as bool? ?? false,
        quietBuilder: j?['quietBuilder'] as bool? ?? false,
        vocalizeFolders: j?['vocalizeFolders'] as bool? ?? true,
        inputDebounceMs: (j?['inputDebounceMs'] as num?)?.toInt() ?? 0,
        preventExit: j?['preventExit'] as bool? ?? false,
        clearOnSpeak: j?['clearOnSpeak'] as bool? ?? false,
        goHomeOnPress: j?['goHomeOnPress'] as bool? ?? false,
        buttonView: ButtonView.values.firstWhere(
            (v) => v.name == j?['buttonView'],
            orElse: () => ButtonView.symbolText),
        labelPosition: LabelPosition.values.firstWhere(
            (v) => v.name == j?['labelPosition'],
            orElse: () => LabelPosition.below),
        messageWindowTop: j?['messageWindowTop'] as bool? ?? true,
        scanningEnabled: j?['scanningEnabled'] as bool? ?? false,
        scanDelayMs: (j?['scanDelayMs'] as num?)?.toInt() ?? 1200,
        dwellEnabled: j?['dwellEnabled'] as bool? ?? false,
        dwellSeconds: (j?['dwellSeconds'] as num?)?.toDouble() ?? 1.0,
        cviMode: j?['cviMode'] as bool? ?? false,
        haptics: j?['haptics'] as bool? ?? true,
        audioCues: j?['audioCues'] as bool? ?? false,
        arasaacEnabled: j?['arasaacEnabled'] as bool? ?? true,
        arasaacSkin: (j?['arasaacSkin'] as num?)?.toInt() ?? 0,
        arasaacHair: (j?['arasaacHair'] as num?)?.toInt() ?? 0,
      );
}

AppStorage? _defaultStorage;
AppStorageProvider get defaultAppStorageProvider => StorageProviderAdapter(_defaultStorage!);

Future<AppStorage> initDefaultStorage() async {
  _defaultStorage ??= await AppStorage.instance();
  return _defaultStorage!;
}
