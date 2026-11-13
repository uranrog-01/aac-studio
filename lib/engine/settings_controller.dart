import 'i18n.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, rootBundle;

import '../data/pack_loader.dart';
import '../models/domain.dart';
import 'app_lock.dart';
import 'arasaac.dart';
import 'storage.dart';

/// M5: settings state (speech defaults + restrictions) persisted to JSON.
class SettingsController extends ChangeNotifier {
  final AppStorage storage;
  late AppSettings settings;
  final _screenPinning = ValueNotifier<bool?>(null);
  int _pinningRead = 0;
  bool _changingLock = false;

  SettingsController(this.storage);

  bool get editMode => settings.editMode;
  bool get restrictionsEnabled => settings.restrictionsEnabled;
  ValueListenable<bool?> get screenPinning => _screenPinning;

  @override
  void dispose() {
    _pinningRead++;
    _screenPinning.dispose();
    super.dispose();
  }

  Future<void> load() async {
    // Unreadable settings never stop the app: it opens with defaults.
    try {
      settings =
          AppSettings.fromJson(await storage.readJson(storage.settingsFile));
    } catch (_) {
      settings = AppSettings();
    }
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

  Future<bool?> refreshScreenPinning() async {
    if (!AppLock.canPin) return null;
    final read = ++_pinningRead;
    final pinned = await AppLock.active();
    if (read == _pinningRead) _screenPinning.value = pinned;
    return pinned;
  }

  Future<void> pinScreen() async {
    if (!AppLock.canPin || await refreshScreenPinning() == true) return;
    if (!settings.lockApp) return;
    await AppLock.start();
    await refreshScreenPinning();
  }

  Future<void> changeAppLock(BuildContext context, bool locked,
      {VoidCallback? onLocked}) async {
    if (_changingLock) return;
    final messenger = ScaffoldMessenger.of(context);
    _changingLock = true;
    try {
      if (!locked) {
        if (!await guardPrivileged(context) || !context.mounted) return;
        if (AppLock.canPin && await refreshScreenPinning() != false) {
          final accepted = await AppLock.stop();
          var pinned = await refreshScreenPinning();
          if (accepted == true && pinned == true) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            pinned = await refreshScreenPinning();
          }
          if (pinned == true) {
            _showNotice(messenger,
                'Android still has the screen pinned. Try unlocking again.');
            return;
          }
        }
      }
      final previousLock = settings.lockApp;
      final previousEdit = settings.editMode;
      settings.lockApp = locked;
      if (locked) settings.editMode = false;
      try {
        await update();
      } catch (_) {
        settings.lockApp = previousLock;
        settings.editMode = previousEdit;
        notifyListeners();
        _showNotice(
            messenger, 'Changes could not be saved. Check free storage space.');
        return;
      }
      if (locked) {
        if (context.mounted) onLocked?.call();
        await pinScreen();
      }
    } finally {
      _changingLock = false;
    }
  }

  void _showNotice(ScaffoldMessengerState messenger, String message) {
    if (messenger.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(I18n.t(message))));
    }
  }

  /// Always prompts for the caregiver code.
  Future<bool> guardPrivileged(BuildContext context) =>
      confirmPin(context, settings.pin);

  static Future<bool> confirmPin(BuildContext context, String expected) async =>
      await _readPin(context, 'Enter code') == expected;

  static Future<String?> _readPin(BuildContext context, String title) =>
      showDialog<String>(
        context: context,
        builder: (ctx) => _PinDialog(title),
      );

  Future<void> changePin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await guardPrivileged(context) || !context.mounted) return;
    final pin = await _readPin(context, 'Set a new 4-digit code');
    if (!context.mounted || pin == null || pin.length != 4) return;
    final previous = settings.pin;
    settings.pin = pin;
    try {
      await update();
    } catch (_) {
      settings.pin = previous;
      _showNotice(
          messenger, 'Changes could not be saved. Check free storage space.');
    }
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

class _PinDialog extends StatefulWidget {
  final String title;
  const _PinDialog(this.title);

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final TextEditingController c = TextEditingController();

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF2A2E35),
      title: Text(I18n.t(widget.title),
          style: const TextStyle(color: Colors.white, fontSize: 16)),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(color: Colors.white),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(I18n.t('Cancel'))),
        FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text(I18n.t('OK'))),
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
    // Upgrade when the bundled board file is newer than the saved one. The
    // board file's own version is used (not the app's), so a stale cached
    // board file during an update cannot mark a board as upgraded.
    final factoryVersion = (factory['packVersion'] as num?)?.toInt() ?? 0;

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
    if (stored != null && storedVersion < factoryVersion) {
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

  /// Moves Home and "All categories" to the current starter layout (the
  /// simpler Home). Only a caregiver does this, on purpose: buttons change
  /// places. The person's own buttons stay, after the starter ones, and
  /// buttons they deleted stay deleted.
  Future<void> useStarterLayout(
      {String assetPath = 'assets/sample_pack.json'}) async {
    if (vocabulary == null) return;
    final factory = loader.save(await loader.loadAsset(assetPath));
    final json = loader.save(vocabulary!);
    final views = json['views'] as Map<String, dynamic>;
    final mineIds = {for (final b in json['buttons'] as List) b['id']};
    final factoryIds = {for (final b in factory['buttons'] as List) b['id']};
    for (final page in {'${json['rootFolder'] ?? 'home'}', 'allcats'}) {
      final fresh = (factory['views'] as Map)[page] as List?;
      final mine = views[page] as List?;
      if (fresh == null || fresh.isEmpty || mine == null || mine.isEmpty) {
        continue;
      }
      final cells = <dynamic>[
        for (final c in (fresh.first as Map)['cells'] as List)
          if (mineIds.contains(c['btn'])) Map<String, dynamic>.from(c as Map)
      ];
      final placed = {for (final c in cells) c['btn']};
      final view = mine.first as Map;
      for (final c in view['cells'] as List) {
        if (!placed.contains(c['btn']) && !factoryIds.contains(c['btn'])) {
          cells.add(c);
        }
      }
      view['cells'] = cells;
      view['columns'] = (fresh.first as Map)['columns'];
    }
    final next = _usable(json);
    if (next == null) return;
    vocabulary = next;
    await save();
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
