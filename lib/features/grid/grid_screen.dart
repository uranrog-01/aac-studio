import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/prediction.dart';
import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../settings/settings_sheet.dart';
import 'keyboard_view.dart';

/// M2 grid engine: session controller + shared grid renderer used by both the
/// original app mode and the P2G research viewer.

class GridSession extends ChangeNotifier {
  final Vocabulary vocabulary;
  final SpeechEngine speech;
  final List<String> _stack; // folder ids
  String _message = '';
  bool showKeyboard = false;

  GridSession({required this.vocabulary, required this.speech})
      : _stack = [vocabulary.rootFolderId];

  String get currentFolderId => _stack.last;
  String get message => _message;
  bool get canGoBack => _stack.length > 1;
  VocabFolder? get currentFolder => vocabulary.folderOf(currentFolderId);

  VocabView? viewFor(String folderId, {int maxColumns = 6}) {
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

  void tap(VocabButton b, {int maxColumns = 6}) {
    if (b.kind == ButtonKind.folder) {
      // Auto-speak: folders announce their label when entered (P2G-style).
      if (b.speakText.isNotEmpty) speech.speak(b.speakText, style: b.voice);
      for (final a in b.actions) {
        if (a.kind == ActionKind.gotoFolder &&
            vocabulary.folders.containsKey(a.data)) {
          _stack.add(a.data);
          notifyListeners();
          return;
        }
      }
      return;
    }
    var spoke = false;
    String appended = '';
    for (final a in b.actions) {
      switch (a.kind) {
        case ActionKind.addText:
          appended = a.data.isNotEmpty ? a.data : b.speakText;
          _append(appended);
          break;
        case ActionKind.speakNow:
          speech.speak(a.data.isNotEmpty ? a.data : b.speakText, style: b.voice);
          spoke = true;
          break;
        case ActionKind.speakMessage:
          speech.speak(_message);
          spoke = true;
          break;
        case ActionKind.clearMessage:
          _message = '';
          break;
        case ActionKind.launchUrl:
          break; // explorer: no-op
        case ActionKind.gotoFolder:
          if (vocabulary.folders.containsKey(a.data)) _stack.add(a.data);
          break;
      }
    }
    if (b.kind == ButtonKind.item) {
      if (!b.actions.any((a) => a.kind == ActionKind.addText)) {
        appended = b.speakText;
        _append(appended);
      }
      // Auto-speak: tapping a symbol always says its word, unless an
      // action above already spoke (speakNow / speakMessage).
      if (!spoke && appended.isNotEmpty) {
        speech.speak(appended, style: b.voice);
      }
    }
    notifyListeners();
  }

  void _append(String text) {
    if (text.isEmpty) return;
    _message = _message.isEmpty ? text : '$_message $text';
  }

  /// M4 (revised): live typing — replaces the message window contents
  /// on every keystroke; no send step.
  void setMessageLive(String text) {
    _message = text;
    notifyListeners();
  }

  void toggleKeyboard() {
    showKeyboard = !showKeyboard;
    notifyListeners();
  }

  /// M5: replace a button (by id) in the current view and persist via callback.
  void replaceButton(VocabButton updated, {VoidCallback? persist}) {
    final view = viewFor(currentFolderId, maxColumns: 99);
    if (view == null) return;
    final cells = view.cells;
    for (var i = 0; i < cells.length; i++) {
      if (cells[i].button.id == updated.id) {
        cells[i] = GridCell(updated,
            col: cells[i].col, row: cells[i].row,
            span: cells[i].span, hidden: cells[i].hidden, dimmed: cells[i].dimmed);
        break;
      }
    }
    persist?.call();
    notifyListeners();
  }

  /// M5: append a new button cell to the current view.
  void addButton(VocabButton b, {VoidCallback? persist}) {
    final view = viewFor(currentFolderId, maxColumns: 99);
    if (view == null) return;
    view.cells.add(GridCell(b));
    persist?.call();
    notifyListeners();
  }

  /// M5: remove a button from the current view.
  void removeButton(String id, {VoidCallback? persist}) {
    final view = viewFor(currentFolderId, maxColumns: 99);
    if (view == null) return;
    view.cells.removeWhere((c) => c.button.id == id);
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
    _stack..clear()..add(vocabulary.rootFolderId);
    notifyListeners();
  }

  void clearMessage() {
    _message = '';
    notifyListeners();
  }

  void speakMessage() => speech.speak(_message);
}

class GridScreen extends StatelessWidget {
  final GridSession session;
  final int maxColumns;
  final String? titleOverride;

  /// M4 collaborators + M5 edit mode (only provided in My AAC mode).
  final Predictor? predictor;
  final SymbolLibrary? library;
  final bool editMode;
  final void Function(VocabButton updated)? onEditButton;
  final VoidCallback? onAddButton;

