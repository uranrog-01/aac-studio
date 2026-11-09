import 'dart:convert';
import '../engine/read_text.dart';

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
///   "views": {"folderId": [{"columns": n, "cells":[{"btn","col","row","span"}]}]}
/// }
class PackLoader {
  Future<Vocabulary> loadAsset(String assetPath) async {
    final raw = await rootBundle.loadString(assetPath);
    return loadString(raw);
  }

  Future<Vocabulary> loadFile(String path) async =>
      loadString(await readTextFile(path));

  Vocabulary loadString(String raw) {
    final m = json.decode(raw) as Map<String, dynamic>;
    final folders = <String, VocabFolder>{};
    for (final f in (m['folders'] as List).cast<Map>()) {
      final id = f['id'] as String;
      folders[id] = VocabFolder(
          id,
          f['label'] as String,
          SymbolRef(f['symbol'] as String? ?? '📁',
              pack: f['symbolPack'] as String?,
              key: f['symbolKey'] as String?,
              imagePath: f['imagePath'] as String?));
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
        kind: _buttonKind((b['kind'] ?? 'item') as String),
        wordClass: WordClass.fromName(b['class'] as String?),
        symbol: SymbolRef.fromJson({
          'emoji': b['symbol'] ?? '⬛',
          'pack': b['symbolPack'],
          'key': b['symbolKey'],
          'imagePath': b['imagePath'],
        }),
        actions: actions,
        favorite: b['favorite'] == true,
        userEdited: b['userEdited'] == true,
        voice: VoiceStyle.fromJson(b['voice'] as Map<String, dynamic>?),
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
          // A cell whose button is missing is skipped instead of stopping the
          // whole board from opening.
          cells: ((vm['cells'] ?? const []) as List)
              .where((c) => c is Map && buttons.containsKey(c['btn']))
              .map((c) {
            final cm = c as Map;
            return GridCell(
              buttons[cm['btn'] as String]!,
              col: cm['col'] != null ? (cm['col'] as num).toInt() : null,
              row: cm['row'] != null ? (cm['row'] as num).toInt() : null,
              span: cm['span'] != null ? (cm['span'] as num).toInt() : 1,
              hidden: cm['hidden'] == true,
              dimmed: cm['dimmed'] == true,
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
      removedIds: (m['removedIds'] as List? ?? []).cast<String>().toSet(),
      packVersion: (m['packVersion'] as num?)?.toInt(),
    );
  }

  /// Serialize a vocabulary back to the pack JSON schema (M5 persistence).
  Map<String, dynamic> save(Vocabulary v) {
    final buttons = <Map<String, dynamic>>[];
    // The board keeps the version it was read with; a board without one
    // (built in code) gets the current bundled version.
    final packVersion = v.packVersion ?? 11;
    final views = <String, dynamic>{};
    for (final e in v.viewsByFolder.entries) {
      views[e.key] = e.value.map((view) {
        return {
          'columns': view.columns,
          'cells': view.cells.map((c) {
            final b = c.button;
            return {
              'btn': b.id,
              if (c.col != null) 'col': c.col,
              if (c.row != null) 'row': c.row,
              if (c.span != 1) 'span': c.span,
              if (c.hidden) 'hidden': true,
              if (c.dimmed) 'dimmed': true,
            };
          }).toList(),
        };
      }).toList();
    }
    // collect buttons from views + folders
    final allButtons = <String, VocabButton>{};
    for (final list in v.viewsByFolder.values) {
      for (final view in list) {
        for (final c in view.cells) {
          allButtons[c.button.id] = c.button;
        }
      }
    }
    for (final b in allButtons.values) {
      buttons.add({
        'id': b.id,
        'kind': switch (b.kind) {
          ButtonKind.folder => 'folder',
          ButtonKind.action => 'action',
          _ => 'item',
        },
        'label': b.label,
        'favorite': b.favorite,
        'userEdited': b.userEdited,
        if (b.symbol.imagePath != null) 'imagePath': b.symbol.imagePath,
        if (b.spokenText != null && b.spokenText != b.label)
          'spoken': b.spokenText,
        'class': b.wordClass.name,
        'symbol': b.symbol.pack == null ? b.symbol.emoji : b.symbol.emoji,
        if (b.symbol.pack != null) ...{
          'symbolPack': b.symbol.pack,
          'symbolKey': b.symbol.key,
        },
        'actions': b.actions
            .map((a) => {
                  'kind': switch (a.kind) {
                    ActionKind.addText => 'addText',
                    ActionKind.speakNow => 'speakNow',
                    ActionKind.speakMessage => 'speakMessage',
                    ActionKind.clearMessage => 'clearMessage',
                    ActionKind.gotoFolder => 'gotoFolder',
                    ActionKind.launchUrl => 'launchUrl',
                    ActionKind.sensoryGames => 'sensoryGames',
                  },
                  if (a.data.isNotEmpty) 'data': a.data,
                })
            .toList(),
        if (b.voice != null) 'voice': b.voice!.toJson(),
      });
    }
    return {
      'packVersion': packVersion,
      'id': v.id,
      'label': v.label,
      'rootFolder': v.rootFolderId,
      'folders': v.folders.values
          .map((f) => {
                'id': f.id,
                'label': f.label,
                if (f.symbol.imagePath != null) 'imagePath': f.symbol.imagePath,
                'symbol':
                    f.symbol.pack == null ? f.symbol.emoji : f.symbol.emoji,
                if (f.symbol.pack != null) ...{
                  'symbolPack': f.symbol.pack,
                  'symbolKey': f.symbol.key,
                },
              })
          .toList(),
      'buttons': buttons,
      'removedIds': v.removedIds.toList(),
      'views': views,
    };
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
        'sensoryGames' => ActionKind.sensoryGames,
        _ => ActionKind.addText,
      };
}
