import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine/prediction.dart';
import 'engine/settings_controller.dart';
import 'engine/speech.dart';
import 'engine/storage.dart';
import 'engine/symbol_library.dart';
import 'studio/device_frame.dart';
import 'studio/studio_home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop SQLite (needed by the P2G Explorer research viewer).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final storage = await initDefaultStorage();
  final settings = SettingsController(storage);
  await settings.load();

  final predictor = Predictor();
  await predictor.load();
  await predictor.loadLearned(StorageProviderAdapter(storage));

  final library = SymbolLibrary();
  await library.load();

  final pack = PackController(storage);
  await pack.load();

  runApp(StudioApp(
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

  const StudioApp({
    super.key,
    required this.settings,
    required this.predictor,
    required this.library,
    required this.pack,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SpeechEngine>(create: (_) => SpeechEngine()),
        ChangeNotifierProvider<ValueNotifier<DeviceMode?>>(
          create: (_) => ValueNotifier<DeviceMode?>(DeviceMode(kDevices[0])),
        ),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        Provider<Predictor>.value(value: predictor),
        Provider<SymbolLibrary>.value(value: library),
        ChangeNotifierProvider<PackController>.value(value: pack),
      ],
      child: MaterialApp(
        title: 'AAC Studio',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepOrange,
            brightness: Brightness.dark,
          ),
        ),
        home: const StudioHome(),
      ),
    );
  }
}
