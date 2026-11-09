import 'dart:convert';
import 'dart:js_interop';

@JS('aacStorage.read')
external JSPromise<JSAny?> _read(JSString key);
@JS('aacStorage.write')
external JSPromise<JSAny?> _write(JSString key, JSString value);

/// JSON files are separate IndexedDB records; images can remain data URLs
/// inside a board without running into localStorage's small text quota.
class BrowserStorageFile {
  final String path;
  BrowserStorageFile(this.path);

  Future<bool> exists() async => await _read(path.toJS).toDart != null;
  Future<String> readAsString() async {
    final result = await _read(path.toJS).toDart;
    if (result == null) throw StateError('Saved data not found: $path');
    return (result as JSString).toDart;
  }

  Future<void> writeAsString(String value) async {
    await _write(path.toJS, value.toJS).toDart;
  }

  Future<void> copy(String destination) async =>
      BrowserStorageFile(destination).writeAsString(await readAsString());
}

class AppStorage {
  AppStorage._();
  static final _instance = AppStorage._();
  static Future<AppStorage> instance() async => _instance;

  BrowserStorageFile packFile(String id) =>
      BrowserStorageFile('packs/$id.json');
  BrowserStorageFile get settingsFile => BrowserStorageFile('settings.json');
  BrowserStorageFile get learnedFile =>
      BrowserStorageFile('learned_words.json');

  // Browser boards keep pictures as data URLs; paths need no rewriting.
  String storedPicturePath(String path) => path;
  String resolvePicturePath(String path) => path;

  // IndexedDB replaces a record atomically; saves to one key stay in order.
  final Map<String, Future<void>> _writes = {};
  Future<void> writeJson(BrowserStorageFile file, Object json) {
    final text = jsonEncode(json);
    final earlier = _writes[file.path] ?? Future.value();
    final next =
        earlier.catchError((_) {}).then((_) => file.writeAsString(text));
    _writes[file.path] = next;
    return next;
  }

  Future<void> flush() async {
    for (final pending in List.of(_writes.values)) {
      try {
        await pending;
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> readJson(BrowserStorageFile file) async {
    if (!await file.exists()) return null;
    // Let invalid JSON/storage failures surface instead of replacing user edits.
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }
}
