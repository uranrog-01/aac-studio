import 'package:flutter/material.dart';
import '../../engine/prediction.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';

/// On-screen letters, numbers and editing keys without a second keyboard.
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
  bool _uppercase = false;
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

  void _typeKey(String key) {
    _insert(_uppercase
        ? (key == ','
            ? '?'
            : key == '.'
                ? '!'
                : key.toUpperCase())
        : key);
    if (_uppercase && !RegExp(r'^[0-9]$').hasMatch(key)) {
      setState(() => _uppercase = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cursor = _controller.selection.isValid
        ? _controller.selection.start
        : _controller.text.length;
    final prefix = RegExp(r"[a-zA-Z']+$")
            .firstMatch(_controller.text.substring(0, cursor))
            ?.group(0) ??
        '';
    final suggestions = prefix.isEmpty
        ? <String>[]
        : widget.predictor
            .suggest(prefix)
            .take(3)
            .map((word) => prefix[0] == prefix[0].toUpperCase()
                ? '${word[0].toUpperCase()}${word.substring(1)}'
                : word)
            .toList();
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      body: SafeArea(
          child: Column(children: [
        Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.none,
                  minLines: 1,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      hintText: 'Type your message',
                      hintStyle: TextStyle(color: Colors.black54),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero),
                  style: const TextStyle(fontSize: 24, color: Colors.black87)),
            )),
        SizedBox(
            height: 44,
            child: Row(children: [
              TextButton.icon(
                  onPressed: () {
                    if (_controller.text.trim().isNotEmpty) {
                      widget.predictor.learnFrom(
                          _controller.text, defaultAppStorageProvider);
                    }
                    widget.onClose();
                  },
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back')),
              const Spacer(),
              TextButton.icon(
                  onPressed: widget.onSpeak,
                  style: TextButton.styleFrom(foregroundColor: Colors.white),
                  icon: const Icon(Icons.volume_up),
                  label: const Text('Speak')),
            ])),
        if (suggestions.isNotEmpty)
          SizedBox(
              height: 38,
              child: Row(children: [
                for (final word in suggestions)
                  Expanded(
                      child: TextButton(
                          onPressed: () {
                            final suffix = RegExp(r"^[a-zA-Z']*")
                                .firstMatch(_controller.text.substring(cursor))!
                                .group(0)!;
                            _controller.selection = TextSelection(
                                baseOffset: cursor - prefix.length,
                                extentOffset: cursor + suffix.length);
                            _insert('$word ');
                          },
                          child: Text(word,
                              maxLines: 1, overflow: TextOverflow.ellipsis))),
              ])),
        Expanded(child: LayoutBuilder(builder: (context, constraints) {
          final height = ((constraints.maxHeight - 18) / 4).clamp(44.0, 64.0);
          return Align(
              alignment: Alignment.bottomCenter,
              child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(children: [
                    for (final row in [
                      '1234567890',
                      'qwertyuiop',
                      "asdfghjkl'",
                      'zxcvbnm,.'
                    ])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: SizedBox(
                              height: height,
                              child: Row(children: [
                                if (row.startsWith('z'))
                                  Expanded(
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2),
                                          child: _key(
                                              'Shift',
                                              () => setState(() =>
                                                  _uppercase = !_uppercase),
                                              icon: Icons.keyboard_arrow_up,
                                              selected: _uppercase))),
                                for (final letter in row.split(''))
                                  Expanded(
                                      child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 2),
                                          child: _key(
                                              _uppercase
                                                  ? (letter == ','
                                                      ? '?'
                                                      : letter == '.'
                                                          ? '!'
                                                          : letter
                                                              .toUpperCase())
                                                  : letter,
                                              () => _typeKey(letter)))),
                              ]))),
                  ])));
        })),
        Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
            child: SizedBox(
                height: 52,
                child: Row(children: [
                  Expanded(flex: 4, child: _key('Space', () => _insert(' '))),
                  const SizedBox(width: 6),
                  Expanded(flex: 2, child: _key('Delete', _backspace)),
                ]))),
      ])),
    );
  }

  Widget _key(String label, VoidCallback onTap,
          {IconData? icon, bool selected = false}) =>
      Semantics(
        button: true,
        label: label,
        toggled: label == 'Shift' ? selected : null,
        excludeSemantics: true,
        child: Material(
          color: selected
              ? const Color(0xFF90CAF9)
              : label == 'Space'
                  ? const Color(0xFFD8EBFF)
                  : const Color(0xFFF3F5F7),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
              onTap: onTap,
              child: Center(
                  child: Padding(
                padding: const EdgeInsets.all(3),
                child: icon != null
                    ? Icon(icon, color: const Color(0xFF202832))
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(label,
                            style: TextStyle(
                                color: const Color(0xFF202832),
                                fontWeight: FontWeight.w600,
                                fontSize: label.length == 1 ? 24 : 17))),
              ))),
        ),
      );
}
