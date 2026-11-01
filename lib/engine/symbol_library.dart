import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../models/domain.dart';

class SymbolEntry {
  final String pack;
  final String key;
  final String name;
  SymbolEntry(this.pack, this.key, this.name);
}

/// Search + render across bundled open symbol packs (~15k symbols: Twemoji,
/// Noto Emoji, OpenMoji, Mulberry — see THIRD_PARTY_SYMBOLS.md).
class SymbolLibrary {
  final List<SymbolEntry> _entries = [];
  bool loaded = false;

  int get size => _entries.length;

  Future<void> load() async {
    if (loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/symbol_index.json');
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        _entries.add(SymbolEntry(e['p'] as String, e['k'] as String, e['n'] as String));
      }
    } catch (_) {}
    loaded = true;
  }

  List<SymbolEntry> search(String query, {int limit = 60}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final starts = <SymbolEntry>[];
    final contains = <SymbolEntry>[];
    for (final e in _entries) {
      final n = e.name.toLowerCase();
      if (n.startsWith(q)) {
        starts.add(e);
      } else if (n.contains(q) || e.key.toLowerCase().contains(q)) {
        contains.add(e);
      }
      if (starts.length >= limit) break;
    }
    return [...starts, ...contains].take(limit).toList();
  }

  /// Resolve a SymbolRef to a widget (asset packs, local file, or emoji).
  static Widget resolve(SymbolRef ref, {double? size, Color? color}) {
    final s = size ?? 48;
    if (ref.imagePath != null) {
      return Image.file(File(ref.imagePath!),
          width: s, height: s, fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _emoji(ref.emoji, s));
    }
    switch (ref.pack) {
      case 'twemoji':
      case 'noto':
        return Image.asset('assets/symbols/${ref.pack}/${ref.key}.png',
            width: s, height: s, fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _emoji(ref.emoji, s));
      case 'twemoji_svg':
        return SvgPicture.asset('assets/symbols/twemoji/${ref.key}.svg',
            width: s, height: s, fit: BoxFit.contain,
            placeholderBuilder: (_) => _emoji(ref.emoji, s));
      case 'openmoji':
      case 'openmoji_black':
      case 'mulberry':
        return SvgPicture.asset('assets/symbols/${ref.pack}/${ref.key}.svg',
            width: s, height: s, fit: BoxFit.contain,
            placeholderBuilder: (_) => _emoji(ref.emoji, s));
      default:
        return _emoji(ref.emoji, s);
    }
  }

  static Widget _emoji(String emoji, double s) => FittedBox(
        fit: BoxFit.contain,
        child: Text(emoji, style: TextStyle(fontSize: s * 0.95)),
      );
}
