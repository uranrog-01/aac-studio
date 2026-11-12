import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Phrases, Show Message, full screen and speech into phone/FaceTime calls.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tts = <String>[];
  final calls = <MethodCall>[];
  setUp(() {
    tts.clear();
    calls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async {
      if (call.method == 'speak') tts.add(call.arguments as String);
      return call.method == 'isLanguageAvailable' ? true : 1;
    });
    messenger.setMockMethodCallHandler(const MethodChannel('aac/call_speech'),
        (call) async {
      calls.add(call);
      return 1;
    });
  });

  test('new settings are saved; full screen is on by default', () {
    final s = AppSettings();
    expect(s.fullScreen, isTrue);
    expect(s.callSpeech, isFalse);
    s
      ..fullScreen = false
      ..callSpeech = true
      ..phrases.add('My name is Ana');
    final back = AppSettings.fromJson(s.toJson());
    expect(back.fullScreen, isFalse);
    expect(back.callSpeech, isTrue);
    expect(back.phrases, ['My name is Ana']);
  });

  test('iPhone: speech goes into calls when turned on', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final engine = SpeechEngine();
    engine.configure(AppSettings()
      ..usePiper = false
      ..callSpeech = true);
    await engine.speak('hello');
    expect(calls.single.method, 'speak');
    expect((calls.single.arguments as Map)['text'], 'hello');
    expect(tts, isEmpty, reason: 'the call-capable voice spoke instead');

    engine.configure(AppSettings()
      ..usePiper = false
      ..callSpeech = false);
    await engine.speak('bye');
    expect(tts, ['bye']);
  });

  test('Android never uses the iPhone call voice', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final engine = SpeechEngine();
    engine.configure(AppSettings()
      ..usePiper = false
      ..callSpeech = true);
    await engine.speak('hello');
    expect(calls, isEmpty);
    expect(tts, ['hello']);
  });

  Future<(GridSession, SettingsController)> pump(WidgetTester tester,
      {Size size = const Size(430, 932)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('aac_next_');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {/* a settings save may still hold the file */}
    });
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
            home: GridScreen(
                session: session, maxColumns: 5, predictor: Predictor()))));
    return (session, settings);
  }

  testWidgets('Type: save a phrase, use it again, recent messages',
      (tester) async {
    final (session, settings) = await pump(tester);
    session.setMessageLive('I need a break');
    session.speakMessage();
    session.toggleKeyboard();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Phrases'));
    await tester.pumpAndSettle();
    expect(find.text('Recent messages'), findsOneWidget);
    await tester.tap(find.text('Save this message'));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    expect(settings.settings.phrases, ['I need a break']);

    // Pick the saved phrase: it is added to the message and spoken.
    await tester.tap(find.text('I need a break').first);
    await tester.pumpAndSettle();
    expect(session.message, 'I need a break I need a break');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Show Message on the board replays and keeps the draft and folder',
      (tester) async {
    final (session, settings) = await pump(tester, size: const Size(375, 667));
    final show = find.widgetWithText(TextButton, 'Show');
    expect(tester.widget<TextButton>(show).onPressed, isNull);
    await tester.tap(show);
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsNothing);

    settings.settings
      ..usePiper = false
      ..clearOnSpeak = true
      ..goHomeOnPress = true;
    session.speech.configure(settings.settings);
    final folder = session.vocabulary.folders.keys
        .firstWhere((id) => id != session.currentFolderId);
    const phrase = 'I want water';
    session.pushFolder(folder);
    session.setMessageLive(phrase);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Show message'));
    await tester.pumpAndSettle();
    final message = find.text(phrase);
    expect(message, findsOneWidget);
    expect(tester.widget<Text>(message).style!.fontSize, greaterThan(40));
    expect(find.byType(FilledButton), findsNWidgets(2));
    await tester.tap(message);
    await tester.pump();
    expect(tts, isEmpty);

    for (var tap = 0; tap < 2; tap++) {
      await tester.tap(find.widgetWithText(FilledButton, 'Speak'));
      await tester.pump();
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    }
    expect(tts, [phrase, phrase]);
    expect(session.recentMessages, [phrase]);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(show, findsOneWidget);
    expect(session.message, phrase);
    expect(session.currentFolderId, folder);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Show Message from Type scrolls while keeping controls visible',
      (tester) async {
    final (session, _) = await pump(tester, size: const Size(375, 667));
    session.toggleKeyboard();
    await tester.pump();
    final show = find.widgetWithText(TextButton, 'Show');
    expect(tester.widget<TextButton>(show).onPressed, isNull);

    final phrase = List.filled(8,
            'Please call my family. I need a quiet place to sit and some water.')
        .join(' ');
    session.setMessageLive(phrase);
    await tester.pump();
    await tester.tap(show);
    await tester.pumpAndSettle();
    expect(find.text(phrase), findsOneWidget);
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    await tester.drag(
        find.byType(SingleChildScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, greaterThan(0));

    tester.view.physicalSize = const Size(667, 375);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Speak').hitTestable(),
        findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(show, findsOneWidget);
    expect(session.showKeyboard, isTrue);
    expect(session.message, phrase);
    expect(tester.takeException(), isNull);
  });
}
