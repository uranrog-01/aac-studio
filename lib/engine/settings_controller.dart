import 'dart:io';

import 'package:flutter/material.dart';

import '../data/pack_loader.dart';
import '../models/domain.dart';
import 'storage.dart';

/// M5: settings state (speech defaults + restrictions) persisted to JSON.
class SettingsController extends ChangeNotifier {
  final AppStorage storage;
  late AppSettings settings;

  SettingsController(this.storage);

  bool get editMode => settings.editMode;
  bool get restrictionsEnabled => settings.restrictionsEnabled;

  Future<void> load() async {
    settings = AppSettings.fromJson(await storage.readJson(storage.settingsFile));
    notifyListeners();
  }

  Future<void> update() async {
    await storage.writeJson(storage.settingsFile, settings.toJson());
    notifyListeners();
  }

  /// Always prompts for the edit-mode code (default 1234).
  Future<bool> guardPrivileged(BuildContext context) async {
    final s = await showDialog<_PinResult>(
      context: context,
      builder: (ctx) => _PinDialog(),
    );
    return s != null && s.ok && s.pin == settings.pin;
  }

  /// Edit mode always requires the code (default 1234, changeable in
  /// settings) when enabling it.
  Future<void> setEditMode(bool on, BuildContext context) async {
    if (on) {
      final allowed = await guardPrivileged(context);
      if (!allowed) return;
    }
    settings.editMode = on;
    await update();
  }

  Future<bool> verifyPin(String pin) => Future.value(pin == settings.pin);
}

class _PinResult {
  final bool ok;
  final String pin;
  _PinResult(this.ok, this.pin);
}

class _PinDialog extends StatelessWidget {
  final TextEditingController c = TextEditingController();
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2E35),
      title: const Text('Enter restrictions PIN',
          style: TextStyle(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, _PinResult(false, '')),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _PinResult(true, c.text)),
            child: const Text('OK')),
      ],
    );
  }
}

/// M5: holds the editable vocabulary pack (My AAC mode) and persists it.
class PackController extends ChangeNotifier {
  final AppStorage storage;
  final PackLoader loader = PackLoader();
  Vocabulary? vocabulary;
  late String packId;

  PackController(this.storage);

  Future<void> load({String assetPath = 'assets/sample_pack.json'}) async {
    final f = storage.packFile('sample_pack');
    // Bundled pack version: when the shipped pack is newer than the stored
    // one, upgrade (keeping a backup of the user's edits) so improvements
    // reach already-installed devices.
    final assetRaw = await loader.loadAsset(assetPath);
    const kPackVersion = 2;
    int storedVersion = 0;
    if (await f.exists()) {
      final stored = await storage.readJson(f);
      storedVersion = (stored?['packVersion'] as num?)?.toInt() ?? 0;
    }
    if (!await f.exists() || storedVersion < kPackVersion) {
      if (await f.exists()) {
        final backup = File(
            '${f.path}.backup-${DateTime.now().millisecondsSinceEpoch}.json');
        await f.copy(backup.path);
      }
      await storage.writeJson(f, loader.save(assetRaw));
    }
    vocabulary = await loader.loadFile(f.path);
    packId = vocabulary!.id;
    notifyListeners();
  }

  void save() {
    if (vocabulary == null) return;
    storage.writeJson(storage.packFile('sample_pack'), loader.save(vocabulary!));
    notifyListeners();
  }
}
