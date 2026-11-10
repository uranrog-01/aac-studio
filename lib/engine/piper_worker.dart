import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:piper_phonemize/piper_phonemize.dart' as phonemizer;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// One offline Piper voice (sherpa-onnx VITS model + espeak-ng data).
class PiperPack {
  final String id; // language code
  final String name; // shown in Settings
  final String directory; // root folder inside the archive
  final String modelFile;
  final int modelBytes;
  final String espeakVoice;
  final String dictionary; // espeak-ng-data/<dictionary> must exist
  final String? asset; // bundled with the app
  final String? url; // or downloaded once, then offline
  final int downloadBytes;
  final String sha256; // of the downloaded archive
  const PiperPack({
    required this.id,
    required this.name,
    required this.directory,
    required this.modelFile,
    required this.modelBytes,
    required this.espeakVoice,
    required this.dictionary,
    this.asset,
    this.url,
    this.downloadBytes = 0,
    this.sha256 = '',
  });

  /// Folder name under the app's voices folder.
  String get installName => 'piper-$id-v1';

  List<String> toArgs() => [id, directory, modelFile, '$modelBytes',
      espeakVoice, dictionary];
  static PiperPack fromArgs(List<String> a) => PiperPack(
      id: a[0],
      name: a[0],
      directory: a[1],
      modelFile: a[2],
      modelBytes: int.parse(a[3]),
      espeakVoice: a[4],
      dictionary: a[5]);
}

/// US English, built into the app.
const englishPiperPack = PiperPack(
  id: 'en',
  name: 'US English · LJ Speech',
  directory: 'vits-piper-en_US-ljspeech-medium',
  modelFile: 'en_US-ljspeech-medium.onnx',
  modelBytes: 63531507,
  espeakVoice: 'en-us',
  dictionary: 'en_dict',
  asset: 'assets/voices/piper-en-us-ljspeech-medium.tar.bz2',
);

/// Albanian (Piper "edon", trained on the CC0 folsh.ai recordings).
/// Phones and tablets have no Albanian voice, so it is downloaded once
/// when Albanian is chosen and then works offline.
const albanianPiperPack = PiperPack(
  id: 'sq',
  name: 'Shqip · Edon',
  directory: 'vits-piper-sq_AL-edon-medium',
  modelFile: 'sq_AL-edon-medium.onnx',
  modelBytes: 63511167,
  espeakVoice: 'sq',
  dictionary: 'sq_dict',
  url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'vits-piper-sq_AL-edon-medium.tar.bz2',
  downloadBytes: 67191820,
  sha256: '2d7a3b3647a499ad40a28662edd5ff50eb8594ad7ace94a5d3525e280212bf99',
);

const piperPacks = {'en': englishPiperPack, 'sq': albanianPiperPack};

bool isPiperPackInstalled(String installDirectory,
    [PiperPack pack = englishPiperPack]) {
  final directory = p.join(installDirectory, pack.directory);
  final model = File(p.join(directory, pack.modelFile));
  return File(p.join(directory, '.ready-v1')).existsSync() &&
      model.existsSync() &&
      model.lengthSync() == pack.modelBytes &&
      File(p.join(directory, 'tokens.txt')).existsSync() &&
      File(p.join(directory, 'espeak-ng-data', pack.dictionary)).existsSync();
}

/// Owns the native model on a persistent worker, never on Flutter's UI isolate.
class PiperSynthesizer {
  final Isolate _isolate;
  final SendPort _commands;
  bool _closed = false;

  PiperSynthesizer._(this._isolate, this._commands);

