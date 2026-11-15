import 'dart:async';

import '../models/domain.dart';
import 'storage.dart';

/// One word as it went into the message: its English board label, its
/// word class and the text shown in the chosen language.
class SaidWord {
  final String word; // English board label, lower case
  final WordClass wordClass;
  final String text; // as shown / spoken
  const SaidWord(this.word, this.wordClass, this.text);
}

/// The board's helpers that make it answer faster: next-word ideas, words
/// for the time of day, quick replies and a fuller sentence.
///
/// Everything runs on the device; what it learns stays on the device.
class SmartWords {
  SmartWords._();
  static final SmartWords instance = SmartWords._();

  // ------------------------------------------------------------ next word

  /// Words that usually come next in a child's or adult's first sentences
  /// (core vocabulary research: "I want", "want more", "go outside").
  static const Map<String, List<String>> starters = {
    'i': ['want', 'need', 'like', 'feel', "don't know", 'go', 'love', 'help'],
    'you': ['want', 'help', 'go', 'like', 'play', 'stop', 'come'],
    'he': ['want', 'like', 'go', 'help', 'play'],
    'she': ['want', 'like', 'go', 'help', 'play'],
    'we': ['go', 'play', 'eat', 'want', 'help'],
    'they': ['go', 'play', 'want', 'like'],
    'want': ['more', 'eat', 'drink', 'go', 'play', 'help', 'water', 'toilet', 'break', 'hug'],
    'need': ['help', 'toilet', 'break', 'water', 'drink', 'eat', 'sleep', 'more'],
    'like': ['this', 'that', 'music', 'play', 'eat', 'more'],
    "don't like": ['this', 'that', 'it'],
    'love': ['you', 'mom', 'dad', 'this', 'music'],
    'feel': ['happy', 'sad', 'tired', 'sick', 'angry', 'scared', 'hot', 'cold'],
    'go': ['home', 'outside', 'toilet', 'park', 'school', 'bed', 'out'],
    'eat': ['more', 'apple', 'banana', 'bread', 'pizza', 'chicken', 'rice'],
    'drink': ['water', 'juice', 'milk', 'more'],
    'play': ['ball', 'music', 'games', 'outside', 'more', 'with'],
    'help': ['me', 'please', 'open'],
    'more': ['please', 'water', 'food', 'play', 'music'],
    'stop': ['please', 'it', 'that'],
    'open': ['this', 'that', 'door', 'please'],
    'turn': ['on', 'off'],
    'what': ['is', 'this', 'that', 'time', 'happened'],
    'where': ['is', 'mom', 'dad', 'toilet', 'go'],
    'who': ['is', 'this', 'that'],
    'yes': ['please', 'more'],
    'no': ['thank you', 'more', 'stop'],
    'all done': ['thank you', 'go', 'play'],
    'hurt': ['head', 'tummy', 'stomach', 'leg', 'arm', 'tooth', 'ear'],
    'my': ['turn', 'head', 'tummy', 'stomach', 'mom', 'dad'],
    'this': ['one', 'please', 'more'],
    'that': ['one', 'please', 'more'],
  };

