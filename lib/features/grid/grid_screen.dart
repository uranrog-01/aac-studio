import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../engine/prediction.dart';
import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../settings/settings_sheet.dart';
import 'keyboard_view.dart';

/// P0/P2 behavior flags read from settings at tap time.
class TapFlags {
  final bool quietBuilder;
  final bool vocalizeFolders;
  final bool clearOnSpeak;
  final bool goHomeOnPress;
  final int inputDebounceMs;
  final bool haptics;
  final bool audioCues;
  const TapFlags({
    required this.quietBuilder,
    required this.vocalizeFolders,
    required this.clearOnSpeak,
    required this.goHomeOnPress,
    required this.inputDebounceMs,
    required this.haptics,
    required this.audioCues,
  });
}

/// Session state: navigation stack, message window, recents (P0), plus
/// per-tap behavior driven by settings. Its owner (AppShell / studio state)
/// keeps one instance per vocabulary so it survives rebuilds.
class GridSession extends ChangeNotifier {
  final Vocabulary vocabulary;
  final SpeechEngine speech;
  final List<String> _stack; // folder ids (may include virtual ids)
  String _message = '';
  bool showKeyboard = false;
  String? lastSpoken;
  final List<VocabButton> _recents = [];
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  static const recentsFolderId = '__recents';
  static const favoritesFolderId = '__favorites';
  static const recentsCap = 9;

  GridSession({required this.vocabulary, required this.speech})
      : _stack = [vocabulary.rootFolderId];

  String get currentFolderId => _stack.last;
  String get message => _message;
  bool get canGoBack => _stack.length > 1;
  VocabFolder? get currentFolder => vocabulary.folderOf(currentFolderId);
  List<VocabButton> get recents => List.unmodifiable(_recents);

  VocabFolder? _virtualFolder(String id) {
    if (id == recentsFolderId) {
      return const VocabFolder(recentsFolderId, 'Recent', SymbolRef('🕘'));
    }
    if (id == favoritesFolderId) {
      return const VocabFolder(favoritesFolderId, 'My words', SymbolRef('⭐'));
    }
    return null;
  }

  /// Resolves a folder's view; virtual folders (recents/favorites) are
  /// built live from session state.
  VocabView? viewFor(String folderId, {int maxColumns = 6}) {
    if (folderId == recentsFolderId) {
      return VocabView(
          id: folderId,
          folderId: folderId,
          columns: maxColumns,
          cells: [for (final b in _recents) GridCell(b)]);
    }
    if (folderId == favoritesFolderId) {
      final favs = <GridCell>[];
      for (final list in vocabulary.viewsByFolder.values) {
        for (final v in list) {
          for (final c in v.cells) {
            if (c.button.favorite &&
                !favs.any((f) => f.button.id == c.button.id)) {
              favs.add(GridCell(c.button));
            }
          }
        }
      }
      return VocabView(
          id: folderId, folderId: folderId, columns: maxColumns, cells: favs);
    }
    final views = vocabulary.viewsByFolder[folderId];
    if (views == null || views.isEmpty) return null;
    VocabView best = views.first;
    for (final v in views.skip(1)) {
      final curFits = best.columns <= maxColumns;
      final vFits = v.columns <= maxColumns;
      if (curFits != vFits) {
        if (vFits) best = v;
      } else if (vFits && v.columns > best.columns) {
        best = v;
      }
    }
    return best;
  }

  void pushFolder(String folderId) {
    _stack.add(folderId);
    notifyListeners();
  }

