import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../models/domain.dart';

/// M1 data layer: JSON vocabulary pack loader for the ORIGINAL content.
///
/// Pack format (assets/sample_pack.json):
/// {
///   "id": "...", "label": "...", "rootFolder": "home",
///   "folders": [{"id","label","symbol"}],
///   "buttons": [{"id","kind":"item/folder/action","label","spoken","class",
///                "symbol","actions":[{"kind","data"}]}],
///   "views": {"<folderId>": [{"columns": n, "cells":[{"btn","col","row","span"}]}]}
/// }
class PackLoader {
  Future<Vocabulary> loadAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return loadString(raw);
  }

  Future<Vocabulary> loadFile(String path) async =>
      loadString(await File(path).readAsString());

  Vocabulary loadString(String raw) {
    final m = json.decode(raw) as Map<String, dynamic>;
    final folders = <String, VocabFolder>{};
    for (final f in (m['folders'] as List).cast<Map>()) {
      final id = f['id'] as String;
      folders[id] = VocabFolder(id, f['label'] as String,
          SymbolRef(f['symbol'] as String? ?? '📁'));
    }
    final buttons = <String, VocabButton>{};
    for (final b in (m['buttons'] as List).cast<Map>()) {
      final actions = <VocabAction>[];
      for (final a in ((b['actions'] ?? const []) as List).cast<Map>()) {
        actions.add(VocabAction(
          _kind(a['kind'] as String),
          data: a['data'] as String? ?? '',
        ));
      }
      final id = b['id'] as String;
      buttons[id] = VocabButton(
        id: id,
        label: b['label'] as String,
        spokenText: b['spoken'] as String?,
        kind: _buttonKind(b['kind'] as String),
        wordClass: WordClass.fromName(b['class'] as String?),
        symbol: SymbolRef(b['symbol'] as String? ?? '⬛'),
        actions: actions,
      );
    }
    final views = <String, List<VocabView>>{};
    (m['views'] as Map<String, dynamic>).forEach((folderId, list) {
      views[folderId] = (list as List).map((v) {
        final vm = v as Map;
        return VocabView(
          id: '$folderId-view',
          folderId: folderId,
          columns: (vm['columns'] as num).toInt(),
          cells: ((vm['cells'] ?? const []) as List).map((c) {
            final cm = c as Map;
            return GridCell(
              buttons[cm['btn'] as String]!,
              col: cm['col'] != null ? (cm['col'] as num).toInt() : null,
              row: cm['row'] != null ? (cm['row'] as num).toInt() : null,
              span: cm['span'] != null ? (cm['span'] as num).toInt() : 1,
            );
          }).toList(),
        );
      }).toList();
    });
    return Vocabulary(
      id: m['id'] as String,
      label: m['label'] as String,
      rootFolderId: m['rootFolder'] as String,
      folders: folders,
      viewsByFolder: views,
    );
  }

  ButtonKind _buttonKind(String s) => switch (s) {
        'folder' => ButtonKind.folder,
        'action' => ButtonKind.action,
        _ => ButtonKind.item,
      };

  ActionKind _kind(String s) => switch (s) {
        'addText' => ActionKind.addText,
        'speakNow' => ActionKind.speakNow,
        'speakMessage' => ActionKind.speakMessage,
        'clearMessage' => ActionKind.clearMessage,
        'gotoFolder' => ActionKind.gotoFolder,
        'launchUrl' => ActionKind.launchUrl,
        _ => ActionKind.addText,
      };
}
