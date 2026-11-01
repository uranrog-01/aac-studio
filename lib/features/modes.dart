import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/p2g_loader.dart';
import '../engine/prediction.dart';
import '../engine/settings_controller.dart';
import '../engine/speech.dart';
import '../engine/symbol_library.dart';
import '../models/domain.dart';
import '../studio/device_frame.dart';
import 'editor/editor_dialog.dart';
import 'grid/grid_screen.dart';

/// M2+M3+M5: the ORIGINAL sample vocabulary running in the studio, with
/// persisted edits and voice styles.
class MyAppHome extends StatelessWidget {
  const MyAppHome({super.key});

  @override
  Widget build(BuildContext context) {
    final device = context.watch<ValueNotifier<DeviceMode?>>();
    final settings = context.watch<SettingsController>();
    final library = context.watch<SymbolLibrary>();
    final pack = context.watch<PackController>();
    if (pack.vocabulary == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final session = GridSession(
      vocabulary: pack.vocabulary!,
      speech: SpeechEngineProvider.of(context),
    );
    return GridScreen(
      session: session,
      maxColumns: device.value?.spec.maxGridColumns ?? 6,
      titleOverride: pack.vocabulary!.label,
      predictor: context.watch<Predictor>(),
      editMode: settings.editMode,
      onEditButton: (b) => _edit(context, session, pack, library, b),
      onAddButton: () => _add(context, session, pack, library),
    );
  }

  void _edit(BuildContext context, GridSession session, PackController pack,
      SymbolLibrary library, VocabButton b) {
    ButtonEditorDialog.show(
      context,
      library: library,
      existing: b,
      onSave: (updated) {
        session.replaceButton(updated, persist: pack.save);
        final s = updated.voice;
        if (s != null) {
          SpeechEngineProvider.of(context).speak(updated.speakText, style: s);
        }
      },
      onDelete: () {
        session.removeButton(b.id, persist: pack.save);
      },
    );
  }

  void _add(BuildContext context, GridSession session, PackController pack,
      SymbolLibrary library) {
    ButtonEditorDialog.show(
      context,
      library: library,
      onSave: (b) {
        session.addButton(b, persist: pack.save);
      },
    );
  }
}

/// P2G Explorer: renders the locally extracted IPA vocabulary data
/// (research viewer; editing disabled).
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
        return GridScreen(
          session: session,
          maxColumns: maxCols,
          predictor: context.watch<Predictor>(),
        );
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
