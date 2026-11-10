import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/i18n.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Letters without "capital", natural pronoun + word phrases, best voice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final file = File(utf8.decode(message!.buffer.asUint8List()));
    if (!await file.exists()) return null;
    return ByteData.sublistView(await file.readAsBytes());
  });
  final spoken = <String>[];
  final setVoices = <Map>[];
  List<Map<String, String>> deviceVoices = [];
  setUp(() {
    spoken.clear();
    setVoices.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
            (call) async {
      if (call.method == 'speak') spoken.add(call.arguments as String);
      if (call.method == 'setVoice') setVoices.add(call.arguments as Map);
      if (call.method == 'getVoices') return deviceVoices;
      return call.method == 'isLanguageAvailable' ? true : 1;
    });
  });
  tearDown(() => I18n.load('en'));

  test('a single letter is spoken without "capital"', () async {
    expect(speechText('A'), 'a');
    expect(speechText('Ç'), 'ç');
    expect(speechText('7'), '7');
    expect(speechText('I want'), 'I want');
    final engine = SpeechEngine();
    await engine.speak('B', interrupt: true);
    expect(spoken, ['b']);
  });

  GridSession board() => GridSession(
      vocabulary: PackLoader()
          .loadString(File('assets/sample_pack.json').readAsStringSync()),
      speech: SpeechEngine());
  VocabButton find(GridSession s, String page, String label) => s
      .vocabulary.viewsByFolder[page]!.first.cells
      .firstWhere((c) => c.button.label == label)
      .button;

  test('French: pronoun + word become a natural phrase; delete undoes it',
      () async {
    await I18n.load('fr');
    final s = board();
    s.tap(find(s, 'home', 'I'));
    s.tap(find(s, 'home', 'want'));
    expect(s.message, 'je veux');
    s.tap(find(s, 'home', 'eat'));
    expect(s.message, 'je veux manger');
    s.removeLastWord();
    s.removeLastWord();
    expect(s.message, 'je', reason: 'deleting the phrase gives the pronoun back');
    s.tap(find(s, 'home', 'hungry'));
    expect(s.message, "j'ai faim");
  });

  test('English: he + want = he wants, I + hungry = I am hungry', () async {
    await I18n.load('en');
    final s = board();
    s.tap(find(s, 'home', 'he'));
    s.tap(find(s, 'home', 'want'));
    expect(s.message, 'he wants');
    s.clearMessage();
    s.tap(find(s, 'home', 'I'));
    s.tap(find(s, 'home', 'hungry'));
    expect(s.message, 'I am hungry');
  });

  test('every language has a natural phrase for every pronoun + word', () {
    final keys = File('tools/data/i18n/_source/forms.txt')
        .readAsLinesSync()
        .where((l) => l.trim().isNotEmpty)
        .map((l) => l.toLowerCase());
    for (final lang in kLanguages) {
      final forms = (jsonDecode(File('assets/i18n/${lang.code}.json')
              .readAsStringSync()) as Map)['forms'] as Map;
      expect(keys.where((k) => !forms.containsKey(k)), isEmpty,
          reason: lang.name);
    }
  });

  test('the most natural installed voice is chosen for the language', () {
    final fr = languageFor('fr');
    VoiceInfo v(String name, String locale,
            {String quality = '', bool network = false}) =>
        (name: name, locale: locale, quality: quality, network: network);
    final voices = [
      v('Samantha', 'en-US', quality: 'enhanced'),
      v('Amélie', 'fr-CA'),
      v('Thomas', 'fr-FR'),
      v('Audrey (Premium)', 'fr-FR', quality: 'premium'),
      v('Bells', 'fr-FR'),
    ];
    expect(bestVoice(fr, voices)!.name, 'Audrey (Premium)');
    expect(bestVoice(fr, voices.take(3))!.name, 'Thomas',
        reason: 'France before Canada');
    expect(bestVoice(languageFor('sq'), voices), isNull,
        reason: 'no Albanian voice installed');
    expect(voiceSpeaks(languageFor('hr'), 'sr-Latn-RS'), isTrue);
  });

  test('the device switches to the best voice when the language changes',
      () async {
    deviceVoices = [
      {'name': 'Samantha', 'locale': 'en-US', 'quality': 'default'},
      {'name': 'Anna', 'locale': 'de-DE', 'quality': 'default'},
      {'name': 'Petra (Premium)', 'locale': 'de-DE', 'quality': 'premium'},
    ];
    final engine = SpeechEngine();
    engine.configure(AppSettings()
      ..usePiper = false
      ..language = 'de'
      // A voice chosen earlier for English must not read German words.
      ..voiceName = 'Samantha'
      ..voiceLocale = 'en-US');
    await engine.speak('Hallo');
    expect(setVoices.last['name'], 'Petra (Premium)');
    deviceVoices = [];
  });
}
