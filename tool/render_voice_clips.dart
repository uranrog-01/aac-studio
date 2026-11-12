// Records a list of phrases with an offline voice pack, one WAV per phrase,
// so a language's board words can ship as ready-made recordings
// (tools/build_voice_clips.py turns them into the app's clips).
//   dart run tool/render_voice_clips.dart <code> <install-dir> <cache-dir> <texts.json> <out-dir>
// Recorded at the pack's own pace (PiperPack.pace), as phones speak it.
// texts.json is a JSON list of strings; phrase i is saved as <out-dir>/<i>.wav.
import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/engine/piper_worker.dart';

Future<void> main(List<String> args) async {
  final pack = piperPacks[args[0]]!;
  final texts = (jsonDecode(File(args[3]).readAsStringSync()) as List).cast<String>();
  final out = Directory(args[4])..createSync(recursive: true);
  final synth = await PiperSynthesizer.start(
      archivePath: '${args[1]}${Platform.pathSeparator}voice.tar.bz2',
      installDirectory: args[1],
      cacheDirectory: args[2],
      pack: pack);
  var failed = 0;
  for (var i = 0; i < texts.length; i++) {
    final target = File('${out.path}${Platform.pathSeparator}$i.wav');
    if (target.existsSync()) continue;
    try {
      // The engine keeps only its latest files, so copy each one at once.
      File(await synth.synthesize(texts[i], pack.pace)).copySync(target.path);
    } catch (error) {
      failed++;
      stderr.writeln('$i "${texts[i]}": $error');
    }
    if (i % 250 == 0) stdout.writeln('$i / ${texts.length}');
  }
  stdout.writeln('done: ${texts.length - failed} recorded, $failed failed');
  synth.dispose();
  await Future<void>.delayed(const Duration(seconds: 2));
  exit(failed == 0 ? 0 : 1);
}
