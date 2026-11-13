import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/symbol_library.dart';
import 'package:aac_studio/features/app/app_shell.dart';
import 'package:aac_studio/features/settings/settings_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const pin = '6817';
  var pinned = false;
  var stopSucceeds = true;
  var pinRequests = 0;
  var unpinRequests = 0;

  setUp(() {
    pinned = false;
    stopSucceeds = true;
    pinRequests = 0;
    unpinRequests = 0;
    messenger.setMockMethodCallHandler(
        const MethodChannel('aac_studio/app_lock'), (call) async {
      switch (call.method) {
        case 'active':
          return pinned;
        case 'start':
          pinRequests++;
          // Android accepts the request before the system prompt is answered.
          return true;
        case 'stop':
          unpinRequests++;
          if (stopSucceeds) pinned = false;
          return stopSucceeds;
        default:
          throw MissingPluginException();
      }
    });
    messenger.setMockMethodCallHandler(const MethodChannel('flutter_tts'),
        (call) async => call.method == 'isLanguageAvailable' ? true : 1);
  });

  Future<(SettingsController, _SettingsStorage)> openApp(WidgetTester tester,
      {bool locked = false}) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final stored = _SettingsStorage(AppSettings(pin: pin, lockApp: locked));
    final settings = SettingsController(stored);
    await settings.load();
    final pack = PackController(stored)
      ..vocabulary = PackLoader()
          .loadString(File('assets/sample_pack.json').readAsStringSync());
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: pack),
        Provider.value(value: SpeechEngine()),
        Provider.value(value: Predictor()),
        Provider.value(value: SymbolLibrary()),
      ],
      child: const MaterialApp(home: AppShell()),
    ));
    await tester.pumpAndSettle();
    return (settings, stored);
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> more(WidgetTester tester) =>
      tap(tester, find.bySemanticsLabel('More'));

  Future<void> enterCode(WidgetTester tester, String code) async {
    expect(find.text('Enter code'), findsOneWidget);
    await tester.enterText(find.byType(TextField), code);
    await tap(tester, find.text('OK'));
  }

  Future<void> inSettings(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 160,
        scrollable: find.descendant(
            of: find.byType(SettingsSheet), matching: find.byType(Scrollable)));
    await tap(tester, finder);
  }

  Future<void> caregiver(WidgetTester tester) async {
    await more(tester);
    await tap(tester, find.text('Settings'));
    await inSettings(tester, find.text('Caregiver'));
  }

  testWidgets('Lock closes Settings and shows confirmed Android pinning',
      (tester) async {
    final (settings, stored) = await openApp(tester);
    settings.settings.editMode = true;
    await settings.update();
    await tester.pumpAndSettle();
    await caregiver(tester);
    await inSettings(tester, find.text('Caregiver lock'));
    expect(find.byType(SettingsSheet), findsNothing);
    expect(settings.settings.editMode, isFalse);
    expect(stored.saved['lockApp'], isTrue);
    expect(pinRequests, 1);
    expect(settings.screenPinning.value, isFalse);

    await more(tester);
    expect(find.text('Screen pinning is off'), findsOneWidget);
    pinned = true;
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Screen pinning is active'), findsOneWidget);
    expect(pinRequests, 1);
  });

  testWidgets('Failed unpin keeps the caregiver lock and allows retry',
      (tester) async {
    final (settings, stored) = await openApp(tester, locked: true);
    pinned = true;
    stopSucceeds = false;
    await more(tester);
    await tap(tester, find.text('Unlock the app'));
    await enterCode(tester, '0000');
    expect(unpinRequests, 0);
    expect(settings.settings.lockApp, isTrue);

    await more(tester);
    await tap(tester, find.text('Unlock the app'));
    await enterCode(tester, pin);
    expect(unpinRequests, 1);
    expect(stored.saved['lockApp'], isTrue);
    expect(
        find.text('Android still has the screen pinned. Try unlocking again.'),
        findsOneWidget);

    stopSucceeds = true;
    await more(tester);
    await tap(tester, find.text('Unlock the app'));
    await enterCode(tester, pin);
    expect(unpinRequests, 2);
    expect(pinned, isFalse);
    expect(stored.saved['lockApp'], isFalse);
    await more(tester);
    expect(find.text('Unlock the app'), findsNothing);
  });

  testWidgets('Changing the caregiver PIN requires the current PIN',
      (tester) async {
    final (_, stored) = await openApp(tester);
    await caregiver(tester);
    await inSettings(tester, find.text('Change code'));
    await enterCode(tester, '0000');
    expect(find.text('Set a new 4-digit code'), findsNothing);
    expect(stored.saved['pin'], pin);

    await inSettings(tester, find.text('Change code'));
    await enterCode(tester, pin);
    expect(find.text('Set a new 4-digit code'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty);
    await tester.enterText(find.byType(TextField), '7624');
    await tap(tester, find.text('OK'));
    expect(stored.saved['pin'], '7624');
  });
}

class _SettingsStorage implements AppStorage {
  Map<String, dynamic> saved;
  _SettingsStorage(AppSettings settings) : saved = settings.toJson();

  @override
  File get settingsFile => File('settings.json');

  @override
  Future<Map<String, dynamic>?> readJson(File file) async => Map.of(saved);

  @override
  Future<void> writeJson(File file, Object json) async {
    saved = Map<String, dynamic>.from(json as Map);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
