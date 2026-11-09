import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/board_backup.dart';
import '../../engine/prediction.dart';
import '../../engine/settings_controller.dart';
import '../../engine/storage.dart';

/// Save / restore the whole board on Android, iPhone, iPad and Windows, so a
/// lost, broken or reset device does not take the person's words with it.
class BackupTools extends StatefulWidget {
  const BackupTools({super.key});
  @override
  State<BackupTools> createState() => _BackupToolsState();
}

class _BackupToolsState extends State<BackupTools> {
  bool _busy = false;

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    final storage = context.read<PackController>().storage;
    setState(() => _busy = true);
    try {
      final backup = await BoardBackup.create(storage);
      final bytes = Uint8List.fromList(
          utf8.encode(const JsonEncoder.withIndent(' ').convert(backup)));
      final day = DateTime.now().toIso8601String().substring(0, 10);
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Save AAC Studio backup',
        fileName: 'AAC-Studio-backup-$day.json',
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (saved != null) _message('Backup saved.');
    } catch (_) {
      _message('The backup could not be saved. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final pack = context.read<PackController>();
    final settings = context.read<SettingsController>();
    final predictor = context.read<Predictor>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
          dialogTitle: 'Choose an AAC Studio backup');
      if (file == null || !mounted) return;
      final backup = BoardBackup.parse(utf8.decode(await file.readAsBytes()));
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('Restore this backup?'),
                content: const Text(
                    'This replaces the current board, settings and learned '
                    'words on this device. Save a backup first if you want '
                    'to keep them.'),
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
      await BoardBackup.restore(pack.storage, backup);
      await settings.load();
      await pack.load();
      await predictor.loadLearned(StorageProviderAdapter(pack.storage));
      if (navigator.canPop()) navigator.pop(); // close the old settings sheet
      messenger.showSnackBar(const SnackBar(content: Text('Backup restored.')));
    } catch (_) {
      _message('This file could not be restored. Choose an AAC Studio '
          'backup file.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
                'Keep a backup somewhere else (Files, Drive, email) so a lost '
                'or reset device does not lose this board.',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save backup')),
            TextButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: const Text('Restore backup')),
          ]),
        ],
      );
}
