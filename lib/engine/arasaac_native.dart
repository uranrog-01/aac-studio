import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'storage.dart';

/// P2: ARASAAC online pictogram search + skin/hair variants, with an LRU
/// disk cache (Cboard's proven design: quota cap, lastUsed eviction).
class ArasaacService {
  static const _base = 'https://api.arasaac.org/api';
  final AppStorage storage;
  final HttpClient _http = HttpClient();
  Map<String, dynamic>? _cacheIndex; // url -> {file, lastUsed, size}

  ArasaacService(this.storage);

  Future<Map<String, dynamic>> _index() async {
    if (_cacheIndex != null) return _cacheIndex!;
    final f = File(p.join(storage.root.path, 'imgcache.json'));
    _cacheIndex = await storage.readJson(f) ?? {};
    // Older versions saved full paths, which break when iOS moves the
    // app's data folder; keep them relative instead.
    for (final entry in _cacheIndex!.values) {
      if (entry is Map && entry['file'] is String) {
        entry['file'] = storage.storedPicturePath(entry['file'] as String);
      }
    }
    return _cacheIndex!;
  }

  Future<void> _saveIndex() async {
    final f = File(p.join(storage.root.path, 'imgcache.json'));
    await storage.writeJson(f, _cacheIndex ?? {});
  }

  Future<List<({int id, String name})>> search(String text) async {
    final url = '$_base/pictograms/en/search/${Uri.encodeComponent(text)}';
    final req = await _http.getUrl(Uri.parse(url));
    final res = await req.close();
    if (res.statusCode != 200) return const [];
    final body = await res.transform(utf8.decoder).join();
    final list = jsonDecode(body) as List;
    final out = <({int id, String name})>[];
    for (final e in list) {
      final id = (e['_id'] as num).toInt();
      final kws = (e['keywords'] as List?) ?? const [];
      String name = 'pictogram $id';
      if (kws.isNotEmpty) {
        final k0 = kws.first as Map<String, dynamic>;
        name = (k0['keyword'] ?? name) as String;
      }
      out.add((id: id, name: name));
    }
    return out;
  }

  /// Downloads (or returns cached) pictogram PNG honoring skin/hair params.
  /// skin: 0 none, 1 white, 2 black, 3 Asian; hair: 0 none,1 blond,2 brown,3 dark,4 red,5 gray
  ///
  /// Returns the picture's saved path (relative to the app's storage, see
  /// [AppStorage.storedPicturePath]); draw it with `referenceImage`.
  Future<String?> cachePictogram(int id, {int skin = 0, int hair = 0}) async {
    final url = pictogramUrl(id, skin: skin, hair: hair);
    final idx = await _index();
    final hit = idx[url] as Map<String, dynamic>?;
    if (hit != null) {
      final stored = hit['file'] as String;
      if (await File(storage.resolvePicturePath(stored)).exists()) {
        hit['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
        await _saveIndex();
        return stored;
      }
    }
    try {
      final req = await _http.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final dir = Directory(p.join(storage.root.path, 'imgcache'));
      await dir.create(recursive: true);
      final file = File(p.join(
          dir.path,
          'arasaac_$id'
          '${skin > 0 ? "_s$skin" : ""}${hair > 0 ? "_h$hair" : ""}.png'));
      // Download to a temporary file first: a dropped connection must not
      // leave a broken picture that later looks cached.
      final partial = File('${file.path}.part');
      await res.pipe(partial.openWrite());
      await partial.rename(file.path);
      final stored = storage.storedPicturePath(file.path);
      idx[url] = {
        'file': stored,
        'lastUsed': DateTime.now().millisecondsSinceEpoch,
        'size': await file.length(),
      };
      await evict(idx);
      await _saveIndex();
      return stored;
    } catch (_) {
      return null;
    }
  }

  /// Saved paths of every picture the board currently uses.
  /// Null when the board cannot be read.
  Future<Set<String>?> _picturesOnBoard() async {
    final inUse = <String>{};
    try {
      final pack = await storage.readJson(storage.packFile('sample_pack'));
      if (pack == null) return null;
      for (final item in [
        ...(pack['buttons'] as List? ?? const []),
        ...(pack['folders'] as List? ?? const []),
      ]) {
        final path = item is Map ? item['imagePath'] : null;
        if (path is String) inUse.add(storage.storedPicturePath(path));
      }
    } catch (_) {
      return null;
    }
    return inUse;
  }

  /// LRU eviction: keep total under 200MB (Cboard's 250MB/quota concept).
  /// Pictures used on the board are never removed: deleting one would leave
  /// a blank button the person relies on.
  Future<void> evict(Map<String, dynamic> idx,
      {int cap = 200 * 1024 * 1024}) async {
    var total = 0;
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final e in idx.entries) {
      final m = e.value as Map<String, dynamic>;
      total += (m['size'] as num?)?.toInt() ?? 0;
      entries.add(MapEntry(e.key, m));
    }
    if (total <= cap) return;
    final inUse = await _picturesOnBoard();
    if (inUse == null) return; // board unreadable: evict nothing, never guess
    entries.sort((a, b) =>
        (a.value['lastUsed'] as num).compareTo(b.value['lastUsed'] as num));
    for (final e in entries) {
      if (total <= cap) break;
      final stored = e.value['file'] as String;
      if (inUse.contains(stored)) continue;
      try {
        await File(storage.resolvePicturePath(stored)).delete();
      } catch (_) {}
      total -= (e.value['size'] as num?)?.toInt() ?? 0;
      idx.remove(e.key);
    }
  }

  /// ARASAAC pictogram image URL (for previews).
  static String pictogramUrl(int id, {int skin = 0, int hair = 0}) {
    var url = '$_base/pictograms/$id/${id}_500.png';
    final params = <String>[];
    if (skin > 0) params.add('skin=$skin');
    if (hair > 0) params.add('hair=$hair');
    if (params.isNotEmpty) url = '$url?${params.join('&')}';
    return url;
  }
}
