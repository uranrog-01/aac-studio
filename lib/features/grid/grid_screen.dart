import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../engine/i18n.dart';
import '../../engine/prediction.dart';
import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../settings/settings_sheet.dart';
import 'keyboard_view.dart';
import 'message_bar.dart';
import 'phrases.dart';
import 'word_search_view.dart';

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
          appended = b.textFor(a);
          _append(appended);
          break;
        case ActionKind.speakNow:
          _speak(b.textFor(a), b, f);
          spoke = true;
          break;
        case ActionKind.speakMessage:
          _speakMessage(f);
          spoke = true;
          break;
        case ActionKind.clearMessage:
          _message = '';
          _pieces.clear();
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
    if (f?.clearOnSpeak ?? false) {
      _message = '';
      _pieces.clear();
    }
    if (f?.goHomeOnPress ?? false) {
      _stack
        ..clear()
        ..add(vocabulary.rootFolderId);
    }
  }

  /// The last spoken messages, newest first (Phrases > Recent messages).
  final List<String> recentMessages = [];

  void _speakMessage(TapFlags? f) {
    if (_message.trim().isEmpty) return;
    speech.speak(_message);
    lastSpoken = _message;
    final said = _message.trim();
    recentMessages
      ..remove(said)
      ..insert(0, said);
    if (recentMessages.length > 10) recentMessages.removeLast();
    if (f?.clearOnSpeak ?? false) {
      _message = '';
      _pieces.clear();
    }
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

  /// What each symbol tap added, so Delete removes "thank you" as one.
  final List<String> _pieces = [];

  void _append(String text) {
    if (text.isEmpty) return;
    _message = _message.isEmpty ? text : '$_message $text';
    _pieces.add(text);
  }

  /// M4: live typing — replaces the message window contents on every
  /// keystroke (no send step).
  void setMessageLive(String text) {
    _message = text;
    _pieces.clear();
    notifyListeners();
  }

  /// Removes the last symbol's words (or the last typed word).
  void removeLastWord() {
    final text = _message.trimRight();
    if (_pieces.isNotEmpty && text.endsWith(_pieces.last)) {
      _message =
          text.substring(0, text.length - _pieces.removeLast().length).trim();
    } else {
      _pieces.clear();
      final words = text.split(' ')..removeWhere((w) => w.isEmpty);
      if (words.isNotEmpty) words.removeLast();
      _message = words.join(' ');
    }
    notifyListeners();
  }

  void removeWordAt(int index) {
    final words = _message.trim().split(' ')..removeWhere((w) => w.isEmpty);
    if (index >= 0 && index < words.length) words.removeAt(index);
    _message = words.join(' ').trim();
    notifyListeners();
  }

  /// Adds a saved or recent phrase to the message and says it.
  void addPhrase(String phrase) {
    if (phrase.trim().isEmpty) return;
    _append(phrase.trim());
    speech.speak(phrase.trim());
    lastSpoken = phrase.trim();
    notifyListeners();
  }

  void toggleKeyboard() {
    showKeyboard = !showKeyboard;
    showSearch = false;
    notifyListeners();
  }

  /// "Find a word" screen.
  bool showSearch = false;

  void toggleSearch() {
    showSearch = !showSearch;
    showKeyboard = false;
    notifyListeners();
  }

  /// Every reachable button with the page it is on, nearest to Home first
  /// (pages in the order a person reaches them). Built once per session.
  List<({VocabButton button, String folderId})>? _searchIndex;

  List<({VocabButton button, String folderId})> _buildSearchIndex() {
    final out = <({VocabButton button, String folderId})>[];
    final seen = <String>{vocabulary.rootFolderId};
    final queue = [vocabulary.rootFolderId];
    while (queue.isNotEmpty) {
      final folderId = queue.removeAt(0);
      for (final view in vocabulary.viewsByFolder[folderId] ?? const []) {
        for (final cell in view.cells) {
          if (cell.hidden) continue;
          out.add((button: cell.button, folderId: folderId));
          for (final a in cell.button.actions) {
            if (a.kind == ActionKind.gotoFolder && seen.add(a.data)) {
              queue.add(a.data);
            }
          }
        }
      }
    }
    return out;
  }

  /// Words (and categories) whose label matches [query]: exact first, then
  /// starts-with, then a word inside starts-with, then anywhere. One result
  /// per word; it shows the page nearest to Home.
  List<({VocabButton button, String folderId})> findWords(String query,
      {int limit = 80}) {
    final q = query.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (q.isEmpty) return const [];
    final index = _searchIndex ??= _buildSearchIndex();
    final ranked = <(int, int, int, ({VocabButton button, String folderId}))>[];
    final labels = <String>{};
    for (var i = 0; i < index.length; i++) {
      final entry = index[i];
      final button = entry.button;
      if (button.kind == ButtonKind.action) continue;
      // The word as shown (chosen language) ranks first; the English
      // word is also found, so a caregiver can search either way.
      final shown = button.shownLabel.toLowerCase();
      final label = button.label.toLowerCase();
      final key = button.kind == ButtonKind.folder ? 'folder:$label' : label;
      if (labels.contains(key)) continue;
      int? rankOf(String text) => text == q
          ? 0
          : text.startsWith(q)
              ? 1
              : text.split(RegExp(r"[\s,./()-]+")).any((w) => w.startsWith(q))
                  ? 2
                  : text.contains(q)
                      ? 3
                      : null;
      // Best match in either language; on a tie the shown word wins.
      final inShown = rankOf(shown);
      final inEnglish = shown == label ? null : rankOf(label);
      final candidates = [
        if (inShown != null) inShown * 2,
        if (inEnglish != null) inEnglish * 2 + 1,
      ];
      final rank = candidates.isEmpty
          ? null
          : candidates.reduce((a, b) => a < b ? a : b);
      if (rank == null) continue;
      labels.add(key);
      ranked.add((rank, shown.length, i, entry));
    }
    ranked.sort((a, b) => a.$1 != b.$1
        ? a.$1.compareTo(b.$1)
        : a.$2 != b.$2
            ? a.$2.compareTo(b.$2)
            : a.$3.compareTo(b.$3));
    return [for (final r in ranked.take(limit)) r.$4];
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
    _searchIndex = null;
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
    _searchIndex = null;
    final view = viewFor(currentFolderId, maxColumns: 99);
    if (view == null) return;
    view.cells.add(GridCell(b));
    vocabulary.removedIds.remove(b.id);
    persist?.call();
    notifyListeners();
  }

  /// M5: remove a button from the current view.
  void removeButton(String id, {VoidCallback? persist}) {
    _searchIndex = null;
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
    _pieces.clear();
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

/// One thing switch scanning can pick: a grid cell or a toolbar button.
class _ScanTarget {
  final String key;
  final VoidCallback activate;
  const _ScanTarget(this.key, this.activate);
}

/// A toolbar control, shared by the drawn toolbar and the scan order.
class _ToolEntry {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;
  const _ToolEntry(this.icon, this.label, this.onTap,
      {this.color, this.active = false});
}

class _GridScreenState extends State<GridScreen> {
  // Switch scanning: groups are the grid rows (top to bottom) followed by
  // the toolbar. First a whole group is highlighted; a select opens it and
  // its items are highlighted one by one; a second select activates the
  // highlighted item. Scanning keeps running afterwards so a switch user is
  // never left without a way to continue.
  bool _scanning = false;
  int _scanGroup = 0;
  int? _scanItem; // null = group phase
  int _scanItemSteps = 0;
  Timer? _scanTimer;
  final FocusNode _scanFocus = FocusNode(debugLabel: 'switch scanning');
  List<({int col, int row, GridCell cell})> _layout = const [];
  List<_ToolEntry> _tools = const [];
  late AppSettings _settings;

  @override
  void dispose() {
    _scanTimer?.cancel();
    _scanFocus.dispose();
    _gridScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    _settings = settings;
    if (_scanning && !settings.scanningEnabled) _stopScanning();
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
            typingSpeech: settings.typingSpeech,
            onShow: () => _showBig(context, settings),
            onPhrases: () => _openPhrases(context),
          );
        }
        if (widget.session.showSearch) {
          final session = widget.session;
          return WordSearchView(
            message: session.message,
            search: session.findWords,
            pageName: (id) =>
                I18n.word(session.vocabulary.folders[id]?.label ?? ''),
            columns: widget.maxColumns.clamp(3, 5),
            onSpeak: () => session.speakMessage(flags: _tapFlags(settings)),
            onDeleteWord: session.removeLastWord,
            onClear: session.clearMessage,
            onClose: session.toggleSearch,
            tileBuilder: (button) => _CellButton(
              button: button,
              settings: settings,
              showEditBadge: widget.editMode,
              onTap: () {
                // A category result opens that category.
                if (button.kind == ButtonKind.folder) session.toggleSearch();
                _onCellTapExecute(GridCell(button), settings);
              },
            ),
          );
        }
        // A newly opened category starts at its top, not at the previous
        // page's scroll position.
        if (_shownFolder != widget.session.currentFolderId) {
          _shownFolder = widget.session.currentFolderId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_gridScroll.hasClients) _gridScroll.jumpTo(0);
          });
        }
        final view = widget.session.viewFor(widget.session.currentFolderId,
            maxColumns: widget.maxColumns);
        final folder = widget.session.currentFolder ??
            widget.session._virtualFolder(widget.session.currentFolderId);
        final cols = view?.columns.clamp(1, 12) ?? widget.maxColumns;
        final body = view == null
            ? Center(
                child: Text(I18n.t('Nothing here yet'),
                    style: TextStyle(
                        color:
                            settings.cviMode ? Colors.white : Colors.white54)))
            : _grid(view, cols, settings);
        if (view == null) _layout = const [];

        final messageWindow = _messageWindow(context, settings);
        final toolbar = _toolbar(
            context, folder?.label ?? widget.titleOverride ?? '', settings);

        // While scanning, a touch anywhere on the grid is the "select"
        // switch (switch-adapted touch), so it can never pick the wrong cell.
        final gridArea = _scanning
            ? Stack(children: [
                Positioned.fill(child: body),
                Positioned.fill(
                  child: Semantics(
                    button: true,
                    label: 'Select highlighted',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _scanSelect,
                    ),
                  ),
                ),
              ])
            : body;

        final children = settings.messageWindowTop
            ? [messageWindow, toolbar, Expanded(child: gridArea)]
            : [Expanded(child: gridArea), toolbar, messageWindow];

        return Focus(
          focusNode: _scanFocus,
          onKeyEvent: _onScanKey,
          child: Scaffold(
            backgroundColor:
                settings.cviMode ? Colors.black : const Color(0xFF2B2F36),
            body: SafeArea(child: Column(children: children)),
          ),
        );
      },
    );
  }

  /// Bluetooth/USB switch interfaces send Space or Enter.
  KeyEventResult _onScanKey(FocusNode node, KeyEvent event) {
    if (!_scanning || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select) {
      _scanSelect();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ---------------- message window (P0 upgrades) ----------------

  Widget _messageWindow(BuildContext context, AppSettings settings) {
    final session = widget.session;
    return Column(children: [
      MessageBar(
        message: session.message,
        placeholder: 'Tap symbols to build a message',
        onSpeak: () => session.speakMessage(flags: _tapFlags(settings)),
        // Removes the last word (a whole symbol, e.g. "thank you").
        onDeleteWord: session.removeLastWord,
        deleteHighlight: _scanHighlightFor('msg:delete'),
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

  /// Six large controls a communicator uses every day; caregiver and
  /// occasional tools (recent words, repeat, copy, settings) live in More.
  Widget _toolbar(BuildContext context, String folderLabel, AppSettings s) {
    final session = widget.session;
    _tools = [
      _ToolEntry(
          Icons.arrow_back, 'Back', session.canGoBack ? session.back : null),
      _ToolEntry(Icons.home_rounded, 'Home', session.goHome),
      if (widget.editMode) _ToolEntry(Icons.add_box, 'Add', widget.onAddButton),
      if (s.scanningEnabled)
        _ToolEntry(Icons.accessibility_new, _scanning ? 'Stop scan' : 'Scan',
            _toggleScanning,
            active: _scanning),
      _ToolEntry(Icons.keyboard_alt_outlined, 'Type',
          widget.predictor != null ? session.toggleKeyboard : null),
      _ToolEntry(Icons.search, 'Find', session.toggleSearch),
      _ToolEntry(Icons.volume_up, 'Speak',
          () => session.speakMessage(flags: _tapFlags(s)),
          color: const Color(0xFF2E7D32)),
      _ToolEntry(Icons.clear_all, 'Clear', session.clearMessage),
      _ToolEntry(Icons.more_horiz, 'More', () => _showMore(context)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(children: [
        for (final t in _tools)
          ToolbarButton(
              icon: t.icon,
              label: t.label,
              onTap: t.onTap,
              color: t.color,
              active: t.active,
              scanHighlight: _scanHighlightFor('tool:${t.label}')),
      ]),
    );
  }

  void _showBig(BuildContext context, AppSettings settings) => showBigMessage(
      context,
      widget.session.message,
      () => widget.session.speakMessage(flags: _tapFlags(settings)));

  void _openPhrases(BuildContext context) {
    final controller = context.read<SettingsController>();
    PhrasesSheet.show(
      context,
      message: widget.session.message,
      phrases: List.of(controller.settings.phrases),
      recent: List.of(widget.session.recentMessages),
      onPick: widget.session.addPhrase,
      onSave: (phrase) {
        controller.settings.phrases.insert(0, phrase);
        controller.update();
      },
      onDelete: (phrase) {
        controller.settings.phrases.remove(phrase);
        controller.update();
      },
    );
  }

  void _showMore(BuildContext context) {
    final session = widget.session;
    final messenger = ScaffoldMessenger.of(context);
    Widget item(IconData icon, String label, VoidCallback? onTap) => ListTile(
          leading: Icon(icon, color: Colors.white),
          title: Text(I18n.t(label),
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
          item(Icons.star_outline, 'Phrases', () => _openPhrases(context)),
          item(Icons.fit_screen, 'Show big',
              () => _showBig(context, context.read<SettingsController>().settings)),
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
                      messenger.showSnackBar(SnackBar(
                          content: Text(I18n.t('Copied')),
                          duration: const Duration(seconds: 1)));
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
    _layout = [
      for (var i = 0; i < visible.length; i++)
        (col: effCol[i], row: effRow[i], cell: visible[i]),
    ];

    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, cons) {
        final cellW = cons.maxWidth / cols;
        final cellH =
            (nRows > 0 ? cons.maxHeight / nRows : cellW).clamp(100.0, 180.0);
        _cellHeight = cellH;
        return SingleChildScrollView(
            controller: _gridScroll,
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
                        scanHighlight:
                            _scanHighlightFor('cell:${effCol[i]}:${effRow[i]}'),
                        onTap: () => _onCellTapExecute(visible[i], settings),
                      ),
                    ),
                ])));
      }),
    );
  }

  final ScrollController _gridScroll = ScrollController();
  double _cellHeight = 100;
  String? _shownFolder;

  // ---------------- switch scanning ----------------

  /// Scan groups in order: each grid row that has buttons, then the
  /// toolbar's usable controls.
  List<List<_ScanTarget>> _scanGroups() {
    final rows = <int, List<({int col, int row, GridCell cell})>>{};
    for (final e in _layout) {
      rows.putIfAbsent(e.row, () => []).add(e);
    }
    final groups = <List<_ScanTarget>>[];
    for (final row in rows.keys.toList()..sort()) {
      final cells = rows[row]!..sort((a, b) => a.col.compareTo(b.col));
      groups.add([
        for (final e in cells)
          _ScanTarget('cell:${e.col}:${e.row}',
              () => _onCellTapExecute(e.cell, _settings)),
      ]);
    }
    final tools = [
      if (widget.session.message.trim().isNotEmpty)
        _ScanTarget('msg:delete', widget.session.removeLastWord),
      for (final t in _tools)
        if (t.onTap != null) _ScanTarget('tool:${t.label}', t.onTap!),
    ];
    if (tools.isNotEmpty) groups.add(tools);
    return groups;
  }

  /// 0 none, 1 its group is highlighted, 2 it is the highlighted item.
  int _scanHighlightFor(String key) {
    if (!_scanning) return 0;
    final groups = _scanGroups();
    if (groups.isEmpty) return 0;
    final group = groups[_scanGroup.clamp(0, groups.length - 1)];
    final item = _scanItem;
    if (item == null) {
      return group.any((t) => t.key == key) ? 1 : 0;
    }
    return group[item.clamp(0, group.length - 1)].key == key ? 2 : 0;
  }

  void _toggleScanning() {
    if (_scanning) {
      setState(_stopScanning);
      return;
    }
    setState(() {
      _scanning = true;
      _scanGroup = 0;
      _scanItem = null;
      _scanItemSteps = 0;
    });
    _scanFocus.requestFocus();
    _restartScanTimer();
  }

  void _restartScanTimer() {
    _scanTimer?.cancel();
    _scanTimer = Timer.periodic(
        Duration(milliseconds: _settings.scanDelayMs.clamp(200, 10000)),
        (_) => _scanStep());
  }

  void _scanStep() {
    if (!mounted || !_scanning) return;
    if (widget.session.showKeyboard) return; // paused while typing
    final groups = _scanGroups();
    if (groups.isEmpty) return;
    setState(() {
      _scanGroup = _scanGroup.clamp(0, groups.length - 1);
      final item = _scanItem;
      if (item == null) {
        _scanGroup = (_scanGroup + 1) % groups.length;
      } else {
        final size = groups[_scanGroup].length;
        _scanItemSteps++;
        if (_scanItemSteps >= size * 2) {
          // Two passes without a choice: back to choosing a group.
          _scanItem = null;
          _scanItemSteps = 0;
        } else {
          _scanItem = (item + 1) % size;
        }
      }
    });
    _revealScannedRow();
  }

  /// Keeps the highlighted grid row on screen when the grid scrolls.
  void _revealScannedRow() {
    if (!_gridScroll.hasClients) return;
    final groups = _scanGroups();
    if (_scanGroup >= groups.length) return;
    final first = groups[_scanGroup].first.key;
    if (!first.startsWith('cell:')) return;
    final row = int.parse(first.split(':')[2]);
    final top = (row - 1) * _cellHeight;
    final position = _gridScroll.position;
    if (top < position.pixels ||
        top + _cellHeight > position.pixels + position.viewportDimension) {
      _gridScroll.jumpTo(top.clamp(0.0, position.maxScrollExtent));
    }
  }

  /// The single switch: opens the highlighted group, or activates the
  /// highlighted item and starts again from the top.
  void _scanSelect() {
    if (!_scanning) return;
    if (!widget.session.allowTap(_tapFlags(_settings))) return;
    final groups = _scanGroups();
    if (groups.isEmpty) return;
    final group = groups[_scanGroup.clamp(0, groups.length - 1)];
    final item = _scanItem;
    if (item == null && group.length > 1) {
      setState(() {
        _scanItem = 0;
        _scanItemSteps = 0;
      });
      _restartScanTimer();
      return;
    }
    final target = group[(item ?? 0).clamp(0, group.length - 1)];
    setState(() {
      _scanGroup = 0;
      _scanItem = null;
      _scanItemSteps = 0;
    });
    target.activate();
    if (_scanning) {
      _restartScanTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _gridScroll.hasClients) _gridScroll.jumpTo(0);
      });
    }
  }

  /// Safe to call during build (no setState).
  void _stopScanning() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _scanning = false;
    _scanItem = null;
    _scanGroup = 0;
    _scanItemSteps = 0;
  }

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
    // Scan selections already passed the debounce check.
    if (!_scanning && !widget.session.allowTap(flags)) return;
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

  Timer? _dwellTimer;
  Offset _dwellOrigin = Offset.zero;

  /// Hold to select: the circle starts filling the moment the finger lands
  /// and the button fires only when it is full. Lifting early does nothing,
  /// so brushes and accidental taps are ignored.
  void _startDwell() {
    if (!widget.settings.dwellEnabled) return;
    _dwellTimer?.cancel();
    final totalMs = (widget.settings.dwellSeconds * 1000).clamp(100.0, 10000.0);
    const tickMs = 30;
    _dwellTimer = Timer.periodic(const Duration(milliseconds: tickMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final progress = (timer.tick * tickMs / totalMs).clamp(0.0, 1.0);
      if (progress >= 1.0) {
        timer.cancel();
        _dwellTimer = null;
        setState(() => _dwellProgress = 0);
        widget.onTap();
        return;
      }
      setState(() => _dwellProgress = progress);
    });
  }

  void _cancelDwell() {
    _dwellTimer?.cancel();
    _dwellTimer = null;
    if (mounted && _dwellProgress != 0) setState(() => _dwellProgress = 0);
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    super.dispose();
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
            widget.button.shownLabel,
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
        // With hold-to-select on, a quick tap must not activate the button.
        onTap: s.dwellEnabled ? null : widget.onTap,
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
      // Dwell-to-activate: press and hold for the configured duration.
      // A raw Listener starts at once (no long-press delay first) and is
      // cancelled when the finger lifts or the gesture is taken away.
      cell = Semantics(
        button: true,
        label: widget.button.shownLabel,
        hint: 'Hold to select',
        onTap: widget.onTap, // screen readers still activate directly
        child: Listener(
          onPointerDown: (e) {
            _dwellOrigin = e.position;
            _startDwell();
          },
          // Sliding the finger (e.g. to scroll) cancels the hold.
          onPointerMove: (e) {
            if ((e.position - _dwellOrigin).distance > 18) _cancelDwell();
          },
          onPointerUp: (_) => _cancelDwell(),
          onPointerCancel: (_) => _cancelDwell(),
          child: cell,
        ),
      );
    }

    return Opacity(
      opacity: widget.dimmed ? 0.4 : 1,
      child: cell,
    );
  }
}
