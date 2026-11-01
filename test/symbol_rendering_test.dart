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

  test('every bundled Mulberry SVG normalizes without losing its paths', () {
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
