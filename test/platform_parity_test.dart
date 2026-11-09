import 'dart:io';
import 'dart:ui' as ui;

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/photo_picker.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/symbol_library.dart';
import 'package:aac_studio/features/app/app_shell.dart';
import 'package:aac_studio/features/editor/editor_dialog.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Fixes from the cross-device review (iPhone/iPad, Android, web).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      calls.add(call);
      return call.method == 'isLanguageAvailable' ? true : 1;
    });
  });

  test('Android release builds can reach online pictures', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android.permission.INTERNET'));
  });

  test('typing speech cuts off the previous letter; picture taps queue',
      () async {
    final engine = SpeechEngine();
    await Future.wait([
      engine.speak('H', interrupt: true),
      engine.speak('I', interrupt: true),
    ]);
    final spoken = [
      for (final c in calls)
        if (c.method == 'speak') c.arguments
    ];
    expect(spoken, ['I'], reason: 'the older letter is dropped');
    expect(calls.any((c) => c.method == 'stop'), isTrue);
    calls.clear();
    await Future.wait([engine.speak('I'), engine.speak('want')]);
    expect([
      for (final c in calls)
        if (c.method == 'speak') c.arguments
    ], ['I', 'want'], reason: 'both picture words are heard');
  });

  test('photos are shrunk to at most 512 px, keeping their shape', () async {
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 1200, 800),
        ui.Paint()..color = const ui.Color(0xFF3366CC));
    final image = await recorder.endRecording().toImage(1200, 800);
    final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final small = await PhotoPicker.shrink(png);
    final codec = await ui.instantiateImageCodec(small);
    final frame = await codec.getNextFrame();
    expect(frame.image.width, 512);
    expect(frame.image.height, 341);
  });

  VocabButton starred() => const VocabButton(
      id: 'b1',
      label: 'I',
      kind: ButtonKind.item,
      wordClass: WordClass.pronoun,
      symbol: SymbolRef('🙋'),
      actions: [VocabAction(ActionKind.addText)],
      favorite: true);

  Future<void> openEditor(WidgetTester tester,
      {required void Function(VocabButton) onSave,
      required VoidCallback onDelete}) async {
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () => ButtonEditorDialog.show(context,
                    library: SymbolLibrary(),
                    existing: starred(),
                    onSave: onSave,
                    onDelete: onDelete),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('editing a button keeps its star', (tester) async {
    VocabButton? saved;
    await openEditor(tester, onSave: (b) => saved = b, onDelete: () {});
    await tester.enterText(find.byType(TextField).first, 'me');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved!.label, 'me');
    expect(saved!.favorite, isTrue);
  });

  testWidgets('delete asks first, then closes the editor', (tester) async {
    var deleted = 0;
    await openEditor(tester, onSave: (_) {}, onDelete: () => deleted++);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete "I"?'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    expect(deleted, 0);
    expect(find.text('Edit button'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deleted, 1);
    expect(find.text('Edit button'), findsNothing, reason: 'editor closed');
  });

  testWidgets('system Back closes Type, then goes back one category',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('aac_back_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final storage = await tester.runAsync(() => AppStorage.at(temp));
    final settings = SettingsController(storage!)..settings = AppSettings();
    final pack = PackController(storage)
      ..vocabulary = PackLoader()
          .loadString(File('assets/sample_pack.json').readAsStringSync());
    final exits = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') exits.add(call);
      return null;
    });
    await tester.pumpWidget(MultiProvider(
        providers: [
          Provider<SpeechEngine>.value(value: SpeechEngine()),
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: pack),
          Provider.value(value: Predictor()),
          Provider.value(value: SymbolLibrary()),
        ],
        child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: const AppShell())));
    await tester.scrollUntilVisible(find.text('Feelings'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Feelings'));
    await tester.pump();
    expect(find.text('happy'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Type'));
    await tester.pump();
    expect(find.bySemanticsLabel('Space'), findsOneWidget);

    await tester.binding.handlePopRoute(); // closes Type
    await tester.pump();
    expect(find.bySemanticsLabel('Space'), findsNothing);
    expect(find.text('happy'), findsOneWidget, reason: 'still in Feelings');

    await tester.binding.handlePopRoute(); // back to Home
    await tester.pump();
    expect(find.text('Feelings'), findsOneWidget);
    expect(exits, isEmpty, reason: 'the app did not close');
    expect(tester.takeException(), isNull);
  });
}
