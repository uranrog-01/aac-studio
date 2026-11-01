import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
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
  PiperSynthesizer? _synthesizer;
  Future<void>? _initializing;
  AudioPlayer? _player;

  @override
  Future<void> prepare() => _initializing ??= _prepare();

  Future<void> _prepare() async {
    try {
      final support = await getApplicationSupportDirectory();
      final installDirectory =
          p.join(support.path, 'voices', 'piper-ljspeech-v1');
      final archive = File(p.join(installDirectory, 'voice.tar.bz2'));
      if (!isPiperPackInstalled(installDirectory)) {
        await archive.parent.create(recursive: true);
        final bytes = await rootBundle
            .load('assets/voices/piper-en-us-ljspeech-medium.tar.bz2');
        await archive.writeAsBytes(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
            flush: true);
      }
      final temporary = await getTemporaryDirectory();
      final cache =
          await Directory(p.join(temporary.path, 'aac-piper-')).createTemp();
      _synthesizer = await PiperSynthesizer.start(
        archivePath: archive.path,
        installDirectory: installDirectory,
        cacheDirectory: cache.path,
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
          await _synthesizer!.synthesize(text, (rate / 0.45).clamp(0.5, 2.0));
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
