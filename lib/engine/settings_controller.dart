import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../data/pack_loader.dart';
import '../models/domain.dart';
import 'arasaac.dart';
import 'storage.dart';

/// M5: settings state (speech defaults + restrictions) persisted to JSON.
class SettingsController extends ChangeNotifier {
  final AppStorage storage;
  late AppSettings settings;

  SettingsController(this.storage);

  bool get editMode => settings.editMode;
  bool get restrictionsEnabled => settings.restrictionsEnabled;

  Future<void> load() async {
    settings =
        AppSettings.fromJson(await storage.readJson(storage.settingsFile));
    if (kIsWeb) settings.usePiper = false;
    // The app always opens ready to talk: a caregiver who forgot to leave
    // edit mode must not turn every tap into an editor after a restart.
    settings.editMode = false;
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

  /// True when the last save did not reach storage.
  bool saveFailed = false;

  /// Set when the saved board could not be read and the starter board was
  /// opened instead (the unreadable file is kept beside it).
  bool recoveredFromDamage = false;

  /// Parses [json] as a usable board (has a Home page) or returns null.
  Vocabulary? _usable(Map<String, dynamic>? json) {
    if (json == null) return null;
    try {
      final v = loader.loadString(jsonEncode(json));
      return (v.viewsByFolder[v.rootFolderId]?.isNotEmpty ?? false) ? v : null;
    } catch (_) {
      return null;
    }
  }

  /// Opens the saved board. A damaged or unreadable save never blocks the
  /// app: the previous good copy is tried, then the starter board opens so
  /// the person can still talk.
  Future<void> load({String assetPath = 'assets/sample_pack.json'}) async {
    final f = storage.packFile('sample_pack');
    final factory = loader.save(await loader.loadAsset(assetPath));
    const kPackVersion = 9;

    Map<String, dynamic>? stored;
    try {
      stored = await storage.readJson(f);
    } catch (_) {/* Treated as unreadable below. */}
    final exists = await f.exists();
    recoveredFromDamage = false;
    if (_usable(stored) == null) {
      if (exists) {
        recoveredFromDamage = true;
        try {
          await f.copy('${f.path}.unreadable-'
              '${DateTime.now().millisecondsSinceEpoch}.json');
        } catch (_) {/* Opening the starter board matters more. */}
      }
      stored = null;
    }

    var result = stored ?? factory;
    var changed = stored == null;
    final storedVersion = (stored?['packVersion'] as num?)?.toInt() ?? 0;
    if (stored != null && storedVersion < kPackVersion) {
      // Bundled pack is newer: merge so improvements reach installed
      // devices while user additions and edits survive (Vocable pattern).
      try {
        await f.copy(
            '${f.path}.backup-${DateTime.now().millisecondsSinceEpoch}.json');
      } catch (_) {}
      try {
        final history = jsonDecode(await rootBundle.loadString(
            'assets/factory_symbol_history.json')) as Map<String, dynamic>;
        final merged = PackUpgrade.merge(stored, factory,
            factorySymbolHistory: history);
        if (_usable(merged) != null) {
          result = merged;
          changed = true;
        }
      } catch (_) {
        // Keep the user's own board rather than replacing it.
      }
    }

    if (_normalizePicturePaths(result)) changed = true;
    vocabulary = _usable(result) ?? loader.loadString(jsonEncode(factory));
    if (changed) {
      try {
        await storage.writeJson(f, result);
      } catch (_) {
        saveFailed = true;
      }
    }
    packId = vocabulary!.id;
    notifyListeners();
  }

  /// Rewrites picture paths into the form that survives the app's data
  /// folder moving (iOS updates). Returns true when anything changed.
  bool _normalizePicturePaths(Map<String, dynamic> json) {
    var changed = false;
    for (final item in [
      ...(json['buttons'] as List? ?? const []),
      ...(json['folders'] as List? ?? const []),
    ]) {
      if (item is! Map) continue;
      final path = item['imagePath'];
      if (path is! String) continue;
      final stored = storage.storedPicturePath(path);
      if (stored != path) {
        item['imagePath'] = stored;
        changed = true;
      }
    }
    return changed;
  }

  Future<void> save() async {
    if (vocabulary == null) return;
    final json = loader.save(vocabulary!);
    notifyListeners();
    try {
      await storage.writeJson(storage.packFile('sample_pack'), json);
      if (saveFailed) {
        saveFailed = false;
        notifyListeners();
      }
    } catch (_) {
      saveFailed = true;
      notifyListeners();
    }
  }
}
