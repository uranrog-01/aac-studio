// Real native inference check; run from studio: dart run tools/piper_smoke.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:aac_studio/engine/piper_worker.dart';

Future<void> main() async {
  final output = Directory('dist/piper-smoke')..createSync(recursive: true);
  final temporary = await Directory.systemTemp.createTemp('aac-piper-smoke-');
  final timer = Stopwatch()..start();
  final synth = await PiperSynthesizer.start(
    archivePath:
        p.absolute('assets/voices/piper-en-us-ljspeech-medium.tar.bz2'),
    installDirectory: p.absolute('build/piper-smoke-model'),
    cacheDirectory: temporary.path,
  );
  stdout.writeln('Initialization: ${timer.elapsedMilliseconds} ms');
  try {
    for (final entry in {
      'help': 'Help.',
      'message': 'Hello. I need some water, please.',
      'numbers': 'I have 2 apples. It costs 5 dollars.',
    }.entries) {
      timer.reset();
      final path = await synth.synthesize(entry.value, 1.0);
      final bytes = await File(path).readAsBytes();
      final header = ByteData.sublistView(bytes);
      if (String.fromCharCodes(bytes.take(4)) != 'RIFF' ||
          String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE' ||
          header.getUint32(24, Endian.little) != 22050 ||
          bytes.length <= 44) {
        throw StateError('Invalid WAV for ${entry.key}');
      }
      final duration = (bytes.length - 44) / (22050 * 2);
      final nonzero = bytes.skip(44).any((b) => b != 0);
      if (!nonzero) throw StateError('Silent PCM for ${entry.key}');
      await File(path).copy(p.join(output.path, '${entry.key}.wav'));
      stdout.writeln('${entry.key}: ${timer.elapsedMilliseconds} ms, '
          '${duration.toStringAsFixed(2)} s audio, ${bytes.length} bytes');
      timer.reset();
      final cached = await synth.synthesize(entry.value, 1.0);
      if (cached != path) throw StateError('Speech cache missed');
      stdout.writeln('  Cache hit: ${timer.elapsedMilliseconds} ms');
    }
  } finally {
    synth.dispose();
  }
}