  /// App mode: show the in-app ⚙ Options button (speech, restrictions, edit).
  final bool showOptions;

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
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        if (session.showKeyboard && predictor != null) {
          return KeyboardView(
            predictor: predictor!,
            library: library,
            speech: session.speech,
            initialText: session.message,
            onTextChanged: session.setMessageLive,
            onSpeak: session.speakMessage,
            onClose: session.toggleKeyboard,
          );
        }
        final view = session.viewFor(session.currentFolderId, maxColumns: maxColumns);
        final folder = session.currentFolder;
        final cols = view?.columns.clamp(1, 12) ?? maxColumns;
        return Scaffold(
          backgroundColor: const Color(0xFF2B2F36),
          body: SafeArea(
            child: Column(
              children: [
                _messageWindow(context),
                _toolbar(context, folder?.label ?? titleOverride ?? ''),
                Expanded(
                  child: view == null
                      ? const Center(
                          child: Text('No view for this folder',
                              style: TextStyle(color: Colors.white54)))
                      : _grid(view, cols),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _messageWindow(BuildContext context) {
    return GestureDetector(
      onTap: session.speakMessage,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
        constraints: const BoxConstraints(minHeight: 64),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black26),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            session.message.isEmpty
                ? '…'
                : session.message,
            style: const TextStyle(fontSize: 22, color: Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _toolbarBtn(
      {required IconData icon, required String label, VoidCallback? onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF3A4049),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 22),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(BuildContext context, String folderLabel) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          _toolbarBtn(
            icon: Icons.arrow_back_ios_new,
            label: 'Back',
            onTap: session.canGoBack ? session.back : null,
          ),
          _toolbarBtn(icon: Icons.home_outlined, label: 'Home', onTap: session.goHome),
          Expanded(
            child: Center(
              child: Text(
                folderLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (editMode) ...[
            _toolbarBtn(icon: Icons.add_box, label: 'Add', onTap: onAddButton),
          ],
          _toolbarBtn(
              icon: Icons.keyboard_alt_outlined,
              label: 'Type',
              onTap: predictor != null ? session.toggleKeyboard : null),
          _toolbarBtn(icon: Icons.volume_up, label: 'Speak', onTap: session.speakMessage),
          _toolbarBtn(icon: Icons.backspace_outlined, label: 'Clear', onTap: session.clearMessage),
          if (showOptions)
            _toolbarBtn(icon: Icons.settings_outlined, label: 'Options', onTap: () {
              SettingsSheet.show(
                context,
                speech: session.speech,
                settings: context.read<SettingsController>().settings,
                settingsController: context.read<SettingsController>(),
                onChanged: () => context.read<SettingsController>().update(),
              );
            }),
        ],
      ),
    );
  }

  Widget _grid(VocabView view, int cols) {
    final visible = view.cells.where((c) => !c.hidden).toList();
    final usePositions = visible.isNotEmpty &&
        visible.every((c) => c.col != null && c.row != null);
    // Ordered (column grid) cells get sequential positions when the view has
    // no explicit layout coordinates.
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

    return Padding(
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, cons) {
        final cellW = cons.maxWidth / cols;
        final cellH = nRows > 0 ? cons.maxHeight / nRows : cellW;
        return Stack(children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: (effCol[i] - 1) * cellW + 3,
              top: (effRow[i] - 1) * cellH + 3,
              width: (visible[i].span.clamp(1, cols)) * cellW - 6,
              height: cellH - 6,
              child: _CellButton(
                button: visible[i].button,
                dimmed: visible[i].dimmed,
                showEditBadge: editMode,
                onTap: () {
                  if (editMode && onEditButton != null) {
                    onEditButton!(visible[i].button);
                  } else {
                    session.tap(visible[i].button, maxColumns: maxColumns);
                  }
                },
              ),
            ),
        ]);
      }),
    );
  }
}

class _CellButton extends StatelessWidget {
  final VocabButton button;
  final bool dimmed;
  final bool showEditBadge;
  final VoidCallback onTap;
  const _CellButton({
    required this.button,
    required this.onTap,
    this.dimmed = false,
    this.showEditBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = button.kind == ButtonKind.folder
        ? const Color(0xFFFFF3C4)
        : kWordClassColors[button.wordClass] ?? const Color(0xFFEEEEEE);
    final sym = button.symbol;
    return Opacity(
      opacity: dimmed ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: showEditBadge ? Colors.deepOrange : Colors.black26,
                  width: showEditBadge ? 2 : 1),
            ),
            padding: const EdgeInsets.all(4),
            child: Stack(children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: sym.imagePath != null
                          ? Image.file(
                              File(sym.imagePath!),
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) =>
                                  FittedBox(child: Text(sym.emoji)),
                            )
                          : SymbolLibrary.resolve(sym, size: 56),
                    ),
                  ),
                  Text(
                    button.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.05,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (showEditBadge)
                const Positioned(
                  right: 0,
                  top: 0,
                  child: Icon(Icons.edit, size: 13, color: Colors.deepOrange),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
