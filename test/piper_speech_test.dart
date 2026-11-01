import 'dart:async';

import 'package:aac_studio/engine/piper_voice.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeOfflineVoice implements OfflineSpeechVoice {
  bool failPrepare = false;
  bool failSpeak = false;
  Completer<void>? preparing;
  Completer<void>? generating;
  final started = Completer<void>();
  final spoken = <String>[];
  double? lastRate;
  double? lastVolume;

  @override
  Future<void> prepare() async {
    await preparing?.future;
    if (failPrepare) throw StateError('Voice pack unavailable');
  }

  @override
  Future<void> speak(String text,
      {required double rate,
      required double volume,
      required bool Function() isCurrent}) async {
    if (!started.isCompleted) started.complete();
    await generating?.future;
    if (failSpeak) throw StateError('Playback failed');
    if (isCurrent()) {
      spoken.add(text);
      lastRate = rate;
      lastVolume = volume;
    }
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final nativeCalls = <MethodCall>[];
  setUp(() {
    nativeCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      nativeCalls.add(call);
      if (call.method == 'isLanguageAvailable') return true;
      return 1;
    });
  });

  test('ready Piper speaks with per-button rate and volume', () async {
    final voice = FakeOfflineVoice();
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.warmOfflineVoice();
    await engine.speak('Help', style: const VoiceStyle(rate: 0.3, volume: 0.6));
    expect(voice.spoken, ['Help']);
    expect(voice.lastRate, 0.3);
    expect(voice.lastVolume, 0.6);
    expect(nativeCalls.where((c) => c.method == 'speak'), isEmpty);
    expect(engine.error.value, isNull);
    await engine.dispose();
  });

  test('setup does not block native speech, and switches to Piper when ready',
      () async {
    final voice = FakeOfflineVoice()..preparing = Completer<void>();
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.speak('Help');
    expect(nativeCalls.where((c) => c.method == 'speak'), hasLength(1));
    expect(voice.spoken, isEmpty);
    voice.preparing!.complete();
    await engine.warmOfflineVoice();
    await engine.speak('Water');
    expect(voice.spoken, ['Water']);
    await engine.dispose();
  });

  test('failed Piper falls back for the same utterance and can be retried',
      () async {
    final voice = FakeOfflineVoice()..failSpeak = true;
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.warmOfflineVoice();
    await engine.speak('Help');
    expect(nativeCalls.where((c) => c.method == 'speak'), hasLength(1));
    expect(engine.status.value, contains('Using device voice'));
    expect(engine.error.value, isNull);
    voice.failSpeak = false;
    await engine.warmOfflineVoice();
    await engine.speak('Water');
    expect(voice.spoken, ['Water']);
    await engine.dispose();
  });

  test('missing voice pack keeps device speech available', () async {
    final voice = FakeOfflineVoice()..failPrepare = true;
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.warmOfflineVoice();
    await engine.speak('Help');
    expect(nativeCalls.where((c) => c.method == 'speak'), hasLength(1));
    expect(engine.error.value, isNull);
    await engine.dispose();
  });

  test('stop suppresses audio from an in-flight synthesis', () async {
    final voice = FakeOfflineVoice()..generating = Completer<void>();
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.warmOfflineVoice();
    final speech = engine.speak('Old message');
    await voice.started.future;
    await engine.stop();
    voice.generating!.complete();
    await speech;
    expect(voice.spoken, isEmpty);
    expect(nativeCalls.where((c) => c.method == 'speak'), isEmpty);
    await engine.dispose();
  });

  test('newer request replaces in-flight and queued Piper messages', () async {
    final voice = FakeOfflineVoice()..generating = Completer<void>();
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.warmOfflineVoice();
    final first = engine.speak('Old message');
    await voice.started.future;
    final queued = engine.speak('Intermediate message');
    final latest = engine.speak('Help now');
    voice.generating!.complete();
    await Future.wait([first, queued, latest]);
    expect(voice.spoken, ['Help now']);
    await engine.dispose();
  });

  test('pitch overrides use native speech without silently ignoring pitch',
      () async {
    final voice = FakeOfflineVoice();
    final engine = SpeechEngine(offlineVoice: voice)..usePiper = true;
    await engine.warmOfflineVoice();
    await engine.speak('Hello', style: const VoiceStyle(pitch: 1.3));
    expect(voice.spoken, isEmpty);
    expect(
        nativeCalls.where((c) => c.method == 'setPitch').last.arguments, 1.3);
    expect(nativeCalls.where((c) => c.method == 'speak'), hasLength(1));
    await engine.dispose();
  });

  test('old settings opt into Piper; explicit device choice survives saving',
      () {
    expect(AppSettings.fromJson({'rate': 0.4}).usePiper, isTrue);
    final settings = AppSettings(usePiper: false);
    expect(AppSettings.fromJson(settings.toJson()).usePiper, isFalse);
  });
}
