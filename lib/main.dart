import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show
        LicenseEntryWithLineBreaks,
        LicenseRegistry,
        kIsWeb,
        defaultTargetPlatform,
        TargetPlatform;
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'engine/desktop_native.dart'
    if (dart.library.js_interop) 'engine/desktop_web.dart' as desktop;

import 'engine/arasaac.dart';
import 'engine/i18n.dart';
import 'engine/screen_mode.dart';
import 'engine/prediction.dart';
import 'engine/settings_controller.dart';
import 'engine/speech.dart';
import 'engine/storage.dart';
import 'engine/symbol_library.dart';
import 'features/app/app_shell.dart';
import 'studio/device_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _start();
  } catch (_) {
    runApp(MaterialApp(
        home: Scaffold(
            body: SafeArea(
                child: Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'AAC Studio could not open saved boards. Check available storage and your connection, then retry. Your saved data has not been cleared.',
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: main, child: const Text('Retry')),
          ])),
    )))));
  }
}

Future<void> _start() async {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Piper LJ Speech offline voice'],
        await rootBundle.loadString('assets/voices/NOTICE.txt'));
  });
  // SQLite on desktop (P2G Explorer research viewer); mobile uses plugins.
  desktop.initialize();

  final storage = await initDefaultStorage();
  final settings = SettingsController(storage);
  await settings.load();
  await I18n.load(settings.settings.language);
  await ScreenMode.apply(settings.settings.fullScreen);

  final predictor = Predictor();
  await predictor.load();
  await predictor.loadLearned(StorageProviderAdapter(storage));

  final library = SymbolLibrary();
  await library.load();

  final pack = PackController(storage);
  await pack.load();

  final arasaac = ArasaacService(storage);

  // Warm up the TTS engine before the first tap (first-tap silence on
  // Android/Fire otherwise).
  final speech = SpeechEngine();
  void syncSpeech() {
    speech.configure(settings.settings);
    SymbolLibrary.skinTone = settings.settings.skinTone;
    if (settings.settings.language != I18n.language.code) {
      I18n.load(settings.settings.language);
    }
  }

  syncSpeech();
  settings.addListener(syncSpeech);
  try {
    await speech.ensure().timeout(const Duration(seconds: 8));
  } catch (_) {/* Retry on first speech request. */}

  runApp(StudioApp(
    arasaac: arasaac,
    speech: speech,
    settings: settings,
    predictor: predictor,
    library: library,
    pack: pack,
  ));
}

class StudioApp extends StatelessWidget {
  final SettingsController settings;
  final Predictor predictor;
  final SymbolLibrary library;
  final PackController pack;
  final SpeechEngine speech;
  final ArasaacService arasaac;

  const StudioApp({
    super.key,
    required this.arasaac,
    required this.speech,
    required this.settings,
    required this.predictor,
    required this.library,
    required this.pack,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SpeechEngine>.value(value: speech),
        Provider<ArasaacService>.value(value: arasaac),
        ChangeNotifierProvider<ValueNotifier<DeviceMode?>>(
          create: (_) => ValueNotifier<DeviceMode?>(DeviceMode(kDevices[0])),
        ),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        Provider<Predictor>.value(value: predictor),
        Provider<SymbolLibrary>.value(value: library),
        ChangeNotifierProvider<PackController>.value(value: pack),
      ],
      // Redraws every screen when the language changes.
      child: ValueListenableBuilder<String>(
        valueListenable: I18n.changes,
        builder: (context, _, __) => MaterialApp(
        title: 'AAC Studio',
        debugShowCheckedModeBanner: false,
        // Arabic and Urdu read right to left.
        builder: (context, child) => Directionality(
          textDirection: I18n.language.rightToLeft
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
        theme: ThemeData(
          useMaterial3: true,
          splashFactory: NoSplash.splashFactory,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepOrange,
            brightness: Brightness.dark,
          ),
        ),
        // A new key rebuilds every word in the new language.
        home: _isMobile
            ? AppShell(key: ValueKey(I18n.language.code))
            : desktop.studioHome(),
      ),
      ),
    );
  }

  /// Phones/tablets run the real AAC app full-screen (like the studied
  /// original); desktops run the developer Studio with previews and tools.
  static bool get _isMobile =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}
