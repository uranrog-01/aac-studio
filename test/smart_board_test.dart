import 'dart:convert';
import 'dart:io';

import 'package:aac_studio/data/pack_loader.dart';
import 'package:aac_studio/engine/smart_words.dart';
import 'package:aac_studio/engine/speech.dart';
import 'package:aac_studio/engine/storage.dart';
import 'package:aac_studio/engine/word_forms.dart';
import 'package:aac_studio/features/grid/grid_screen.dart';
import 'package:aac_studio/features/tools/tools.dart';
import 'package:aac_studio/models/domain.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1.12: word forms, next-word and time suggestions, fuller sentences,
/// the word-use record, start small on every page, hide for now and
/// "Show me where".
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('flutter_tts'),
          (call) async => call.method == 'isLanguageAvailable' ? true : 1);

  Vocabulary board() => PackLoader()
      .loadString(File('assets/sample_pack.json').readAsStringSync());

  group('word forms', () {
    test('verbs: he eats, ate, eating (irregular and doubled)', () {
      expect(WordForms.of('eat', WordClass.verb),
          ['eat', 'eats', 'ate', 'eating']);
      expect(WordForms.of('go', WordClass.verb), ['go', 'goes', 'went', 'going']);
      expect(WordForms.of('stop', WordClass.verb),
          ['stop', 'stops', 'stopped', 'stopping']);
      expect(WordForms.of('cry', WordClass.verb), ['cry', 'cries', 'cried', 'crying']);
      expect(WordForms.of('make', WordClass.verb),
          ['make', 'makes', 'made', 'making']);
      expect(WordForms.of('wash hands', WordClass.verb),
          ['wash hands', 'washes hands', 'washed hands', 'washing hands']);
    });

    test('nouns, describing words and pronouns', () {
      expect(WordForms.of('dog', WordClass.noun), ['dog', 'dogs']);
      expect(WordForms.of('box', WordClass.noun), ['box', 'boxes']);
      expect(WordForms.of('baby', WordClass.noun), ['baby', 'babies']);
      expect(WordForms.of('child', WordClass.noun), ['child', 'children']);
      expect(WordForms.of('water', WordClass.noun), isEmpty);
      expect(WordForms.of('big', WordClass.adjective).take(3),
          ['big', 'bigger', 'biggest']);
      expect(WordForms.of('happy', WordClass.adjective).take(3),
          ['happy', 'happier', 'happiest']);
      expect(WordForms.of('good', WordClass.adjective), ['good', 'better', 'best']);
      expect(WordForms.of('tired', WordClass.adjective).take(3),
          ['tired', 'more tired', 'most tired']);
      expect(WordForms.of('I', WordClass.pronoun),
          ['i', 'me', 'my', 'mine', 'myself']);
      expect(WordForms.of('hello', WordClass.social), isEmpty);
    });
  });

  group('fuller sentence', () {
    SaidWord w(String word, WordClass c, [String? text]) =>
        SaidWord(word, c, text ?? word);

    test('English: subject, "to" before a verb, "to the" after go', () {
      expect(
          SmartWords.betterSentence([
            w('want', WordClass.verb),
            w('drink', WordClass.verb),
            w('water', WordClass.noun),
          ], 'en'),
          'I want to drink water.');
      expect(
          SmartWords.betterSentence(
              [w('want', WordClass.verb, 'I want'), w('go', WordClass.verb)],
              'en'),
          'I want to go.');
      expect(
          SmartWords.betterSentence(
              [w('go', WordClass.verb), w('toilet', WordClass.noun)], 'en'),
          'Go to the toilet.');
      expect(SmartWords.betterSentence([w('hungry', WordClass.adjective)], 'en'),
          "I'm hungry.");
      expect(
          SmartWords.betterSentence(
              [w('tired', WordClass.adjective), w('it', WordClass.pronoun)], 'en'),
          isNull,
          reason: 'no sentence like "I am tired it"');
      expect(
          SmartWords.betterSentence(
              [w('where', WordClass.question), w('mom', WordClass.noun)], 'en'),
          isNull,
          reason: 'nothing to improve');
    });

    test('Albanian: "të" and the right verb form after dua / kam nevojë', () {
      expect(
          SmartWords.betterSentence([
            w('want', WordClass.verb, 'dua'),
            w('go', WordClass.verb, 'shko'),
          ], 'sq'),
          'Dua të shkoj.');
      expect(
          SmartWords.betterSentence([
            w('want', WordClass.verb, 'unë dua'),
            w('drink', WordClass.verb, 'pi'),
            w('water', WordClass.noun, 'ujë'),
          ], 'sq'),
          'Unë dua të pi ujë.');
      expect(
          SmartWords.betterSentence(
              [w('mom', WordClass.noun, 'mami'), w('go', WordClass.verb, 'shko')],
              'sq'),
          isNull);
    });

    test('other languages are left as they are', () {
      expect(
          SmartWords.betterSentence(
              [w('want', WordClass.verb, 'veux'), w('go', WordClass.verb, 'aller')],
              'fr'),
          isNull);
    });
  });

  group('suggestions', () {
    test('next words: starters, then what this person says often first', () {
      final smart = SmartWords.instance;
      expect(smart.nextAfter('want').take(3), ['more', 'eat', 'drink']);
      smart.learn('want', 'juice');
      expect(smart.nextAfter('want').first, isNot('juice'),
          reason: 'one use is not a habit');
      smart.learn('want', 'juice');
      expect(smart.nextAfter('want').first, 'juice');
      smart.forget();
    });

    test('words for the time of day and the weekend', () {
      final monday = DateTime(2026, 11, 16, 7, 30);
      final saturday = DateTime(2026, 11, 14, 7, 30);
      expect(SmartWords.forTime(monday), containsAll(['breakfast', 'school']));
      expect(SmartWords.forTime(saturday), isNot(contains('school')));
      expect(SmartWords.forTime(DateTime(2026, 11, 16, 19)), contains('bath'));
      expect(SmartWords.forTime(DateTime(2026, 11, 16, 23)), contains('sleep'));
    });

    test('every suggested word is on the board', () {
      final session = GridSession(vocabulary: board(), speech: SpeechEngine());
      final words = {
        for (final list in SmartWords.starters.values) ...list,
        ...SmartWords.starters.keys,
        for (var h = 0; h < 24; h++) ...SmartWords.forTime(DateTime(2026, 11, 16, h)),
        for (var h = 0; h < 24; h++) ...SmartWords.forTime(DateTime(2026, 11, 14, h)),
      };
      final missing = [
        for (final w in words)
          if (session.buttonForLabel(w) == null) w
      ];
      // A few function words are fine without a button (they are skipped).
      expect(missing.length, lessThan(words.length ~/ 5), reason: '$missing');
    });

    test('the session knows the words tapped and can say the sentence', () {
      final session = GridSession(vocabulary: board(), speech: SpeechEngine());
      final want = session.buttonForLabel('want')!;
      final drink = session.buttonForLabel('drink')!;
      final used = <String>[];
      session.onWordUsed = (b, previous) => used.add('$previous>${b.label}');
      session.tap(want);
      session.tap(drink);
      expect(session.lastWord, 'drink');
      expect(session.saidWords.map((w) => w.word), ['want', 'drink']);
      expect(used, ['null>want', 'want>drink']);
      expect(SmartWords.betterSentence(session.saidWords, 'en'), 'I want to drink.');
      session.useSentence('I want to drink.');
      expect(session.message, 'I want to drink.');
      session.setMessageLive('typed text');
      expect(session.saidWords, isEmpty);
      expect(session.lastWord, isNull);
    });
  });

  group('board layout', () {
    test('start small on every page: hidden words leave their place', () {
      final session = GridSession(vocabulary: board(), speech: SpeechEngine());
      final full = session.viewFor('food', maxColumns: 99)!;
      session.homeLevel = 1;
      final small = session.viewFor('food', maxColumns: 99)!;
      expect(small.cells.length, full.cells.length,
          reason: 'every word keeps its index');
      final shown = small.cells
          .where((c) => !c.blank && c.button.kind == ButtonKind.item)
          .length;
      expect(shown, lessThanOrEqualTo(12));
      for (var i = 0; i < small.cells.length; i++) {
        expect(small.cells[i].button.id, full.cells[i].button.id);
      }
      final home = session.viewFor('home', maxColumns: 99)!;
      expect(
          home.cells
              .where((c) => !c.blank && c.button.kind == ButtonKind.item)
              .length,
          10);
      expect(
          home.cells.where((c) => c.button.kind == ButtonKind.folder && !c.blank),
          isEmpty,
          reason: 'no categories yet at the first level');
    });

    test('hide for now keeps the cell, is saved and is skipped by Find', () {
      final vocabulary = board();
      final session = GridSession(vocabulary: vocabulary, speech: SpeechEngine());
      final cell = vocabulary.viewsByFolder['home']!.first.cells[3];
      session.setHidden(cell.button.id, true);
      final saved = PackLoader().save(vocabulary);
      final again = PackLoader().loadString(jsonEncode(saved));
      expect(again.viewsByFolder['home']!.first.cells[3].hidden, isTrue);
      expect(
          session
              .findWords(cell.button.label)
              .where((r) => r.button.id == cell.button.id && r.folderId == 'home'),
          isEmpty);
      session.setHidden(cell.button.id, false);
      expect(vocabulary.viewsByFolder['home']!.first.cells[3].hidden, isFalse);
    });

    test('show me where: the way from Home to a page', () {
      final session = GridSession(vocabulary: board(), speech: SpeechEngine());
      expect(session.pathTo('home'), ['home']);
      final path = session.pathTo('fruits')!;
      expect(path.first, 'home');
      expect(path.last, 'fruits');
      expect(path.length, greaterThan(1));
      expect(session.pathTo('no such page'), isNull);
    });

    test('v18 games page: new games in, tap and hear and match pairs out', () {
      final raw = jsonDecode(File('assets/sample_pack.json').readAsStringSync())
          as Map<String, dynamic>;
      final games = [
        for (final c in (raw['views']['games'] as List).first['cells'] as List)
          c['btn'] as String
      ];
      expect(games, containsAll(['game_kineticsand', 'game_soap', 'game_beads',
          'game_wash', 'game_cradle', 'game_tunnel', 'game_aurora', 'game_jellyfish']));
      expect(games, isNot(contains('game_hear')));
      expect(games, isNot(contains('game_pairs')));
      // Boards already installed lose them on the upgrade too.
      final history = jsonDecode(
          File('assets/factory_symbol_history.json').readAsStringSync()) as Map;
      expect((history['retired'] as Map)['games'],
          containsAll(['game_hear', 'game_pairs']));
    });

    test('board v17 tool buttons open their tools', () {
      final vocabulary = board();
      final tools = <String>{};
      for (final views in vocabulary.viewsByFolder.values) {
        for (final v in views) {
          for (final c in v.cells) {
            for (final a in c.button.actions) {
              if (a.kind == ActionKind.openTool) tools.add(a.data);
            }
          }
        }
      }
      expect(tools, containsAll(['schedule', 'firstthen', 'timer', 'pain', 'listen', 'scenes']));
      expect(tools.every(ToolScreens.names.contains), isTrue);
    });
  });

  group('word-use record', () {
    test('counts per day and sums a period', () {
      final log = WordUseLog.instance;
      log.days.clear();
      final today = DateTime(2026, 11, 14, 10);
      log.record('want', at: today);
      log.record('want', at: today);
      log.record('drink', at: today);
      log.record('play', at: today.subtract(const Duration(days: 3)));
      log.record('old', at: today.subtract(const Duration(days: 40)));
      final week = log.summary(7, now: today);
      expect(week.taps, 4);
      expect(week.words, 3);
      expect(week.activeDays, 2);
      expect(week.top.first.key, 'want');
      expect(log.summary(1, now: today).taps, 3);
      expect(log.summary(90, now: today).words, 4);
      log.days.clear();
    });

    test('new settings are saved and read back', () {
      final s = AppSettings.fromJson((AppSettings()
            ..suggestNext = false
            ..betterSentences = false
            ..quickReplies = true
            ..timeSuggestions = true
            ..listenEnabled = true
            ..gridColumns = 4
            ..hoverSelect = true
            ..logWords = true
            ..schedule = ['a', 'b']
            ..scheduleStep = 1
            ..firstId = 'x'
            ..thenId = 'y')
          .toJson());
      expect(s.suggestNext, isFalse);
      expect(s.betterSentences, isFalse);
      expect(s.quickReplies, isTrue);
      expect(s.timeSuggestions, isTrue);
      expect(s.listenEnabled, isTrue);
      // Extras stay off until a caregiver turns them on.
      final fresh = AppSettings();
      expect([fresh.suggestNext, fresh.timeSuggestions, fresh.quickReplies,
          fresh.hoverSelect, fresh.listenEnabled], [false, false, false, false, false]);
      expect(AppSettings.fromJson({}).suggestNext, isFalse);
      expect(AppSettings.fromJson({'suggestNext': true}).suggestNext, isTrue);
      expect(s.gridColumns, 4);
      expect(s.hoverSelect, isTrue);
      expect(s.logWords, isTrue);
      expect(s.schedule, ['a', 'b']);
      expect(s.scheduleStep, 1);
      expect(s.firstId, 'x');
      expect(s.thenId, 'y');
      expect(AppSettings().logWords, isFalse, reason: 'off until a caregiver turns it on');
      expect(AppSettings.fromJson({'gridColumns': 99}).gridColumns, 12);
    });
  });
}
