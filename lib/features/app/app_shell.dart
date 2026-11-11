import '../../engine/app_lock.dart';
import '../../engine/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../engine/prediction.dart';
import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../editor/editor_dialog.dart';
import '../grid/grid_screen.dart';
import '../../engine/speech_provider.dart';
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
  int _backAttempts = 0;
  bool _toldRecovery = false;
  DateTime _firstBack = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    // A locked app is locked again every time it opens.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<SettingsController>().settings.lockApp) {
        AppLock.apply(true);
      }
    });
  }

  GridSession? _sessionFor(Vocabulary vocab, SpeechEngine speech) {
    if (_session == null || _builtFor != vocab) {
      _session = GridSession(vocabulary: vocab, speech: speech);
      _builtFor = vocab;
    }
    return _session;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final settings = controller.settings;
    final pack = context.watch<PackController>();
    if (pack.vocabulary == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF2B2F36),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (pack.recoveredFromDamage && !_toldRecovery) {
      _toldRecovery = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          duration: const Duration(seconds: 10),
          content: Text(I18n.t('The saved board could not be opened, so the '
              'starter board is shown. A copy of the damaged file was kept. '
              'Restore a backup in Settings > Caregiver.')),
        ));
      });
    }
    final session =
        _sessionFor(pack.vocabulary!, SpeechEngineProvider.of(context))!;
    Widget grid = _gridBody(context, settings, pack, session);
    if (pack.saveFailed) {
      grid = Column(children: [
        Material(
          color: const Color(0xFFB71C1C),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                  I18n.t('Changes could not be saved. Check free storage space.'),
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
        Expanded(child: grid),
      ]);
    }
    // The system Back button (Android, iPad keyboards, browser) first closes
    // Type/Find, then goes back one category; only on Home does it leave
    // the app. Kiosk mode (preventExit) needs 3 quick presses on Home.
    return AnimatedBuilder(
      animation: session,
      builder: (context, child) => PopScope(
        canPop: !settings.preventExit &&
            !settings.lockApp &&
            !session.canGoBack &&
            !session.showKeyboard &&
            !session.showSearch,
        onPopInvokedWithResult: (didPop, result) =>
            _handleBack(didPop, session, settings),
        child: child!,
      ),
      child: grid,
    );
  }

  Widget _gridBody(BuildContext context, AppSettings settings,
      PackController pack, GridSession session) {
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

  void _handleBack(bool didPop, GridSession session, AppSettings settings) {
    if (didPop) return;
    if (session.showKeyboard) {
      session.toggleKeyboard();
    } else if (session.showSearch) {
      session.toggleSearch();
    } else if (session.canGoBack) {
      session.back();
    } else if (settings.lockApp) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(I18n.t('The app is locked. A caregiver can unlock it '
            'in More.')),
        duration: const Duration(seconds: 2),
      ));
    } else if (!settings.preventExit) {
      SystemNavigator.pop();
    } else {
      _kioskBack();
    }
  }

  void _kioskBack() {
    // P0 kiosk mode: require 3 quick back presses to leave the app.
    final now = DateTime.now();
    if (now.difference(_firstBack).inMilliseconds > 2000) {
      _backAttempts = 0;
    }
    _firstBack = now;
    _backAttempts++;
    HapticFeedback.selectionClick();
    if (_backAttempts >= 3) {
      SystemNavigator.pop();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(I18n.t('Press Back 3 times quickly to leave')),
      duration: const Duration(milliseconds: 800),
    ));
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
        session.replaceButton(updated.copyWith(userEdited: true),
            persist: pack.save);
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
      onSave: (b) =>
          session.addButton(b.copyWith(userEdited: true), persist: pack.save),
    );
  }
}
