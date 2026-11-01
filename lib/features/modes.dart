import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/pack_loader.dart';
import '../../data/p2g_loader.dart';
import '../../engine/speech.dart';
import '../../models/domain.dart';
import '../studio/device_frame.dart';
import 'grid/grid_screen.dart';

/// M2: the ORIGINAL sample vocabulary running in the studio.
class MyAppHome extends StatelessWidget {
  const MyAppHome({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<ValueNotifier<DeviceMode?>>();
    return FutureBuilder<Vocabulary>(
      future: PackLoader().loadAsset('assets/sample_pack.json'),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final session = GridSession(
          vocabulary: snap.data!,
          speech: SpeechEngineProvider.of(context),
        );
        return GridScreen(
          session: session,
          maxColumns: device.value?.spec.maxGridColumns ?? 6,
          titleOverride: snap.data!.label,
        );
      },
    );
  }
}

/// P2G Explorer: renders the locally extracted IPA vocabulary data.
class P2gExplorer extends StatelessWidget {
  final P2gConfig config;
  const P2gExplorer({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<ValueNotifier<DeviceMode?>>();
    final maxCols = device.value?.spec.maxGridColumns ?? 6;
    return FutureBuilder<Vocabulary>(
      future: P2gLoader(
        dbPath: config.dbPath,
        typesPath: config.typesPath,
        pngDir: config.pngDir,
      ).load(maxColumnsForDevice: maxCols),
      builder: (context, snap) {
        if (snap.hasError) {
          return _error(snap.error!);
        }
        if (!snap.hasData) {
          return const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading vocabulary from extracted IPA…',
                style: TextStyle(color: Colors.white70)),
          ]));
        }
        final session = GridSession(
          vocabulary: snap.data!,
          speech: SpeechEngineProvider.of(context),
        );
        return GridScreen(session: session, maxColumns: maxCols);
      },
    );
  }

  Widget _error(Object e) {
    return Container(
      color: const Color(0xFF2B2F36),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(
        'Explorer failed to load the extracted data.\n\n$e\n\n'
        'Expected paths:\n  db:   ${config.dbPath}\n  png:  ${config.pngDir}',
        style: const TextStyle(color: Colors.orangeAccent, fontSize: 11),
      ),
    );
  }
}

class P2gConfig {
  final String dbPath;
  final String typesPath;
  final String pngDir;
  const P2gConfig({required this.dbPath, required this.typesPath, required this.pngDir});

  /// Defaults resolved relative to this project on disk (research viewer).
  static P2gConfig localDefault() {
    const base = r'C:\Users\zer0ne_LP_Local\Desktop\Proloquo2Go\work';
    return P2gConfig(
      dbPath: '$base\\extracted\\Payload\\Proloquo2Go.app\\Databases\\'
          'com.assistiveware.proloquo2go.vocabulary.coreword.cache.sqlite',
      typesPath: '$base\\extracted\\Payload\\Proloquo2Go.app\\Databases\\p2g_types.sqlite',
      pngDir: '$base\\p2g_symbols_png',
    );
  }
}

/// Tiny service locator for the speech engine.
class SpeechEngineProvider {
  static SpeechEngine of(BuildContext context) =>
      Provider.of<SpeechEngine>(context, listen: false);
}
