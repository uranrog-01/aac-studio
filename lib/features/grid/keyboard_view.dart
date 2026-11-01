import 'package:flutter/material.dart';

import '../../engine/prediction.dart';
import '../../engine/speech.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../../engine/storage.dart';

/// M4 (revised): typing view — hardware + on-screen keyboard, prediction bar,
/// auto-learn on close. Every keystroke goes **live** into the message window
/// (no send button); tapping the chat banner speaks it.
class KeyboardView extends StatefulWidget {
  final Predictor predictor;
  final SpeechEngine speech;
  final SymbolLibrary? library; // symbols-typing pack (24k+)
  final String initialText;
  final ValueChanged<String> onTextChanged; // live, every keystroke
  final VoidCallback onClose;
  final VoidCallback onSpeak; // banner tap

  const KeyboardView({
    super.key,
    required this.predictor,
    required this.speech,
    this.library,
    this.initialText = '',
    required this.onTextChanged,
    required this.onClose,
    required this.onSpeak,
  });

  @override
  State<KeyboardView> createState() => _KeyboardViewState();
}

enum _KbMode { abc, symbols }

class _KeyboardViewState extends State<KeyboardView> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  String _currentWord = '';
  _KbMode _mode = _KbMode.abc;
  String _symQuery = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _changed());
  }

  @override
  void dispose() {
    _learnAll();
    _controller.removeListener(_changed);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    // push text live to the message window (no send button)
    widget.onTextChanged(_controller.text);
    final text = _controller.text;
    final i = _controller.selection.baseOffset < 0 ? text.length : _controller.selection.baseOffset;
    var start = i;
    while (start > 0 && !_isSep(text[start - 1])) {
      start--;
    }
    final w = text.substring(start, i);
    if (w != _currentWord && mounted) {
      setState(() => _currentWord = w);
    }
  }

  /// Learn every word in the composed text (called when leaving the view).
  void _learnAll() {
    final t = _controller.text.trim();
    if (t.isNotEmpty) widget.predictor.learnFrom(t, defaultAppStorageProvider);
  }

  static bool _isSep(String ch) =>
      ch == ' ' || ch == '\n' || '.,!?;:\'"'.contains(ch);

  void _insert(String s) {
    final sel = _controller.selection;
    final i = sel.baseOffset < 0 ? _controller.text.length : sel.baseOffset;
    final t = _controller.text;
    _controller.value = TextEditingValue(
      text: t.substring(0, i) + s + t.substring(i),
      selection: TextSelection.collapsed(offset: i + s.length),
    );
  }

  void _backspace() {
    final sel = _controller.selection;
    var i = sel.baseOffset < 0 ? _controller.text.length : sel.baseOffset;
    if (i == 0) return;
    final t = _controller.text;
    _controller.value = TextEditingValue(
      text: t.substring(0, i - 1) + t.substring(i),
      selection: TextSelection.collapsed(offset: i - 1),
    );
  }

  void _applySuggestion(String w) {
    final text = _controller.text;
    final i = _controller.selection.baseOffset < 0
        ? text.length
        : _controller.selection.baseOffset;
    var start = i;
    while (start > 0 && !_isSep(text[start - 1])) {
      start--;
    }
    _controller.value = TextEditingValue(
      text: '${text.substring(0, start)}$w ${text.substring(i)}',
      selection: TextSelection.collapsed(offset: start + w.length + 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.predictor.suggest(_currentWord);
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      body: SafeArea(
        child: Column(
          children: [
            // chat banner — taps speak (M4 revised)
            GestureDetector(
              onTap: widget.onSpeak,
              child: Container(
                margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                constraints: const BoxConstraints(minHeight: 64),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black26),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _controller.text.isEmpty ? '… (tap to speak)' : _controller.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, color: Colors.black87),
                    ),
                  ),
                  const Icon(Icons.volume_up, color: Colors.black38),
                ]),
              ),
            ),
            Row(children: [
              _actionBtn(Icons.grid_view, 'Grid', widget.onClose),
              _actionBtn(Icons.text_fields, 'ABC',
                  () => setState(() => _mode = _KbMode.abc)),
              _actionBtn(Icons.extension, 'Symbols',
                  () => setState(() => _mode = _KbMode.symbols)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Type here — goes straight to the banner…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
            ]),
            if (_mode == _KbMode.abc) ...[
              // prediction bar
              Container(
                height: 44,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Row(children: [
                  for (final s in suggestions)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Material(
                          color: const Color(0xFF3A4049),
                          borderRadius: BorderRadius.circular(8),
                          child: InkWell(
                            onTap: () => _applySuggestion(s),
                            child: Center(
                              child: Text(s,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 13)),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (suggestions.isEmpty)
                    const Expanded(
                      child: Center(
                          child: Text('predictions…',
                              style: TextStyle(color: Colors.white24))),
                    ),
                ]),
              ),
              Expanded(child: _keyboard()),
            ] else ...[
              // M4b: symbols typing — search the open symbol library and
              // insert the word straight into the banner
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                child: TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.library == null
                        ? 'symbol library unavailable'
                        : 'Search ${widget.library!.size} symbols — tap to insert…',
                    hintStyle: const TextStyle(color: Colors.white38),
                    prefixIcon:
                        const Icon(Icons.search, color: Colors.white38),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (q) => setState(() => _symQuery = q),
                ),
              ),
              Expanded(
                child: widget.library == null
                    ? const SizedBox.shrink()
                    : GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 86,
                                mainAxisSpacing: 6,
                                crossAxisSpacing: 6),
                        itemCount: widget.library!.search(_symQuery, limit: 120).length,
                        itemBuilder: (context, i) {
                          final e = widget.library!
                              .search(_symQuery, limit: 120)[i];
                          return Material(
                            color: const Color(0xFF3A4049),
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _insertWord(e.name),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: SymbolLibrary.resolve(
                                          SymbolRef(e.name,
                                              pack: e.pack, key: e.key),
                                          size: 44),
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 4, left: 2, right: 2),
                                    child: Text(
                                      e.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 9.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Symbols typing: append the symbol's word to the message (live).
  void _insertWord(String word) {
    final t = _controller.text;
    final needsSpace = t.isNotEmpty && !t.endsWith(' ');
    _controller.text = needsSpace ? '$t $word ' : '$t$word ';
    _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length);
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback? onTap) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF3A4049),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: Colors.white, size: 20),
              Text(label, style: const TextStyle(color: Colors.white70, fontSize: 9)),
            ]),
          ),
        ),
      );

  static const rows = [
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  Widget _keyboard() {
    return Container(
      color: const Color(0xFF20242B),
      padding: const EdgeInsets.all(6),
      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
        for (final row in rows)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final k in row)
                Expanded(child: _key(k.toUpperCase(), () => _insert(k))),
            ],
          ),
        Row(children: [
          Expanded(child: _key('123', () {}, small: true)),
          Expanded(child: _key(',', () => _insert(', '))),
          Expanded(flex: 5, child: _key('space', () => _insert(' '))),
          Expanded(child: _key('.', () => _insert('. '))),
          Expanded(
              child: _key('⌫', _backspace,
                  small: true, color: const Color(0xFF4A5058))),
        ]),
      ]),
    );
  }

  Widget _key(String label, VoidCallback onTap,
          {bool small = false, Color? color}) => Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: color ?? const Color(0xFF3A4049),
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: small ? 38 : 44,
              child: Center(
                child: Text(label,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: small ? 11 : 16,
                        fontWeight: FontWeight.w500)),
              ),
            ),
          ),
        ),
      );
}
