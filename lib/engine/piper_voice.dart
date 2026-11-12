import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'piper_worker.dart';

abstract class OfflineSpeechVoice {
  Future<void> prepare();
  Future<void> speak(String text,
      {required double rate,
      required double volume,
      required bool Function() isCurrent});
  Future<void> stop();
  Future<void> dispose();
}

class PiperVoice implements OfflineSpeechVoice {
  PiperVoice([this.pack = englishPiperPack]);

  final PiperPack pack;
  PiperSynthesizer? _synthesizer;

  static Future<String> _installDirectory(PiperPack pack) async {
    final support = await getApplicationSupportDirectory();
    // The English folder keeps its original name so existing installs stay.
    return p.join(support.path, 'voices',
        pack.id == 'en' ? 'piper-ljspeech-v1' : pack.installName);
  }

  /// Whether this pack can speak without downloading (bundled or saved).
  static Future<bool> isReady(PiperPack pack) async {
    if (pack.asset != null) return true;
    final dir = await _installDirectory(pack);
    return isPiperPackInstalled(dir, pack) ||
        File(p.join(dir, 'voice.tar.bz2')).existsSync();
  }

  /// Downloads a pack once (then it works offline). The archive is checked
  /// against its SHA-256 before use. [onProgress] gets 0..1.
  static Future<void> download(PiperPack pack,
      {void Function(double progress)? onProgress}) async {
    final url = pack.url;
    if (url == null || await isReady(pack)) return;
    final dir = await _installDirectory(pack);
    await Directory(dir).create(recursive: true);
    final partial = File(p.join(dir, 'voice.tar.bz2.part'));
    final client = HttpClient();
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != 200) {
        throw HttpException('Voice download failed (${response.statusCode})');
      }
      final sink = partial.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (pack.downloadBytes > 0) {
            onProgress?.call((received / pack.downloadBytes).clamp(0.0, 1.0));
          }
        }
      } finally {
        await sink.close();
      }
      final digest = await sha256.bind(partial.openRead()).first;
      if (digest.toString() != pack.sha256) {
        await partial.delete();
        throw const FormatException('The voice download was damaged. Try again.');
      }
      await partial.rename(p.join(dir, 'voice.tar.bz2'));
    } finally {
      client.close(force: true);
    }
  }
  Future<void>? _initializing;
  AudioPlayer? _player;

  @override
  Future<void> prepare() => _initializing ??= _prepare();

  Future<void> _prepare() async {
    try {
      final installDirectory = await _installDirectory(pack);
      final archive = File(p.join(installDirectory, 'voice.tar.bz2'));
      if (!isPiperPackInstalled(installDirectory, pack)) {
        await archive.parent.create(recursive: true);
        final asset = pack.asset;
        if (asset == null) {
          if (!archive.existsSync()) {
            throw StateError('${pack.name} voice is not downloaded yet');
          }
        } else {
          final bytes = await rootBundle.load(asset);
          await archive.writeAsBytes(
              bytes.buffer
                  .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
              flush: true);
        }
      }
      final temporary = await getTemporaryDirectory();
      final cache =
          await Directory(p.join(temporary.path, 'aac-piper-')).createTemp();
      _synthesizer = await PiperSynthesizer.start(
        archivePath: archive.path,
        installDirectory: installDirectory,
        cacheDirectory: cache.path,
        pack: pack,
      );
      try {
        if (await archive.exists()) await archive.delete();
      } catch (_) {/* Cleanup must not disable a usable offline voice. */}
    } catch (_) {
      _initializing = null;
      rethrow;
    }
  }

  @override
  Future<void> speak(String text,
      {required double rate,
      required double volume,
      required bool Function() isCurrent}) async {
    try {
      await prepare();
      if (!isCurrent()) return;
      final path =
          await _synthesizer!.synthesize(
              text, (rate / 0.45 * pack.pace).clamp(0.5, 2.0));
      if (!isCurrent()) return;
      if (_player == null) {
        final player = AudioPlayer();
        _player = player;
        await player.setAudioContext(AudioContext(
          iOS: AudioContextIOS(
              category: AVAudioSessionCategory.playback,
              options: {AVAudioSessionOptions.duckOthers}),
          android: const AudioContextAndroid(
              contentType: AndroidContentType.speech,
              usageType: AndroidUsageType.assistanceAccessibility,
              audioFocus: AndroidAudioFocus.gainTransientMayDuck),
        ));
      }
      await _player!.stop();
      if (!isCurrent()) return;
      await _player!
          .play(DeviceFileSource(path), volume: volume.clamp(0.0, 1.0));
      // Stop can arrive while the platform player is starting.
      if (!isCurrent()) await _player!.stop();
    } catch (_) {
      try {
        await _player?.dispose();
      } catch (_) {/* Reset broken playback. */}
      _player = null;
      _synthesizer?.dispose();
      _synthesizer = null;
      _initializing = null;
      rethrow;
    }
  }

  @override
  Future<void> stop() async => _player?.stop();

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    _player = null;
    _synthesizer?.dispose();
    _synthesizer = null;
    _initializing = null;
  }
}