  void tap(VocabButton b, {int maxColumns = 6, TapFlags? flags}) {
    final f = flags;
    if (b.kind == ButtonKind.folder) {
      var navigated = false;
      for (final a in b.actions) {
        if (a.kind == ActionKind.gotoFolder &&
            (vocabulary.folders.containsKey(a.data) ||
                a.data == recentsFolderId ||
                a.data == favoritesFolderId)) {
          _stack.add(a.data);
          navigated = true;
          break;
        }
      }
      if (navigated && (f?.vocalizeFolders ?? true) && b.speakText.isNotEmpty) {
        speech.speak(b.speakText, style: b.voice);
      }
      notifyListeners();
      return;
    }
    var spoke = false;
    var appended = '';
    for (final a in b.actions) {
      switch (a.kind) {
        case ActionKind.addText:
          appended = a.data.isNotEmpty ? a.data : b.speakText;
          _append(appended);
          break;
        case ActionKind.speakNow:
          _speak(a.data.isNotEmpty ? a.data : b.speakText, b, f);
          spoke = true;
          break;
        case ActionKind.speakMessage:
          _speakMessage(f);
          spoke = true;
          break;
        case ActionKind.clearMessage:
          _message = '';
          break;
        case ActionKind.launchUrl:
        case ActionKind.sensoryGames:
          break; // handled by the screen
        case ActionKind.gotoFolder:
          if (vocabulary.folders.containsKey(a.data) ||
              a.data == recentsFolderId ||
              a.data == favoritesFolderId) {
            _stack.add(a.data);
          }
          break;
      }
    }
    if (b.kind == ButtonKind.item) {
      if (!b.actions.any((a) => a.kind == ActionKind.addText)) {
        appended = b.speakText;
        _append(appended);
      }
      // Auto-speak unless quiet builder mode is on or an action spoke.
      if (!(f?.quietBuilder ?? false) && !spoke && appended.isNotEmpty) {
        _speak(appended, b, f);
      }
    }
    notifyListeners();
  }

  void _speak(String text, VocabButton b, TapFlags? f) {
    if (text.trim().isEmpty) return;
    speech.speak(text, style: b.voice);
    lastSpoken = text;
    _stampRecent(b);
    if (f?.clearOnSpeak ?? false) _message = '';
    if (f?.goHomeOnPress ?? false) {
      _stack
        ..clear()
        ..add(vocabulary.rootFolderId);
    }
  }

  void _speakMessage(TapFlags? f) {
    if (_message.trim().isEmpty) return;
    speech.speak(_message);
    lastSpoken = _message;
    if (f?.clearOnSpeak ?? false) _message = '';
    if (f?.goHomeOnPress ?? false) {
      _stack
        ..clear()
        ..add(vocabulary.rootFolderId);
    }
  }

  void _stampRecent(VocabButton b) {
    if (b.kind != ButtonKind.item) return;
    _recents.removeWhere((r) => r.id == b.id);
    _recents.insert(0, b);
    if (_recents.length > recentsCap) {
      _recents.removeRange(recentsCap, _recents.length);
    }
  }

  void _append(String text) {
    if (text.isEmpty) return;
    _message = _message.isEmpty ? text : '$_message $text';
  }

  /// M4: live typing — replaces the message window contents on every
  /// keystroke (no send step).
  void setMessageLive(String text) {
    _message = text;
    notifyListeners();
  }

  void removeLastWord() {
    final words = _message.trim().split(' ')..removeWhere((w) => w.isEmpty);
    if (words.isNotEmpty) words.removeLast();
    _message = words.join(' ').trim();
    notifyListeners();
  }

  void removeWordAt(int index) {
    final words = _message.trim().split(' ')..removeWhere((w) => w.isEmpty);
    if (index >= 0 && index < words.length) words.removeAt(index);
    _message = words.join(' ').trim();
    notifyListeners();
  }

  void toggleKeyboard() {
    showKeyboard = !showKeyboard;
    notifyListeners();
  }

  /// Debounce guard (P0 accessibility): returns true when the tap passes.
  bool allowTap(TapFlags? f) {
    final ms = f?.inputDebounceMs ?? 0;
    if (ms <= 0) return true;
    final now = DateTime.now();
    if (now.difference(_lastTap).inMilliseconds < ms) return false;
    _lastTap = now;
    return true;
  }

  /// M5: replace a button (by id) in the current view and persist.
  void replaceButton(VocabButton updated, {VoidCallback? persist}) {
    for (final views in vocabulary.viewsByFolder.values) {
      for (final view in views) {
        for (var i = 0; i < view.cells.length; i++) {
          final cell = view.cells[i];
          if (cell.button.id != updated.id) continue;
          view.cells[i] = GridCell(updated.copyWith(userEdited: true),
              col: cell.col,
              row: cell.row,
              span: cell.span,
              hidden: cell.hidden,
              dimmed: cell.dimmed);
        }
      }
    }
    for (var i = 0; i < _recents.length; i++) {
      if (_recents[i].id == updated.id) _recents[i] = updated;
    }
    persist?.call();
    notifyListeners();
  }

