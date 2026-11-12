import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/engine/i18n.dart';
import 'package:aac_studio/engine/pack_upgrade.dart';
import 'package:aac_studio/engine/prediction.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/voice_clips.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Words implements AppStorageProvider {
  Map<String, int> words = {};
  @override
  Future<Map<String, int>> readLearned() async => Map.of(words);
  @override
  Future<void> writeLearned(Map<String, int> words) async =>
      this.words = Map.of(words);
}

/// Every text handed to I18n.t as plain quoted text, in all of lib/.
Set<String> _appTexts() {
  final call = RegExp(r"I18n\.t\(\s*((?:'(?:[^'\\]|\\.)*'\s*)+)[,)]");
  final piece = RegExp(r"'((?:[^'\\]|\\.)*)'");
  final out = <String>{};
  for (final f in Directory('lib').listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    for (final m in call.allMatches(f.readAsStringSync())) {
      out.add(piece
          .allMatches(m.group(1)!)
          .map((p) => p.group(1)!.replaceAll(r"\'", "'"))
          .join());
    }
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    final file = File(utf8.decode(message!.buffer.asUint8List()));
    if (!await file.exists()) return null;
    return ByteData.sublistView(await file.readAsBytes());
  });
  tearDown(() async {
    I18n.setFemale(false);
    await I18n.load('en');
  });

  test('typed words are learned whole in every alphabet, per language',
      () async {
    final storage = _Words();
    final predictor = Predictor()..setLanguage('sq', const ['mollë', 'mirë']);
    await predictor.learnFrom('Unë është çokollatë', storage);
    expect(storage.words.keys,
        containsAll(['sq:unë', 'sq:është', 'sq:çokollatë']));
    expect(storage.words.keys.any((w) => w.contains('sht') && w.length < 7),
        isFalse,
        reason: 'no fragments such as "sht"');
    expect(predictor.suggest('ço'), ['çokollatë']);
    // The board's own Albanian words are suggested too.
    expect(predictor.suggest('mo'), ['mollë']);
    // Albanian words never appear among English suggestions.
    predictor.setLanguage('en', const []);
    expect(predictor.suggest('ço'), isEmpty);
    await predictor.learnFrom('привет', storage);
    expect(storage.words.containsKey('привет'), isTrue);
  });

  test('a wrong value in saved settings does not stop the app', () {
    final s = AppSettings.fromJson({
      'rate': 'fast',
      'pitch': null,
      'pin': 4321,
      'language': 7,
      'haptics': 'yes',
      'scanDelayMs': 'slow',
      'phrases': 'none',
      'voiceName': 12,
    });
    expect(s.rate, 0.45);
    expect(s.pin, '1234');
    expect(s.language, 'en');
    expect(s.haptics, isTrue);
    expect(s.scanDelayMs, 1200);
    expect(s.voiceName, isNull);
    expect(AppSettings.fromJson(s.toJson()).speakerFemale, isFalse);
  });

  test('Albanian: a girl or woman gets feminine words and phrases', () async {
    await I18n.load('sq');
    expect(I18n.hasFeminine, isTrue);
    expect(I18n.word('tired'), 'i lodhur');
    expect(I18n.form('I', 'happy'), 'unë jam i lumtur');
    I18n.setFemale(true);
    expect(I18n.word('tired'), 'e lodhur');
    expect(I18n.form('I', 'happy'), 'unë jam e lumtur');
    // Words without a feminine form stay as they are.
    expect(I18n.word('apple'), 'mollë');
    expect(I18n.form('I', 'want'), 'unë dua');
  });

  test('one word, two meanings: a button can have its own translation',
      () async {
    await I18n.load('sq');
    expect(I18n.word('sink'), 'fundoset');
    expect(I18n.word('sink', id: 'v11_kitchen_sink'), 'lavaman');
    expect(I18n.word('watch', id: 'v11_actions_watch'), 'shiko');
  });

  test('an update never moves Home buttons; the new layout is a choice',
      () {
    Map<String, dynamic> read(String path) =>
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final fresh = read('assets/sample_pack.json');
    final history = read('assets/factory_symbol_history.json');
    final v11Home = ((history['layouts'] as Map)['home'] as List).last as List;
    List<String> home(Map<String, dynamic> pack) => [
          for (final c in (pack['views']['home'] as List).first['cells'] as List)
            c['btn'] as String
        ];
    Map<String, dynamic> installed(List ids) {
      final old = jsonDecode(jsonEncode(fresh)) as Map<String, dynamic>;
      old['packVersion'] = 11;
      (old['buttons'] as List)
          .removeWhere((b) =>
              (b['id'] as String).startsWith(RegExp('v1[34]_')));
      old['views']['home'][0]['cells'] = [
        for (final id in ids) {'btn': id}
      ];
      return old;
    }

    // By default the person's Home stays exactly in its order; the new
    // words are added to it.
    final kept = PackUpgrade.merge(installed(v11Home), fresh,
        factorySymbolHistory: history);
    expect(home(kept).where(v11Home.contains).toList(), v11Home);
    expect(home(kept), containsAll(['v13_home_water', 'v13_home_mom']));
    // Asked for, an untouched Home moves to the new starter layout.
    final untouched = PackUpgrade.merge(installed(v11Home), fresh,
        factorySymbolHistory: history, adoptStarterLayouts: true);
    expect(home(untouched), home(fresh));

    // The person moved "help" to the front: their order is kept, and the
    // new words are still added.
    final own = [...v11Home]
      ..remove('b10')
      ..insert(0, 'b10');
    final changed = PackUpgrade.merge(installed(own), fresh,
        factorySymbolHistory: history, adoptStarterLayouts: true);
    expect(home(changed).first, 'b10');
    expect(home(changed), isNot(home(fresh)));
    expect(home(changed), containsAll(['v13_home_water', 'v13_home_mom']));
  });

  test('voices are sorted into female and male', () {
    expect(voiceGender('Microsoft Zira - English (United States)'),
        VoiceGender.female);
    expect(voiceGender('Microsoft David - English (United States)'),
        VoiceGender.male);
    expect(voiceGender('en-us-x-sfg#female_1-local'), VoiceGender.female);
    expect(voiceGender('en-us-x-iom#male_2-local'), VoiceGender.male);
    expect(voiceGender('Samantha'), VoiceGender.female);
    expect(voiceGender('Daniel (Enhanced)'), VoiceGender.male);
    // The device's own answer wins over the name.
    expect(voiceGender('Alex', hint: 'female'), VoiceGender.female);
    // Not guessed.
    expect(voiceGender('sq-al-x-voice-local'), VoiceGender.unknown);
  });

  test('start small: Home level and app lock are saved and safe', () {
    final s = AppSettings.fromJson({'homeLevel': 2, 'lockApp': true});
    expect(s.homeLevel, 2);
    expect(s.lockApp, isTrue);
    expect(AppSettings.fromJson(s.toJson()).homeLevel, 2);
    expect(AppSettings.fromJson({'homeLevel': 99}).homeLevel, 3);
    expect(AppSettings.fromJson({'homeLevel': 'big'}).homeLevel, 0);
    expect(AppSettings().lockApp, isFalse);
  });

  test('Albanian recordings cover whole messages or nothing', () {
    VoiceClips.useIndex('sq', {
      'unë': 'a.mp3',
      'dua': 'b.mp3',
      'ujë': 'c.mp3',
      'unë jam i lodhur': 'd.mp3',
    });
    expect(VoiceClips.clipsFor('Ujë'), ['voices/clips/sq/c.mp3']);
    expect(VoiceClips.clipsFor('unë jam i lodhur.'), ['voices/clips/sq/d.mp3']);
    expect(VoiceClips.clipsFor('unë  dua ujë'),
        ['voices/clips/sq/a.mp3', 'voices/clips/sq/b.mp3', 'voices/clips/sq/c.mp3']);
    expect(VoiceClips.clipsFor('unë jam i lodhur dua ujë'), hasLength(3));
    // One unknown word: no recordings, so no mixed voices.
    expect(VoiceClips.clipsFor('unë dua kafe'), isNull);
    VoiceClips.useIndex('', {});
  });

  test('every Albanian board word has a recording', () {
    final index = (jsonDecode(
            File('assets/voices/clips/sq/index.json').readAsStringSync()) as Map)
        .cast<String, String>();
    VoiceClips.useIndex('sq', index);
    final data = jsonDecode(File('assets/i18n/sq.json').readAsStringSync()) as Map;
    final missing = [
      for (final section in ['words', 'words_f', 'forms', 'forms_f'])
        for (final text in ((data[section] as Map?) ?? const {}).values)
          if (VoiceClips.clipsFor(text as String) == null) text
    ];
    expect(missing, isEmpty);
    for (final file in index.values.toSet()) {
      expect(File('assets/voices/clips/sq/$file').existsSync(), isTrue, reason: file);
    }
    VoiceClips.useIndex('', {});
  });

  test('every app text is translated in every language', () {
    final texts = _appTexts();
    expect(texts.length, greaterThan(60));
    // Shown only where the language has them (Albanian voice, girl/boy).
    const albanianOnly = {
      'The person speaking is',
      'Board words are spoken by recordings of a native voice built into the '
          'app, so they sound right even when this device has no voice for the '
          'language.',
      'Download voice',
      'Downloading the voice for this language…',
      'The voice for this language is installed. It works without internet.',
      'The voice could not be downloaded. Check the internet connection and '
          'try again.',
      'This app has its own voice for this language. Download it once (67 MB, '
          'Wi-Fi recommended); then it works without internet.',
    };
    for (final lang in kLanguages.where((l) => l.code != 'en')) {
      final ui = ((jsonDecode(
                  File('assets/i18n/${lang.code}.json').readAsStringSync())
              as Map)['ui'] as Map)
          .keys
          .toSet();
      final missing = texts.difference(ui);
      if (lang.code != 'sq') missing.removeAll(albanianOnly);
      expect(missing, isEmpty, reason: '${lang.name}: app text not translated');
    }
  });
}
