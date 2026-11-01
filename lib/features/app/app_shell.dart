import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/prediction.dart';
import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../editor/editor_dialog.dart';
import '../grid/grid_screen.dart';
import '../modes.dart' show SpeechEngineProvider;
import '../settings/settings_sheet.dart';
import '../sensory/sensory_games.dart';

/// The REAL app (mobile): like the studied original — launch straight into
/// the full-screen vocabulary grid. No studio chrome, no device frames.
/// Settings + edit mode live inside the app behind the ⚙ button (PIN-gated).
///
/// Stateful on purpose: the GridSession must survive parent rebuilds
/// (keyboard open/close, MediaQuery changes) — recreating it in build()
/// reset navigation and closed the keyboard instantly on Android.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  GridSession? _session;
  Vocabulary? _builtFor;

  GridSession? _sessionFor(Vocabulary vocab, SpeechEngine speech) {
    if (_session == null || _builtFor != vocab) {
      _session = GridSession(vocabulary: vocab, speech: speech);
      _builtFor = vocab;
    }
    return _session;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final pack = context.watch<PackController>();
    if (pack.vocabulary == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF2B2F36),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final session = _sessionFor(
        pack.vocabulary!, SpeechEngineProvider.of(context))!;
    return GridScreen(
      session: session,
      // Auto-fit the grid to the real screen (phone vs tablet).
      maxColumns: _autoColumns(context),
      titleOverride: pack.vocabulary!.label,
      predictor: context.watch<Predictor>(),
      library: context.watch<SymbolLibrary>(),
      editMode: settings.editMode,
      showOptions: true,
      onSensoryGames: () => _openSensory(context),
      onEditButton: (b) => _edit(context, session, pack, b),
      onAddButton: () => _add(context, session, pack),
    );
  }

  int _autoColumns(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w ~/ 95).clamp(4, 9);
  }

  void _openSensory(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const SensoryGamesScreen(),
    ));
  }

  void _edit(BuildContext context, GridSession session, PackController pack,
      VocabButton b) {
    ButtonEditorDialog.show(
      context,
      library: context.read<SymbolLibrary>(),
      existing: b,
      onSave: (updated) {
        session.replaceButton(updated, persist: pack.save);
        final s = updated.voice;
        if (s != null) {
          SpeechEngineProvider.of(context).speak(updated.speakText, style: s);
        }
      },
      onDelete: () => session.removeButton(b.id, persist: pack.save),
    );
  }

  void _add(BuildContext context, GridSession session, PackController pack) {
    ButtonEditorDialog.show(
      context,
      library: context.read<SymbolLibrary>(),
      onSave: (b) => session.addButton(b, persist: pack.save),
    );
  }
}
