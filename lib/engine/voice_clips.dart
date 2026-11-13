import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Ready-made recordings of a language's board words, made with a native
/// voice (tools/build_voice_clips.py). Albanian has them because iPhones,
/// iPads, most Android phones and most browsers have no Albanian voice: an
/// English voice would otherwise read Albanian words with English sounds.
///
/// A message is spoken from recordings only when every word in it has one,
/// so a sentence never mixes an Albanian and an English-sounding voice.
class VoiceClips {
  /// Languages with recordings bundled in assets/voices/clips/<code>/.
  static const languages = {'sq'};

  /// Languages that also have a female recording set, in
  /// assets/voices/clips/<code>-f/. The plain folder is the male voice.
  static const femaleLanguages = {'sq'};

  static final _indexes = <String, Map<String, String>>{};
  static final _loading = <String, Future<void>>{};

  static String _folder(String code, bool female) =>
      female && femaleLanguages.contains(code) ? '$code-f' : code;

  /// Preload both indexes so a tap can play the selected voice immediately.
  static Future<void> preload() async {
    await Future.wait([
      for (final code in languages) load(code),
      for (final code in femaleLanguages) load(code, female: true),
    ]);
  }

  static Future<void> load(String code, {bool female = false}) async {
    if (!languages.contains(code)) return;
    final folder = _folder(code, female);
    if (_indexes.containsKey(folder)) return;
    await _loading.putIfAbsent(folder, () async {
      try {
        final raw = await rootBundle
            .loadString('assets/voices/clips/$folder/index.json');
        _indexes[folder] = (jsonDecode(raw) as Map).cast<String, String>();
      } catch (_) {
        // A missing index leaves the matching live voice available.
      } finally {
        _loading.remove(folder);
      }
    });
  }

  /// For tests.
  static void useIndex(String code, Map<String, String> index,
      {bool female = false}) {
    if (code.isEmpty) {
      _indexes.clear();
    } else {
      _indexes[_folder(code, female)] = index;
    }
  }

  static String normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.,!?;:]+|[\s.,!?;:]+$'), '');

  /// Asset paths (relative to assets/) that speak [text] in order, or null
  /// when some word has no recording. Longest phrases are matched first, so
  /// "unë jam i lodhur" plays as one recording.
  static List<String>? clipsFor(String text, String code,
      {bool female = false}) {
    final folder = _folder(code, female);
    final index = _indexes[folder];
    if (index == null || index.isEmpty) return null;
    final whole = index[normalize(text)];
    if (whole != null) return ['voices/clips/$folder/$whole'];
    final words = normalize(text)
        .split(' ')
        .map(normalize)
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return null;
    final clips = <String>[];
    var i = 0;
    while (i < words.length) {
      var found = false;
      for (var n = (words.length - i).clamp(1, 6); n >= 1; n--) {
        final file = index[words.sublist(i, i + n).join(' ')];
        if (file != null) {
          clips.add('voices/clips/$folder/$file');
          i += n;
          found = true;
          break;
        }
      }
      if (!found) return null;
    }
    return clips;
  }
}
