import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/pack_upgrade.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// v11: a word library of thousands of words in clear categories.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final file = File(utf8.decode(message!.buffer.asUint8List()));
    if (!await file.exists()) return null;
    return ByteData.sublistView(await file.readAsBytes());
  });
  Map<String, dynamic> read(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  test('the board has thousands of words and categories are grouped by topic',
      () {
    final pack = read('assets/sample_pack.json');
    final buttons = {for (final b in pack['buttons']) b['id']: b};
    final words = buttons.values.where((b) => b['kind'] == 'item').length;
    expect(words, greaterThanOrEqualTo(3000));
    final views = pack['views'] as Map<String, dynamic>;
    final all = [
      for (final c in (views['allcats'] as List).first['cells'])
        buttons[c['btn']]
    ];
    final targets = {
      for (final b in all)
        for (final a in b['actions'] as List) a['data']
    };
    expect(targets, containsAll(views.keys.where((k) => k != 'home' && k != 'allcats')));
    // v13: grouped by topic (people, food, body, home, play, places,
    // school, animals, words). A to Z by the English name meant nothing
    // in the other languages.
    final labels = [for (final b in all) b['label'] as String];
    expect(labels.first, 'People');
    expect(labels.indexOf('Meals'), labels.indexOf('Eat & drink') + 1);
    expect(labels.indexOf('Wild animals'), labels.indexOf('Animals') + 1);
    final home = [
      for (final c in (views['home'] as List).first['cells'])
        buttons[c['btn']]['label']
    ];
    expect(home, contains('All categories'));
    // Home starts with what is needed most; the first screen answers
    // "what do you want / need / feel".
    expect(home.take(15), containsAll(['I', 'want', 'more', 'help', 'stop',
        'yes', 'no', 'eat', 'drink', 'water', 'toilet', 'sleep']));
    expect(home, containsAll(['hurt', 'happy', 'sad', 'mom', 'dad', 'break']));
    // Categories that left Home are one tap inside a related category.
    List<String> page(String id) => [
          for (final c in (views[id] as List).first['cells'])
            buttons[c['btn']]['label'] as String
        ];
    expect(page('people'), containsAll(['Chat', 'Questions']));
    expect(page('actions'), contains('Describing words'));
    expect(page('routines'), containsAll(['Clothes', 'Time']));
  });

  test('library labels are clean words', () {
    final pack = read('assets/sample_pack.json');
    for (final b in pack['buttons'] as List) {
      if (!(b['id'] as String).startsWith('v11_')) continue;
      final label = b['label'] as String;
      expect(label, isNot(matches(RegExp(r' , |\s\d+[a-z]?$|  '))),
          reason: b['id']);
      expect(b['symbolKey'],
          isNot(matches(RegExp(r'-(light|medium-light|medium|medium-dark|dark)$'))),
          reason: '${b['id']}: skin tone copy');
    }
  });

  test('an installed v10 board gets the library and keeps its own order', () {
    final v10 = read('test/fixtures/sample_pack_v10.json');
    final fresh = read('assets/sample_pack.json');
    final history = read('assets/factory_symbol_history.json');
    final edited = (v10['buttons'] as List).firstWhere((b) => b['id'] == 'b5');
    edited['label'] = 'I want';
    edited['userEdited'] = true;
    final merged = PackUpgrade.merge(v10, fresh, factorySymbolHistory: history);
    List<String> ids(Map<String, dynamic> pack, String page) => [
          for (final c in (pack['views'][page] as List).first['cells'] as List)
            c['btn'] as String
        ];
    for (final page in ['food', 'actions', 'jobs', 'allcats']) {
      expect(ids(merged, page), ids(fresh, page), reason: page);
    }
    // Home keeps the person's own order; the new words are added to it.
    final before = ids(v10, 'home');
    expect(ids(merged, 'home').where(before.contains).toList(), before);
    expect(ids(merged, 'home'), containsAll(ids(fresh, 'home')));
    final buttons = {for (final b in merged['buttons'] as List) b['id']: b};
    expect(buttons['b5']['label'], 'I want');
    final v = PackLoader().loadString(jsonEncode(merged));
    expect(v.viewsByFolder['questions']!.first.cells.map((c) => c.button.label),
        containsAll(['what', 'where', 'why']));
  });

  test('an old cached board file during an update cannot skip the upgrade',
      () async {
    final temp = Directory.systemTemp.createTempSync('aac_v11_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final storage = await AppStorage.at(temp);
    final file = storage.packFile('sample_pack');
    await storage.writeJson(file, read('test/fixtures/sample_pack_v10.json'));

    // The new app meets the previous board file (e.g. from a cache) and
    // the person edits the board: it must stay marked as v10.
    final stale = PackController(storage);
    await stale.load(assetPath: 'test/fixtures/sample_pack_v10.json');
    await stale.save();
    expect((await storage.readJson(file))!['packVersion'], 10);

    // With the real v11 board file the upgrade still happens.
    final current = PackController(storage);
    await current.load();
    final saved = (await storage.readJson(file))!;
    expect(saved['packVersion'], 14);
    expect((saved['buttons'] as List).length, greaterThan(3000));
    await current.save();
    expect((await storage.readJson(file))!['packVersion'], 14);
  });
}
