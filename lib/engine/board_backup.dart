import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/pack_loader.dart';
import 'storage.dart';

/// One-file backup of everything a communicator relies on: the board, the
/// settings, learned words and any downloaded or custom pictures the board
/// points to. The file layout matches the web app's backup, so a backup
/// made in either app can be restored in the other.
class BoardBackup {
  static const format = 'aac-studio';
  static const webFormat = 'aac-studio-web';
  static const version = 1;
  static const packKey = 'packs/sample_pack.json';
  static const settingsKey = 'settings.json';
  static const learnedKey = 'learned_words.json';

  /// Builds the backup from what is saved on this device.
  static Future<Map<String, dynamic>> create(AppStorage storage) async {
    await storage.flush();
    final files = <String, dynamic>{};
    final pack = await storage.readJson(storage.packFile('sample_pack'));
    if (pack != null) files[packKey] = pack;
    final settings = await storage.readJson(storage.settingsFile);
    if (settings != null) files[settingsKey] = settings;
    final learned = await storage.readJson(storage.learnedFile);
    if (learned != null) files[learnedKey] = learned;

    final images = <String, String>{};
    for (final path in _imagePaths(pack)) {
      if (images.containsKey(path) || path.startsWith('data:')) continue;
      try {
        final file = File(storage.resolvePicturePath(path));
        if (await file.exists()) {
          images[path] = base64Encode(await file.readAsBytes());
        }
      } catch (_) {/* A missing picture must not block the backup. */}
    }
    return {
      'format': format,
      'version': version,
      'created': DateTime.now().toIso8601String(),
      'files': files,
      if (images.isNotEmpty) 'images': images,
    };
  }

  /// Parses and fully checks a backup without changing anything.
  static Map<String, dynamic> parse(String text) {
    final backup = jsonDecode(text);
    if (backup is! Map<String, dynamic> ||
        (backup['format'] != format && backup['format'] != webFormat) ||
        backup['version'] != version) {
      throw const FormatException('Not an AAC Studio backup');
    }
    final files = backup['files'];
    if (files is! Map<String, dynamic> ||
        files[packKey] is! Map<String, dynamic>) {
      throw const FormatException('The backup has no board');
    }
    final vocabulary = PackLoader().loadString(jsonEncode(files[packKey]));
    if (vocabulary.viewsByFolder[vocabulary.rootFolderId]?.isNotEmpty !=
        true) {
      throw const FormatException('The backup board has no Home page');
    }
    final settings = files[settingsKey];
    if (settings != null && settings is! Map<String, dynamic>) {
      throw const FormatException('Invalid settings');
    }
    AppSettings.fromJson(settings as Map<String, dynamic>?);
    final learned = files[learnedKey];
    if (learned != null &&
        (learned is! Map || learned.values.any((v) => v is! int || v < 0))) {
      throw const FormatException('Invalid learned words');
    }
    final images = backup['images'];
    if (images != null &&
        (images is! Map || images.values.any((v) => v is! String))) {
      throw const FormatException('Invalid pictures');
    }
    return backup;
  }

  /// Writes a parsed backup to this device, replacing the current board,
  /// settings and learned words. Pictures are restored first and the board
  /// is pointed at their new location.
  static Future<void> restore(
      AppStorage storage, Map<String, dynamic> backup) async {
    final files = backup['files'] as Map<String, dynamic>;
    final pack = jsonDecode(jsonEncode(files[packKey])) as Map<String, dynamic>;
    final images = (backup['images'] as Map?)?.cast<String, String>() ?? {};
    if (images.isNotEmpty) {
      final dir = Directory(p.join(storage.root.path, 'restored_pictures'));
      await dir.create(recursive: true);
      final moved = <String, String>{};
      var n = 0;
      for (final entry in images.entries) {
        final extension = p.extension(entry.key).toLowerCase();
        final target = File(p.join(dir.path,
            'picture_${DateTime.now().millisecondsSinceEpoch}_${n++}$extension'));
        await target.writeAsBytes(base64Decode(entry.value), flush: true);
        moved[entry.key] = storage.storedPicturePath(target.path);
      }
      for (final item in [
        ...(pack['buttons'] as List? ?? const []),
        ...(pack['folders'] as List? ?? const []),
      ]) {
        if (item is Map && moved.containsKey(item['imagePath'])) {
          item['imagePath'] = moved[item['imagePath']];
        }
      }
    }
    await storage.writeJson(storage.packFile('sample_pack'), pack);
    if (files[settingsKey] != null) {
      await storage.writeJson(storage.settingsFile, files[settingsKey] as Object);
    }
    await storage.writeJson(
        storage.learnedFile, (files[learnedKey] as Object?) ?? <String, int>{});
  }

  static Iterable<String> _imagePaths(Map<String, dynamic>? pack) sync* {
    if (pack == null) return;
    for (final item in [
      ...(pack['buttons'] as List? ?? const []),
      ...(pack['folders'] as List? ?? const []),
    ]) {
      final path = item is Map ? item['imagePath'] : null;
      if (path is String && path.isNotEmpty) yield path;
    }
  }
}