  /// Learned pairs: "want>drink" → how often "drink" followed "want".
  final Map<String, int> _pairs = {};
  bool _loaded = false;
  final _saver = _Saver('next_words.json');

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final storage = await AppStorage.instance();
      final json = await storage.readJson(storage.dataFile('next_words.json'));
      json?.forEach((k, v) => _pairs[k] = (v as num).toInt());
    } catch (_) {
      // A damaged file only loses what was learned.
    }
  }

  /// Remembers that [next] followed [previous] (both English labels).
  void learn(String? previous, String next) {
    if (previous == null || previous.isEmpty || next.isEmpty) return;
    final key = '${previous.toLowerCase()}>${next.toLowerCase()}';
    _pairs[key] = (_pairs[key] ?? 0) + 1;
    if (_pairs.length > 4000) {
      // Keep the strongest pairs only.
      final keep = (_pairs.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value)))
          .take(3000)
          .toList();
      _pairs
        ..clear()
        ..addEntries(keep);
    }
    _saver.save(() => _pairs);
  }

  void forget() {
    _pairs.clear();
    _saver.save(() => _pairs);
  }

  /// English labels likely to come after [previous]: what this person
  /// said before comes first, then the starter pairs.
  List<String> nextAfter(String previous, {int limit = 8}) {
    final p = previous.toLowerCase();
    final learned = _pairs.entries
        .where((e) => e.key.startsWith('$p>') && e.value >= 2)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final out = <String>[];
    for (final e in learned) {
      out.add(e.key.substring(p.length + 1));
    }
    for (final w in starters[p] ?? const <String>[]) {
      if (!out.contains(w)) out.add(w);
    }
    return out.take(limit).toList();
  }

  // ------------------------------------------------------------ time

  /// Words for this moment of the day (and the weekend).
  static List<String> forTime(DateTime now) {
    final h = now.hour;
    final weekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final List<String> words;
    if (h >= 5 && h < 10) {
      words = ['breakfast', 'toilet', 'get dressed', 'brush teeth', 'milk',
          weekend ? 'play' : 'school', 'tired'];
    } else if (h >= 10 && h < 12) {
      words = ['snack', 'play', 'toilet', 'drink', 'break', 'outside'];
    } else if (h >= 12 && h < 15) {
      words = ['lunch', 'eat', 'drink', 'toilet', 'play', 'rest'];
    } else if (h >= 15 && h < 18) {
      words = ['snack', 'play', 'outside', weekend ? 'park' : 'home', 'tv', 'drink'];
    } else if (h >= 18 && h < 21) {
      words = ['dinner', 'bath', 'tv', 'music', 'tired', 'hug', 'pyjamas'];
    } else {
      words = ['sleep', 'toilet', 'drink', 'scared', 'hug', 'bed'];
    }
    return words;
  }

  // ------------------------------------------------------------ replies

  /// Quick replies, always one tap away (English; shown in the chosen
  /// language through the app's translations).
  static const quickReplies = [
    'Yes',
    'No',
    'Wait, please',
    "I don't know",
    'Say it again, please',
    'Something else',
  ];

  // ------------------------------------------------------------ sentence

  static const _subjectVerbs = {
    'want', 'need', 'like', 'love', 'feel', 'see', 'have', 'think', 'know',
    "don't like", "don't want", "don't know",
  };
  static const _toVerbs = {'want', 'need', 'like', 'love', 'try', "don't want", "don't like"};
  static const _feelings = {
    'hungry', 'thirsty', 'tired', 'sick', 'happy', 'sad', 'angry', 'scared',
    'hot', 'cold', 'bored', 'sleepy', 'excited', 'okay', 'ok', 'hurt',
    'worried', 'frustrated', 'calm', 'full', 'lonely', 'nervous', 'silly',
  };
  static const _toThe = {
    'toilet', 'bathroom', 'park', 'shop', 'store', 'beach', 'doctor', 'pool',
    'playground', 'kitchen', 'garden', 'zoo', 'library', 'dentist', 'car',
    'bus', 'cinema', 'hospital', 'supermarket', 'swimming pool',
  };
  static const _toPlace = {'school', 'bed', 'church', 'work', 'mosque'};
  static const _questions = {'what', 'where', 'who', 'when', 'why', 'how', 'which'};

  /// Albanian verbs after "dua / kam nevojë / më pëlqen / mund": the
  /// board shows the command form ("shko"), a sentence needs "të shkoj".
  static const _sqSubjunctive = {
    'eat': 'ha', 'drink': 'pi', 'go': 'shkoj', 'sleep': 'fle', 'play': 'luaj',
    'see': 'shoh', 'watch': 'shikoj', 'look': 'shikoj', 'listen': 'dëgjoj',
    'read': 'lexoj', 'write': 'shkruaj', 'draw': 'vizatoj', 'walk': 'eci',
    'run': 'vrapoj', 'swim': 'notoj', 'wash': 'laj', 'open': 'hap',
    'close': 'mbyll', 'make': 'bëj', 'give': 'jap', 'get': 'marr',
    'take': 'marr', 'come': 'vij', 'sing': 'këndoj', 'dance': 'kërcej',
    'cook': 'gatuaj', 'build': 'ndërtoj', 'buy': 'blej', 'rest': 'pushoj',
    'talk': 'flas', 'stop': 'ndaloj', 'finish': 'mbaroj', 'jump': 'kërcej',
    'sit': 'ulem', 'colour': 'ngjyros', 'color': 'ngjyros', 'paint': 'pikturoj',
    'go out': 'dal', 'go outside': 'dal jashtë', 'go home': 'shkoj në shtëpi',
  };

  /// A fuller, more natural sentence from the words tapped, or null when
  /// there is nothing to improve. English gets the full rules; Albanian
  /// gets "të" before a verb; other languages get only a capital letter
  /// and a full stop (shown only together with a real change).
  static String? betterSentence(List<SaidWord> words, String language) {
    if (words.length < 2 &&
        !(words.length == 1 &&
            language == 'en' &&
            _feelings.contains(words.first.word))) {
      return null;
    }
    final out = <String>[];
    var changed = false;
    if (language == 'en') {
      final first = words.first;
      final hasSubject = first.wordClass == WordClass.pronoun ||
          first.word == 'i' ||
          first.text.toLowerCase().startsWith('i ') ||
          first.text.toLowerCase().startsWith("i'm");
      if (!hasSubject && _subjectVerbs.contains(first.word)) {
        out.add('I');
        changed = true;
      } else if (!hasSubject &&
          _feelings.contains(first.word) &&
          words.skip(1).every((w) =>
              _feelings.contains(w.word) ||
              const {'and', 'very', 'too', 'now', 'so'}.contains(w.word))) {
        // "tired" → "I'm tired."; "hungry and tired" → "I'm hungry and
        // tired." Anything else after the feeling is left alone.
        out.add("I'm");
        changed = true;
      }
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        final prev = i > 0 ? words[i - 1] : null;
        if (prev != null) {
          if (_toVerbs.contains(prev.word) &&
              w.wordClass == WordClass.verb &&
              !w.text.toLowerCase().startsWith('to ')) {
            out.add('to');
            changed = true;
          } else if (prev.word == 'go' || prev.word == 'going') {
            if (_toThe.contains(w.word)) {
              out.add('to the');
              changed = true;
            } else if (_toPlace.contains(w.word)) {
              out.add('to');
              changed = true;
            }
          } else if (prev.word == 'i' && _feelings.contains(w.word) &&
              prev.text.toLowerCase() == 'i') {
            out.add('am');
            changed = true;
          }
        }
        out.add(w.text);
      }
    } else if (language == 'sq') {
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        final prev = i > 0 ? words[i - 1] : null;
        final form = _sqSubjunctive[w.word];
        if (prev != null &&
            form != null &&
            w.wordClass == WordClass.verb &&
            const {'want', 'need', 'like', 'love', 'can', "don't want"}
                .contains(prev.word)) {
          out.add('të $form');
          changed = true;
        } else {
          out.add(w.text);
        }
      }
    } else {
      return null;
    }
    if (!changed) return null;
    var sentence = out.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    sentence = sentence[0].toUpperCase() + sentence.substring(1);
    if (!RegExp(r'[.!?…]$').hasMatch(sentence)) {
      final q = words.first.word;
      sentence += _questions.contains(q) || words.first.wordClass == WordClass.question
          ? '?'
          : '.';
    }
    return sentence;
  }
}

