import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/arasaac.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/settings_controller.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:provider/provider.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/features/grid/keyboard_view.dart';
import 'package:aac_studio/engine/symbol_library.dart';

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
    final bytes = await file.readAsBytes();
    return ByteData.sublistView(bytes);
  });
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isLanguageAvailable') return true;
      return 1;
    });
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows
  ]) {
    test('speech initializes once and delivers rapid taps on $platform',
        () async {
      debugDefaultTargetPlatformOverride = platform;
      final engine = SpeechEngine();
      await Future.wait(
          [engine.ensure(), engine.speak('stop'), engine.speak('help')]);
      expect(calls.where((c) => c.method == 'speak').length, 2);
      expect(calls.where((c) => c.method == 'setQueueMode').length,
          platform == TargetPlatform.android ? 1 : 0);
      expect(calls.where((c) => c.method == 'setSharedInstance').length,
          platform == TargetPlatform.iOS ? 1 : 0);
      expect(engine.error.value, isNull);
    });
  }
  test('speech failure is visible and subsequent taps recover', () async {
    var fail = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'isLanguageAvailable') return true;
      return call.method == 'speak' && fail ? 0 : 1;
    });
    final engine = SpeechEngine();
    await engine.speak('help');
    expect(engine.error.value, isNotNull);
    fail = false;
    await engine.speak('help');
    expect(engine.error.value, isNull);
  });

  test('all factory buttons and categories have existing bundled images',
      () async {
    final pack =
        jsonDecode(await File('assets/sample_pack.json').readAsString())
            as Map<String, dynamic>;
    for (final item in [...pack['buttons'], ...pack['folders']]) {
      final ext = ['noto', 'learning', 'modern3d'].contains(item['symbolPack'])
          ? 'webp'
          : 'svg';
      expect(
          File('assets/symbols/${item['symbolPack']}/${item['symbolKey']}.$ext')
              .existsSync(),
          isTrue,
          reason: '${item['id']}: ${item['label']}');
    }
    final v = await PackLoader().loadAsset('assets/sample_pack.json');
    expect(v.viewsByFolder['alphabet']!.first.cells.length, 26);
    expect(v.viewsByFolder['numbers']!.first.cells.length, 21);
    expect(v.viewsByFolder['fruits']!.first.cells.length, 28);
    final saved = PackLoader().save(v);
    final roundTrip = PackLoader().loadString(jsonEncode(saved));
    expect(roundTrip.folders['fruits']!.symbol.key, 'scene-fruit');
    expect(v.viewsByFolder['home']!.first.cells.first.button.symbol.key,
        isNot('P'));
  });
  test(
      'upgrade retains edits, placement, favorites, custom buttons and repairs images',
      () async {
    final fresh =
        jsonDecode(await File('assets/sample_pack.json').readAsString())
            as Map<String, dynamic>;
    final old = jsonDecode(jsonEncode(fresh)) as Map<String, dynamic>;
    old['buttons'][0]['symbolPack'] = 'mulberry';
    old['buttons'][0]['symbolKey'] = 'P';
    old['buttons'][1]['label'] = 'my friend';
    old['buttons'][1]['favorite'] = true;
    old['buttons'].add(
        {'id': 'custom123', 'label': 'custom', 'symbol': 'A', 'kind': 'item'});
    old['views']['home'][0]['cells'].insert(0, {'btn': 'custom123'});
    final merged = PackUpgrade.merge(old, fresh);
    final v = PackLoader().loadString(jsonEncode(merged));
    final home = v.viewsByFolder['home']!.first;
    expect(home.cells.first.button.id, 'custom123');
    expect(home.cells.firstWhere((c) => c.button.id == 'b2').button.label,
        'my friend');
    expect(home.cells.firstWhere((c) => c.button.id == 'b2').button.favorite,
        isTrue);
    expect(home.cells.firstWhere((c) => c.button.id == 'b1').button.symbol.key,
        isNot('P'));
    final roundTrip = PackLoader().loadString(jsonEncode(PackLoader().save(v)));
    expect(
        roundTrip.viewsByFolder['home']!.first.cells
            .firstWhere((c) => c.button.id == 'b2')
            .button
            .favorite,
        isTrue);
  });
  testWidgets('symbol tap and whole message panel speak on a small phone',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final vocabulary = PackLoader()
        .loadString(File('assets/sample_pack.json').readAsStringSync());
    final storage = await tester.runAsync(AppStorage.instance);
    final settings = SettingsController(storage!)..settings = AppSettings();
    final session = GridSession(vocabulary: vocabulary, speech: SpeechEngine());
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
            theme: ThemeData(splashFactory: NoSplash.splashFactory),
            home: GridScreen(session: session, maxColumns: 4))));
    session.tap(vocabulary.viewsByFolder['home']!.first.cells.first.button);
    await tester.pumpAndSettle();
    expect(session.message, 'I');
    expect(calls.where((c) => c.method == 'speak').length, 1);
    await tester.tap(find.bySemanticsLabel('Speak message'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'speak').length, 2);
    expect(find.text('Del'), findsNothing);
    session.setMessageLive('I want water');
    await tester.pump();
    expect(find.text('I want water'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.clear_all));
    await tester.pump();
    expect(session.message, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final size in [
    const Size(320, 568),
    const Size(568, 320),
    const Size(768, 1024)
  ]) {
    testWidgets('single keyboard works without overflow at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var text = '';
      var spoken = '';
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(splashFactory: NoSplash.splashFactory),
          home: KeyboardView(
              predictor: Predictor(),
              speech: SpeechEngine(),
              onTextChanged: (value) => text = value,
              onClose: () {},
              onSpeak: () => spoken = text)));
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).keyboardType,
          TextInputType.none);
      await tester.tap(find.bySemanticsLabel('help'));
      await tester.pump();
      expect(text, 'help ');
      expect(find.text('help '), findsOneWidget);
      await tester.tap(find.text('help ').first);
      await tester.pump();
      expect(spoken, 'help ');
      await tester.scrollUntilVisible(find.text('0'), 150,
          scrollable: find.byType(Scrollable).last);
      await Scrollable.ensureVisible(tester.element(find.text('0')),
          alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(find.text('0'));
      await tester.pump();
      expect(text, 'help 0');
      expect(tester.takeException(), isNull);
    });
  }

  test('v7 repairs known pictures on installed packs and keeps custom pictures',
      () {
    final fresh = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
        as Map<String, dynamic>;
    final history = jsonDecode(
            File('assets/factory_symbol_history.json').readAsStringSync())
        as Map<String, dynamic>;
    final old = jsonDecode(jsonEncode(fresh)) as Map<String, dynamic>;
    old['packVersion'] = 6;
    for (final item in old['buttons'] as List) {
      final ref = (history['buttons'][item['id']] as List).first as Map;
      item.addAll(ref);
    }
    for (final item in old['folders'] as List) {
      item.addAll((history['folders'][item['id']] as List).first as Map);
      if (item['id'] == 'play') {
        item.remove('symbolPack');
        item.remove('symbolKey');
      }
    }
    final oldButtons = {for (final b in old['buttons'] as List) b['id']: b};
    oldButtons['b1']['favorite'] = true;
    oldButtons['b2']['userEdited'] = true;
    oldButtons['b2']['symbolKey'] = '1f431';
    oldButtons['b3']['imagePath'] = 'custom-picture.png';
    oldButtons['b4']['label'] = 'my pushpin';
    oldButtons['b6']['symbolKey'] =
        '1f431'; // Legacy custom image, no edit flag.
    oldButtons['b5']['userEdited'] = true;
    oldButtons['b5']['voice'] = {'rate': 0.8};
    final firstCell = old['views']['home'][0]['cells'].removeAt(3);
    old['views']['home'][0]['cells'].insert(0, firstCell);
    final merged = PackUpgrade.merge(old, fresh, factorySymbolHistory: history);
    final buttons = {for (final b in merged['buttons'] as List) b['id']: b};
    expect(merged['packVersion'], 7);
    expect(buttons['b1']['symbolKey'], 'scene-i');
    expect(buttons['b1']['favorite'], true);
    expect(buttons['b2']['symbolKey'], '1f431');
    expect(buttons['b3']['imagePath'], 'custom-picture.png');
    expect(buttons['b4']['label'], 'my pushpin');
    expect(buttons['b4']['symbolKey'], '1f4cc');
    expect(buttons['b6']['symbolKey'], '1f431');
    expect(buttons['b5']['symbolKey'], 'scene-want');
    expect(buttons['b5']['voice'], {'rate': 0.8});
    expect(buttons['x64']['symbolKey'], 'fluent-american-football');
    expect(merged['views']['home'][0]['cells'].first, firstCell);
    final folders = {for (final f in merged['folders'] as List) f['id']: f};
    expect(folders['play']['symbolKey'], 'scene-play');
    final again =
        PackUpgrade.merge(merged, fresh, factorySymbolHistory: history);
    expect(jsonEncode(again), jsonEncode(merged));
  });

  test('factory vocabulary has no duplicate buttons and a short Home page',
      () async {
    final pack =
        jsonDecode(await File('assets/sample_pack.json').readAsString())
            as Map<String, dynamic>;
    final buttons = {for (final b in pack['buttons']) b['id']: b};
    final views = pack['views'] as Map<String, dynamic>;
    for (final entry in views.entries) {
      final cells = (entry.value as List).first['cells'] as List;
      final labels = <String>{};
      final pictures = <String>{};
      for (final c in cells) {
        final b = buttons[c['btn']];
        expect(labels.add((b['label'] as String).toLowerCase()), isTrue,
            reason: '${entry.key}: duplicate "${b['label']}"');
        expect(pictures.add('${b['symbolPack']}/${b['symbolKey']}'), isTrue,
            reason: '${entry.key}: "${b['label']}" repeats a picture');
      }
    }
    final home = (views['home'] as List).first['cells'] as List;
    expect(home.length, lessThanOrEqualTo(40));
    expect(home.map((c) => buttons[c['btn']]['label']),
        containsAll(['yes', 'no', 'wait']));
    // Every category is reachable from Home through category buttons.
    final reachable = <String>{'home'};
    final queue = ['home'];
    while (queue.isNotEmpty) {
      for (final c in (views[queue.removeLast()] as List).first['cells']) {
        for (final a in buttons[c['btn']]['actions'] as List) {
          if (a['kind'] == 'gotoFolder' && reachable.add(a['data'])) {
            queue.add(a['data']);
          }
        }
      }
    }
    expect(reachable, containsAll(views.keys));
    expect(buttons['b21']['symbolKey'], isNot(buttons['b22']['symbolKey']));
    expect(buttons['x161']['class'], 'verb');
    expect(buttons['x37']['class'], 'adjective');
  });

  test('symbol index lists each picture name once', () async {
    final index =
        jsonDecode(await File('assets/symbol_index.json').readAsString())
            as List;
    final keys = index.map((e) => '${e['p']}/${e['k']}/${e['n']}').toList();
    expect(keys.toSet().length, keys.length);
  });

  test('v7 upgrade removes duplicate factory buttons from installed packs',
      () {
    final fresh = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
        as Map<String, dynamic>;
    final history = jsonDecode(
            File('assets/factory_symbol_history.json').readAsStringSync())
        as Map<String, dynamic>;
    final old = jsonDecode(jsonEncode(fresh)) as Map<String, dynamic>;
    old['packVersion'] = 6;
    final oldButtons = old['buttons'] as List;
    final homeCells = old['views']['home'][0]['cells'] as List;
    // A v6 Home: no yes/no/wait, duplicate category links, Speak on the grid.
    homeCells.removeWhere((c) => (c['btn'] as String).startsWith('core_'));
    oldButtons.removeWhere((b) => (b['id'] as String).startsWith('core_'));
    for (final id in ['fx_people', 'speakBtn', 'fx_vehicles']) {
      oldButtons.add({
        'id': id,
        'kind': 'folder',
        'label': id,
        'actions': [
          {'kind': 'gotoFolder', 'data': 'people'}
        ]
      });
      homeCells.add({'btn': id});
    }
    oldButtons.firstWhere((b) => b['id'] == 'fx_vehicles')['favorite'] = true;
    oldButtons.add({'id': 'x15', 'kind': 'item', 'label': 'fire truck 2'});
    (old['views']['vehicles'][0]['cells'] as List).add({'btn': 'x15'});
    oldButtons.firstWhere((b) => b['id'] == 'x161')['class'] = 'noun';
    final edited = oldButtons.firstWhere((b) => b['id'] == 'x162');
    edited['class'] = 'noun';
    edited['userEdited'] = true;

    final merged = PackUpgrade.merge(old, fresh, factorySymbolHistory: history);
    final home = [
      for (final c in merged['views']['home'][0]['cells']) c['btn'] as String
    ];
    expect(home, isNot(contains('fx_people')));
    expect(home, isNot(contains('speakBtn')));
    expect(home, contains('fx_vehicles'), reason: 'starred by the user');
    expect(home.sublist(24, 27), ['core_yes', 'core_no', 'core_wait']);
    expect([for (final c in merged['views']['vehicles'][0]['cells']) c['btn']],
        isNot(contains('x15')));
    expect([for (final c in merged['views']['places'][0]['cells']) c['btn']],
        contains('sub_vehicles'));
    final buttons = {for (final b in merged['buttons'] as List) b['id']: b};
    expect(buttons['x161']['class'], 'verb');
    expect(buttons['x162']['class'], 'noun', reason: 'user edit kept');
    final again =
        PackUpgrade.merge(merged, fresh, factorySymbolHistory: history);
    expect(jsonEncode(again), jsonEncode(merged));
  });

  test('chosen device voice is applied once and a missing voice still speaks',
      () async {
    final engine = SpeechEngine()
      ..configure(
          AppSettings(usePiper: false, voiceName: 'Zira', voiceLocale: 'en-US'));
    await engine.speak('hi');
    await engine.speak('bye');
    final setVoice = calls.where((c) => c.method == 'setVoice').toList();
    expect(setVoice, hasLength(1));
    expect(setVoice.single.arguments, {'name': 'Zira', 'locale': 'en-US'});
    expect(calls.indexOf(setVoice.single),
        lessThan(calls.indexWhere((c) => c.method == 'speak')));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setVoice') throw PlatformException(code: 'gone');
      if (call.method == 'getVoices') {
        return [
          {'name': 'Hortense', 'locale': 'fr-FR'},
          {'name': 'Zira', 'locale': 'en-US'},
        ];
      }
      return 1;
    });
    engine.voice = const DeviceVoice('Old', 'en-GB');
    await engine.speak('help');
    expect(engine.error.value, isNull);
    expect(calls.where((c) => c.method == 'speak'), hasLength(3));
    final voices = await engine.deviceVoices();
    expect(voices.map((v) => v.name), ['Zira', 'Hortense']);
    final saved = AppSettings.fromJson(
        AppSettings(voiceName: 'Zira', voiceLocale: 'en-US').toJson());
    expect([saved.voiceName, saved.voiceLocale], ['Zira', 'en-US']);
  });

  test('modern symbol search prefers exact meanings over partial names',
      () async {
    final library = SymbolLibrary();
    await library.load();
    for (final expected in {
      'water': 'scene-water',
      'football': 'fluent-american-football',
      'date': 'scene-date',
      'no': 'fluent-cross-mark',
    }.entries) {
      final result = library.search(expected.key, limit: 1).single;
      expect(result.pack, 'modern3d');
      expect(result.key, expected.value);
    }
    final pack =
        jsonDecode(File('assets/sample_pack.json').readAsStringSync()) as Map;
    final buttons = {for (final b in pack['buttons']) b['id']: b};
    expect(buttons['fruits_5']['symbolKey'], 'fluent-tangerine');
    expect(buttons['x43']['symbolKey'], 'color-orange');
    expect(buttons['b77']['symbolKey'], 'fluent-poultry-leg');
  });

  testWidgets(
      'one message editor supports selected deletion and emoji backspace',
      (tester) async {
    var text = '';
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: KeyboardView(
            predictor: Predictor(),
            speech: SpeechEngine(),
            initialText: 'water 👨‍👩‍👧‍👦',
            onTextChanged: (value) => text = value,
            onClose: () {},
            onSpeak: () {})));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(find.text('water 👨‍👩‍👧‍👦'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delete'), 200,
        scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(text, 'water ');
    field.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 5);
    await tester.pump();
    await tester.tap(find.text('Delete'));
    await tester.pump();
    expect(text, ' ');
    expect(tester.takeException(), isNull);
  });
}
