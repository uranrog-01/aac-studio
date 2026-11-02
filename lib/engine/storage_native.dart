import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
