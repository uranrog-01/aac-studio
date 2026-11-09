import 'package:flutter/material.dart';

import '../../engine/photo_picker.dart';
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
  bool _pickingPhoto = false;

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
    final results = widget.library
        .search(_query, limit: 600)
        .where((e) => _packFilter == 'all' || e.pack == _packFilter)
        .take(60)
        .toList();
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
                      // Fits narrow phones: long names shorten, no overflow.
                      isExpanded: true,
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
                  // The picture sets bundled with the app.
                  items: const [
                    DropdownMenuItem(value: 'all', child: Text('All pictures')),
                    DropdownMenuItem(
                        value: 'modernflat', child: Text('Modern flat')),
                    DropdownMenuItem(value: 'mulberry', child: Text('Mulberry')),
                    DropdownMenuItem(value: 'twemoji', child: Text('Flags')),
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
              Wrap(spacing: 8, children: [
                OutlinedButton.icon(
                  onPressed: _pickingPhoto ? null : _usePhoto,
                  icon: _pickingPhoto
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.photo_library_outlined),
                  label: const Text('Use a photo'),
                ),
                if (_symbol.imagePath != null)
                  TextButton(
                    onPressed: () => setState(
                        () => _symbol = SymbolRef(_symbol.emoji)),
                    child: const Text('Remove photo'),
                  ),
              ]),
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
                // Speech rate is 0-1 on every platform (0.45 = normal).
                _slider('speed', _voice?.rate, 0.45, 0.1, 1.0,
                    (v) => _applyVoice(rate: v)),
                _slider('pitch', _voice?.pitch, 1.0, 0.5, 2.0,
                    (v) => _applyVoice(pitch: v)),
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
            onPressed: _confirmDelete,
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
              // Editing must not drop the star (My words).
              favorite: widget.existing?.favorite ?? false,
            ));
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final label = widget.existing?.label ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "$label"?'),
        content: const Text('The button is removed from this board. '
            'Save a backup first if you may want it back.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.onDelete?.call();
    Navigator.pop(context);
  }

  Future<void> _usePhoto() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _pickingPhoto = true);
    try {
      final path = await PhotoPicker.pick();
      if (path != null && mounted) {
        setState(() => _symbol = SymbolRef(
            _label.text.trim().isEmpty ? '📷' : _label.text.trim(),
            imagePath: path));
      }
    } catch (_) {
      messenger?.showSnackBar(const SnackBar(
          content: Text('That photo could not be used. Try another one.')));
    } finally {
      if (mounted) setState(() => _pickingPhoto = false);
    }
  }

  void _applyVoice({double? rate, double? pitch}) {
    setState(() {
      _voice = (_voice ?? const VoiceStyle())
          .copyWith(rate: rate, pitch: pitch);
    });
  }

  Widget _slider(String label, double? value, double normal, double min,
      double max, ValueChanged<double> onChanged) {
    final v = (value ?? normal).clamp(min, max);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 11)),
      // A fixed width: an unbounded slider overflowed phone screens.
      SizedBox(
        width: 150,
        child: Slider(
          value: v,
          min: min,
          max: max,
          divisions: ((max - min) * 20).round(),
          label: v.toStringAsFixed(2),
          onChanged: onChanged,
        ),
      ),
    ]);
  }

  Widget _emojiQuickRow() => const SizedBox.shrink();
}