  static Future<PiperSynthesizer> start({
    required String archivePath,
    required String installDirectory,
    required String cacheDirectory,
    PiperPack pack = englishPiperPack,
  }) async {
    final ready = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(_piperWorker,
          [ready.sendPort, archivePath, installDirectory, cacheDirectory,
            pack.toArgs()]);
      final result = await ready.first.timeout(const Duration(seconds: 90));
      if (result is! SendPort) throw StateError('$result');
      return PiperSynthesizer._(worker, result);
    } catch (_) {
      worker?.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<String> synthesize(String text, double speed) async {
    if (_closed) throw StateError('Piper is closed');
    final reply = ReceivePort();
    try {
      _commands.send([reply.sendPort, text, speed]);
      final result = await reply.first.timeout(const Duration(seconds: 30));
      if (result is Map && result['path'] is String) {
        return result['path'] as String;
      }
      throw StateError('Piper synthesis failed: $result');
    } on TimeoutException {
      dispose();
      rethrow;
    } finally {
      reply.close();
    }
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    // The worker frees native handles and removes its private WAV cache.
    _commands.send(null);
    // An unresponsive native call must not retain a worker indefinitely.
    Future<void>.delayed(const Duration(seconds: 2),
        () => _isolate.kill(priority: Isolate.immediate));
  }
}

/// Extract only regular files inside the expected package. Stream to disk to
/// avoid retaining an uncompressed model and dictionaries in Dart memory.
String installPiperPack(String archivePath, String installDirectory,
    [PiperPack pack = englishPiperPack]) {
  final modelDirectory = p.join(installDirectory, pack.directory);
  final marker = File(p.join(modelDirectory, '.ready-v1'));
  final model = File(p.join(modelDirectory, pack.modelFile));
  final tokens = File(p.join(modelDirectory, 'tokens.txt'));
  final dictionary =
      File(p.join(modelDirectory, 'espeak-ng-data', pack.dictionary));
  if (isPiperPackInstalled(installDirectory, pack)) {
    return modelDirectory;
  }
  Directory(installDirectory).createSync(recursive: true);
  final input = InputFileStream(archivePath);
  final tarPath = p.join(installDirectory, 'voice-install.tar');
  final output = OutputFileStream(tarPath);
  try {
    BZip2Decoder().decodeStream(input, output,
        verify: true, maxOutputSize: 256 * 1024 * 1024);
  } finally {
    input.closeSync();
    output.closeSync();
  }
  final tarInput = InputFileStream(tarPath);
  try {
    TarDecoder().decodeStream(tarInput, verify: true, keepEntries: false,
        callback: (entry) {
      final name = p.posix.normalize(entry.name.replaceAll('\\', '/'));
      if (name != pack.directory && !name.startsWith('${pack.directory}/')) {
        throw const FormatException('Unexpected Piper archive path');
      }
      if (entry.isSymbolicLink || entry.isHardLink) {
        throw const FormatException('Links are not allowed in voice packs');
      }
      final target = p.joinAll([installDirectory, ...p.posix.split(name)]);
      if (!p.isWithin(p.absolute(installDirectory), p.absolute(target))) {
        throw const FormatException('Voice archive escapes install directory');
      }
      if (entry.isFile) {
        File(target).parent.createSync(recursive: true);
        final fileOutput = OutputFileStream(target);
        try {
          entry.writeContent(fileOutput);
        } finally {
          fileOutput.closeSync();
        }
      } else {
        Directory(target).createSync(recursive: true);
      }
    });
  } finally {
    tarInput.closeSync();
    File(tarPath).deleteSync();
  }
  if (!model.existsSync() ||
      model.lengthSync() != pack.modelBytes ||
      !tokens.existsSync() ||
      !dictionary.existsSync()) {
    throw const FormatException('Incomplete Piper voice pack');
  }
  marker.writeAsStringSync('${pack.id}-v1');
  return modelDirectory;
}

void _piperWorker(List<Object> arguments) async {
  final ready = arguments[0] as SendPort;
  final cacheDirectory = Directory(arguments[3] as String);
  final pack = arguments.length > 4
      ? PiperPack.fromArgs((arguments[4] as List).cast<String>())
      : englishPiperPack;
  sherpa.OfflineTts? tts;
  final cache = <String, String>{};
  var cacheBytes = 0;
  var sequence = 0;
  try {
    final modelDirectory =
        installPiperPack(arguments[1] as String, arguments[2] as String, pack);
    if (Platform.isWindows) {
      // Windows ships an older onnxruntime.dll in System32. Preload our
      // matching runtime before loading sherpa's dependent DLL (also for CLI).
      var nativeDirectory = File(Platform.resolvedExecutable).parent.path;
      if (!File(p.join(nativeDirectory, 'onnxruntime.dll')).existsSync()) {
        nativeDirectory = await sherpa.resolveSherpaOnnxPath();
      }
      DynamicLibrary.open(p.join(nativeDirectory, 'onnxruntime.dll'));
    }
    await sherpa.initBindingsAsync();
    await phonemizer.initBindingsAsync();
    final result = phonemizer.PiperPhonemize.initialize(
        p.join(modelDirectory, 'espeak-ng-data'));
    if (result < 0) throw StateError('Piper pronunciation data unavailable');
    tts = sherpa.OfflineTts(sherpa.OfflineTtsConfig(
      model: sherpa.OfflineTtsModelConfig(
        vits: sherpa.OfflineTtsVitsModelConfig(
          model: p.join(modelDirectory, pack.modelFile),
          tokens: p.join(modelDirectory, 'tokens.txt'),
        ),
        numThreads: 2,
        provider: 'cpu',
      ),
      maxNumSentences: 1,
    ));
    cacheDirectory.createSync(recursive: true);
    final commands = ReceivePort();
    ready.send(commands.sendPort);
    await for (final message in commands) {
      if (message == null) {
        commands.close();
        break;
      }
      final request = message as List;
      final reply = request[0] as SendPort;
      try {
        final text = request[1] as String;
        final speed = (request[2] as double).clamp(0.5, 2.0);
        final key = '$speed\n$text';
        final cached = cache.remove(key);
        if (cached != null && File(cached).existsSync()) {
          cache[key] = cached;
          reply.send({'path': cached});
          continue;
        }
        final sentences =
            phonemizer.PiperPhonemize.phonemize(text, voice: pack.espeakVoice)
                .where((s) => s.isNotEmpty)
                .toList();
        if (sentences.isEmpty) throw StateError('No pronounceable text');
        final audio = tts.generateWithConfig(
          text: '',
          config: sherpa.OfflineTtsGenerationConfig(
            sid: 0,
            speed: speed,
            phonemeCodepoints: sentences,
          ),
        );
        if (audio.samples.isEmpty) throw StateError('Piper produced no audio');
        final path = p.join(cacheDirectory.path, '${sequence++}.wav');
        final written = sherpa.writeWave(
            filename: path,
            samples: audio.samples,
            sampleRate: audio.sampleRate);
        if (!written) throw StateError('Could not save speech audio');
        cache[key] = path;
        cacheBytes += File(path).lengthSync();
        while (cache.length > 1 &&
            (cache.length > 32 || cacheBytes > 16 * 1024 * 1024)) {
          final old = File(cache.remove(cache.keys.first)!);
          cacheBytes -= old.lengthSync();
          try {
            old.deleteSync();
          } catch (_) {
            /* Windows may still be playing this file. Clean up on dispose. */
          }
        }
        reply.send({'path': path});
      } catch (error) {
        reply.send({'error': error.toString()});
      }
    }
  } catch (error) {
    ready.send('Piper initialization failed: $error');
  } finally {
    tts?.free();
    if (cacheDirectory.existsSync()) {
      for (final file in cacheDirectory.listSync().whereType<File>()) {
        try {
          file.deleteSync();
        } catch (_) {/* Player may still own a file. */}
      }
      try {
        cacheDirectory.deleteSync();
      } catch (_) {/* Best-effort cleanup. */}
    }
  }
}
