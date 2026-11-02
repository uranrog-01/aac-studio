import 'dart:convert';
import 'image_reference.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:xml/xml.dart';

import '../models/domain.dart';

class SymbolEntry {
  final String pack;
  final String key;
  final String name;
  SymbolEntry(this.pack, this.key, this.name);
}

/// Modern flat is the picture style; Mulberry (SVG) covers AAC words not yet
/// drawn and Twemoji supplies country flags. See THIRD_PARTY_SYMBOLS.md.
class SymbolLibrary {
  static final _svgSources = <String, Future<String>>{};

  /// Saved references to retired emoji sets -> same concept in modern flat.
  static final Map<String, String> _aliases = {};

  /// Modern flat keys that exist, for skin-tone variants.
  static final Set<String> _modernKeys = {};

  /// Caregiver's choice for people pictures: '' (default yellow), 'light',
  /// 'medium-light', 'medium', 'medium-dark' or 'dark'.
  static String skinTone = '';
  static const skinTones = ['light', 'medium-light', 'medium', 'medium-dark', 'dark'];

  final List<SymbolEntry> _entries = [];
  final Set<(String, String)> _pictures = {};
  bool loaded = false;

  int get size => _pictures.length;

  Future<void> load() async {
    if (loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/symbol_index.json');
      final list = jsonDecode(raw) as List;
      for (final e in list) {
        _entries.add(
            SymbolEntry(e['p'] as String, e['k'] as String, e['n'] as String));
        _pictures.add((e['p'] as String, e['k'] as String));
        if (e['p'] == 'modernflat') _modernKeys.add(e['k'] as String);
      }
      final aliases = jsonDecode(
              await rootBundle.loadString('assets/symbol_aliases.json'))
          as Map<String, dynamic>;
      _aliases.addAll(aliases.cast<String, String>());
    } catch (_) {}
    loaded = true;
  }

  /// Skin-tone variants are one picture in search; the chosen tone is drawn.
  static bool _isToneVariant(String key) =>
      skinTones.any((t) => key.endsWith('-$t'));

  static String _toned(String key) {
    if (skinTone.isEmpty || _isToneVariant(key)) return key;
    final variant = '$key-$skinTone';
    return _modernKeys.contains(variant) ? variant : key;
  }

  List<SymbolEntry> search(String query, {int limit = 60}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final matches = <({SymbolEntry entry, int rank, int order})>[];
    for (final e in _entries) {
      if (e.pack == 'modernflat' && _isToneVariant(e.key)) continue;
      final n = e.name.toLowerCase();
      final rank = n == q
          ? 0
          : n.startsWith(q)
              ? 100
              : n.contains(q)
                  ? 200
                  : e.key.toLowerCase().contains(q)
                      ? 300
                      : null;
      if (rank != null) {
        matches.add((
          entry: e,
          rank: rank + (e.pack == 'modernflat' ? 0 : 10),
          order: matches.length
        ));
      }
    }
    matches.sort((a, b) {
      final rank = a.rank.compareTo(b.rank);
      return rank != 0 ? rank : a.order.compareTo(b.order);
    });
    final seen = <(String, String)>{};
    return matches
        .where((match) => seen.add((match.entry.pack, match.entry.key)))
        .take(limit)
        .map((match) => match.entry)
        .toList();
  }

  /// Resolve a SymbolRef to a widget (asset packs, local file, or emoji).
  static Widget resolve(SymbolRef ref, {double? size, Color? color}) {
    final s = size ?? 48;
    if (ref.imagePath != null) {
      return referenceImage(ref.imagePath!,
          width: s,
          height: s,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _emoji(ref.emoji, s));
    }
    var pack = ref.pack == 'modern3d'
        ? 'modernflat'
        : ref.pack == 'twemoji_svg'
            ? 'twemoji'
            : ref.pack;
    var key = ref.key ?? '';
    // Retired emoji sets: show the same concept in modern flat.
    final alias = _aliases['$pack/$key'];
    if (alias != null) {
      pack = 'modernflat';
      key = alias;
    }
    switch (pack) {
      case 'mulberry':
        final path = 'assets/symbols/mulberry/$key.svg';
        return FutureBuilder<String>(
            future: _svgSources.putIfAbsent(path,
                () async => inlineSvgStyles(await rootBundle.loadString(path))),
            builder: (context, snapshot) => snapshot.hasData
                ? SvgPicture.string(snapshot.data!,
                    width: s,
                    height: s,
                    fit: BoxFit.contain,
                    placeholderBuilder: (_) => _emoji(ref.emoji, s),
                    errorBuilder: (_, __, ___) => _emoji(ref.emoji, s))
                : _emoji(ref.emoji, s));
      case 'modernflat':
      case 'learning':
      case 'twemoji':
      case 'communication':
        final file = pack == 'modernflat' ? _toned(key) : key;
        return Image.asset('assets/flat_symbols/$pack/$file.webp',
            width: s,
            height: s,
            filterQuality: FilterQuality.high,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => _emoji(ref.emoji, s));
      default:
        return _emoji(ref.emoji, s);
    }
  }

  /// Flutter's SVG renderer ignores style elements. Mulberry uses simple class
  /// rules (including comma-separated selectors); inline them before rendering
  /// so colored fills and outlined details do not turn into black silhouettes.
  static String inlineSvgStyles(String source) {
    if (!source.contains('<style')) return source;
    final document = XmlDocument.parse(source);
    final styles = document.findAllElements('style').toList();
    final rules = <({Set<String> classes, Map<String, String> declarations})>[];
    Map<String, String> declarations(String text) {
      final values = <String, String>{};
      for (final part in text.split(';')) {
        final colon = part.indexOf(':');
        if (colon > 0) {
          values[part.substring(0, colon).trim()] =
              part.substring(colon + 1).trim();
        }
      }
      return values;
    }

    for (final style in styles) {
      final css = style.innerText.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      for (final match in RegExp(r'([^{}]+)\{([^{}]*)\}').allMatches(css)) {
        final classes = match[1]!.split(',').map((s) => s.trim()).toList();
        if (classes.every((s) => RegExp(r'^\.[\w-]+$').hasMatch(s))) {
          rules.add((
            classes: classes.map((s) => s.substring(1)).toSet(),
            declarations: declarations(match[2]!),
          ));
        }
      }
      style.parent!.children.remove(style);
    }
    for (final element in document.descendants.whereType<XmlElement>()) {
      final classes =
          (element.getAttribute('class') ?? '').split(RegExp(r'\s+')).toSet();
      final values = <String, String>{};
      for (final rule in rules) {
        if (rule.classes.intersection(classes).isNotEmpty) {
          values.addAll(rule.declarations);
        }
      }
      // An inline style has higher priority than a class or presentation attribute.
      values.addAll(declarations(element.getAttribute('style') ?? ''));
      for (final entry in values.entries) {
        element.setAttribute(entry.key, entry.value);
      }
      element.removeAttribute('style');
    }
    return document.toXmlString();
  }

  static Widget _emoji(String emoji, double s) => FittedBox(
        fit: BoxFit.contain,
        child: Text(emoji, style: TextStyle(fontSize: s * 0.95)),
      );
}
