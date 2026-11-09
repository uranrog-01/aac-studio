import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/i18n.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/features/grid/keyboard_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Albanian, French, German, Spanish, Italian, Chinese, Japanese, Hindi.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final file = File(utf8.decode(message!.buffer.asUint8List()));
    if (!await file.exists()) return null;
    return ByteData.sublistView(await file.readAsBytes());
  });
  final spoken = <String>[];
  final languages = <String>[];
  setUp(() {
    spoken.clear();
    languages.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      if (call.method == 'setLanguage') languages.add(call.arguments as String);
      return call.method == 'isLanguageAvailable' ? true : 1;
    });
  });
  tearDown(() => I18n.load('en'));

  test('every language translates all app text and all core words', () {
    final pack = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
        as Map<String, dynamic>;
    final core = {
      for (final b in pack['buttons'] as List)
        if (!(b['id'] as String).startsWith('v11_')) b['label'] as String,
      for (final f in pack['folders'] as List) f['label'] as String,
    }.where((l) => l.length > 1 && int.tryParse(l) == null).toSet();
    final ui = (jsonDecode(File('assets/i18n/fr.json').readAsStringSync())
            as Map)['ui']
        .keys
        .toSet();
    for (final lang in kLanguages.where((l) => l.code != 'en')) {
      final data = jsonDecode(
              File('assets/i18n/${lang.code}.json').readAsStringSync())
          as Map<String, dynamic>;
      final words = (data['words'] as Map).keys.toSet();
      expect(core.where((l) => !words.contains(l.toLowerCase())), isEmpty,
          reason: '${lang.name}: core words missing');
      expect((data['ui'] as Map).keys.toSet(), ui,
          reason: '${lang.name}: app text');
    }
  });

  test('words show and speak in the language; the board stays English',
      () async {
    await I18n.load('fr');
    final v = PackLoader()
        .loadString(File('assets/sample_pack.json').readAsStringSync());
    final session = GridSession(vocabulary: v, speech: SpeechEngine());
    final want = v.viewsByFolder['home']!.first.cells
        .firstWhere((c) => c.button.label == 'want')
        .button;
    expect(want.shownLabel, 'vouloir');
    final pronoun = v.viewsByFolder['home']!.first.cells.first.button;
    expect(pronoun.shownLabel, 'je');
    final letterI = v.viewsByFolder['alphabet']!.first.cells
        .firstWhere((c) => c.button.label == 'I')
        .button;
    expect(letterI.shownLabel, 'I', reason: 'letters are never translated');
    session.tap(want);
    expect(session.message, 'vouloir');
    expect(PackLoader().save(v).toString(), contains("label: want"),
        reason: 'saved board keeps English');
    expect(session.findWords('pomme').first.button.label, 'apple');
    expect(session.findWords('apple').first.button.shownLabel, 'pomme');
    await I18n.load('en');
    expect(want.shownLabel, 'want');
  });

  test('the device voice switches to the language', () async {
    final engine = SpeechEngine();
    engine.configure(AppSettings()..language = 'de');
    await engine.speak('Hallo');
    expect(languages.last, 'de-DE');
    expect(spoken, ['Hallo']);
    expect(AppSettings.fromJson((AppSettings()..language = 'ja').toJson())
        .language, 'ja');
  });

  testWidgets('the toolbar and message bar change language', (tester) async {
    await tester.runAsync(() => I18n.load('es'));
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('aac_lang_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final storage = await tester.runAsync(() => AppStorage.at(temp));
    final settings = SettingsController(storage!)..settings = AppSettings();
    final session = GridSession(
        vocabulary: PackLoader()
            .loadString(File('assets/sample_pack.json').readAsStringSync()),
        speech: SpeechEngine());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: GridScreen(session: session, maxColumns: 5))));
    expect(find.text('Hablar'), findsOneWidget);
    expect(find.text('Toca los símbolos para formar un mensaje'), findsOneWidget);
    expect(find.text('quiero'), findsOneWidget);
    await tester.runAsync(() => I18n.load('en'));
  });

  testWidgets('Chinese types with the device keyboard; French has accents',
      (tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var text = '';
    Widget keyboard() => MaterialApp(
        home: KeyboardView(
            predictor: Predictor(),
            speech: SpeechEngine(),
            onTextChanged: (v) => text = v,
            onClose: () {},
            onSpeak: () {}));

    await tester.runAsync(() => I18n.load('zh'));
    await tester.pumpWidget(keyboard());
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '我要水');
    await tester.tap(find.bySemanticsLabel('Add to message'));
    await tester.pump();
    expect(text, '我要水 ');
    expect(spoken, contains('我要水'));

    await tester.runAsync(() => I18n.load('fr'));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(keyboard());
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.bySemanticsLabel('é'));
    await tester.pump();
    expect(text, 'é');
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => I18n.load('en'));
  });
}
