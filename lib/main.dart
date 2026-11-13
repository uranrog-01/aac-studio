import 'engine/voice_clips.dart';
import 'dart:async';

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
import 'engine/voice_downloads.dart';
import 'engine/prediction.dart';
import 'engine/settings_controller.dart';
import 'engine/speech.dart';
import 'engine/storage.dart';
import 'engine/symbol_library.dart';
import 'features/app/app_shell.dart';
import 'studio/device_frame.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Something is on screen at once; loading the pictures, the board and
  // the voice can take several seconds on older tablets.
  runApp(const _Splash());
  try {
    await _start();
  } catch (error) {
    runApp(MaterialApp(
        home: Scaffold(
            body: SafeArea(
                child: Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'AAC Studio could not start. Check available storage and your connection, then retry. Your saved data has not been cleared.',
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            // The real cause, so the problem can be reported and fixed.
            Text('$error',
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            FilledButton(onPressed: main, child: const Text('Retry')),
          ])),
    )))));
  }
}

Future<void> _start() async {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['AAC Studio voices'],
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
  predictor.setLanguage(I18n.language.code, I18n.boardWords);
  await VoiceClips.preload();

  final library = SymbolLibrary();
  await library.load();

  final pack = PackController(storage);
  await pack.load();

  final arasaac = ArasaacService(storage);

  // Warm up the TTS engine before the first tap (first-tap silence on
  // Android/Fire otherwise).
  final speech = SpeechEngine();
  var requestedLanguage = I18n.language.code;
  void syncSpeech() {
    speech.configure(settings.settings);
    SymbolLibrary.skinTone = settings.settings.skinTone;
    I18n.setFemale(settings.settings.speakerFemale);
    if (settings.settings.language != requestedLanguage) {
      requestedLanguage = settings.settings.language;
      I18n.load(requestedLanguage).then(
          (_) => predictor.setLanguage(I18n.language.code, I18n.boardWords));
    }
  }

  syncSpeech();
  settings.addListener(syncSpeech);
  // Finish an offline voice download that was interrupted (e.g. Albanian).
  unawaited(VoiceDownloads.ensure(speech, settings.settings.language));
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

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF2B2F36),
          body: Center(child: CircularProgressIndicator()),
        ),
      );
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
        // Redraw localized text without replacing the current board session.
        home: _isMobile ? const AppShell() : desktop.studioHome(),
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
