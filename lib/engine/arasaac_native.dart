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
    if (await f.exists()) {
      try {
        _cacheIndex =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      } catch (_) {}
    }
    _cacheIndex ??= {};
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
  Future<String?> cachePictogram(int id, {int skin = 0, int hair = 0}) async {
    var url = '$_base/pictograms/$id/${id}_500.png';
    final params = <String>[];
    if (skin > 0) params.add('skin=$skin');
    if (hair > 0) params.add('hair=$hair');
    if (params.isNotEmpty) url = '$url?${params.join('&')}';

    final idx = await _index();
    final hit = idx[url] as Map<String, dynamic>?;
    if (hit != null) {
      final f = File(hit['file'] as String);
      if (await f.exists()) {
        hit['lastUsed'] = DateTime.now().millisecondsSinceEpoch;
        await _saveIndex();
        return f.path;
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
      await res.pipe(file.openWrite());
      idx[url] = {
        'file': file.path,
        'lastUsed': DateTime.now().millisecondsSinceEpoch,
        'size': await file.length(),
      };
      await _evict(idx);
      await _saveIndex();
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// LRU eviction: keep total under 200MB (Cboard's 250MB/quota concept).
  Future<void> _evict(Map<String, dynamic> idx) async {
    const cap = 200 * 1024 * 1024;
    var total = 0;
    final entries = <MapEntry<String, Map<String, dynamic>>>[];
    for (final e in idx.entries) {
      final m = e.value as Map<String, dynamic>;
      total += (m['size'] as num?)?.toInt() ?? 0;
      entries.add(MapEntry(e.key, m));
    }
    if (total <= cap) return;
    entries.sort((a, b) =>
        (a.value['lastUsed'] as num).compareTo(b.value['lastUsed'] as num));
    for (final e in entries) {
      if (total <= cap) break;
      try {
        await File(e.value['file'] as String).delete();
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
