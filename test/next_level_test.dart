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

/// Phrases, Show big, full screen and speech into phone/FaceTime calls.
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

  Future<(GridSession, SettingsController)> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
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

  testWidgets('Show big: large message, turn around, speak', (tester) async {
    final (session, _) = await pump(tester);
    session.setMessageLive('I want water');
    session.toggleKeyboard();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Show big'));
    await tester.pumpAndSettle();
    expect(find.text('I want water'), findsOneWidget);
    expect(find.byType(RotatedBox), findsOneWidget);
    await tester.tap(find.text('Turn around'));
    await tester.pump();
    expect(tester.widget<RotatedBox>(find.byType(RotatedBox)).quarterTurns, 2);
    await tester.tap(find.text('I want water'));
    await tester.pump();
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    expect(tts, contains('I want water'));
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Turn around'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
