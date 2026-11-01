import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../modes.dart' show SpeechEngineProvider;

/// Browse ALL bundled symbols (24,296): search, tap to hear the word,
/// add any symbol as a button to the Home folder of your vocabulary.
class SymbolBrowser extends StatefulWidget {
  const SymbolBrowser({super.key});

  @override
  State<SymbolBrowser> createState() => _SymbolBrowserState();
}

class _SymbolBrowserState extends State<SymbolBrowser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final library = context.watch<SymbolLibrary>();
    final results = library.search(_query, limit: 400);
    return Scaffold(
      backgroundColor: const Color(0xFF26323C),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E2730),
        title: Text('All symbols (${library.size})',
            style: const TextStyle(color: Colors.white, fontSize: 17)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            autofocus: true,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search ${library.size} symbols…',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon: const Icon(Icons.search, color: Colors.white38),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF31383F),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (q) => setState(() => _query = q),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 92,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6),
            itemCount: results.length,
            itemBuilder: (context, i) {
              final e = results[i];
              return _SymbolTile(entry: e);
            },
          ),
        ),
      ]),
    );
  }
}

class _SymbolTile extends StatelessWidget {
  final SymbolEntry entry;
  const _SymbolTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final ref = SymbolRef(entry.name, pack: entry.pack, key: entry.key);
    return Material(
      color: const Color(0xFF31383F),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: SymbolLibrary.resolve(ref, size: 48),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4, left: 3, right: 3),
            child: Text(entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 9)),
          ),
        ]),
      ),
    );
  }

  void _open(BuildContext context) {
    final pack = context.read<PackController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF22262D),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              height: 110,
              child: SymbolLibrary.resolve(
                  SymbolRef(entry.name, pack: entry.pack, key: entry.key),
                  size: 100)),
          const SizedBox(height: 8),
          Text(entry.name,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(
              onPressed: () {
                SpeechEngineProvider.of(ctx).speak(entry.name);
              },
              icon: const Icon(Icons.volume_up),
              label: const Text('Hear it'),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                _addToVocabulary(ctx, pack);
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add to Home'),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Tap a symbol on the grid to hear it speak. Long text? '
              'Edit it in Options → Edit mode.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white24, fontSize: 10)),
        ]),
      ),
    );
  }

  void _addToVocabulary(BuildContext context, PackController pack) {
    final vocab = pack.vocabulary;
    if (vocab == null) return;
    final views = vocab.viewsByFolder[vocab.rootFolderId];
    if (views == null || views.isEmpty) return;
    final button = VocabButton(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      label: entry.name,
      kind: ButtonKind.item,
      wordClass: WordClass.noun,
      symbol: SymbolRef(entry.name, pack: entry.pack, key: entry.key),
      actions: const [VocabAction(ActionKind.addText)],
    );
    views.first.cells.add(GridCell(button));
    pack.save();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${entry.name}" added to Home'),
      duration: const Duration(seconds: 2),
    ));
  }
}
