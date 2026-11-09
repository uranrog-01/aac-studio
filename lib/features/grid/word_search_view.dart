import 'package:flutter/material.dart';

import '../../engine/i18n.dart';

import '../../models/domain.dart';
import 'message_bar.dart';

/// One search result: the button and the page it is on.
typedef SearchResult = ({VocabButton button, String folderId});

/// "Find a word": type part of a word and its picture button appears,
/// wherever it is on the board. Tapping a word adds and speaks it like on
/// its own page; tapping a category opens it. The message bar and toolbar
/// are the same as on Home.
class WordSearchView extends StatefulWidget {
  final String message;
  final List<SearchResult> Function(String query) search;
  final String Function(String folderId) pageName;

  /// Draws a result with the board's own button (colours, hold-to-select).
  final Widget Function(VocabButton button) tileBuilder;
  final VoidCallback onSpeak;
  final VoidCallback onDeleteWord;
  final VoidCallback onClear;
  final VoidCallback onClose;
  final int columns;

  const WordSearchView({
    super.key,
    required this.message,
    required this.search,
    required this.pageName,
    required this.tileBuilder,
    required this.onSpeak,
    required this.onDeleteWord,
    required this.onClear,
    required this.onClose,
    this.columns = 4,
  });

  @override
  State<WordSearchView> createState() => _WordSearchViewState();
}

class _WordSearchViewState extends State<WordSearchView> {
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final results = widget.search(query);
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      body: SafeArea(
        child: Column(children: [
          MessageBar(
            message: widget.message,
            placeholder: 'Tap symbols to build a message',
            onSpeak: widget.onSpeak,
            onDeleteWord: widget.onDeleteWord,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
            child: Row(children: [
              ToolbarButton(
                  icon: Icons.arrow_back, label: 'Back', onTap: widget.onClose),
              ToolbarButton(
                  icon: Icons.volume_up,
                  label: 'Speak',
                  onTap: widget.onSpeak,
                  color: const Color(0xFF2E7D32)),
              ToolbarButton(
                  icon: Icons.clear_all,
                  label: 'Clear',
                  onTap: widget.message.isEmpty ? null : widget.onClear),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              child: TextField(
                controller: _query,
                focusNode: _focus,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _focus.unfocus(),
                style: const TextStyle(fontSize: 22, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: I18n.t('Find a word'),
                  hintStyle: const TextStyle(color: Colors.black45),
                  prefixIcon: const Icon(Icons.search,
                      size: 30, color: Color(0xFF1E88E5)),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: I18n.t('Clear search'),
                          icon: const Icon(Icons.cancel, color: Colors.black45),
                          onPressed: _query.clear),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                ),
              ),
            ),
          ),
          Expanded(
            child: query.isEmpty
                ? _note(I18n.t('Type part of a word, like "app" for apple. '
                    'Tap a picture to say it.'))
                : results.isEmpty
                    ? _note(I18n.t('No picture for this word yet. '
                        'Use Type to write it.'))
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: widget.columns,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: results.length,
                        itemBuilder: (context, i) {
                          final r = results[i];
                          return Column(children: [
                            Expanded(child: widget.tileBuilder(r.button)),
                            const SizedBox(height: 2),
                            // Where the word lives, so it can be found again.
                            Text(
                              r.button.kind == ButtonKind.folder
                                  ? I18n.t('category')
                                  : widget.pageName(r.folderId),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ]);
                        },
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 17)),
      );
}