  /// M5: append a new button cell to the current view.
  void addButton(VocabButton b, {VoidCallback? persist}) {
    final view = viewFor(currentFolderId, maxColumns: 99);
    if (view == null) return;
    view.cells.add(GridCell(b));
    vocabulary.removedIds.remove(b.id);
    persist?.call();
    notifyListeners();
  }

  /// M5: remove a button from the current view.
  void removeButton(String id, {VoidCallback? persist}) {
    for (final views in vocabulary.viewsByFolder.values) {
      for (final view in views) {
        view.cells.removeWhere((cell) => cell.button.id == id);
      }
    }
    _recents.removeWhere((button) => button.id == id);
    vocabulary.removedIds.add(id);
    persist?.call();
    notifyListeners();
  }

  void back() {
    if (canGoBack) {
      _stack.removeLast();
      notifyListeners();
    }
  }

  void goHome() {
    speech.stop();
    _stack
      ..clear()
      ..add(vocabulary.rootFolderId);
    notifyListeners();
  }

  void clearMessage() {
    _message = '';
    notifyListeners();
  }

  void speakMessage({TapFlags? flags}) {
    _speakMessage(flags);
    notifyListeners();
  }
}

/// Shared grid screen used by the mobile app AND the studio preview.
class GridScreen extends StatefulWidget {
  final GridSession session;
  final int maxColumns;
  final String? titleOverride;

  final Predictor? predictor;
  final SymbolLibrary? library;
  final bool editMode;
  final bool showOptions;
  final void Function(VocabButton updated)? onEditButton;
  final VoidCallback? onAddButton;
  final VoidCallback? onSensoryGames;

  const GridScreen({
    super.key,
    required this.session,
    required this.maxColumns,
    this.titleOverride,
    this.predictor,
    this.library,
    this.editMode = false,
    this.onEditButton,
    this.onAddButton,
    this.showOptions = false,
    this.onSensoryGames,
  });

  @override
  State<GridScreen> createState() => _GridScreenState();
}

