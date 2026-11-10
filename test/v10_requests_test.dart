import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/pack_upgrade.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/features/grid/keyboard_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Requests from November 2026 testing: a delete-word button in the
/// message bar, speech while typing, and a larger, easier vocabulary.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final spoken = <String>[];
  setUp(() {
    spoken.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      return call.method == 'isLanguageAvailable' ? true : 1;
    });
  });

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('aac_v10_'));
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<GridSession> pumpGrid(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 1366);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vocabulary = PackLoader()
        .loadString(File('assets/sample_pack.json').readAsStringSync());
    final storage = await tester.runAsync(() => AppStorage.at(temp));
    final settings = SettingsController(storage!)..settings = AppSettings();
    final session = GridSession(vocabulary: vocabulary, speech: SpeechEngine());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: GridScreen(session: session, maxColumns: 6))));
    return session;
  }

  testWidgets('the message bar delete button removes the last symbol',
      (tester) async {
    final session = await pumpGrid(tester);
    final delete = find.bySemanticsLabel('Delete last word');
    expect(delete, findsOneWidget);
    await tester.tap(find.text('I'));
    await tester.tap(find.text('want'));
    await tester.scrollUntilVisible(find.text('thank you'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('thank you'));
    await tester.pump();
    expect(session.message, 'I want thank you');
    await tester.tap(delete);
    await tester.pump();
    expect(session.message, 'I want', reason: '"thank you" goes as one');
    await tester.tap(delete);
    await tester.tap(delete);
    await tester.pump();
    expect(session.message, isEmpty);
    await tester.tap(delete); // nothing left: no error
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('delete removes the last typed word when the message was typed', () {
    final session = GridSession(
        vocabulary: PackLoader()
            .loadString(File('assets/sample_pack.json').readAsStringSync()),
        speech: SpeechEngine());
    session.setMessageLive('I want juice ');
    session.removeLastWord();
    expect(session.message, 'I want');
  });

  Future<String> pumpKeyboard(WidgetTester tester, String mode) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var text = '';
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: KeyboardView(
            predictor: Predictor(),
            speech: SpeechEngine(),
            typingSpeech: mode,
            onTextChanged: (value) => text = value,
            onClose: () {},
            onSpeak: () {})));
    for (final key in ['h', 'i']) {
      await tester.tap(find.bySemanticsLabel(key));
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel('Space'));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    return text;
  }

  testWidgets('Type says each finished word', (tester) async {
    expect(await pumpKeyboard(tester, 'words'), 'hi ');
    expect(spoken, ['hi']);
  });

  testWidgets('Type can also say each letter', (tester) async {
    await pumpKeyboard(tester, 'letters');
    expect(spoken, ['h', 'i', 'hi'], reason: 'letters without "capital"');
  });

  testWidgets('Type stays quiet when speech while typing is off',
      (tester) async {
    await pumpKeyboard(tester, 'off');
    expect(spoken, isEmpty);
  });

  test('typing speech setting is saved and unknown values fall back', () {
    // Typing makes sound by default: each letter and each word.
    expect(AppSettings().typingSpeech, 'letters');
    final s = AppSettings()..typingSpeech = 'words';
    expect(AppSettings.fromJson(s.toJson()).typingSpeech, 'words');
    expect(AppSettings.fromJson({'typingSpeak': 'loud'}).typingSpeech,
        'letters');
    // The v10 default ('words' under the old name) does not keep typing
    // quiet after the update.
    expect(AppSettings.fromJson({'typingSpeech': 'words'}).typingSpeech,
        'letters');
  });

  test('an installed v9 board gets the new words in the new order', () {
    final v9 = jsonDecode(File('test/fixtures/sample_pack_v9.json')
        .readAsStringSync()) as Map<String, dynamic>;
    final fresh = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
        as Map<String, dynamic>;
    final history = jsonDecode(
            File('assets/factory_symbol_history.json').readAsStringSync())
        as Map<String, dynamic>;
    // The person renamed a word: the upgrade must keep it.
    final edited = (v9['buttons'] as List).firstWhere((b) => b['id'] == 'b9');
    edited['label'] = 'more please';
    edited['userEdited'] = true;
    final merged = PackUpgrade.merge(v9, fresh, factorySymbolHistory: history);
    List<String> ids(Map<String, dynamic> pack, String page) => [
          for (final c in (pack['views'][page] as List).first['cells'] as List)
            c['btn'] as String
        ];
    for (final page in ['home', 'food', 'people', 'drinks']) {
      expect(ids(merged, page), ids(fresh, page), reason: page);
    }
    final buttons = {for (final b in merged['buttons'] as List) b['id']: b};
    expect(buttons['b9']['label'], 'more please');
    final v = PackLoader().loadString(jsonEncode(merged));
    expect(v.viewsByFolder['drinks']!.first.cells, isNotEmpty);
  });

  testWidgets('typing after picture words starts a new word', (tester) async {
    var text = '';
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: KeyboardView(
            predictor: Predictor(),
            speech: SpeechEngine(),
            initialText: 'want it',
            onTextChanged: (value) => text = value,
            onClose: () {},
            onSpeak: () {})));
    await tester.tap(find.bySemanticsLabel('h'));
    await tester.tap(find.bySemanticsLabel('i'));
    await tester.pump();
    expect(text, 'want it hi');
  });

  testWidgets('a newly opened category starts at its top', (tester) async {
    final session = await pumpGrid(tester);
    final grid = find.byType(Scrollable).first;
    await tester.drag(grid, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(grid).position.pixels, greaterThan(0));
    session.pushFolder('actions');
    await tester.pump();
    await tester.pump();
    expect(tester.state<ScrollableState>(find.byType(Scrollable).first)
        .position.pixels, 0);
    expect(tester.takeException(), isNull);
  });
}
