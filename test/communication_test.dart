import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/arasaac.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/features/grid/keyboard_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
    .setMockMessageHandler('flutter/assets', (message) async {
      final key = utf8.decode(message!.buffer.asUint8List());
      if (key == 'AssetManifest.bin') return const StandardMessageCodec().encodeMessage(<String, Object>{});
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
      expect(calls.where((c) => c.method == 'setIosAudioCategory').length,
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
      final ext =
          ['twemoji', 'noto', 'learning'].contains(item['symbolPack']) ? 'png' : 'svg';
      expect(
          File('assets/symbols/${item['symbolPack']}/${item['symbolKey']}.$ext')
              .existsSync(),
          isTrue,
          reason: '${item['id']}: ${item['label']}');
    }
    final v = await PackLoader().loadAsset('assets/sample_pack.json');
    expect(v.viewsByFolder['alphabet']!.first.cells.length, 26);
    expect(v.viewsByFolder['numbers']!.first.cells.length, 21);
    expect(v.viewsByFolder['fruits']!.first.cells.length, 29);
    final saved = PackLoader().save(v);
    final roundTrip = PackLoader().loadString(jsonEncode(saved));
    expect(roundTrip.folders['fruits']!.symbol.key, '1f34e');
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
          home: KeyboardView(
              predictor: Predictor(),
              speech: SpeechEngine(),
              onTextChanged: (value) => text = value,
              onClose: () {},
              onSpeak: () => spoken = text)));
      expect(find.byType(TextField), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).keyboardType,
          TextInputType.none);
      await tester.tap(find.text('help'));
      await tester.pump();
      expect(text, 'help ');
      await tester.tap(find.text('help ').first);
      await tester.pump();
      expect(spoken, 'help ');
      await tester.scrollUntilVisible(find.text('0'), 150,
          scrollable: find.byType(Scrollable).last);
      await tester.tap(find.text('0'));
      await tester.pump();
      expect(text, 'help 0');
      expect(tester.takeException(), isNull);
    });
  }
}
