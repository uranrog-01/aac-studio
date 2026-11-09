import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/arasaac.dart';
import 'package:aac_studio/engine/board_backup.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final key = utf8.decode(message!.buffer.asUint8List());
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object>{});
    }
    final file = File(key);
    if (!await file.exists()) return null;
    return ByteData.sublistView(await file.readAsBytes());
  });
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async => call.method == 'isLanguageAvailable' ? true : 1);

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('aac_fix_'));
  tearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('crash-safe saving', () {
    test('a damaged file falls back to the previous good copy', () async {
      final storage = await AppStorage.at(temp);
      final f = storage.settingsFile;
      await storage.writeJson(f, {'n': 1});
      await storage.writeJson(f, {'n': 2});
      expect((await storage.readJson(f))!['n'], 2);
      await f.writeAsString('{"n": 3, broken'); // half-written file
      expect((await storage.readJson(f))!['n'], 1,
          reason: 'previous good copy is used');
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    });

    test('rapid saves land in order with the last one winning', () async {
      final storage = await AppStorage.at(temp);
      final f = storage.learnedFile;
      final data = <String, int>{};
      final saves = <Future<void>>[];
      for (var i = 0; i < 25; i++) {
        data['w$i'] = i;
        saves.add(storage.writeJson(f, data));
      }
      await Future.wait(saves);
      expect((await storage.readJson(f))!.length, 25);
    });

    test('an unreadable board opens the starter board and keeps a copy',
        () async {
      final storage = await AppStorage.at(temp);
      final f = storage.packFile('sample_pack');
      await f.writeAsString('{"id": "sample", "buttons": [ truncated');
      final pack = PackController(storage);
      await pack.load();
      expect(pack.vocabulary, isNotNull);
      expect(pack.recoveredFromDamage, isTrue);
      expect(
          pack.vocabulary!.viewsByFolder[pack.vocabulary!.rootFolderId],
          isNotEmpty);
      expect(
          storage.packsDir
              .listSync()
              .any((e) => e.path.contains('.unreadable-')),
          isTrue);
    });

    test('a good board opens normally and edits survive a reload', () async {
      final storage = await AppStorage.at(temp);
      final first = PackController(storage);
      await first.load();
      expect(first.recoveredFromDamage, isFalse);
      first.vocabulary!.removedIds.add('marker');
      await first.save();
      final second = PackController(storage);
      await second.load();
      expect(second.vocabulary!.removedIds, contains('marker'));
    });
  });

  test('a cell pointing at a missing button is skipped, not fatal', () {
    final json = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
        as Map<String, dynamic>;
    final home = (json['views'] as Map)['home'] as List;
    ((home.first as Map)['cells'] as List).add({'btn': 'does-not-exist'});
    final v = PackLoader().loadString(jsonEncode(json));
    expect(v.viewsByFolder['home']!.first.cells, isNotEmpty);
    expect(
        v.viewsByFolder['home']!.first.cells
            .any((c) => c.button.id == 'does-not-exist'),
        isFalse);
  });

  test('the app never starts in edit mode', () async {
    final storage = await AppStorage.at(temp);
    await storage.writeJson(
        storage.settingsFile, (AppSettings()..editMode = true).toJson());
    final settings = SettingsController(storage);
    await settings.load();
    expect(settings.editMode, isFalse);
  });

  test('backup round trip restores board, settings, words and pictures',
      () async {
    final source = await AppStorage.at(Directory('${temp.path}/a'));
    final pack = PackController(source);
    await pack.load();
    final picture = File('${temp.path}/photo.png')
      ..writeAsBytesSync([1, 2, 3, 4]);
    final json = PackLoader().save(pack.vocabulary!);
    (json['buttons'] as List).first['imagePath'] = picture.path;
    await source.writeJson(source.packFile('sample_pack'), json);
    await source.writeJson(
        source.settingsFile, (AppSettings()..rate = 0.3).toJson());
    await source.writeJson(source.learnedFile, {'dinosaur': 4});

    final backup = BoardBackup.create(source);
    final text = jsonEncode(await backup);
    final parsed = BoardBackup.parse(text);

    final target = await AppStorage.at(Directory('${temp.path}/b'));
    await BoardBackup.restore(target, parsed);
    final restored = await target.readJson(target.packFile('sample_pack'));
    final newPath = (restored!['buttons'] as List).first['imagePath'] as String;
    expect(newPath, startsWith('restored_pictures/'),
        reason: 'saved relative to the app folder');
    expect(File(target.resolvePicturePath(newPath)).readAsBytesSync(),
        [1, 2, 3, 4]);
    expect((await target.readJson(target.settingsFile))!['rate'], 0.3);
    expect((await target.readJson(target.learnedFile))!['dinosaur'], 4);

    expect(() => BoardBackup.parse('{"format": "other"}'),
        throwsFormatException);
  });

  group('board pictures', () {
    test('picture paths are saved relative to the app folder', () async {
      final storage = await AppStorage.at(temp);
      final inside = '${storage.root.path}${Platform.pathSeparator}imgcache'
          '${Platform.pathSeparator}arasaac_5.png';
      expect(storage.storedPicturePath(inside), 'imgcache/arasaac_5.png');
      // A full path saved before an iOS update moved the app's folder.
      expect(
          storage.storedPicturePath('/var/mobile/Containers/Data/Application/'
              'OLD-ID/Library/Application Support/data/imgcache/arasaac_5.png'),
          'imgcache/arasaac_5.png');
      expect(storage.storedPicturePath('data:image/png;base64,AAAA'),
          'data:image/png;base64,AAAA');
      expect(storage.storedPicturePath('https://example.org/a.png'),
          'https://example.org/a.png');
      final elsewhere = '${temp.parent.path}${Platform.pathSeparator}x.png';
      expect(storage.storedPicturePath(elsewhere), elsewhere);
      expect(storage.resolvePicturePath('imgcache/arasaac_5.png'), inside);
    });

    test('an old board with full picture paths is repaired on load',
        () async {
      final storage = await AppStorage.at(temp);
      final picture =
          File('${storage.root.path}/imgcache/arasaac_7.png')
            ..createSync(recursive: true)
            ..writeAsBytesSync([9]);
      final pack = PackController(storage);
      await pack.load();
      final json = PackLoader().save(pack.vocabulary!);
      (json['buttons'] as List).first['imagePath'] =
          '/var/mobile/Containers/Data/Application/OLD-ID/Library/'
          'Application Support/data/imgcache/arasaac_7.png';
      await storage.writeJson(storage.packFile('sample_pack'), json);

      final reopened = PackController(storage);
      await reopened.load();
      final first = reopened.vocabulary!.viewsByFolder.values
          .expand((views) => views)
          .expand((view) => view.cells)
          .map((c) => c.button)
          .firstWhere((b) => b.symbol.imagePath != null);
      expect(first.symbol.imagePath, 'imgcache/arasaac_7.png');
      expect(File(storage.resolvePicturePath(first.symbol.imagePath!))
          .readAsBytesSync(), picture.readAsBytesSync());
      final saved = await storage.readJson(storage.packFile('sample_pack'));
      expect(
          (saved!['buttons'] as List)
              .any((b) => b['imagePath'] == 'imgcache/arasaac_7.png'),
          isTrue,
          reason: 'the repair is saved');
    });

    test('cache cleanup never deletes a picture the board uses', () async {
      final storage = await AppStorage.at(temp);
      final pack = PackController(storage);
      await pack.load();
      final cache = Directory('${storage.root.path}/imgcache')
        ..createSync(recursive: true);
      for (final name in ['old_used', 'old_unused', 'new']) {
        File('${cache.path}/$name.png').writeAsBytesSync(List.filled(100, 1));
      }
      final json = PackLoader().save(pack.vocabulary!);
      (json['buttons'] as List).first['imagePath'] = 'imgcache/old_used.png';
      await storage.writeJson(storage.packFile('sample_pack'), json);

      final index = <String, dynamic>{
        'u1': {'file': 'imgcache/old_used.png', 'lastUsed': 1, 'size': 100},
        'u2': {'file': 'imgcache/old_unused.png', 'lastUsed': 2, 'size': 100},
        'u3': {'file': 'imgcache/new.png', 'lastUsed': 3, 'size': 100},
      };
      await ArasaacService(storage).evict(index, cap: 250);
      expect(File('${cache.path}/old_used.png').existsSync(), isTrue,
          reason: 'used on the board, although least recently used');
      expect(File('${cache.path}/old_unused.png').existsSync(), isFalse);
      expect(index.keys, containsAll(['u1', 'u3']));
      expect(index.containsKey('u2'), isFalse);
    });
  });

  group('access methods', () {
    Future<(GridSession, SettingsController)> pumpGrid(
        WidgetTester tester, void Function(AppSettings) configure) async {
      tester.view.physicalSize = const Size(1024, 1366);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final vocabulary = PackLoader()
          .loadString(File('assets/sample_pack.json').readAsStringSync());
      final storage = await tester.runAsync(() => AppStorage.at(temp));
      final settings = SettingsController(storage!)..settings = AppSettings();
      configure(settings.settings);
      final session =
          GridSession(vocabulary: vocabulary, speech: SpeechEngine());
      await tester.pumpWidget(ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
              theme: ThemeData(splashFactory: NoSplash.splashFactory),
              home: GridScreen(session: session, maxColumns: 6))));
      return (session, settings);
    }

    testWidgets('switch scanning selects the highlighted button',
        (tester) async {
      final (session, _) = await pumpGrid(tester, (s) {
        s.scanningEnabled = true;
        s.scanDelayMs = 1000;
      });
      await tester.tap(find.bySemanticsLabel('Scan'));
      await tester.pump();
      // Row 1 is highlighted: Space opens it, Space picks its first word.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(session.message, 'I');

      // Scanning continues from the top: wait one step to reach row 2,
      // open it, wait one step to the 2nd word, then select by touching a
      // DIFFERENT place on the screen; the highlighted word must win.
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      await tester.tapAt(const Offset(40, 1200));
      await tester.pump();
      expect(session.message, 'I like');

      await tester.tap(find.bySemanticsLabel('Stop scan'));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('hold to select ignores quick taps and fires when held',
        (tester) async {
      final (session, _) = await pumpGrid(tester, (s) {
        s.dwellEnabled = true;
        s.dwellSeconds = 1.0;
      });
      final word = find.text('want');
      await tester.tap(word);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(session.message, isEmpty, reason: 'a quick tap does nothing');

      final gesture = await tester.startGesture(tester.getCenter(word));
      await tester.pump(const Duration(milliseconds: 500));
      expect(session.message, isEmpty, reason: 'not held long enough yet');
      await tester.pump(const Duration(milliseconds: 600));
      expect(session.message, 'want');
      await gesture.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
