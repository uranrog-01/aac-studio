import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:aac_studio/engine/symbol_library.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SVG classes preserve grouped rules, cascade and inline overrides', () {
    final result = SymbolLibrary.inlineSvgStyles('''
<svg xmlns="http://www.w3.org/2000/svg"><style>
.a,.b{fill:#ffeec8;stroke:#231f20}.b{fill:#ff0000}
</style><path class="a"/><path class="b" style="fill:#00ff00"/>
<path class="b" fill="#000000"/></svg>''');
    final document = XmlDocument.parse(result);
    expect(document.findAllElements('style'), isEmpty);
    final paths = document.findAllElements('path').toList();
    expect(paths[0].getAttribute('fill'), '#ffeec8');
    expect(paths[0].getAttribute('stroke'), '#231f20');
    expect(paths[1].getAttribute('fill'), '#00ff00');
    expect(paths[2].getAttribute('fill'), '#ff0000');
  });

  test('all bundled WebP symbols decode at no more than 340 pixels',
      () async {
    final manifest =
        jsonDecode(File('docs/flat-symbol-manifest.json').readAsStringSync())
            as Map;
    final files = (manifest['files'] as Map).keys.cast<String>();
    // Modern flat, flags, numbers and communication; Mulberry ships as SVG.
    expect(files.length, greaterThan(3600));
    expect(files.where((f) => f.startsWith('modernflat/')).length,
        greaterThan(3300));
    for (final relative in files) {
      final f = File('assets/flat_symbols/$relative');
      final bytes = f.readAsBytesSync();
      expect(ascii.decode(bytes.sublist(0, 4)), 'RIFF', reason: f.path);
      expect(ascii.decode(bytes.sublist(8, 12)), 'WEBP', reason: f.path);
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, inInclusiveRange(1, 340), reason: f.path);
      expect(frame.image.height, inInclusiveRange(1, 340), reason: f.path);
      frame.image.dispose();
      codec.dispose();
    }
  }, timeout: const Timeout(Duration(minutes: 5)));

  String assetOf(SymbolRef ref) =>
      ((SymbolLibrary.resolve(ref) as Image).image as AssetImage).assetName;

  test('saved picture references resolve to bundled modern flat pictures',
      () async {
    await SymbolLibrary().load();
    for (final entry in {
      'modern3d': 'modernflat',
      'twemoji_svg': 'twemoji',
    }.entries) {
      expect(assetOf(SymbolRef('test', pack: entry.key, key: 'example')),
          'assets/flat_symbols/${entry.value}/example.webp');
    }
    // Retired emoji sets show the same concept in modern flat.
    expect(
        assetOf(const SymbolRef('0',
            pack: 'noto', key: 'emoji_u0030_20e3')),
        'assets/flat_symbols/modernflat/fluent-keycap-0.webp');
    final aliases =
        jsonDecode(File('assets/symbol_aliases.json').readAsStringSync())
            as Map<String, dynamic>;
    for (final target in aliases.values.toSet()) {
      expect(File('assets/flat_symbols/modernflat/$target.webp').existsSync(),
          isTrue,
          reason: target as String);
    }
    expect(SymbolLibrary.resolve(
            const SymbolRef('help', pack: 'mulberry', key: 'help_,_to')),
        isA<FutureBuilder<String>>());
  });

  test('chosen skin tone is drawn and variants are one search result',
      () async {
    final library = SymbolLibrary();
    await library.load();
    const hand = SymbolRef('wave', pack: 'modernflat', key: 'fluent-waving-hand');
    expect(assetOf(hand), 'assets/flat_symbols/modernflat/fluent-waving-hand.webp');
    SymbolLibrary.skinTone = 'dark';
    try {
      expect(assetOf(hand),
          'assets/flat_symbols/modernflat/fluent-waving-hand-dark.webp');
      // Pictures without people keep their only version.
      expect(
          assetOf(const SymbolRef('car', pack: 'modernflat', key: 'fluent-automobile')),
          'assets/flat_symbols/modernflat/fluent-automobile.webp');
    } finally {
      SymbolLibrary.skinTone = '';
    }
    final results = library.search('waving hand', limit: 20);
    expect(results.where((e) => e.key.startsWith('fluent-waving-hand')).length, 1);
  });

  test('every source Mulberry SVG normalizes without losing its paths', () {
    var styled = 0;
    for (final file
        in Directory('assets/symbols/mulberry').listSync().whereType<File>()) {
      if (!file.path.endsWith('.svg')) continue;
      final source = file.readAsStringSync();
      if (!source.contains('<style')) continue;
      styled++;
      final before = XmlDocument.parse(source);
      final after = XmlDocument.parse(SymbolLibrary.inlineSvgStyles(source));
      expect(after.findAllElements('style'), isEmpty, reason: file.path);
      expect(after.findAllElements('path').length,
          before.findAllElements('path').length,
          reason: file.path);
    }
    expect(styled, 327);
  });

  testWidgets(
      'actual help picture renders skin colors instead of a black silhouette',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer.asUint8List());
      if (path == 'AssetManifest.bin') {
        return const StandardMessageCodec().encodeMessage(<String, Object>{});
      }
      final file = File(path);
      if (!file.existsSync()) return null;
      return ByteData.sublistView(file.readAsBytesSync());
    });
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                    color: Colors.white,
                    child: SymbolLibrary.resolve(
                        const SymbolRef('help',
                            pack: 'mulberry', key: 'help_,_to'),
                        size: 128))))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final pixels = data!.buffer.asUint8List();
      var skinPixels = 0;
      for (var i = 0; i < pixels.length; i += 4) {
        if (pixels[i] > 240 &&
            pixels[i + 1] > 210 &&
            pixels[i + 1] < 250 &&
            pixels[i + 2] > 160 &&
            pixels[i + 2] < 230) {
          skinPixels++;
        }
      }
      image.dispose();
      expect(skinPixels, greaterThan(300));
    });
    expect(tester.takeException(), isNull);
  });
}
