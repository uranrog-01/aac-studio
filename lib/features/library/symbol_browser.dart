import 'dart:async';
import '../../engine/image_reference.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/arasaac.dart';
import '../../engine/settings_controller.dart';
import '../../engine/storage.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../../engine/speech_provider.dart';

/// Browse all bundled flat symbols and optional ARASAAC online
/// pictograms. Tap to hear; add any symbol as a button to Home.
class SymbolBrowser extends StatefulWidget {
  const SymbolBrowser({super.key});

  @override
  State<SymbolBrowser> createState() => _SymbolBrowserState();
}

class _SymbolBrowserState extends State<SymbolBrowser> {
  String _query = '';
  List<({int id, String name})> _arasaac = const [];
  bool _arasaacLoading = false;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _searchArasaac(String q, AppSettings settings) {
    if (!settings.arasaacEnabled || q.trim().length < 2) {
      if (_arasaac.isNotEmpty) setState(() => _arasaac = const []);
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _arasaacLoading = true);
      try {
        final res = await context.read<ArasaacService>().search(q.trim());
        if (mounted) setState(() => _arasaac = res.take(20).toList());
      } catch (_) {
        if (mounted) setState(() => _arasaac = const []);
      } finally {
        if (mounted) setState(() => _arasaacLoading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = context.watch<SymbolLibrary>();
    final settings = context.watch<SettingsController>().settings;
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
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (q) {
              setState(() => _query = q);
              _searchArasaac(q, settings);
            },
          ),
        ),
        // ARASAAC online pictograms (P2)
        if (_arasaac.isNotEmpty || _arasaacLoading)
          SizedBox(
            height: 116,
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 2),
                child: Text(
                    _arasaacLoading
                        ? 'ARASAAC (online)…'
                        : 'ARASAAC pictograms (online)',
                    style:
                        const TextStyle(color: Colors.white38, fontSize: 10)),
              ),
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (final r in _arasaac)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => _openArasaac(context, r, settings),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 92,
                            decoration: BoxDecoration(
                              color: const Color(0xFF31383F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(6),
                            child: Column(children: [
                              Expanded(
                                child: Image.network(
                                    ArasaacService.pictogramUrl(r.id,
                                        skin: settings.arasaacSkin,
                                        hair: settings.arasaacHair),
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.image_not_supported,
                                        color: Colors.white24)),
                              ),
                              Text(r.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 9)),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 92,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6),
            itemCount: results.length,
            itemBuilder: (context, i) => _SymbolTile(entry: results[i]),
          ),
        ),
      ]),
    );
  }

  Future<void> _openArasaac(BuildContext context, ({int id, String name}) r,
      AppSettings settings) async {
    final arasaac = context.read<ArasaacService>();
    final path = await arasaac.cachePictogram(r.id,
        skin: settings.arasaacSkin, hair: settings.arasaacHair);
    if (!context.mounted || path == null) return;
    final pack = context.read<PackController>();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF22262D),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              height: 110, child: referenceImage(path, fit: BoxFit.contain)),
          const SizedBox(height: 8),
          Text(r.name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(
              onPressed: () => SpeechEngineProvider.of(ctx).speak(r.name),
              icon: const Icon(Icons.volume_up),
              label: const Text('Hear it'),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                _addFile(ctx, pack, r.name, path);
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add to Home'),
            ),
          ]),
        ]),
      ),
    );
  }

  void _addFile(
      BuildContext context, PackController pack, String label, String path) {
    final vocab = pack.vocabulary;
    if (vocab == null) return;
    final views = vocab.viewsByFolder[vocab.rootFolderId];
    if (views == null || views.isEmpty) return;
    views.first.cells.add(GridCell(VocabButton(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      label: label,
      kind: ButtonKind.item,
      wordClass: WordClass.noun,
      symbol: SymbolRef(label, imagePath: path),
      actions: const [VocabAction(ActionKind.addText)],
    )));
    pack.save();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"$label" added to Home'),
        duration: const Duration(seconds: 2)));
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
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            FilledButton.icon(
              onPressed: () => SpeechEngineProvider.of(ctx).speak(entry.name),
              icon: const Icon(Icons.volume_up),
              label: const Text('Hear it'),
            ),
            const SizedBox(width: 12),
            FilledButton.tonalIcon(
              onPressed: () {
                _add(ctx, pack);
                Navigator.pop(ctx);
              },
              icon: const Icon(Icons.add),
              label: const Text('Add to Home'),
            ),
          ]),
        ]),
      ),
    );
  }

  void _add(BuildContext context, PackController pack) {
    final vocab = pack.vocabulary;
    if (vocab == null) return;
    final views = vocab.viewsByFolder[vocab.rootFolderId];
    if (views == null || views.isEmpty) return;
    views.first.cells.add(GridCell(VocabButton(
      id: 'u${DateTime.now().microsecondsSinceEpoch}',
      label: entry.name,
      kind: ButtonKind.item,
      wordClass: WordClass.noun,
      symbol: SymbolRef(entry.name, pack: entry.pack, key: entry.key),
      actions: const [VocabAction(ActionKind.addText)],
    )));
    pack.save();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('"${entry.name}" added to Home'),
        duration: const Duration(seconds: 2)));
  }
}