class _GridScreenState extends State<GridScreen> {
  // P2 scanning state: phase 0=off, 1=row scan, 2=cell scan
  int _scanPhase = 0;
  int? _scanRow;
  int? _scanCol;
  int _scanCellsInRow = 0;
  int _gridCols = 6;
  int _gridRows = 4;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    return AnimatedBuilder(
      animation: widget.session,
      builder: (context, _) {
        if (widget.session.showKeyboard && widget.predictor != null) {
          return KeyboardView(
            predictor: widget.predictor!,
            library: widget.library,
            speech: widget.session.speech,
            initialText: widget.session.message,
            onTextChanged: widget.session.setMessageLive,
            onSpeak: () =>
                widget.session.speakMessage(flags: _tapFlags(settings)),
            onClose: widget.session.toggleKeyboard,
          );
        }
        final view = widget.session.viewFor(widget.session.currentFolderId,
            maxColumns: widget.maxColumns);
        final folder = widget.session.currentFolder ??
            widget.session._virtualFolder(widget.session.currentFolderId);
        final cols = view?.columns.clamp(1, 12) ?? widget.maxColumns;
        final body = view == null
            ? Center(
                child: Text('Nothing here yet',
                    style: TextStyle(
                        color:
                            settings.cviMode ? Colors.white : Colors.white54)))
            : _grid(view, cols, settings);

        final messageWindow = _messageWindow(context, settings);
        final toolbar = _toolbar(
            context, folder?.label ?? widget.titleOverride ?? '', settings);

        final children = settings.messageWindowTop
            ? [messageWindow, toolbar, Expanded(child: body)]
            : [Expanded(child: body), toolbar, messageWindow];

        return Scaffold(
          backgroundColor:
              settings.cviMode ? Colors.black : const Color(0xFF2B2F36),
          body: SafeArea(child: Column(children: children)),
        );
      },
    );
  }

  // ---------------- message window (P0 upgrades) ----------------

  Widget _messageWindow(BuildContext context, AppSettings settings) {
    final session = widget.session;
    return Column(children: [
      Semantics(
        button: true,
        label: 'Speak message',
        excludeSemantics: true,
        child: Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: () => session.speakMessage(flags: _tapFlags(settings)),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(16),
              child: Text(
                  session.message.isEmpty
                      ? 'Tap symbols to build a message'
                      : session.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, color: Colors.black87)),
            ),
          ),
        ),
      ),
      ValueListenableBuilder<String?>(
        valueListenable: session.speech.error,
        builder: (context, error, _) => error == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(8),
                child:
                    Text(error, style: const TextStyle(color: Colors.white))),
      ),
    ]);
  }

  Widget _toolbarBtn(
      {required IconData icon,
      required String label,
      VoidCallback? onTap,
      Color? color,
      bool active = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Semantics(
          button: true,
          label: label,
          enabled: onTap != null,
          excludeSemantics: true,
          child: Material(
            color: active
                ? Colors.deepOrangeAccent.withValues(alpha: .35)
                : (color ?? const Color(0xFF3A4049)),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: onTap == null ? .4 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: Colors.white, size: 26),
                    FittedBox(
                      child: Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Six large controls a communicator uses every day; caregiver and
  /// occasional tools (recent words, repeat, copy, settings) live in More.
  Widget _toolbar(BuildContext context, String folderLabel, AppSettings s) {
    final session = widget.session;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(children: [
        _toolbarBtn(
            icon: Icons.arrow_back,
            label: 'Back',
            onTap: session.canGoBack ? session.back : null),
        _toolbarBtn(
            icon: Icons.home_rounded, label: 'Home', onTap: session.goHome),
        if (widget.editMode)
          _toolbarBtn(
              icon: Icons.add_box, label: 'Add', onTap: widget.onAddButton),
        if (s.scanningEnabled)
          _toolbarBtn(
              icon: Icons.accessibility_new,
              label: 'Scan',
              active: _scanPhase != 0,
              onTap: () => _toggleScanning(s, _gridCols, _gridRows)),
        _toolbarBtn(
            icon: Icons.keyboard_alt_outlined,
            label: 'Type',
            onTap: widget.predictor != null ? session.toggleKeyboard : null),
        _toolbarBtn(
            icon: Icons.volume_up,
            label: 'Speak',
            color: const Color(0xFF2E7D32),
            onTap: () => session.speakMessage(flags: _tapFlags(s))),
        _toolbarBtn(
            icon: Icons.clear_all, label: 'Clear', onTap: session.clearMessage),
        _toolbarBtn(
            icon: Icons.more_horiz,
            label: 'More',
            onTap: () => _showMore(context)),
      ]),
    );
  }

  void _showMore(BuildContext context) {
    final session = widget.session;
    final messenger = ScaffoldMessenger.of(context);
    Widget item(IconData icon, String label, VoidCallback? onTap) => ListTile(
          leading: Icon(icon, color: Colors.white),
          title: Text(label,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          enabled: onTap != null,
          onTap: onTap == null
              ? null
              : () {
                  Navigator.pop(context);
                  onTap();
                },
        );
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF22262D),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          item(Icons.history, 'Recent words',
              () => session.pushFolder(GridSession.recentsFolderId)),
          item(
              Icons.replay,
              'Say the last word again',
              session.lastSpoken == null
                  ? null
                  : () => session.speech.speak(session.lastSpoken!)),
          item(
              Icons.copy_all,
              'Copy the message',
              session.message.isEmpty
                  ? null
                  : () {
                      Clipboard.setData(ClipboardData(text: session.message));
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Copied'),
                          duration: Duration(seconds: 1)));
                    }),
          if (widget.showOptions)
            item(Icons.settings_outlined, 'Settings', () async {
              final sc = context.read<SettingsController>();
              if (sc.restrictionsEnabled &&
                  !await sc.guardPrivileged(context)) {
                return;
              }
              if (!context.mounted) return;
              SettingsSheet.show(
                context,
                speech: session.speech,
                settings: context.read<SettingsController>().settings,
                settingsController: context.read<SettingsController>(),
                onChanged: () => context.read<SettingsController>().update(),
              );
            }),
        ]),
      ),
    );
  }

  // ---------------- grid ----------------

  Widget _grid(VocabView view, int cols, AppSettings settings) {
    final visible = view.cells.where((c) => !c.hidden).toList();
    final usePositions = visible.isNotEmpty &&
        visible.every((c) => c.col != null && c.row != null);
    final effCol = <int>[];
    final effRow = <int>[];
    for (var i = 0; i < visible.length; i++) {
      if (usePositions) {
        effCol.add(visible[i].col!);
        effRow.add(visible[i].row!);
      } else {
        effCol.add((i % cols) + 1);
        effRow.add((i ~/ cols) + 1);
      }
    }
    final nRows = effRow.fold<int>(0, (m, r) => r > m ? r : m);
    _gridCols = cols;
    _gridRows = nRows;

    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, cons) {
        final cellW = cons.maxWidth / cols;
        final cellH =
            (nRows > 0 ? cons.maxHeight / nRows : cellW).clamp(100.0, 180.0);
        return SingleChildScrollView(
            child: SizedBox(
                height: cellH * nRows,
                width: cons.maxWidth,
                child: Stack(children: [
                  for (var i = 0; i < visible.length; i++)
                    Positioned(
                      left: (effCol[i] - 1) * cellW + 3,
                      top: (effRow[i] - 1) * cellH + 3,
                      width: (visible[i].span.clamp(1, cols)) * cellW - 6,
                      height: cellH - 6,
                      child: _CellButton(
                        button: visible[i].button,
                        dimmed: visible[i].dimmed,
                        showEditBadge: widget.editMode,
                        settings: settings,
                        scanHighlight: _scanHighlightFor(effCol[i], effRow[i]),
                        onTap: () => _onCellTap(visible[i], settings),
                      ),
                    ),
                ])));
      }),
    );
  }

  int _scanHighlightFor(int col, int row) {
    if (_scanPhase == 1 && _scanRow == row) return 1;
    if (_scanPhase == 2 && _scanRow == row && _scanCol == col) return 2;
    return 0;
  }

  void _onCellTap(GridCell c, AppSettings settings) {
    // scanning: a tap selects the currently highlighted row/cell
    if (settings.scanningEnabled && _scanPhase > 0) {
      if (_scanPhase == 1) {
        setState(() {
          _scanPhase = 2;
          _scanCol = 1;
        });
      } else {
        final cell = _findCell(c);
        _stopScanning();
        if (cell != null) _onCellTapExecute(cell, settings);
      }
      return;
    }
    _onCellTapExecute(c, settings);
  }

  GridCell? _findCell(GridCell c) => c;

  TapFlags _tapFlags(AppSettings settings) => TapFlags(
        quietBuilder: settings.quietBuilder,
        vocalizeFolders: settings.vocalizeFolders,
        clearOnSpeak: settings.clearOnSpeak,
        goHomeOnPress: settings.goHomeOnPress,
        inputDebounceMs: settings.inputDebounceMs,
        haptics: settings.haptics,
        audioCues: settings.audioCues,
      );

  void _onCellTapExecute(GridCell c, AppSettings settings) {
    final flags = _tapFlags(settings);
    if (!widget.session.allowTap(flags)) return;
    if (settings.haptics) HapticFeedback.selectionClick();
    if (settings.audioCues) SystemSound.play(SystemSoundType.click);
    final btn = c.button;
    if (widget.editMode && widget.onEditButton != null) {
      widget.onEditButton!(btn);
      return;
    }
    if (btn.actions.any((a) => a.kind == ActionKind.sensoryGames)) {
      widget.onSensoryGames?.call();
      return;
    }
    widget.session.tap(btn, maxColumns: widget.maxColumns, flags: flags);
  }

  /// P2 scanning: toggle automatic row-column scanning for this grid.
  void _toggleScanning(AppSettings settings, int cols, int nRows) {
    if (nRows == 0 || cols == 0) return;
    if (_scanPhase != 0) {
      _stopScanning();
      setState(() {});
      return;
    }
    _scanPhase = 1;
    _scanRow = 1;
    _scanCol = null;
    _scanCellsInRow = cols;
    Stream.periodic(Duration(milliseconds: settings.scanDelayMs))
        .takeWhile((_) => mounted && _scanPhase != 0)
        .listen((_) {
      setState(() {
        if (_scanPhase == 1) {
          _scanRow = (_scanRow! % nRows) + 1;
        } else if (_scanPhase == 2) {
          _scanCol = (_scanCol! % _scanCellsInRow) + 1;
        }
      });
    });
  }

  void _stopScanning() {
    _scanPhase = 0;
    _scanRow = null;
    _scanCol = null;
  }
}

