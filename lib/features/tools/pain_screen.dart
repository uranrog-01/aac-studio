import 'package:flutter/material.dart';

import '../../engine/i18n.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../grid/grid_screen.dart';
import 'tools.dart';

/// Where it hurts and how much: tap the body part, then a face on the
/// 0–5 scale. The sentence is said and can go into the message.
class PainScreen extends StatefulWidget {
  final GridSession session;
  const PainScreen({super.key, required this.session});

  @override
  State<PainScreen> createState() => _PainScreenState();
}

class _PainScreenState extends State<PainScreen> {
  /// Body parts, head to toe: English board words, the first one the
  /// board has is used (parts the board does not have are left out).
  static const parts = [
    ['head'], ['eye', 'eyes'], ['ear', 'ears'], ['nose'], ['mouth'],
    ['tooth', 'teeth'], ['throat'], ['neck'], ['chest'],
    ['tummy', 'stomach', 'belly'], ['back'], ['arm', 'arms'], ['hand'],
    ['finger', 'fingers'], ['leg', 'legs'], ['knee'], ['foot', 'feet'],
    ['skin'],
  ];

  static const _plural = {'eyes', 'ears', 'teeth', 'arms', 'fingers', 'legs', 'feet'};

  /// 0–5, with the faces people know from the hospital pain scale.
  /// The faces are the app's own pictures, so they show offline too.
  static const levels = [
    ('No pain', 'fluent-grinning-face', Color(0xFF43A047)),
    ('It hurts a little', 'fluent-slightly-smiling-face', Color(0xFF7CB342)),
    ('It hurts', 'fluent-neutral-face', Color(0xFFFDD835)),
    ('It hurts a lot', 'fluent-worried-face', Color(0xFFFB8C00)),
    ('It hurts very much', 'fluent-persevering-face', Color(0xFFF4511E)),
    ('The worst pain', 'fluent-loudly-crying-face', Color(0xFFC62828)),
  ];

  String? _part;
  VocabButton? _partButton;
  int? _level;

  String get _sentence {
    final bits = <String>[];
    if (_part != null) {
      final word = _partButton?.shownLabel ?? I18n.word(_part!);
      final template = _plural.contains(_part) ? 'My {part} hurt' : 'My {part} hurts';
      bits.add(I18n.t(template).replaceAll('{part}', word));
    }
    if (_level != null) bits.add(I18n.t(levels[_level!].$1));
    return bits.map((b) => b.endsWith('.') ? b : '$b.').join(' ');
  }

  void _say() {
    final s = _sentence;
    if (s.isNotEmpty) widget.session.sayNow(s);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final width = MediaQuery.of(context).size.width;
    final partGrid = GridView.extent(
      maxCrossAxisExtent: (width / 5).clamp(96.0, 170.0),
      padding: const EdgeInsets.all(12),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.9,
      children: [
        for (final names in parts)
          for (final p in [
            names.firstWhere((n) => session.buttonForLabel(n) != null,
                orElse: () => ''),
          ])
            if (p.isNotEmpty)
              _PartTile(
                label: p,
                button: session.buttonForLabel(p),
                selected: _part == p,
                onTap: (b) {
                  setState(() {
                    _part = p;
                    _partButton = b;
                  });
                  _say();
                },
              ),
      ],
    );
    final scale = Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < levels.length; i++)
          Material(
            color: levels[i].$3,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                setState(() => _level = i);
                _say();
              },
              child: Container(
                width: 92,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: _level == i ? Colors.white : Colors.transparent,
                      width: 4),
                ),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SymbolLibrary.resolve(
                      SymbolRef('', pack: 'modernflat', key: levels[i].$2),
                      size: 44),
                  Text('$i',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.black87)),
                  Text(I18n.t(levels[i].$1),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87)),
                ]),
              ),
            ),
          ),
      ],
    );
    return ToolPage(
      title: 'Where it hurts',
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(I18n.t('Where does it hurt?'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
        ),
        Expanded(child: partGrid),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Text(I18n.t('How much does it hurt?'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
        ),
        Padding(padding: const EdgeInsets.all(8), child: scale),
        if (_sentence.isNotEmpty)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Expanded(
                child: Text(_sentence,
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
              ),
              IconButton(
                  tooltip: I18n.t('Speak'),
                  onPressed: _say,
                  icon: const Icon(Icons.volume_up,
                      color: Color(0xFF2E7D32), size: 30)),
              IconButton(
                tooltip: I18n.t('Add to the message'),
                onPressed: () {
                  session.addPhrase(_sentence);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.playlist_add,
                    color: Color(0xFF1565C0), size: 30),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _PartTile extends StatelessWidget {
  final String label;
  final VocabButton? button;
  final bool selected;
  final ValueChanged<VocabButton?> onTap;
  const _PartTile(
      {required this.label,
      required this.button,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = button;
    return Material(
      color: const Color(0xFFFFB74D),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onTap(b),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? const Color(0xFFC62828) : Colors.black26,
                width: selected ? 5 : 1),
          ),
          child: Column(children: [
            Expanded(
              child: b == null
                  ? const Icon(Icons.accessibility_new,
                      size: 44, color: Colors.black54)
                  : LayoutBuilder(
                      builder: (_, c) => SymbolLibrary.resolve(b.symbol,
                          size: c.biggest.shortestSide)),
            ),
            Text(b?.shownLabel ?? I18n.word(label),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87)),
          ]),
        ),
      ),
    );
  }
}
