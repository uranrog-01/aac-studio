// Speaks a few phrases with an offline Piper voice pack into one WAV file,
// using the same engine as the app (sherpa-onnx + piper_phonemize).
//
//   dart run tool/voice_sample.dart <unpacked-pack-dir> <model.onnx> \
//       <espeak-voice> <out.wav> "phrase one" "phrase two" ...
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:piper_phonemize/piper_phonemize.dart' as phonemizer;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

Future<void> main(List<String> args) async {
  if (args.length < 5) {
    stderr.writeln('usage: <pack-dir> <model.onnx> <voice> <out.wav> <phrases...>');
    exit(2);
  }
  final [dir, modelFile, voice, out, ...phrases] = args;
  if (Platform.isWindows) {
    DynamicLibrary.open(
        p.join(await sherpa.resolveSherpaOnnxPath(), 'onnxruntime.dll'));
  }
  await sherpa.initBindingsAsync();
  await phonemizer.initBindingsAsync();
  if (phonemizer.PiperPhonemize.initialize(p.join(dir, 'espeak-ng-data')) < 0) {
    throw StateError('pronunciation data unavailable');
  }
  final tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
    model: sherpa.OfflineTtsModelConfig(
      vits: sherpa.OfflineTtsVitsModelConfig(
        model: p.join(dir, modelFile),
        tokens: p.join(dir, 'tokens.txt'),
      ),
      numThreads: 2,
      provider: 'cpu',
    ),
    maxNumSentences: 1,
  ));
  final samples = <double>[];
  var rate = 22050;
  for (final text in phrases) {
    final sentences = phonemizer.PiperPhonemize.phonemize(text, voice: voice)
        .where((s) => s.isNotEmpty)
        .toList();
    final audio = tts.generateWithConfig(
        text: '',
        config: sherpa.OfflineTtsGenerationConfig(
            sid: 0, speed: 0.95, phonemeCodepoints: sentences));
    rate = audio.sampleRate;
    samples
      ..addAll(audio.samples)
      ..addAll(List.filled((rate * 0.5).round(), 0.0));
    stdout.writeln('$text  (${audio.samples.length} samples)');
  }
  sherpa.writeWave(
      filename: out, samples: Float32List.fromList(samples), sampleRate: rate);
  tts.free();
  stdout.writeln('wrote $out');
}
