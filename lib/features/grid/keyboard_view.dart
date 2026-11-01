import 'package:flutter/material.dart';
import '../../engine/prediction.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';

/// One keyboard: symbols, letters and numbers, with no system keyboard overlay.
class KeyboardView extends StatefulWidget {
  final Predictor predictor;
  final SpeechEngine speech;
  final SymbolLibrary? library;
  final String initialText;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onClose;
  final VoidCallback onSpeak;
  const KeyboardView(
      {super.key,
      required this.predictor,
      required this.speech,
      this.library,
      this.initialText = '',
      required this.onTextChanged,
      required this.onClose,
      required this.onSpeak});
  @override
  State<KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends State<KeyboardView> {
  late final TextEditingController _controller;
  bool _upper = false;
  static const symbols = {
    'yes': SymbolRef('✅', pack: 'modern3d', key: 'fluent-check-mark-button'),
    'no': SymbolRef('❌', pack: 'modern3d', key: 'fluent-cross-mark'),
    'help': SymbolRef('🆘', pack: 'modern3d', key: 'scene-help'),
    'stop': SymbolRef('🛑', pack: 'modern3d', key: 'fluent-stop-sign'),
    'water': SymbolRef('🚰', pack: 'modern3d', key: 'scene-water'),
    'eat': SymbolRef('🍽', pack: 'modern3d', key: 'scene-eat'),
    'bathroom': SymbolRef('🚻', pack: 'modern3d', key: 'fluent-restroom'),
    'rest': SymbolRef('😌', pack: 'modern3d', key: 'fluent-person-in-bed'),
  };
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(KeyboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != _controller.text) {
      _controller.removeListener(_changed);
      _controller.value = TextEditingValue(
          text: widget.initialText,
          selection:
              TextSelection.collapsed(offset: widget.initialText.length));
      _controller.addListener(_changed);
    }
  }

  void _changed() {
    widget.onTextChanged(_controller.text);
    setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _insert(String text) {
    final selection = _controller.selection;
    final start = selection.isValid ? selection.start : _controller.text.length;
    final end = selection.isValid ? selection.end : start;
    _controller.value = TextEditingValue(
        text: _controller.text.replaceRange(start, end, text),
        selection: TextSelection.collapsed(offset: start + text.length));
  }

  void _backspace() {
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      _insert('');
      return;
    }
    final end = selection.isValid ? selection.start : _controller.text.length;
    if (end == 0) return;
    final prefix = _controller.text.substring(0, end);
    final start = end - prefix.characters.last.length;
    _controller.value = TextEditingValue(
        text: _controller.text.replaceRange(start, end, ''),
        selection: TextSelection.collapsed(offset: start));
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _controller.selection.isValid
        ? _controller.selection.start
        : _controller.text.length;
    final prefix =
        _controller.text.substring(0, cursor).split(RegExp(r'\s+')).last;
    final suggestions = prefix.isEmpty
        ? <String>[]
        : widget.predictor.suggest(prefix).take(3).toList();
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      body: SafeArea(
          child: Column(children: [
        Material(
            color: Colors.white,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.none,
                  onTap: widget.onSpeak,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      hintText: 'Tap keys or symbols',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero),
                  style: const TextStyle(fontSize: 22, color: Colors.black87)),
            )),
        Row(children: [
          TextButton.icon(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.predictor
                      .learnFrom(_controller.text, defaultAppStorageProvider);
                }
                widget.onClose();
              },
              icon: const Icon(Icons.grid_view),
              label: const Text('Symbols')),
        ]),
        if (suggestions.isNotEmpty)
          Wrap(children: [
            for (final word in suggestions)
              TextButton(
                  onPressed: () {
                    _controller.selection = TextSelection(
                        baseOffset: cursor - prefix.length,
                        extentOffset: cursor);
                    _insert('$word ');
                  },
                  child: Text(word)),
          ]),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final columns = (constraints.maxWidth / 64).floor().clamp(4, 10);
          return GridView.count(
            padding: const EdgeInsets.all(8),
            crossAxisCount: columns,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.9,
            children: [
              for (final symbol in symbols.entries)
                _key(symbol.key, () {
                  final text = _controller.text;
                  final separator =
                      text.isNotEmpty && !text.endsWith(' ') ? ' ' : '';
                  _insert('$separator${symbol.key} ');
                }, image: symbol.value),
              for (final letter in 'abcdefghijklmnopqrstuvwxyz'.split(''))
                _key(_upper ? letter.toUpperCase() : letter,
                    () => _insert(_upper ? letter.toUpperCase() : letter)),
              for (final number in '0123456789'.split(''))
                _key(number, () => _insert(number)),
              _key('Aa', () => setState(() => _upper = !_upper)),
              _key('Space', () => _insert(' ')),
              _key('.', () => _insert('.')),
              _key('?', () => _insert('?')),
              _key('Delete', _backspace),
            ],
          );
        })),
      ])),
    );
  }

  Widget _key(String label, VoidCallback onTap, {SymbolRef? image}) => Material(
        color: const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Semantics(
              button: true,
              label: label,
              excludeSemantics: true,
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (image != null)
                      Flexible(
                          child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: SymbolLibrary.resolve(image, size: 36))),
                    Text(label,
                        style: TextStyle(
                            color: Colors.black87,
                            fontSize:
                                image == null && label.length == 1 ? 26 : 14)),
                  ])),
        ),
      );
}
