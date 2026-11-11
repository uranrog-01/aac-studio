import 'package:flutter/services.dart' show rootBundle;

/// M4 word prediction: prefix matcher over a frequency-ranked word list
/// plus user-learned words (auto-learn). Learned words rank first.
///
/// English uses the bundled 10k frequency list. Every other language
/// suggests the board's own words in that language (set with
/// [setLanguage]) and what the person has typed before. Learned words are
/// kept per language: English as the plain word, others as "sq:fjalë".
class Predictor {
  final List<String> _english = [];
  List<String> _other = const [];
  String _language = 'en';
  final Map<String, int> _learned = {}; // word -> use count
  String _lastQuery = '';
  int _lastLimit = 0;
  void _invalidate() {
    _lastQuery = '';
    _lastResults = const [];
  }

  List<String> _lastResults = const [];

  int get learnedCount => _learned.length;

  static final _notWord = RegExp(r"[^\p{L}']+", unicode: true);

  Future<void> load() async {
    if (_english.isNotEmpty) return;
    try {
      final raw =
          await rootBundle.loadString('assets/prediction_en_top10k.txt');
      _english
        ..clear()
        ..addAll(raw
            .split('\n')
            .map((w) => w.trim().toLowerCase())
            .where((w) => w.length > 1));
      _invalidate();
    } catch (_) {}
  }

  /// Chooses the language to suggest in. [boardWords] are the board's
  /// words in that language; short, common words come first.
  void setLanguage(String code, Iterable<String> boardWords) {
    _language = code;
    if (code == 'en') {
      _other = const [];
    } else {
      final words = <String>{};
      for (final phrase in boardWords) {
        for (final w in phrase.toLowerCase().split(_notWord)) {
          if (w.length > 1) words.add(w);
        }
      }
      _other = words.toList()
        ..sort((a, b) => a.length != b.length
            ? a.length.compareTo(b.length)
            : a.compareTo(b));
    }
    _invalidate();
  }

  Future<void> loadLearned(AppStorageProvider storage) async {
    final m = await storage.readLearned();
    _learned
      ..clear()
      ..addAll(m);
    _invalidate();
  }

  String get _prefix => _language == 'en' ? '' : '$_language:';

  /// Returns up to [limit] suggestions for [prefix] (case-insensitive).
  List<String> suggest(String prefix, {int limit = 6}) {
    final q = prefix.trim().toLowerCase();
    if (q.isEmpty || limit <= 0) return const [];
    if (q == _lastQuery && limit == _lastLimit) return _lastResults;
    final res = <String>[];
    // learned words first (most used), in the chosen language only
    final tag = _prefix;
    final learnedMatches = <MapEntry<String, int>>[];
    for (final e in _learned.entries) {
      if (tag.isEmpty ? e.key.contains(':') : !e.key.startsWith(tag)) continue;
      final word = e.key.substring(tag.length);
      if (word.startsWith(q) && word != q) {
        learnedMatches.add(MapEntry(word, e.value));
      }
    }
    learnedMatches.sort((a, b) => b.value.compareTo(a.value));
    res.addAll(learnedMatches.take(limit).map((e) => e.key));
    // then the word list by rank
    for (final w in _language == 'en' ? _english : _other) {
      if (res.length >= limit) break;
      if (w.startsWith(q) && w != q && !res.contains(w)) res.add(w);
    }
    _lastQuery = q;
    _lastLimit = limit;
    _lastResults = List.unmodifiable(res);
    return res;
  }

  /// Auto-learn: count every word in [text]; unseen words enter the lexicon.
  /// Words are split on anything that is not a letter in any alphabet, so
  /// "është" or "привет" are learned whole.
  Future<void> learnFrom(String text, AppStorageProvider storage) async {
    final words = text
        .toLowerCase()
        .split(_notWord)
        .where((w) => w.length > 1)
        .toSet();
    if (words.isEmpty) return;
    final tag = _prefix;
    for (final w in words) {
      _learned['$tag$w'] = (_learned['$tag$w'] ?? 0) + 1;
    }
    _invalidate();
    await storage.writeLearned(_learned);
  }
}

/// Storage contract used by Predictor (implemented by AppStorage wrapper) so
/// tests can stub it.
abstract class AppStorageProvider {
  Future<Map<String, int>> readLearned();
  Future<void> writeLearned(Map<String, int> words);
}
