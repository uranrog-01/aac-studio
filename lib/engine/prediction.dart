import 'package:flutter/services.dart' show rootBundle;

/// M4 word prediction: prefix matcher over an open frequency-ranked lexicon
/// plus user-learned words (auto-learn). Static rank beats learned weight
/// only when both are unknown; learned words rank first.
class Predictor {
  final List<String> _base = [];
  final Map<String, int> _learned = {}; // word -> use count
  String _lastQuery = '';
  int _lastLimit = 0;
  void _invalidate() {
    _lastQuery = '';
    _lastResults = const [];
  }

  List<String> _lastResults = const [];

  int get learnedCount => _learned.length;

  Future<void> load() async {
    if (_base.isNotEmpty) return;
    try {
      final raw =
          await rootBundle.loadString('assets/prediction_en_top10k.txt');
      _base
        ..clear()
        ..addAll(raw
            .split('\n')
            .map((w) => w.trim().toLowerCase())
            .where((w) => w.length > 1));
      _invalidate();
    } catch (_) {}
  }

  Future<void> loadLearned(AppStorageProvider storage) async {
    final m = await storage.readLearned();
    _learned
      ..clear()
      ..addAll(m);
    _invalidate();
  }

  /// Returns up to [limit] suggestions for [prefix] (case-insensitive).
  List<String> suggest(String prefix, {int limit = 6}) {
    final q = prefix.trim().toLowerCase();
    if (q.isEmpty || limit <= 0) return const [];
    if (q == _lastQuery && limit == _lastLimit) return _lastResults;
    final res = <String>[];
    // learned words first (most used)
    final learnedMatches = _learned.entries
        .where((e) => e.key.startsWith(q) && e.key != q)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    res.addAll(learnedMatches.take(limit).map((e) => e.key));
    // then base lexicon by rank
    for (final w in _base) {
      if (res.length >= limit) break;
      if (w.startsWith(q) && !res.contains(w)) res.add(w);
    }
    _lastQuery = q;
    _lastLimit = limit;
    _lastResults = List.unmodifiable(res);
    return res;
  }

  /// Auto-learn: count every word in [text]; unseen words enter the lexicon.
  Future<void> learnFrom(String text, AppStorageProvider storage) async {
    final words = text
        .toLowerCase()
        .split(RegExp("[^a-z']+"))
        .where((w) => w.length > 1)
        .toSet();
    var changed = false;
    for (final w in words) {
      _learned[w] = (_learned[w] ?? 0) + 1;
      changed = true;
    }
    if (changed) {
      _invalidate();
      await storage.writeLearned(_learned);
    }
  }
}

/// Storage contract used by Predictor (implemented by AppStorage wrapper) so
/// tests can stub it.
abstract class AppStorageProvider {
  Future<Map<String, int>> readLearned();
  Future<void> writeLearned(Map<String, int> words);
}
