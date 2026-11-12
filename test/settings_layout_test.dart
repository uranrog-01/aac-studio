import 'dart:io';

import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/features/settings/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Settings is a short menu; every section opens on its own page, fits on
/// phones and tablets with "More options" unfolded, and Back returns to
/// the menu.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async => call.method == 'isLanguageAvailable' ? true : 1);

  const sections = [
    'Language',
    'Voice',
    'Speaking',
    'Screen & look',
    'Touch & access',
    'Offline & backup',
    'Caregiver',
  ];

  for (final size in const [Size(360, 640), Size(393, 852), Size(1180, 820)]) {
    testWidgets('every Settings section opens at ${size.width.round()} wide',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final temp = Directory.systemTemp.createTempSync('aac_set_');
      addTearDown(() => temp.deleteSync(recursive: true));
      final storage = await tester.runAsync(() => AppStorage.at(temp));
      final controller = SettingsController(storage!)..settings = AppSettings();
      final scroll = ScrollController();
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              backgroundColor: const Color(0xFF22262D),
              body: SettingsSheet(
                  speech: SpeechEngine(),
                  settings: controller.settings,
                  settingsController: controller,
                  scrollController: scroll,
                  onChanged: () {}))));
      await tester.pumpAndSettle();

      // The menu: seven sections, nothing else to read through.
      Future<void> scrollTo(double offset) async {
        scroll.jumpTo(offset.clamp(0, scroll.position.maxScrollExtent));
        await tester.pumpAndSettle();
      }

      Future<void> bringUp(Finder target) async {
        for (var y = 0.0; target.evaluate().isEmpty; y += 150) {
          expect(y <= scroll.position.maxScrollExtent + 150, isTrue,
              reason: 'not found: $target');
          await scrollTo(y);
        }
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();
      }

      for (final section in sections) {
        await scrollTo(0);
        expect(find.text('Changes are saved automatically.'), findsOneWidget);
        await bringUp(find.text(section));
        await tester.tap(find.text(section));
        await tester.pumpAndSettle();

        // The section's own page starts at the top, with a Back row.
        expect(scroll.offset, 0, reason: section);
        expect(find.byTooltip('Back'), findsOneWidget, reason: section);
        expect(find.text('Changes are saved automatically.'), findsNothing);
        if (section == 'Voice') {
          expect(find.text('Automatic'), findsOneWidget);
          expect(find.text('Female'), findsOneWidget);
          expect(find.text('Male'), findsOneWidget);
          expect(find.text('Test voice'), findsOneWidget);
          // The long voice list and fine controls are folded away.
          expect(find.text('Pitch'), findsNothing);
        }

        // Unfold "More options" and look at the whole page.
        for (var y = 0.0; y <= scroll.position.maxScrollExtent; y += 200) {
          await scrollTo(y);
          final more = find.text('More options');
          if (more.evaluate().isNotEmpty) {
            await tester.ensureVisible(more);
            await tester.pumpAndSettle();
            await tester.tap(more);
            await tester.pumpAndSettle();
            break;
          }
        }
        for (var y = 0.0; y <= scroll.position.maxScrollExtent; y += 300) {
          await scrollTo(y);
          expect(tester.takeException(), isNull, reason: 'Settings > $section');
        }
        if (section == 'Voice') {
          await bringUp(find.text('Pitch'));
        }

        await scrollTo(0);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      expect(find.text('Changes are saved automatically.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
