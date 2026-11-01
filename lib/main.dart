import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'engine/speech.dart';
import 'studio/device_frame.dart';
import 'studio/studio_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Desktop SQLite (needed by the P2G Explorer research viewer).
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  runApp(const StudioApp());
}

class StudioApp extends StatelessWidget {
  const StudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SpeechEngine>(create: (_) => SpeechEngine()),
        ChangeNotifierProvider<ValueNotifier<DeviceMode?>>(
          create: (_) => ValueNotifier<DeviceMode?>(DeviceMode(kDevices[0])),
        ),
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
