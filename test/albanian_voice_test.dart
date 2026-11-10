import 'package:aac_studio/engine/piper_worker.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'piper_speech_test.dart' show FakeOfflineVoice;

/// The app's own Albanian voice (phones have none).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final deviceSpoken = <String>[];
  setUp(() {
    deviceSpoken.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') deviceSpoken.add(call.arguments as String);
      return call.method == 'isLanguageAvailable' ? true : 1;
    });
  });

  test('the Albanian pack is a pinned, downloadable Piper voice', () {
    final pack = piperPacks['sq']!;
    expect(pack.espeakVoice, 'sq');
    expect(pack.dictionary, 'sq_dict');
    expect(pack.asset, isNull, reason: 'downloaded only when chosen');
    expect(pack.url, startsWith('https://'));
    expect(pack.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(SpeechEngine.hasOfflineVoice('sq'), isTrue);
    expect(SpeechEngine.hasOfflineVoice('fr'), isFalse,
        reason: 'French uses the device voice');
  });

  test('Albanian words are spoken by the Albanian voice, not the device',
      () async {
    final english = FakeOfflineVoice();
    final albanian = FakeOfflineVoice();
    final engine =
        SpeechEngine(offlineVoice: english, packVoices: {'sq': albanian});
    engine.configure(AppSettings()..language = 'sq');
    await engine.warmOfflineVoice();
    await engine.speak('Unë dua ujë');
    expect(albanian.spoken, ['Unë dua ujë']);
    expect(english.spoken, isEmpty);
    expect(deviceSpoken, isEmpty);
  });

  test('without the download, Albanian falls back to the device voice',
      () async {
    final albanian = FakeOfflineVoice()..failPrepare = true;
    final engine = SpeechEngine(
        offlineVoice: FakeOfflineVoice(), packVoices: {'sq': albanian});
    engine.configure(AppSettings()..language = 'sq');
    await engine.warmOfflineVoice();
    await engine.speak('Përshëndetje');
    expect(albanian.spoken, isEmpty);
    expect(deviceSpoken, ['Përshëndetje'], reason: 'the person is never silent');
  });

  test('switching back to English uses the English offline voice again',
      () async {
    final english = FakeOfflineVoice();
    final albanian = FakeOfflineVoice();
    final engine =
        SpeechEngine(offlineVoice: english, packVoices: {'sq': albanian});
    engine.configure(AppSettings()..language = 'sq');
    await engine.warmOfflineVoice();
    engine.configure(AppSettings()..language = 'en');
    await engine.warmOfflineVoice();
    await engine.speak('hello');
    expect(english.spoken, ['hello']);
    expect(albanian.spoken, isEmpty);
  });
}
