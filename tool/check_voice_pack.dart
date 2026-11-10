// Installs a downloaded voice pack archive and speaks one phrase with the
// app's own worker (same code as on phones), to check a pack end to end.
//   dart run tool/check_voice_pack.dart <code> <install-dir> <cache-dir> "text"
import 'dart:io';

import 'package:aac_studio/engine/piper_worker.dart';

Future<void> main(List<String> args) async {
  final pack = piperPacks[args[0]]!;
  final archive = '${args[1]}${Platform.pathSeparator}voice.tar.bz2';
  final synth = await PiperSynthesizer.start(
      archivePath: archive,
      installDirectory: args[1],
      cacheDirectory: args[2],
      pack: pack);
  final wav = await synth.synthesize(args[3], 1.0);
  stdout.writeln('installed: ${isPiperPackInstalled(args[1], pack)}');
  stdout.writeln('spoke "${args[3]}" -> ${File(wav).lengthSync()} bytes');
  synth.dispose();
  await Future<void>.delayed(const Duration(seconds: 3));
  exit(0);
}
