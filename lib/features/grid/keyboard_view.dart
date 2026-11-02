import 'package:flutter/material.dart';
import '../../engine/prediction.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';

/// Picture words and numbers, with no system keyboard overlay.
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
  static const symbols = {
    'yes': SymbolRef('✅', pack: 'modernflat', key: 'fluent-check-mark-button'),
    'no': SymbolRef('❌', pack: 'modernflat', key: 'fluent-cross-mark'),
    'help': SymbolRef('🆘', pack: 'modernflat', key: 'scene-help'),
    'stop': SymbolRef('🛑', pack: 'modernflat', key: 'fluent-stop-sign'),
    'water': SymbolRef('🚰', pack: 'modernflat', key: 'scene-water'),
    'eat': SymbolRef('🍽', pack: 'modernflat', key: 'scene-eat'),
    'bathroom': SymbolRef('🚻', pack: 'modernflat', key: 'fluent-restroom'),
    'rest': SymbolRef('😌', pack: 'modernflat', key: 'fluent-person-in-bed'),
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
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Back')),
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
          final columns = (constraints.maxWidth / 100).floor().clamp(3, 6);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _heading('Numbers'),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: constraints.maxWidth >= 600 ? 10 : 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 56,
                  children: [
                    for (final number in '1234567890'.split(''))
                      _key(number, () => _insert(number)),
                  ],
                ),
                _heading('Symbols'),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: 108,
                  children: [
                    for (final symbol in symbols.entries)
                      _key(symbol.key, () {
                        final cursor = _controller.selection.isValid
                            ? _controller.selection.start
                            : _controller.text.length;
                        final before = _controller.text.substring(0, cursor);
                        final separator = before.isNotEmpty &&
                                !RegExp(r'\s$').hasMatch(before)
                            ? ' '
                            : '';
                        _insert('$separator${symbol.key} ');
                      }, image: symbol.value),
                  ],
                ),
              ],
            ),
          );
        })),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: SizedBox(
            height: 56,
            child: Row(children: [
              Expanded(flex: 4, child: _key('Space', () => _insert(' '))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _key('Delete', _backspace)),
            ]),
          ),
        ),
      ])),
    );
  }

  Widget _heading(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
        child: Text(label,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
      );

  Widget _key(String label, VoidCallback onTap, {SymbolRef? image}) => Material(
        color: label == 'Space'
            ? const Color(0xFFD8EBFF)
            : const Color(0xFFF3F5F7),
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (image != null) ...[
                    Expanded(
                      child: Center(
                        child: SymbolLibrary.resolve(image, size: 64),
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(label,
                        maxLines: 1,
                        style: TextStyle(
                            color: const Color(0xFF202832),
                            fontWeight: FontWeight.w600,
                            fontSize:
                                image == null && label.length == 1 ? 26 : 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
