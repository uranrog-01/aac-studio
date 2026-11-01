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
class AppSettings {
  double rate, pitch, volume;
  bool restrictionsEnabled;
  String? pin;
  bool editMode;
  AppSettings({
    this.rate = 0.45,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.restrictionsEnabled = false,
    this.pin,
    this.editMode = false,
  });

  Map<String, dynamic> toJson() => {
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
        'restrictionsEnabled': restrictionsEnabled,
        'pin': pin,
        'editMode': editMode,
      };

  static AppSettings fromJson(Map<String, dynamic>? j) => AppSettings(
        rate: (j?['rate'] as num?)?.toDouble() ?? 0.45,
        pitch: (j?['pitch'] as num?)?.toDouble() ?? 1.0,
        volume: (j?['volume'] as num?)?.toDouble() ?? 1.0,
        restrictionsEnabled: j?['restrictionsEnabled'] as bool? ?? false,
        pin: j?['pin'] as String?,
        editMode: j?['editMode'] as bool? ?? false,
      );
}

AppStorage? _defaultStorage;
AppStorageProvider get defaultAppStorageProvider => StorageProviderAdapter(_defaultStorage!);

Future<AppStorage> initDefaultStorage() async {
  _defaultStorage ??= await AppStorage.instance();
  return _defaultStorage!;
}
