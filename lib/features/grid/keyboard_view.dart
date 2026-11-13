import 'package:flutter/material.dart';
import '../../engine/i18n.dart';
import '../../engine/prediction.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import 'message_bar.dart';

/// On-screen letters, numbers and editing keys without a second keyboard.
/// The top is the same message bar and toolbar as Home: tap the message to
/// hear it again, the red button removes the last word.
class KeyboardView extends StatefulWidget {
  final Predictor predictor;
  final SpeechEngine speech;
  final SymbolLibrary? library;
  final String initialText;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onClose;
  final VoidCallback onSpeak;

  /// 'letters': say each letter and each finished word; 'words': only
  /// finished words; 'off'.
  final String typingSpeech;

  /// Show the current message, and saved / recent phrases (optional).
  final VoidCallback? onShow;
  final VoidCallback? onPhrases;
  const KeyboardView(
      {super.key,
      required this.predictor,
      required this.speech,
      this.library,
      this.initialText = '',
      required this.onTextChanged,
      required this.onClose,
      required this.onSpeak,
      this.typingSpeech = 'letters',
      this.onShow,
      this.onPhrases});
  @override
  State<KeyboardView> createState() => _KeyboardViewState();
}

class _KeyboardViewState extends State<KeyboardView> {
  late String _text;
  bool _uppercase = false;

  @override
  void initState() {
    super.initState();
    // Typing after picture words starts a new word ("want it" + "hi").
    final start = widget.initialText;
    _text = start.isEmpty || start.endsWith(' ') ? start : '$start ';
  }

  @override
  void didUpdateWidget(KeyboardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The message can change outside (e.g. cleared after speaking).
    if (widget.initialText.trimRight() != _text.trimRight()) {
      // Changed outside (cleared, or a phrase was added): the next letter
      // starts a new word.
      final start = widget.initialText;
      _text = start.isEmpty || start.endsWith(' ') ? start : '$start ';
    }
  }

  void _set(String text) {
    setState(() => _text = text);
    widget.onTextChanged(text);
  }

  void _insert(String text) => _set(_text + text);

  void _backspace() {
    if (_text.isEmpty) return;
    _set(_text.substring(0, _text.length - _text.characters.last.length));
  }

  /// Message bar button: removes the last whole word.
  void _deleteWord() {
    final words = _text.trimRight().split(' ')..removeWhere((w) => w.isEmpty);
    if (words.isNotEmpty) words.removeLast();
    _set(words.isEmpty ? '' : '${words.join(' ')} ');
  }

  String _keyLabel(String key) {
    if (!_uppercase) return key;
    if (key == ',' || key == '،') return I18n.language.rightToLeft ? '؟' : '?';
    if (key == '.') return '!';
    return key.toUpperCase();
  }

  void _typeKey(String key) {
    final typed = _keyLabel(key);
    _insert(typed);
    if (_uppercase && !RegExp(r'^[0-9]$').hasMatch(key)) {
      setState(() => _uppercase = false);
    }
    if (RegExp(r'^[\p{L}\p{N}]$', unicode: true).hasMatch(typed)) {
      // The speech engine says single letters by their name, without
      // "capital" (see SpeechText.forSpeech).
      if (widget.typingSpeech == 'letters') {
        widget.speech.speak(typed, interrupt: true);
      }
    } else if (typed != "'") {
      _sayFinishedWord();
    }
  }

  void _space() {
    _insert(' ');
    _sayFinishedWord();
  }

  /// Says the last word once it is finished (space, punctuation or a picked
  /// suggestion), straight from the key tap so Safari allows the speech.
  void _sayFinishedWord() {
    if (widget.typingSpeech == 'off') return;
    final word = RegExp(r"([\p{L}\p{N}']+)[^\p{L}\p{N}']*$", unicode: true)
        .firstMatch(_text)
        ?.group(1);
    if (word != null) widget.speech.speak(word, interrupt: true);
  }

