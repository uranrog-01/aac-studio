import '../../engine/i18n.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../engine/board_backup.dart';
import '../../engine/install_server.dart';
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
      if (saved != null) _message(I18n.t('Backup saved.'));
    } catch (_) {
      _message(I18n.t('The backup could not be saved. Please try again.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
          dialogTitle: 'Choose an AAC Studio backup');
      if (file == null || !mounted) return;
      final backup = BoardBackup.parse(utf8.decode(await file.readAsBytes()));
      if (!mounted) return;
      await _apply(backup);
    } catch (_) {
      _message(I18n.t('This file could not be restored. Choose an AAC Studio '
          'backup file.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks, then replaces this device's board with [backup].
  Future<void> _apply(Map<String, dynamic> backup) async {
    final pack = context.read<PackController>();
    final settings = context.read<SettingsController>();
    final predictor = context.read<Predictor>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(I18n.t('Restore this backup?')),
                content: Text(I18n.t(
                    'This replaces the current board, settings and learned '
                    'words on this device. Save a backup first if you want '
                    'to keep them.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(I18n.t('Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(I18n.t('Restore'))),
                ],
              ));
      if (confirmed != true) return;
      await BoardBackup.restore(pack.storage, backup);
      await settings.load();
      await pack.load();
      await predictor.loadLearned(StorageProviderAdapter(pack.storage));
      if (navigator.canPop()) navigator.pop(); // close the old settings sheet
      messenger.showSnackBar(
          SnackBar(content: Text(I18n.t('Backup restored.'))));
    }
  }

  // ------------------------------------------------ copy over Wi-Fi

  /// Shares this board on the local Wi-Fi for a few minutes, protected by
  /// a 6-digit code the other device must type.
  Future<void> _send() async {
    final storage = context.read<PackController>().storage;
    setState(() => _busy = true);
    HttpServer? server;
    try {
      final body = jsonEncode(await BoardBackup.create(storage));
      final code = (100000 + Random.secure().nextInt(900000)).toString();
      for (var port = 8790; port < 8810 && server == null; port++) {
        try {
          server = await HttpServer.bind(InternetAddress.anyIPv4, port);
        } on SocketException {
          // try the next port
        }
      }
      final ip = await InstallServer.lanIp();
      if (server == null || ip == null) {
        _message(I18n.t('Connect this device to Wi-Fi first.'));
        return;
      }
      var tries = 0;
      server.listen((req) async {
        if (req.uri.path == '/board/$code') {
          req.response.headers.contentType = ContentType.json;
          req.response.write(body);
        } else {
          // Stop guessing: after 20 wrong codes nothing more is served.
          if (++tries > 20) unawaited(server?.close(force: true));
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });
      final address = '$ip:${server.port}';
      if (!mounted) return;
      final close = Timer(const Duration(minutes: 10), () {
        server?.close(force: true);
      });
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(I18n.t('Send this board')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(I18n.t('On the other device (same Wi-Fi): Settings > Offline '
                'and backup > Receive a board, then type:')),
            const SizedBox(height: 14),
            SelectableText(address,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(I18n.t('Code'), style: const TextStyle(fontSize: 13)),
            SelectableText(code,
                style: const TextStyle(
                    fontSize: 34, fontWeight: FontWeight.w900, letterSpacing: 4)),
            const SizedBox(height: 10),
            Text(I18n.t('Keep this open until the other device says it is done.'),
                style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(c), child: Text(I18n.t('Done'))),
          ],
        ),
      );
      close.cancel();
    } catch (_) {
      _message(I18n.t('The board could not be sent. Please try again.'));
    } finally {
      await server?.close(force: true);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receive() async {
    final address = TextEditingController();
    final code = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(I18n.t('Receive a board')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(I18n.t('On the other device choose Send this board. Then type '
              'the address and code it shows.')),
          TextField(
            controller: address,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
                labelText: I18n.t('Address'), hintText: '192.168.1.20:8790'),
          ),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: I18n.t('Code')),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(I18n.t('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(I18n.t('Receive'))),
        ],
      ),
    );
    if (go != true || !mounted) return;
    final host = address.text.trim().replaceAll(RegExp(r'^https?://'), '');
    final digits = code.text.replaceAll(RegExp(r'\D'), '');
    // Only local network addresses: the board never comes from the internet.
    final local = RegExp(
        r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)[\d.]+(:\d+)?$');
    if (!local.hasMatch(host) || digits.length != 6) {
      _message(I18n.t('Check the address and the 6-digit code.'));
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await http
          .get(Uri.parse('http://$host/board/$digits'))
          .timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        _message(I18n.t('Check the address and the 6-digit code.'));
        return;
      }
      final backup = BoardBackup.parse(utf8.decode(res.bodyBytes));
      if (!mounted) return;
      await _apply(backup);
    } catch (_) {
      _message(I18n.t('The board could not be received. Both devices must be '
          'on the same Wi-Fi.'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                I18n.t('Keep a backup somewhere else (Files, Drive, email) so a lost '
                    'or reset device does not lose this board.'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_alt),
                label: Text(I18n.t('Save backup'))),
            TextButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.restore),
                label: Text(I18n.t('Restore backup'))),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
                I18n.t('Copy this board to another phone or tablet on the same '
                    'Wi-Fi (no internet or account needed).'),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Wrap(spacing: 8, children: [
            TextButton.icon(
                onPressed: _busy ? null : _send,
                icon: const Icon(Icons.wifi_tethering),
                label: Text(I18n.t('Send this board'))),
            TextButton.icon(
                onPressed: _busy ? null : _receive,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: Text(I18n.t('Receive a board'))),
          ]),
        ],
      );
}
