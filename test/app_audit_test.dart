import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/arasaac.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/symbol_library.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/features/grid/keyboard_view.dart';
import 'package:aac_studio/features/library/symbol_browser.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class DelayedPictures extends ArasaacService {
  DelayedPictures(super.storage);
  final requests = <String, Completer<List<({int id, String name})>>>{};
  @override
  Future<List<({int id, String name})>> search(String text) {
    final request = Completer<List<({int id, String name})>>();
    requests[text] = request;
    return request.future;
  }
}

class MemoryWords implements AppStorageProvider {
  Map<String, int> words;
  MemoryWords(this.words);
  @override
  Future<Map<String, int>> readLearned() async => Map.of(words);
  @override
  Future<void> writeLearned(Map<String, int> words) async =>
      this.words = Map.of(words);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prediction refreshes after learning/restoring and respects the limit',
      () async {
    final storage = MemoryWords({'cat': 1, 'car': 2, 'castle': 1});
    final predictor = Predictor();
    await predictor.loadLearned(storage);
    expect(predictor.suggest('ca', limit: 1), ['car']);
    expect(predictor.suggest('ca', limit: 3).length, 3);
    await predictor.learnFrom('cat', storage);
    await predictor.learnFrom('cat', storage);
    expect(predictor.suggest('ca').first, 'cat');
    storage.words = {'carry': 8};
    await predictor.loadLearned(storage);
    expect(predictor.suggest('ca'), ['carry']);
    expect(predictor.suggest('ca', limit: 0), isEmpty);
  });

  test('deleted factory buttons stay deleted through save, reload and upgrade',
      () {
    final raw = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
        as Map<String, dynamic>;
    final loader = PackLoader();
    final vocabulary = loader.loadString(jsonEncode(raw));
    final session = GridSession(vocabulary: vocabulary, speech: SpeechEngine());
    final id = vocabulary.viewsByFolder['home']!.first.cells.first.button.id;
    session.removeButton(id);
    final saved = loader.save(vocabulary);
    expect(saved['removedIds'], contains(id));
    final reloaded = loader.loadString(jsonEncode(saved));
    expect(reloaded.removedIds, contains(id));
    final merged = PackUpgrade.merge(loader.save(reloaded), raw);
    expect(
        (merged['buttons'] as List).any((button) => button['id'] == id), false);
    for (final views in (merged['views'] as Map).values) {
      for (final view in views as List) {
        expect((view['cells'] as List).any((cell) => cell['btn'] == id), false);
      }
    }
  });

  test('editing a shared button survives save/reload in every view', () {
    final original = VocabButton(
        id: 'shared',
        wordClass: WordClass.noun,
        kind: ButtonKind.item,
        label: 'Before',
        symbol: const SymbolRef('a'),
        actions: const []);
    final vocabulary = Vocabulary(
        id: 'test',
        label: 'Test',
        rootFolderId: 'home',
        folders: const {
          'home': VocabFolder('home', 'Home', SymbolRef('a'))
        },
        viewsByFolder: {
          'home': [
            VocabView(
                id: 'one',
                folderId: 'home',
                columns: 4,
                cells: [GridCell(original, hidden: true)]),
            VocabView(
                id: 'two',
                folderId: 'home',
                columns: 6,
                cells: [GridCell(original, dimmed: true)]),
          ]
        });
    GridSession(vocabulary: vocabulary, speech: SpeechEngine())
        .replaceButton(original.copyWith(label: 'After'));
    final loader = PackLoader();
    final saved = loader.save(vocabulary);
    expect((saved['buttons'] as List).length, 1);
    final restored = loader.loadString(jsonEncode(saved));
    expect(
        restored.viewsByFolder['home']!.map((v) => v.cells.single.button.label),
        everyElement('After'));
    expect(restored.viewsByFolder['home']![0].cells.single.hidden, true);
    expect(restored.viewsByFolder['home']![1].cells.single.dimmed, true);
  });

  testWidgets('Shift and completion replace a whole word', (tester) async {
    final predictor = Predictor();
    await predictor.loadLearned(MemoryWords({'hello': 5}));
    var text = '';
    await tester.pumpWidget(MaterialApp(
        home: KeyboardView(
            predictor: predictor,
            speech: SpeechEngine(),
            onTextChanged: (value) => text = value,
            onClose: () {},
            onSpeak: () {})));
    await tester.tap(find.bySemanticsLabel('h'));
    await tester.tap(find.bySemanticsLabel('e'));
    await tester.pump();
    await tester.tap(find.text('hello'));
    await tester.pump();
    expect(text, 'hello ');
    await tester.tap(find.bySemanticsLabel('Shift'));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('I'));
    await tester.pump();
    expect(text, 'hello I');
    expect(find.bySemanticsLabel('i'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Space'));
    await tester.tap(find.bySemanticsLabel('w'));
    await tester.pump();
    expect(text, 'hello I w');
    expect(tester.takeException(), isNull);
  });

  testWidgets('online picture results cannot replace a newer or cleared query',
      (tester) async {
    final storage = await tester.runAsync(AppStorage.instance);
    final pictures = DelayedPictures(storage!);
    final settings = SettingsController(storage)..settings = AppSettings();
    await tester.pumpWidget(MultiProvider(providers: [
      Provider<SymbolLibrary>.value(value: SymbolLibrary()),
      Provider<ArasaacService>.value(value: pictures),
      ChangeNotifierProvider<SettingsController>.value(value: settings),
    ], child: const MaterialApp(home: SymbolBrowser())));
    await tester.enterText(find.byType(TextField), 'cat');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'dog');
    await tester.pump(const Duration(milliseconds: 400));
    pictures.requests['dog']!.complete([(id: 2, name: 'New dog result')]);
    await tester.pump();
    pictures.requests['cat']!.complete([(id: 1, name: 'Stale cat result')]);
    await tester.pump();
    expect(find.text('New dog result'), findsOneWidget);
    expect(find.text('Stale cat result'), findsNothing);
    await tester.enterText(find.byType(TextField), 'horse');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '');
    pictures.requests['horse']!.complete([(id: 3, name: 'Stale horse result')]);
    await tester.pump();
    expect(find.text('New dog result'), findsNothing);
    expect(find.text('Stale horse result'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
