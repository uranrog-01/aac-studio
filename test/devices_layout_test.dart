import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/symbol_library.dart';
import 'package:aac_studio/features/editor/editor_dialog.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/features/settings/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Every main screen on phone and tablet sizes, portrait and landscape:
/// iPhone SE, iPhone 15, small Android, iPad, Android tablet.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async => call.method == 'isLanguageAvailable' ? true : 1);

  const sizes = {
    'iPhone SE': Size(375, 667),
    'iPhone 15': Size(393, 852),
    'small Android': Size(360, 640),
    'iPhone landscape': Size(852, 393),
    'iPad': Size(820, 1180),
    'iPad landscape': Size(1180, 820),
    'Android tablet': Size(800, 1280),
  };

  for (final entry in sizes.entries) {
    testWidgets('all screens fit on ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final temp = Directory.systemTemp.createTempSync('aac_dev_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final storage = await tester.runAsync(() => AppStorage.at(temp));
      final settings = SettingsController(storage!)..settings = AppSettings();
      final session = GridSession(
          vocabulary: PackLoader()
              .loadString(File('assets/sample_pack.json').readAsStringSync()),
          speech: SpeechEngine());
      final columns = (entry.value.width ~/ 95).clamp(4, 9);
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
              theme: ThemeData(splashFactory: NoSplash.splashFactory),
              home: GridScreen(
                  session: session,
                  maxColumns: columns,
                  predictor: Predictor(),
                  showOptions: true))));
      expect(tester.takeException(), isNull, reason: 'Home');

      session.pushFolder('actions'); // the largest page
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Actions');
      session.goHome();

      session.toggleKeyboard();
      await tester.pump();
      expect(find.bySemanticsLabel('Space'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Type');
      session.toggleKeyboard();

      session.toggleSearch();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'Find');
      session.toggleSearch();
      await tester.pump();

      final context = tester.element(find.byType(GridScreen));
      SettingsSheet.show(context,
          speech: session.speech,
          settings: settings.settings,
          settingsController: settings,
          onChanged: () {});
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Settings');
      Navigator.of(context).pop();
      await tester.pumpAndSettle();

      ButtonEditorDialog.show(context,
          library: SymbolLibrary(),
          existing: session.vocabulary.viewsByFolder['home']!.first.cells
              .first.button,
          onSave: (_) {},
          onDelete: () {});
      await tester.pumpAndSettle();
      expect(find.text('Use a photo'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'Editor');
    });
  }
}
