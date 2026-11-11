import 'dart:convert';

/// P0 soft-delete merge (Vocable pattern): user additions and user edits
/// survive factory pack upgrades.
class PackUpgrade {
  /// Applies user edits/additions from [oldJson] onto [newJson].
  static Map<String, dynamic> merge(
      Map<String, dynamic> oldJson, Map<String, dynamic> newJson,
      {Map<String, dynamic> factorySymbolHistory = const {},
      bool adoptStarterLayouts = false}) {
    final result = jsonDecode(jsonEncode(newJson)) as Map<String, dynamic>;
    final fresh = {for (final b in result['buttons'] as List) b['id']: b};
    final old = {for (final b in oldJson['buttons'] as List? ?? []) b['id']: b};
    for (final entry in old.entries) {
      final replacement = fresh[entry.key];
      final button = Map<String, dynamic>.from(entry.value as Map);
      final known =
          (factorySymbolHistory['buttons'] as Map?)?[entry.key] as List? ?? [];
      // Repair only known factory artwork. Custom labels and pictures remain
      // the user's choice even on buttons from the starter pack.
      if (replacement != null &&
          button['imagePath'] == null &&
          button['label'] == replacement['label'] &&
          ((button['userEdited'] != true &&
                  button['symbolPack'] == 'mulberry' &&
                  (button['symbolKey'] as String? ?? '').length == 1) ||
              known.any((ref) => _sameSymbol(button, ref as Map)))) {
        for (final key in ['symbol', 'symbolPack', 'symbolKey']) {
          button[key] = replacement[key];
        }
      }
      // Word-class colour fixes reach buttons the user never edited.
      if (replacement != null &&
          button['userEdited'] != true &&
          replacement['class'] != null) {
        button['class'] = replacement['class'];
      }
      fresh[entry.key] = button;
    }
    // Factory cells withdrawn from a page (duplicates, moved sub-categories).
    final retired = (factorySymbolHistory['retired'] as Map?) ?? const {};
    bool isRetired(String folder, Object? id) {
      if (!((retired[folder] as List?)?.contains(id) ?? false)) return false;
      final b = old[id] as Map?;
      return b == null || (b['userEdited'] != true && b['favorite'] != true);
    }

    final removed = (oldJson['removedIds'] as List? ?? []).toSet();
    result['buttons'] =
        fresh.values.where((b) => !removed.contains(b['id'])).toList();
    final views = result['views'] as Map<String, dynamic>;
    final oldViews = oldJson['views'] as Map<String, dynamic>? ?? {};
    // An installed board keeps its own order: a person who talks with it
    // knows where every button is, so an update never moves buttons by
    // itself. New words are added; a caregiver can switch to the new
    // starter layout in Settings > Caregiver. With [adoptStarterLayouts],
    // a page that is still exactly an earlier starter layout moves to the
    // new one.
    final layouts = (factorySymbolHistory['layouts'] as Map?) ?? const {};
    bool untouched(String folder, List previous) {
      final known = layouts[folder] as List?;
      if (!adoptStarterLayouts || known == null || previous.length != 1) {
        return false;
      }
      final cells = (previous.first as Map)['cells'] as List;
      if (cells.any((c) => c is! Map || c.length != 1)) return false;
      final ids = [for (final c in cells) c['btn']];
      return known.any((layout) =>
          layout is List &&
          layout.length == ids.length &&
          [for (var i = 0; i < ids.length; i++) layout[i] == ids[i]]
              .every((same) => same));
    }

    for (final entry in oldViews.entries) {
      final newViews = views[entry.key] as List? ?? [];
      final previous = entry.value as List;
      if (newViews.isNotEmpty && untouched(entry.key, previous)) continue;
      for (var i = 0; i < previous.length; i++) {
        final view = previous[i] as Map;
        final cells = view['cells'] as List;
        cells.removeWhere((c) => isRetired(entry.key, c['btn']));
        final freshCells = newViews.isEmpty
            ? []
            : newViews[i < newViews.length ? i : 0]['cells'] as List;
        // Keep positions, deletions and user additions; new vocabulary goes
        // to its factory position (e.g. yes/no beside the core words).
        for (var j = 0; j < freshCells.length; j++) {
          final cell = freshCells[j];
          if (!old.containsKey(cell['btn']) &&
              !removed.contains(cell['btn']) &&
              !cells.any((c) => c['btn'] == cell['btn'])) {
            cells.insert(j < cells.length ? j : cells.length, cell);
          }
        }
      }
      views[entry.key] = previous;
    }
    for (final list in views.values) {
      for (final view in list as List) {
        (view['cells'] as List).removeWhere((c) => removed.contains(c['btn']));
      }
    }
    final folders = {for (final f in result['folders'] as List) f['id']: f};
    for (final f in oldJson['folders'] as List? ?? []) {
      final folder = Map<String, dynamic>.from(f as Map);
      final replacement = folders[folder['id']];
      final known =
          (factorySymbolHistory['folders'] as Map?)?[folder['id']] as List? ??
              [];
      if (replacement != null &&
          folder['imagePath'] == null &&
          folder['label'] == replacement['label'] &&
          known.any((ref) =>
              _sameSymbol(folder, ref as Map) ||
              (folder['symbolPack'] == null &&
                  folder['symbol'] == ref['symbol']))) {
        for (final key in ['symbol', 'symbolPack', 'symbolKey']) {
          folder[key] = replacement[key];
        }
      }
      folders[folder['id']] = folder;
    }
    result['folders'] = folders.values.toList();
    result['removedIds'] = removed.toList();
    return result;
  }

  static bool _sameSymbol(Map item, Map reference) =>
      item['label'] == reference['label'] &&
      item['symbolPack'] == reference['symbolPack'] &&
      item['symbolKey'] == reference['symbolKey'];
}
