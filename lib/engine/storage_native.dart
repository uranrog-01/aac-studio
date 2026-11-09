import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// M5 persistence: packs, settings and learned words under the app's
/// application-support directory (Windows + Android + iOS).
///
/// Writes are crash-safe: each save goes to a temporary file that is flushed
/// and then renamed over the real file, so a dead battery or a killed app can
/// never leave a half-written board. The previous good copy is kept as
/// `<file>.prev` and is used automatically if the main file is unreadable.
/// Saves to the same file run one at a time, in the order they were made.
class AppStorage {
  late final Directory root;
  late final Directory packsDir;
  final Map<String, Future<void>> _writes = {};

  AppStorage._();
  static AppStorage? _instance;

  /// Storage rooted at [directory] (tests and tools).
  static Future<AppStorage> at(Directory directory) async {
    final s = AppStorage._();
    s.root = directory;
    s.packsDir = Directory(p.join(directory.path, 'packs'));
    await s.packsDir.create(recursive: true);
    return s;
  }

  /// The storage used to draw saved pictures (set by [instance]).
  static AppStorage? current;

  /// Folders inside the storage root that hold pictures used by boards.
  static const pictureFolders = ['imgcache', 'restored_pictures'];

  /// The form of a picture path saved in boards and indexes.
  ///
  /// Pictures inside the app's own storage are saved relative to it
  /// (`imgcache/arasaac_12.png`), because iOS moves the app's data folder to
  /// a new location on updates and restores, which breaks full paths. Full
  /// paths saved by older versions are rebased onto the current folder.
  /// Anything else (data URLs, web links, files elsewhere) is kept as is.
  String storedPicturePath(String path) {
    if (path.isEmpty || path.startsWith('data:') || path.contains('://')) {
      return path;
    }
    String? inside;
    if (p.isRelative(path)) {
      inside = path;
    } else if (p.isWithin(root.path, path)) {
      inside = p.relative(path, from: root.path);
    } else {
      final parts = p.split(path);
      for (var i = parts.length - 2; i >= 0; i--) {
        if (pictureFolders.contains(parts[i])) {
          inside = p.joinAll(parts.sublist(i));
          break;
        }
      }
    }
    if (inside == null) return path;
    // '/' separators so a backup made on Windows opens on a phone.
    return p.posix.joinAll(p.split(inside.replaceAll('\\', '/')));
  }

  /// The real file location of a saved picture path.
  String resolvePicturePath(String path) {
    if (path.isEmpty ||
        path.startsWith('data:') ||
        path.contains('://') ||
        !p.isRelative(path)) {
      return path;
    }
    return p.joinAll([root.path, ...p.posix.split(path)]);
  }

  static Future<AppStorage> instance() async {
    if (_instance != null) return _instance!;
    final Directory root;
    if (Platform.isAndroid || Platform.isIOS) {
      final base = await getApplicationSupportDirectory();
      root = Directory(p.join(base.path, 'data'));
    } else {
      final home = Platform.environment['USERPROFILE'] ??
          Platform.environment['HOME'] ??
          '.';
      root = Directory(p.join(home, '.aac_studio'));
    }
    return _instance = current = await at(root);
  }

  File packFile(String id) => File(p.join(packsDir.path, '$id.json'));
  File get settingsFile => File(p.join(root.path, 'settings.json'));
  File get learnedFile => File(p.join(root.path, 'learned_words.json'));

  File _previous(File f) => File('${f.path}.prev');

  /// Saves [json] atomically. The data is encoded immediately, so later
  /// changes to the same objects cannot alter what this call writes.
  Future<void> writeJson(File f, Object json) {
    final text = const JsonEncoder.withIndent('  ').convert(json);
    final earlier = _writes[f.path] ?? Future.value();
    final next = earlier.catchError((_) {}).then((_) => _replace(f, text));
    _writes[f.path] = next;
    return next;
  }

  Future<void> _replace(File f, String text) async {
    await f.parent.create(recursive: true);
    final temporary = File('${f.path}.tmp');
    await temporary.writeAsString(text, flush: true);
    if (await f.exists()) {
      try {
        await f.copy(_previous(f).path);
      } catch (_) {/* The new save still replaces the file atomically. */}
    }
    await temporary.rename(f.path);
  }

  /// Waits for every pending save (tests, backup export).
  Future<void> flush() async {
    for (final pending in List.of(_writes.values)) {
      try {
        await pending;
      } catch (_) {}
    }
  }

  /// Reads [f], falling back to its previous good copy when the file is
  /// missing or damaged. Returns null when neither can be read.
  Future<Map<String, dynamic>?> readJson(File f) async {
    for (final candidate in [f, _previous(f)]) {
      if (!await candidate.exists()) continue;
      try {
        return jsonDecode(await candidate.readAsString())
            as Map<String, dynamic>;
      } catch (_) {/* Try the previous copy. */}
    }
    return null;
  }
}