  void _close() {
    if (_text.trim().isNotEmpty) {
      widget.predictor.learnFrom(_text, defaultAppStorageProvider);
    }
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = I18n.language;
    final prefix =
        RegExp(r"[\p{L}']+$", unicode: true).firstMatch(_text)?.group(0) ?? '';
    // English uses a frequency word list; other languages suggest the
    // board's own words in that language and the person's learned words.
    final suggestions = prefix.isEmpty
        ? <String>[]
        : widget.predictor
            .suggest(prefix)
            .take(3)
            .map((word) => prefix[0] == prefix[0].toUpperCase()
                ? '${word[0].toUpperCase()}${word.substring(1)}'
                : word)
            .toList();
    final header = <Widget>[
      MessageBar(
        message: _text,
        placeholder: 'Type your message',
        showCursor: true,
        onSpeak: widget.onSpeak,
        onDeleteWord: _deleteWord,
        onShow: widget.onShow,
      ),
      ValueListenableBuilder<String?>(
        valueListenable: widget.speech.error,
        builder: (context, error, _) => error == null
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.all(8),
                child: Text(I18n.t(error),
                    style: const TextStyle(color: Colors.white))),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: Row(children: [
          ToolbarButton(icon: Icons.arrow_back, label: 'Back', onTap: _close),
          ToolbarButton(
              icon: Icons.volume_up,
              label: 'Speak',
              onTap: widget.onSpeak,
              color: const Color(0xFF2E7D32)),
          if (widget.onPhrases != null)
            ToolbarButton(
                icon: Icons.star_outline,
                label: 'Phrases',
                onTap: widget.onPhrases),
          ToolbarButton(
              icon: Icons.clear_all,
              label: 'Clear',
              onTap: _text.isEmpty ? null : () => _set('')),
        ]),
      ),
      if (suggestions.isNotEmpty)
        SizedBox(
            height: 44,
            child: Row(children: [
              for (final word in suggestions)
                Expanded(
                    child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _key(word, () {
                    _set('${_text.substring(0, _text.length - prefix.length)}'
                        '$word ');
                    _sayFinishedWord();
                  }, suggestion: true),
                )),
            ])),
    ];
    final controls = Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: SizedBox(
            height: 52,
            child: Row(children: [
              Expanded(
                  flex: 2,
                  child: _key('Speak', widget.onSpeak, icon: Icons.volume_up)),
              const SizedBox(width: 6),
              Expanded(
                  flex: 3,
                  child: _key(I18n.t('Space'), _space, semantics: 'Space')),
              const SizedBox(width: 6),
              Expanded(
                  flex: 2,
                  child: _key('Delete', _backspace,
                      icon: Icons.backspace_outlined)),
            ])));
    final rows = lang.keyboardRows;
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      body: SafeArea(
        child: rows == null
            ? ListView(children: [...header, _deviceKeyboardField(), controls])
            : Column(children: [
                ...header,
                Expanded(child: _letterKeys(rows, lang.extraLetters)),
                controls,
              ]),
      ),
    );
  }

  Widget _letterKeys(List<String> letters, String accents) {
    final rows = [
      '1234567890',
      ...letters,
      if (accents.isNotEmpty) accents,
    ];
    return LayoutBuilder(builder: (context, constraints) {
      final height = ((constraints.maxHeight - 6 * rows.length) / rows.length)
          .clamp(40.0, 84.0);
      return Align(
        alignment: Alignment.bottomCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(children: [
            for (var row = 0; row < rows.length; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  height: height,
                  child: Row(children: [
                    if (row == letters.length)
                      _rowKey(_key(
                        'Shift',
                        () => setState(() => _uppercase = !_uppercase),
                        icon: Icons.keyboard_arrow_up,
                        selected: _uppercase,
                      )),
                    for (final key in rows[row].characters)
                      _rowKey(_key(_keyLabel(key), () => _typeKey(key))),
                  ]),
                ),
              ),
          ]),
        ),
      );
    });
  }

  Widget _rowKey(Widget key) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: key,
        ),
      );

  /// Device input methods handle composing characters in this script.
  Widget _deviceKeyboardField() => Padding(
        padding: const EdgeInsets.all(8),
        child: Column(children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: TextField(
              controller: _deviceText,
              autofocus: true,
              minLines: 1,
              maxLines: 3,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 22, color: Colors.black87),
              decoration: InputDecoration(
                hintText: I18n.t('Type your message'),
                hintStyle: const TextStyle(color: Colors.black54),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
              ),
              onSubmitted: (_) => _addDeviceText(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: Row(children: [
              for (final digit in '1234567890'.characters)
                _rowKey(_key(digit, () => _insertDeviceDigit(digit))),
            ]),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            width: double.infinity,
            child: _key(I18n.t('Add to message'), _addDeviceText,
                semantics: 'Add to message', suggestion: true),
          ),
        ]),
      );

  void _insertDeviceDigit(String digit) {
    final input = _deviceText.value;
    final selection = input.selection;
    final start = selection.isValid ? selection.start : input.text.length;
    final end = selection.isValid ? selection.end : start;
    _deviceText.value = TextEditingValue(
      text: input.text.replaceRange(start, end, digit),
      selection: TextSelection.collapsed(offset: start + digit.length),
    );
  }

  final TextEditingController _deviceText = TextEditingController();

  @override
  void dispose() {
    _deviceText.dispose();
    super.dispose();
  }

  void _addDeviceText() {
    final text = _deviceText.text.trim();
    if (text.isEmpty) return;
    _insert('$text ');
    _deviceText.clear();
    if (widget.typingSpeech != 'off') {
      widget.speech.speak(text, interrupt: true);
    }
  }

  Widget _key(String label, VoidCallback onTap,
          {IconData? icon,
          bool selected = false,
          bool suggestion = false,
          String? semantics}) =>
      Semantics(
        button: true,
        label: semantics ?? label,
        toggled: label == 'Shift' ? selected : null,
        excludeSemantics: true,
        child: Material(
          color: selected
              ? const Color(0xFF90CAF9)
              : suggestion
                  ? const Color(0xFFFFF59D)
                  : label == 'Speak'
                      ? const Color(0xFF2E7D32)
                      : (semantics ?? label) == 'Space'
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
                    ? Icon(icon,
                        size: 28,
                        color: label == 'Speak'
                            ? Colors.white
                            : const Color(0xFF202832))
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
