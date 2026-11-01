import 'package:flutter/material.dart';

import '../../engine/prediction.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';

/// M4: typing view — hardware + on-screen keyboard, prediction bar, and
/// auto-learn on send. Sends the composed text back to the message window.
class KeyboardView extends StatefulWidget {
  final Predictor predictor;
  final SpeechEngine speech;
  final String initialText;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;

  const KeyboardView({
    super.key,
    required this.predictor,
    required this.speech,
    this.initialText = '',
    required this.onSend,
    required this.onClose,
  });

  @override
  State<KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends State<KeyboardView> {
  late final TextEditingController _controller;
  final FocusNode _focus = FocusNode();
  String _currentWord = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.addListener(_syncCurrentWord);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncCurrentWord);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _syncCurrentWord() {
    final text = _controller.text;
    final i = text.length;
    var start = i;
    while (start > 0 && !_isSep(text[start - 1])) {
      start--;
    }
    final w = text.substring(start, i);
    if (w != _currentWord) {
      setState(() => _currentWord = w);
    }
  }

  static bool _isSep(String ch) => ch == ' ' || ch == '\n' || '.,!?;:\'"'.contains(ch);

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

  Future<void> _send({bool speak = false}) async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await widget.predictor.learnFrom(text, defaultAppStorageProvider);
    if (speak) await widget.speech.speak(text);
    if (mounted) widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.predictor.suggest(_currentWord);
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      body: SafeArea(
        child: Column(
          children: [
            // message preview + send row
            Container(
              margin: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: const BoxConstraints(minHeight: 64),
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _controller.text.isEmpty ? '…' : _controller.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 20, color: Colors.black87),
              ),
            ),
            Row(children: [
              _actionBtn(Icons.grid_view, 'Grid', widget.onClose),
              _actionBtn(Icons.volume_up, 'Speak', () => _send(speak: true)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    autofocus: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Type here…',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              _actionBtn(Icons.send, 'Add', () => _send()),
            ]),
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
          ],
        ),
      ),
    );
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
