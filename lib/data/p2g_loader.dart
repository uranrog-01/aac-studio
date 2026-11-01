import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/domain.dart';


/// Research-viewer loader: reads a locally extracted Proloquo2Go cache DB
/// (v2.3 vocabulary *.cache.sqlite) and maps it onto the studio domain model.
///
/// Verified schema facts (see work/notes/ARCHITECTURE.md):
/// - vocabulary(1 row): folder_id = root folder
/// - folder(id,label,symbol_id), folderview(gridsystemtype 1=column, width,
///   prioritytype 1=primary/10=secondary/99=storage, folderviewtype 1=elements)
/// - folderview_element(elementtype_id=1 → button; 1-based position_x/y,
///   width/height in cells, hidden, dimmed)
/// - button(buttontype 1=item/2=folder/3=action; item label via item join;
///   folder label via goto_folder action)
/// - button_action: 1=Add Text, 2=add_string, 4=Speak Immediate, 5=speak_string,
///   7=Speak Message Window, 8=Clear, 11=goto_folder (target in `data` as text)
/// - symbol(id,label,filename) → `pngDir/filename.png` pre-rendered PNGs

/// Tolerant int coercion — P2G 2.3 databases store several id columns as
/// TEXT in some rows and INTEGER in others.
int? asInt(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

int asIntOrZero(dynamic v) => asInt(v) ?? 0;

class P2gLoader {
  final String dbPath;
  final String typesPath;
  final String pngDir;
  P2gLoader({required this.dbPath, required this.typesPath, required this.pngDir});

  Future<Vocabulary> load({int maxColumnsForDevice = 8}) async {
    final db = await databaseFactoryFfi.openDatabase(dbPath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false));

    // ---- word class names (dynamic; ids may be 0- or 1-indexed per build)
    final wcNames = <int, String>{};
    try {
      final tdb = await databaseFactoryFfi.openDatabase(typesPath,
          options: OpenDatabaseOptions(readOnly: true, singleInstance: false));
      for (final r in await tdb.query('wordclasstype')) {
        wcNames[asIntOrZero(r['id'])] = (r['label'] ?? r['name'] ?? '') as String;
      }
      await tdb.close();
    } catch (_) {}

    // ---- vocabulary root
    final vocabRows = await db.query('vocabulary');
    if (vocabRows.isEmpty) throw const FormatException('no vocabulary row');
    final rootFolderId = (vocabRows.first['folder_id'] as num).toInt();
    final vocabLabel = (vocabRows.first['label'] ?? 'P2G Vocabulary') as String;

    // ---- folders
    final folders = <String, VocabFolder>{};
    final folderSymbol = <int, int>{};
    for (final r in await db.query('folder', columns: ['id', 'label', 'symbol_id'])) {
      final id = asIntOrZero(r['id']);
      final sid = asInt(r['symbol_id']);
      folders['$id'] = VocabFolder('$id', (r['label'] ?? '') as String,
          const SymbolRef('📁')); // symbol replaced below
      if (sid != null) folderSymbol[id] = sid.toInt();
    }

    // ---- symbols: id → filename → png path
    final symbolPng = <int, String>{};
    for (final r in await db.query('symbol', columns: ['id', 'filename'])) {
      final fn = (r['filename'] ?? '') as String;
      if (fn.isNotEmpty) symbolPng[asIntOrZero(r['id'])] = '$pngDir/$fn.png';
    }
    SymbolRef refFor(int? symbolId, String fallbackEmoji) {
      final p = symbolId == null ? null : symbolPng[symbolId];
      return SymbolRef(fallbackEmoji, imagePath: p);
    }

    for (final e in folderSymbol.entries) {
      final f = folders['${e.key}'];
      if (f != null) {
        folders['${e.key}'] =
            VocabFolder(f.id, f.label, refFor(e.value, '📁'));
      }
    }

    // ---- items: id → (label, wordclass id)
    final itemLabel = <int, String>{};
    final itemClass = <int, int>{};
    for (final r in await db.query('item', columns: ['id', 'label', 'wordclasstype_id'])) {
      final id = asIntOrZero(r['id']);
      itemLabel[id] = (r['label'] ?? '') as String;
      itemClass[id] = asIntOrZero(r['wordclasstype_id']);
    }

    // ---- buttons (base), labels resolved after actions known
    final btnType = <int, int>{};
    final btnItem = <int, int?>{};
    final btnSymbol = <int, int?>{};
    for (final r in await db.query('button',
        columns: ['id', 'buttontype_id', 'item_id', 'symbol_id', 'label'])) {
      final id = asIntOrZero(r['id']);
      btnType[id] = asIntOrZero(r['buttontype_id']);
      btnItem[id] = asInt(r['item_id']);
      btnSymbol[id] = asInt(r['symbol_id']);
    }

    // ---- actions
    final btnActions = <int, List<VocabAction>>{};
    final folderTargetOf = <int, int>{}; // folder button → target folder
    final spokenOf = <int, String>{}; // item button → add_string data
    for (final r in await db.query('button_action',
        columns: ['button_id', 'actiontype_id', 'target', 'data', '"order"'],
        orderBy: '"order"')) {
      final bid = asIntOrZero(r['button_id']);
      final at = asIntOrZero(r['actiontype_id']);
      final data = (r['data'] ?? '') as String;
      final target = r['target'] as String?;
      switch (at) {
        case 1: // Add Text to Message Window
        case 2: // add_string
          btnActions.putIfAbsent(bid, () => []).add(VocabAction(ActionKind.addText, data: data));
          if (data.isNotEmpty) spokenOf[bid] = data;
          break;
        case 4:
        case 5:
          btnActions.putIfAbsent(bid, () => []).add(VocabAction(ActionKind.speakNow, data: data));
          break;
        case 7:
          btnActions.putIfAbsent(bid, () => []).add(VocabAction(ActionKind.speakMessage));
          break;
        case 8:
          btnActions.putIfAbsent(bid, () => []).add(VocabAction(ActionKind.clearMessage));
          break;
        case 11: // goto_folder — target id is a string in `data`
          final tid = int.tryParse(data) ?? int.tryParse(target ?? '');
          if (tid != null) {
            folderTargetOf[bid] = tid;
            btnActions.putIfAbsent(bid, () => []).add(
                VocabAction(ActionKind.gotoFolder, data: '$tid'));
          }
          break;
        case 17:
          btnActions.putIfAbsent(bid, () => []).add(VocabAction(ActionKind.launchUrl, data: data));
          break;
      }
    }

    // ---- folderviews: pick per folder the widest view not exceeding
    //      maxColumnsForDevice, preferring primary priority (1 < 10 < 99).
    final viewsByFolder = <String, List<VocabView>>{};
    final fvRows = await db.query('folderview',
        columns: ['id', 'folder_id', 'gridsystemtype_id', 'width', 'prioritytype_id'],
        where: 'folderviewtype_id = 1');
    final best = <int, Map<String, dynamic>>{}; // folder_id → row
    int priVal(dynamic v) {
      final p = (v as num?)?.toInt() ?? 1;
      return switch (p) { 1 => 0, 10 => 1, _ => 2 };
    }

    for (final r in fvRows) {
      final fid = asIntOrZero(r['folder_id']);
      final w = asInt(r['width']) ?? 6;
      final cand = {...r, '_w': w, '_pri': priVal(r['prioritytype_id'])};
      final cur = best[fid];
      if (cur == null) {
        best[fid] = cand;
      } else {
        final curFits = (cur['_w'] as int) <= maxColumnsForDevice;
        final candFits = w <= maxColumnsForDevice;
        bool take;
        if (curFits != candFits) {
          take = candFits; // a fitting view always beats a non-fitting one
        } else if (cand['_pri'] != cur['_pri']) {
          take = (cand['_pri'] as int) < (cur['_pri'] as int);
        } else {
          // same priority class: prefer the larger fitting grid
          take = candFits && w > (cur['_w'] as int);
        }
        if (take) best[fid] = cand;
      }
    }

    // ---- elements + buttons → cells
    WordClass wcFor(int? itemId) {
      final idx = itemId == null ? null : itemClass[itemId];
      final n = idx == null ? null : wcNames[idx];
      if (n == null || n.isEmpty) return WordClass.unknown;
      final s = n.toLowerCase();
      if (s.contains('pronoun')) return WordClass.pronoun;
      if (s.contains('verb')) return WordClass.verb;
      if (s.contains('noun')) return itemId != null && s.contains('proper') ? WordClass.properNoun : WordClass.noun;
      if (s.contains('adject')) return WordClass.adjective;
      if (s.contains('adverb')) return WordClass.adverb;
      if (s.contains('article')) return WordClass.article;
      if (s.contains('prep')) return WordClass.preposition;
      if (s.contains('conj')) return WordClass.conjunction;
      if (s.contains('number')) return WordClass.number;
      if (s.contains('interjection')) return WordClass.interjection;
      if (s.contains('question')) return WordClass.question;
      if (s.contains('phrase')) return WordClass.phrase;
      return WordClass.other;
    }

    for (final e in best.entries) {
      final fid = e.key;
      final fvid = (e.value['id'] as num).toInt();
      final cols = e.value['_w'] as int;
      final cells = <GridCell>[];
      final elems = await db.query('folderview_element',
          where: 'folderview_id = ? AND elementtype_id = 1',
          whereArgs: [fvid],
          orderBy: 'position_y, position_x');
      for (final el in elems) {
        final bid = asIntOrZero(el['element_id']);
        final bt = btnType[bid];
        if (bt == null) continue;
        final itemId = btnItem[bid];
        final hidden = asIntOrZero(el['hidden']) != 0;
        String label;
        WordClass wc = WordClass.other;
        SymbolRef sym;
        if (bt == 2) {
          final tid = folderTargetOf[bid];
          final f = tid == null ? null : folders['$tid'];
          label = f?.label ?? '';
          sym = refFor(btnSymbol[bid], '📁');
          wc = WordClass.other;
        } else if (bt == 3) {
          label = _actionButtonLabel(btnActions[bid] ?? const []);
          sym = refFor(btnSymbol[bid], '⬛');
        } else {
          label = (itemId != null ? itemLabel[itemId] : null) ?? '';
          wc = wcFor(itemId);
          sym = refFor(btnSymbol[bid], '⬛');
        }
        if (label.isEmpty && bt != 1) continue; // skip empty non-item buttons
        final btn = VocabButton(
          id: '$bid',
          label: label,
          spokenText: spokenOf[bid],
          kind: switch (bt) { 2 => ButtonKind.folder, 3 => ButtonKind.action, _ => ButtonKind.item },
          wordClass: wc,
          symbol: sym,
          actions: btnActions[bid] ?? const [],
        );
        cells.add(GridCell(
          btn,
          col: asInt(el['position_x']),
          row: asInt(el['position_y']),
          span: asInt(el['width']) ?? 1,
          hidden: hidden,
          dimmed: asIntOrZero(el['dimmed']) != 0,
        ));
      }
      viewsByFolder['$fid'] = [
        VocabView(id: '$fvid', folderId: '$fid', columns: cols, cells: cells)
      ];
    }
    await db.close();
    return Vocabulary(
      id: 'p2g.coreword',
      label: vocabLabel,
      rootFolderId: '$rootFolderId',
      folders: folders,
      viewsByFolder: viewsByFolder,
    );
  }

  String _actionButtonLabel(List<VocabAction> actions) {
    for (final a in actions) {
      switch (a.kind) {
        case ActionKind.clearMessage:
          return 'Clear';
        case ActionKind.speakMessage:
          return 'Speak';
        case ActionKind.launchUrl:
          return 'Open';
        default:
          break;
      }
    }
    return '';
  }
}
