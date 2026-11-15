import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../engine/i18n.dart';
import '../../engine/smart_words.dart';
import '../../models/domain.dart';
import '../grid/grid_screen.dart';
import 'tools.dart';

/// Listen to the other person: what they say is written large, with the
/// board's pictures for the words it knows, and answer buttons — the two
/// choices of an "A or B" question, and quick replies.
class ListenScreen extends StatefulWidget {
  final GridSession session;
  const ListenScreen({super.key, required this.session});

  @override
  State<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends State<ListenScreen> {
  final SpeechToText _stt = SpeechToText();
  final _typed = TextEditingController();
  bool? _available; // null while checking
  bool _listening = false;
  String _heard = '';

  /// "or" in each app language, for "Do you want juice or water?".
  static const _or = {
    'en': ['or'], 'sq': ['apo', 'ose', 'a'], 'de': ['oder'], 'fr': ['ou'],
    'es': ['o', 'u'], 'it': ['o', 'oppure'], 'pt': ['ou'], 'nl': ['of'],
    'tr': ['veya', 'yoksa', 'ya da'], 'pl': ['czy', 'albo', 'lub'],
    'ro': ['sau'], 'sv': ['eller'], 'da': ['eller'], 'no': ['eller'],
    'nb': ['eller'], 'fi': ['vai', 'tai'], 'el': ['ή'], 'hr': ['ili'],
    'sr': ['ili'], 'bs': ['ili'], 'mk': ['или'], 'ru': ['или'], 'uk': ['чи', 'або'],
    'cs': ['nebo'], 'sk': ['alebo'], 'hu': ['vagy'], 'bg': ['или'],
    'ar': ['أو', 'أم'],
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    bool ok;
    try {
      ok = await _stt.initialize(
        onStatus: (s) {
          if (!mounted) return;
          if (s == 'done' || s == 'notListening') {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) setState(() => _listening = false);
        },
      );
    } catch (_) {
      ok = false;
    }
    if (mounted) setState(() => _available = ok);
  }

  @override
  void dispose() {
    _stt.cancel();
    _typed.dispose();
    super.dispose();
  }

  Future<String?> _localeId() async {
    try {
      final locales = await _stt.locales();
      for (final want in I18n.language.voiceLocales) {
        final w = want.replaceAll('-', '_').toLowerCase();
        for (final l in locales) {
          if (l.localeId.replaceAll('-', '_').toLowerCase() == w) {
            return l.localeId;
          }
        }
      }
      final code = I18n.language.code.toLowerCase();
      for (final l in locales) {
        if (l.localeId.toLowerCase().startsWith(code)) return l.localeId;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    // Make sure the app's own voice is not heard as the other person.
    widget.session.speech.stop();
    final locale = await _localeId();
    setState(() {
      _heard = '';
      _listening = true;
    });
    await _stt.listen(
      onResult: (r) {
        if (mounted) setState(() => _heard = r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
          localeId: locale,
          partialResults: true,
          listenMode: ListenMode.dictation),
    );
  }

  /// The two choices of "… A or B?", or empty.
  List<String> _choices(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[?!.,;:¿¡]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final ors = _or[I18n.language.code] ?? const ['or'];
    for (var i = 1; i < words.length - 1; i++) {
      if (!ors.contains(words[i])) continue;
      // "a" is also a common word in Albanian; only a choice near the end.
      if (words[i] == 'a' && i < words.length - 3) continue;
      final left = words.sublist((i - 2).clamp(0, i), i);
      final right = words.sublist(i + 1, (i + 3).clamp(i + 1, words.length));
      // The words right before "or" are the first choice; drop question
      // words and verbs the board knows ("want juice" → "juice").
      String pick(List<String> part, {required bool fromEnd}) {
        if (part.isEmpty) return '';
        if (part.length == 1) return part.first;
        final keep = fromEnd ? part.last : part.first;
        final both = part.join(' ');
        return _knownWord(both) != null ? both : keep;
      }

      final a = pick(left, fromEnd: true);
      final b = pick(right, fromEnd: false);
      if (a.isNotEmpty && b.isNotEmpty && a != b) return [a, b];
    }
    return const [];
  }

  /// Board words (in the chosen language) → their button.
  Map<String, VocabButton>? _shown;

  VocabButton? _knownWord(String text) {
    final map = _shown ??= () {
      final m = <String, VocabButton>{};
      for (final w in const [
        'yes', 'no', 'want', 'eat', 'drink', 'water', 'juice', 'milk', 'play',
        'go', 'home', 'outside', 'toilet', 'help', 'more', 'stop', 'finished',
        'happy', 'sad', 'tired', 'hungry', 'thirsty', 'sick', 'hurt', 'mom',
        'dad', 'school', 'park', 'tv', 'music', 'book', 'ball', 'car', 'bed',
        'sleep', 'bath', 'apple', 'banana', 'bread', 'pizza', 'now', 'later',
        'today', 'tomorrow', 'you', 'i', 'what', 'where', 'who', 'when',
        'friend', 'teacher', 'food', 'snack', 'breakfast', 'lunch', 'dinner',
        'cold', 'hot', 'good', 'bad', 'like', 'need', 'come', 'look', 'wait',
      ]) {
        final b = widget.session.buttonForLabel(w);
        if (b != null) m[b.shownLabel.toLowerCase()] = b;
      }
      return m;
    }();
    final key = text.toLowerCase().trim();
    final hit = map[key];
    if (hit != null) return hit;
    final r = widget.session.findWords(key, limit: 1);
    if (r.isNotEmpty &&
        r.first.button.kind == ButtonKind.item &&
        r.first.button.shownLabel.toLowerCase() == key) {
      return r.first.button;
    }
    return null;
  }

  /// Pictures for the words of [text] the board knows (two-word words
  /// first: "ice cream").
  List<VocabButton> _pictures(String text) {
    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[?!.,;:¿¡"]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final out = <VocabButton>[];
    for (var i = 0; i < words.length; i++) {
      VocabButton? b;
      if (i + 1 < words.length) {
        b = _knownWord('${words[i]} ${words[i + 1]}');
        if (b != null) i++;
      }
      b ??= _knownWord(words[i]);
      if (b != null && !out.any((o) => o.id == b!.id)) out.add(b);
    }
    return out;
  }

  void _say(String text) => widget.session.sayNow(text);

  @override
  Widget build(BuildContext context) {
    final text = _heard.isNotEmpty ? _heard : _typed.text.trim();
    final pictures = text.isEmpty ? const <VocabButton>[] : _pictures(text);
    final choices = text.isEmpty ? const <String>[] : _choices(text);
    return ToolPage(
      title: 'Listen',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_available == false)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
                I18n.t('Listening is not available on this device. Type '
                    'what the other person said instead.'),
                style: const TextStyle(color: Colors.white70, fontSize: 16)),
          ),
        if (_available != false)
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  backgroundColor: _listening
                      ? const Color(0xFFC62828)
                      : const Color(0xFF1565C0),
                ),
                onPressed: _available == null ? null : _toggle,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_listening ? Icons.stop : Icons.mic, size: 54),
                  Text(I18n.t(_listening ? 'Stop' : 'Listen'),
                      style: const TextStyle(fontSize: 18)),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 10),
        if (_available != false)
          Text(
              I18n.t('Tap, then let the other person speak. Their words '
                  'appear here.'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60, fontSize: 14)),
        const SizedBox(height: 14),
        TextField(
          controller: _typed,
          style: const TextStyle(color: Colors.white, fontSize: 18),
          decoration: InputDecoration(
            hintText: I18n.t('Or type what they said'),
            hintStyle: const TextStyle(color: Colors.white54),
            filled: true,
            fillColor: const Color(0xFF22262D),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
          onChanged: (_) => setState(() => _heard = ''),
        ),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Text(text,
                style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87)),
          ),
        ],
        if (pictures.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in pictures)
              WordCard(button: b, size: 92, onTap: () => _say(b.speakText)),
          ]),
        ],
        const SizedBox(height: 18),
        Text(I18n.t('Answer'),
            style: const TextStyle(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (choices.isNotEmpty)
          Row(children: [
            for (final c in choices)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF6A1B9A),
                        padding: const EdgeInsets.symmetric(vertical: 22)),
                    onPressed: () => _say(c),
                    child: Column(children: [
                      if (_knownWord(c) != null)
                        SizedBox(
                            height: 70,
                            child: WordCard(button: _knownWord(c)!, size: 60)),
                      Text(c, style: const TextStyle(fontSize: 22)),
                    ]),
                  ),
                ),
              ),
          ]),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in SmartWords.quickReplies)
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: r == 'Yes'
                      ? const Color(0xFF2E7D32)
                      : r == 'No'
                          ? const Color(0xFFC62828)
                          : const Color(0xFF546E7A),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
              onPressed: () => _say(I18n.t(r)),
              child: Text(I18n.t(r), style: const TextStyle(fontSize: 18)),
            ),
        ]),
      ]),
    );
  }
}
