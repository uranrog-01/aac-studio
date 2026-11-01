import 'package:flutter_test/flutter_test.dart';

import 'package:aac_studio/data/pack_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('sample pack loads into a valid vocabulary', () async {
    final v = await PackLoader().loadFile('assets/sample_pack.json');
    expect(v.folders.containsKey(v.rootFolderId), isTrue);
    expect(v.viewsByFolder[v.rootFolderId], isNotEmpty);
    final home = v.viewsByFolder[v.rootFolderId]!.first;
    expect(home.cells, isNotEmpty);
    for (final c in home.cells) {
      expect(c.button.label, isNotEmpty);
    }
  });
}
