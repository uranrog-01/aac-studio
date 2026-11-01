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

  /// Returns true when the action is allowed (no restrictions or PIN ok).
  Future<bool> guardPrivileged(BuildContext context) async {
    if (!settings.restrictionsEnabled) return true;
    final s = await showDialog<_PinResult>(
      context: context,
      builder: (ctx) => _PinDialog(),
    );
    return s != null && s.ok && s.pin == settings.pin;
  }

  Future<void> setEditMode(bool on, BuildContext context) async {
    if (on && settings.restrictionsEnabled) {
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
    if (!await f.exists()) {
      // first run: copy the bundled asset into the editable pack
      final raw = await loader.loadAsset(assetPath);
      await storage.writeJson(f, loader.save(raw));
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
