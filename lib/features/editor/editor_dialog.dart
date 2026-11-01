import 'package:flutter/material.dart';

import '../../engine/symbol_library.dart';
import '../../models/domain.dart';

/// M5 editor: edit an existing button or create a new one.
/// Fields: label, spoken text, word class, symbol (search ~21k open symbols
/// or custom emoji), voice style overrides, delete.
class ButtonEditorDialog extends StatefulWidget {
  final VocabButton? existing; // null = create
  final SymbolLibrary library;
  final void Function(VocabButton result) onSave;
  final VoidCallback? onDelete;

  const ButtonEditorDialog({
    super.key,
    required this.library,
    required this.onSave,
    this.existing,
    this.onDelete,
  });

  static Future<void> show(
    BuildContext context, {
    required SymbolLibrary library,
    required void Function(VocabButton) onSave,
    VocabButton? existing,
    VoidCallback? onDelete,
  }) {
    return showDialog(
      context: context,
      builder: (_) => ButtonEditorDialog(
        library: library,
        onSave: onSave,
        existing: existing,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<ButtonEditorDialog> createState() => _ButtonEditorDialogState();
}

class _ButtonEditorDialogState extends State<ButtonEditorDialog> {
  late final TextEditingController _label;
  late final TextEditingController _spoken;
  late WordClass _wordClass;
  late SymbolRef _symbol;
  VoiceStyle? _voice;
  String _query = '';
  String _packFilter = 'all';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _label = TextEditingController(text: e?.label ?? '');
    _spoken = TextEditingController(text: e?.spokenText ?? '');
    _wordClass = e?.wordClass ?? WordClass.noun;
    _symbol = e?.symbol ?? const SymbolRef('⬛');
    _voice = e?.voice;
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.library.search(_query, limit: 60);
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2E35),
      title: Text(widget.existing == null ? 'Add button' : 'Edit button',
          style: const TextStyle(color: Colors.white, fontSize: 18)),
      content: SizedBox(
        width: 520,
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white70, fontSize: 13),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // live preview
                Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: kWordClassColors[_wordClass],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.black26),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Column(children: [
                    Expanded(
                        child: SymbolLibrary.resolve(_symbol, size: 56)),
                    Text(_label.text.isEmpty ? 'label' : _label.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.black87, fontSize: 11)),
                  ]),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(children: [
                    TextField(
                      controller: _label,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'Label', labelStyle: TextStyle(color: Colors.white54)),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _spoken,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: 'Spoken text (optional)',
                          labelStyle: TextStyle(color: Colors.white54)),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<WordClass>(
                      initialValue: _wordClass,
                      dropdownColor: const Color(0xFF2A2E35),
                      items: [
                        for (final w in WordClass.values)
                          if (w != WordClass.unknown)
                            DropdownMenuItem(value: w, child: Text(w.name))
                      ],
                      onChanged: (w) => setState(() => _wordClass = w ?? WordClass.noun),
                      decoration: const InputDecoration(
                          labelText: 'Word class',
                          labelStyle: TextStyle(color: Colors.white54)),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              // symbol search
              Row(children: [
                Expanded(
                  child: TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          'Search ${widget.library.size} symbols…',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      isDense: true,
                    ),
                    onChanged: (q) => setState(() => _query = q),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _packFilter,
                  dropdownColor: const Color(0xFF2A2E35),
                  style: const TextStyle(color: Colors.white70),
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('all packs')),
                    DropdownMenuItem(value: 'twemoji', child: Text('Twemoji')),
                    DropdownMenuItem(value: 'twemoji_svg', child: Text('Twemoji SVG')),
                    DropdownMenuItem(value: 'noto', child: Text('Noto')),
                    DropdownMenuItem(value: 'openmoji', child: Text('OpenMoji')),
                    DropdownMenuItem(value: 'mulberry', child: Text('Mulberry')),
                  ],
                  onChanged: (p) => setState(() => _packFilter = p ?? 'all'),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 168,
                child: _query.isEmpty
                    ? _emojiQuickRow()
                    : results.isEmpty
                        ? const Center(
                            child: Text('no matches',
                                style: TextStyle(color: Colors.white38)))
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 64, mainAxisSpacing: 4, crossAxisSpacing: 4),
                            itemCount: results.length,
                            itemBuilder: (_, i) {
                              final e = results[i];
                              if (_packFilter != 'all' && e.pack != _packFilter) {
                                return const SizedBox.shrink();
                              }
                              final ref = SymbolRef(e.name,
                                  pack: e.pack, key: e.key);
                              return InkWell(
                                onTap: () =>
                                    setState(() => _symbol = ref),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1D2026),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: _symbol.pack == e.pack &&
                                                _symbol.key == e.key
                                            ? Colors.deepOrangeAccent
                                            : Colors.white10),
                                  ),
                                  padding: const EdgeInsets.all(6),
                                  child: SymbolLibrary.resolve(ref, size: 44),
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 10),
              // emoji quick set + clear
              Wrap(spacing: 6, children: [
                for (final e in ['⬛', '🙋', '👍', '❤️', '⭐', '🍎', '🚗', '🎯'])
                  InkWell(
                    onTap: () => setState(
                        () => _symbol = SymbolRef(e)),
                    child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                            color: const Color(0xFF1D2026),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(e, style: const TextStyle(fontSize: 18))),
                  ),
              ]),
              const SizedBox(height: 12),
              // M3 voice style
              Wrap(spacing: 14, crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                const Text('Voice:', style: TextStyle(color: Colors.white54)),
                _slider('rate', _voice?.rate, (v) => _applyVoice(rate: v)),
                _slider('pitch', _voice?.pitch, (v) => _applyVoice(pitch: v)),
                TextButton(
                  onPressed: () => setState(() => _voice = null),
                  child: const Text('reset voice',
                      style: TextStyle(color: Colors.white38)),
                ),
              ]),
            ]),
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          TextButton(
            onPressed: widget.onDelete,
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final label = _label.text.trim();
            if (label.isEmpty) return;
            widget.onSave(VocabButton(
              id: widget.existing?.id ??
                  'u${DateTime.now().microsecondsSinceEpoch}',
              label: label,
              spokenText: _spoken.text.trim().isEmpty ? null : _spoken.text.trim(),
              kind: widget.existing?.kind ?? ButtonKind.item,
              wordClass: _wordClass,
              symbol: _symbol,
              actions: widget.existing?.actions ??
                  const [VocabAction(ActionKind.addText)],
              voice: _voice,
            ));
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  void _applyVoice({double? rate, double? pitch}) {
    setState(() {
      _voice = (_voice ?? const VoiceStyle())
          .copyWith(rate: rate, pitch: pitch);
    });
  }

  Widget _slider(String label, double? value, ValueChanged<double> onChanged) {
    final v = value ?? 1.0;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      Slider(
        value: v.clamp(0.1, 2.0),
        min: 0.1,
        max: 2.0,
        divisions: 38,
        label: v.toStringAsFixed(2),
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _emojiQuickRow() => const SizedBox.shrink();
}
