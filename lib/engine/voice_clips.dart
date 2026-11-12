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

  static String _folder = '';

  static String _code = '';
  static Map<String, String> _index = const {};

  static bool get available => _index.isNotEmpty;

  /// Loads the recordings list for [code] (empty for other languages),
  /// the female set when [female] is asked for and the language has one.
  static Future<void> load(String code, {bool female = false}) async {
    final folder = !languages.contains(code)
        ? ''
        : female && femaleLanguages.contains(code)
            ? '$code-f'
            : code;
    if (code == _code && folder == _folder) return;
    _code = code;
    _folder = folder;
    _index = const {};
    if (folder.isEmpty) return;
    try {
      final raw = await rootBundle
          .loadString('assets/voices/clips/$folder/index.json');
      final index = (jsonDecode(raw) as Map).cast<String, String>();
      if (_folder == folder) _index = index;
    } catch (_) {/* No recordings: the device voice speaks. */}
  }

  /// For tests.
  static void useIndex(String code, Map<String, String> index) {
    _code = code;
    _folder = code;
    _index = index;
  }

  static String normalize(String text) => text
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.,!?;:]+|[\s.,!?;:]+$'), '');

  /// Asset paths (relative to assets/) that speak [text] in order, or null
  /// when some word has no recording. Longest phrases are matched first, so
  /// "unë jam i lodhur" plays as one recording.
  static List<String>? clipsFor(String text) {
    if (_index.isEmpty) return null;
    final whole = _index[normalize(text)];
    if (whole != null) return ['voices/clips/$_folder/$whole'];
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
        final file = _index[words.sublist(i, i + n).join(' ')];
        if (file != null) {
          clips.add('voices/clips/$_folder/$file');
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