class _CellButton extends StatefulWidget {
  final VocabButton button;
  final bool dimmed;
  final bool showEditBadge;
  final AppSettings settings;
  final int scanHighlight; // 0 none, 1 row, 2 cell
  final VoidCallback onTap;
  const _CellButton({
    required this.button,
    required this.onTap,
    this.dimmed = false,
    this.showEditBadge = false,
    required this.settings,
    this.scanHighlight = 0,
  });

  @override
  State<_CellButton> createState() => _CellButtonState();
}

class _CellButtonState extends State<_CellButton> {
  double _dwellProgress = 0; // 0..1

  void _startDwell() {
    if (!widget.settings.dwellEnabled) return;
    final total = widget.settings.dwellSeconds;
    const tick = Duration(milliseconds: 40);
    var elapsed = 0.0;
    Future.doWhile(() async {
      await Future.delayed(tick);
      if (!mounted || _dwellProgress == 0 && elapsed > 0.05) return false;
      elapsed += tick.inMilliseconds / 1000.0;
      setState(() => _dwellProgress = (elapsed / total).clamp(0.0, 1.0));
      if (_dwellProgress >= 1.0) {
        widget.onTap();
        if (mounted) setState(() => _dwellProgress = 0);
        return false;
      }
      return true;
    });
  }

