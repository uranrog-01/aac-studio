import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:piper_phonemize/piper_phonemize.dart' as phonemizer;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

const piperPackDirectory = 'vits-piper-en_US-ljspeech-medium';
const piperModelFile = 'en_US-ljspeech-medium.onnx';
const piperModelBytes = 63531507;

bool isPiperPackInstalled(String installDirectory) {
  final directory = p.join(installDirectory, piperPackDirectory);
  final model = File(p.join(directory, piperModelFile));
  return File(p.join(directory, '.ready-v1')).existsSync() &&
      model.existsSync() &&
      model.lengthSync() == piperModelBytes &&
      File(p.join(directory, 'tokens.txt')).existsSync() &&
      File(p.join(directory, 'espeak-ng-data', 'en_dict')).existsSync();
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
  }) async {
    final ready = ReceivePort();
    Isolate? worker;
    try {
      worker = await Isolate.spawn(_piperWorker,
          [ready.sendPort, archivePath, installDirectory, cacheDirectory]);
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
String installPiperPack(String archivePath, String installDirectory) {
  final modelDirectory = p.join(installDirectory, piperPackDirectory);
  final marker = File(p.join(modelDirectory, '.ready-v1'));
  final model = File(p.join(modelDirectory, piperModelFile));
  final tokens = File(p.join(modelDirectory, 'tokens.txt'));
  final dictionary = File(p.join(modelDirectory, 'espeak-ng-data', 'en_dict'));
  if (isPiperPackInstalled(installDirectory)) {
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
      if (name != piperPackDirectory &&
          !name.startsWith('$piperPackDirectory/')) {
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
      model.lengthSync() != piperModelBytes ||
      !tokens.existsSync() ||
      !dictionary.existsSync()) {
    throw const FormatException('Incomplete Piper voice pack');
  }
  marker.writeAsStringSync('ljspeech-medium-v1');
  return modelDirectory;
}

void _piperWorker(List<Object> arguments) async {
  final ready = arguments[0] as SendPort;
  final cacheDirectory = Directory(arguments[3] as String);
  sherpa.OfflineTts? tts;
  final cache = <String, String>{};
  var cacheBytes = 0;
  var sequence = 0;
  try {
    final modelDirectory =
        installPiperPack(arguments[1] as String, arguments[2] as String);
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
          model: p.join(modelDirectory, piperModelFile),
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
            phonemizer.PiperPhonemize.phonemize(text, voice: 'en-us')
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