/// Counts of the words a person said, per day, for the therapist report.
/// Off by default; kept only on this device; can be cleared any time.
class WordUseLog {
  WordUseLog._();
  static final WordUseLog instance = WordUseLog._();

  /// day (yyyy-mm-dd) → word → taps
  final Map<String, Map<String, int>> days = {};
  bool _loaded = false;
  final _saver = _Saver('word_use.json');

  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final storage = await AppStorage.instance();
      final json = await storage.readJson(storage.dataFile('word_use.json'));
      final d = json?['days'] as Map<String, dynamic>?;
      d?.forEach((day, words) {
        days[day] = (words as Map<String, dynamic>)
            .map((k, v) => MapEntry(k, (v as num).toInt()));
      });
    } catch (_) {}
  }

  void record(String word, {DateTime? at}) {
    final w = word.trim();
    if (w.isEmpty) return;
    final day = days.putIfAbsent(dayKey(at ?? DateTime.now()), () => {});
    day[w] = (day[w] ?? 0) + 1;
    _saver.save(() => {'days': days});
  }

  void clear() {
    days.clear();
    _saver.save(() => {'days': days});
  }

  /// Totals over the last [daysBack] days (today included).
  ({int taps, int words, int activeDays, List<MapEntry<String, int>> top})
      summary(int daysBack, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final totals = <String, int>{};
    var active = 0;
    for (var i = 0; i < daysBack; i++) {
      final key = dayKey(today.subtract(Duration(days: i)));
      final day = days[key];
      if (day == null || day.isEmpty) continue;
      active++;
      day.forEach((w, n) => totals[w] = (totals[w] ?? 0) + n);
    }
    final top = totals.entries.toList()
      ..sort((a, b) => b.value != a.value
          ? b.value.compareTo(a.value)
          : a.key.compareTo(b.key));
    return (
      taps: totals.values.fold(0, (a, b) => a + b),
      words: totals.length,
      activeDays: active,
      top: top,
    );
  }
}

/// Writes a small data file without timers: one write at a time, and the
/// latest data once more if it changed while a write was running.
class _Saver {
  final String name;
  _Saver(this.name);
  bool _running = false;
  bool _again = false;

  void save(Object Function() data) {
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    unawaited(() async {
      try {
        do {
          _again = false;
          final storage = await AppStorage.instance();
          await storage.writeJson(storage.dataFile(name), data());
        } while (_again);
      } catch (_) {
        // Not saved this time; the next word tries again.
      } finally {
        _running = false;
      }
    }());
  }
}