  void _cancelDwell() {
    if (mounted) setState(() => _dwellProgress = 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final bg = s.cviMode
        ? Colors.yellow
        : widget.button.kind == ButtonKind.folder
            ? const Color(0xFFFFF3C4)
            : kWordClassColors[widget.button.wordClass] ??
                const Color(0xFFEEEEEE);
    final sym = widget.button.symbol;
    final showSymbol = s.buttonView != ButtonView.textOnly;
    final showLabel = s.buttonView != ButtonView.symbolOnly &&
        s.labelPosition != LabelPosition.hidden;
    final labelWidget = showLabel
        ? Text(
            widget.button.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.05,
              color: s.cviMode ? Colors.black : Colors.black87,
              fontWeight: s.cviMode ? FontWeight.w900 : FontWeight.w600,
            ),
          )
        : const SizedBox.shrink();
    final symbolWidget = Expanded(
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: showSymbol
            ? LayoutBuilder(
                builder: (_, constraints) => SymbolLibrary.resolve(sym,
                    size: constraints.biggest.shortestSide))
            : const SizedBox.shrink(),
      ),
    );

    final content = Stack(children: [
      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (s.labelPosition == LabelPosition.above) ...[
          labelWidget,
          symbolWidget,
        ] else ...[
          symbolWidget,
          if (showLabel) labelWidget,
        ],
      ]),
      if (widget.showEditBadge)
        const Positioned(
          right: 0,
          top: 0,
          child: Icon(Icons.edit, size: 13, color: Colors.deepOrange),
        ),
      if (_dwellProgress > 0)
        Positioned.fill(
          child: Center(
            child: SizedBox(
              width: 46,
              height: 46,
              child: CircularProgressIndicator(
                value: _dwellProgress,
                strokeWidth: 4,
                color: Colors.deepOrangeAccent,
              ),
            ),
          ),
        ),
    ]);

    final borderColor = widget.scanHighlight == 2
        ? Colors.lightBlueAccent
        : widget.scanHighlight == 1
            ? Colors.lightGreen
            : widget.showEditBadge
                ? Colors.deepOrange
                : s.cviMode
                    ? Colors.black
                    : Colors.black26;
    final borderWidth = widget.scanHighlight > 0
        ? 4.0
        : widget.showEditBadge
            ? 2.0
            : 1.0;

    Widget cell = Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          padding: const EdgeInsets.all(4),
          child: content,
        ),
      ),
    );

    if (s.dwellEnabled) {
      // Dwell-to-activate: press-and-hold for the configured duration.
      cell = GestureDetector(
        onLongPressStart: (_) => _startDwell(),
        onLongPressEnd: (_) => _cancelDwell(),
        onLongPressCancel: _cancelDwell,
        child: cell,
      );
    }

    return Opacity(
      opacity: widget.dimmed ? 0.4 : 1,
      child: cell,
    );
  }
}
