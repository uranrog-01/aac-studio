import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// "Find a word": any of the board's thousands of words in a few letters.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async => call.method == 'isLanguageAvailable' ? true : 1);

  GridSession session() => GridSession(
      vocabulary: PackLoader()
          .loadString(File('assets/sample_pack.json').readAsStringSync()),
      speech: SpeechEngine());

  test('exact words first, then words that start with the letters', () {
    final s = session();
    expect(s.findWords(''), isEmpty);
    final apple = s.findWords('apple');
    expect(apple.first.button.label, 'apple');
    expect(apple.first.folderId, 'food', reason: 'the page nearest Home');
    final app = s.findWords('app').map((r) => r.button.label).toList();
    expect(app.first, startsWith('app'));
    expect(app, contains('apple'));
    // One result per word even when it is on several pages.
    final eat = s.findWords('eat').where((r) => r.button.label == 'eat');
    expect(eat.length, 1);
    expect(eat.single.folderId, 'home');
    // Library words are found too, and categories by name.
    expect(s.findWords('crawl').map((r) => r.button.label), contains('crawl'));
    final animals = s.findWords('animals');
    expect(animals.any((r) => r.button.kind == ButtonKind.folder), isTrue);
    expect(s.findWords('zzzqx'), isEmpty);
  });

  Future<GridSession> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('aac_find_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final storage = await tester.runAsync(() => AppStorage.at(temp));
    final settings = SettingsController(storage!)..settings = AppSettings();
    final s = session();
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: GridScreen(session: s, maxColumns: 5))));
    return s;
  }

  testWidgets('Find adds a word from anywhere on the board', (tester) async {
    final s = await pump(tester);
    await tester.tap(find.bySemanticsLabel('Find'));
    await tester.pump();
    expect(s.showSearch, isTrue);
    await tester.enterText(find.byType(TextField), 'crawl');
    await tester.pump();
    expect(find.text('Actions'), findsWidgets, reason: 'where the word lives');
    await tester.tap(find.text('crawl').last);
    await tester.pump();
    expect(s.message, 'crawl');
    expect(s.showSearch, isTrue, reason: 'stays open for the next word');
    await tester.tap(find.bySemanticsLabel('Back'));
    await tester.pump();
    expect(s.showSearch, isFalse);
    expect(s.currentFolderId, 'home');
    expect(tester.takeException(), isNull);
  });

  testWidgets('a category result opens that category', (tester) async {
    final s = await pump(tester);
    await tester.tap(find.bySemanticsLabel('Find'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'reptiles');
    await tester.pump();
    await tester.tap(find.text('Reptiles & frogs').first);
    await tester.pump();
    expect(s.showSearch, isFalse);
    expect(s.currentFolderId, 'reptiles');
    expect(tester.takeException(), isNull);
  });
}
