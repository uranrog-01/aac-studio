import 'dart:convert';
import 'package:http/http.dart' as http;
import 'storage.dart';

class ArasaacService {
  final AppStorage storage;
  ArasaacService(this.storage);
  static const _base = 'https://api.arasaac.org/api';

  Future<List<({int id, String name})>> search(String text) async {
    final response = await http
        .get(Uri.parse(
            '$_base/pictograms/en/search/${Uri.encodeComponent(text)}'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return const [];
    return [
      for (final entry in jsonDecode(response.body) as List)
        (
          id: (entry['_id'] as num).toInt(),
          name: (entry['keywords'] as List?)?.isNotEmpty == true
              ? '${entry['keywords'][0]['keyword']}'
              : 'pictogram ${entry['_id']}'
        )
    ];
  }

  Future<String?> cachePictogram(int id, {int skin = 0, int hair = 0}) async {
    try {
      final response = await http
          .get(Uri.parse(pictogramUrl(id, skin: skin, hair: hair)))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;
      // Persist the image with the board so it survives an offline relaunch.
      return 'data:image/png;base64,${base64Encode(response.bodyBytes)}';
    } catch (_) {
      return null;
    }
  }

  static String pictogramUrl(int id, {int skin = 0, int hair = 0}) =>
      '$_base/pictograms/$id/${id}_500.png${skin > 0 || hair > 0 ? '?${[
          if (skin > 0) 'skin=$skin',
          if (hair > 0) 'hair=$hair'
        ].join('&')}' : ''}';
}
