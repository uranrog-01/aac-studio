import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/pack_loader.dart';
import '../../engine/settings_controller.dart';
import '../../engine/storage.dart';
import '../../engine/prediction.dart';

@JS('aacWeb.offlineStatus')
external JSPromise<JSString> _offlineStatus();
@JS('aacWeb.downloadSymbols')
external JSPromise<JSNumber> _downloadSymbols(JSFunction progress);
@JS('aacWeb.exportBackup')
external JSPromise<JSAny?> _exportBackup();
@JS('aacWeb.pickBackup')
external JSPromise<JSString> _pickBackup();
@JS('aacStorage.restore')
external JSPromise<JSAny?> _restoreFiles(JSString files);

class WebTools extends StatefulWidget {
  const WebTools({super.key});
  @override
  State<WebTools> createState() => _WebToolsState();
}

class _WebToolsState extends State<WebTools> {
  String _status = 'Checking offline storage…';
  bool _downloading = false;
  double? _progress;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    _refresh();
    // Show the automatic offline download's progress while Settings is open.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_downloading) _refresh();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final status = (await _offlineStatus().toDart).toDart;
      if (mounted) setState(() => _status = status);
    } catch (_) {
      if (mounted) setState(() => _status = 'Offline storage unavailable.');
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _download() async {
    setState(() {
      _downloading = true;
      _progress = 0;
    });
    try {
      await _downloadSymbols(((JSNumber done, JSNumber total) {
        if (mounted) {
          setState(() {
            _progress = done.toDartDouble / total.toDartDouble;
            _status = '${done.toDartInt} of ${total.toDartInt} pictures saved';
          });
        }
      }).toJS)
          .toDart;
      _message('All bundled pictures saved for offline use.');
      await _refresh();
    } catch (_) {
      _message(
          'Download interrupted. Check space and connection, then retry to resume.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _restore() async {
    final pack = context.read<PackController>();
    final settings = context.read<SettingsController>();
    final predictor = context.read<Predictor>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final text = (await _pickBackup().toDart).toDart;
      if (text.isEmpty || !mounted) return;
      final backup = jsonDecode(text) as Map<String, dynamic>;
      // Backups from the iPhone/iPad/Android app ('aac-studio') restore
      // here too, so a board moves between devices either way.
      if (!const ['aac-studio-web', 'aac-studio'].contains(backup['format']) ||
          backup['version'] != 1) {
        throw const FormatException('Not an AAC Studio backup');
      }
      final files = backup['files'] as Map<String, dynamic>;
      final board = files['packs/sample_pack.json'] as Map<String, dynamic>;
      _embedPictures(board, backup['images']);
      // Fully parse before changing any saved data.
      final vocabulary = PackLoader().loadString(jsonEncode(board));
      if (vocabulary.viewsByFolder[vocabulary.rootFolderId]?.isNotEmpty !=
          true) {
        throw const FormatException('Missing home board');
      }
      AppSettings.fromJson(files['settings.json'] as Map<String, dynamic>?);
      final learned = files['learned_words.json'] as Map<String, dynamic>?;
      if (learned != null && learned.values.any((v) => v is! int || v < 0)) {
        throw const FormatException('Invalid learned words');
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Restore this backup?'),
                content: const Text(
                    'This replaces your current boards, settings and learned words. Save a backup first if you want to keep them.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Restore')),
                ],
              ));
      if (confirmed != true) return;
      await _restoreFiles(jsonEncode(files).toJS).toDart;
      await settings.load();
      await pack.load();
      await predictor.loadLearned(StorageProviderAdapter(pack.storage));
      if (!mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(const SnackBar(content: Text('Backup restored.')));
    } catch (_) {
      _message(
          'Could not restore this backup. Check that it is an AAC Studio backup.');
    }
  }

  /// An app backup carries its photos and downloaded pictures as base64
  /// next to the board; the browser shows them as data URLs.
  static void _embedPictures(Map<String, dynamic> board, Object? images) {
    if (images is! Map) return;
    for (final item in [
      ...(board['buttons'] as List? ?? const []),
      ...(board['folders'] as List? ?? const []),
    ]) {
      if (item is! Map) continue;
      final path = item['imagePath'];
      final data = path is String ? images[path] : null;
      if (data is! String) continue;
      final ext = path.split('.').last.toLowerCase();
      final type = ext == 'jpg' || ext == 'jpeg'
          ? 'image/jpeg'
          : ext == 'webp'
              ? 'image/webp'
              : ext == 'gif'
                  ? 'image/gif'
                  : 'image/png';
      item['imagePath'] = 'data:$type;base64,$data';
    }
  }

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xFF2C313A),
        child: ExpansionTile(
          leading: const Icon(Icons.install_mobile),
          title: const Text('iPhone & offline'),
          subtitle: const Text('Install, save pictures, back up boards'),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            const Text(
                'In Safari, tap Share > Add to Home Screen. Turn on Open as Web App, then tap Add. No Apple Account password is needed.'),
            const SizedBox(height: 12),
            Text(_status, semanticsLabel: _status),
            if (_downloading)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: LinearProgressIndicator(value: _progress)),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  onPressed: _downloading ? null : _download,
                  icon: const Icon(Icons.download),
                  label: const Text('Save all pictures offline')),
              TextButton(
                  onPressed: _refresh, child: const Text('Check status')),
            ]),
            const Text(
                'All pictures download automatically in the background while the app is open online (about 80 MB, once). Then the app works without internet. Test the voice in airplane mode before relying on it offline.'),
            const SizedBox(height: 12),
            const Text(
                'Your changes are saved on this device. Clearing website data removes them. Keep a backup in Files.'),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                  onPressed: () async {
                    try {
                      await _exportBackup().toDart;
                    } catch (_) {
                      _message('Backup could not be saved. Please try again.');
                    }
                  },
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Save backup')),
              TextButton.icon(
                  onPressed: _restore,
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore backup')),
            ]),
          ],
        ),
      );
}
