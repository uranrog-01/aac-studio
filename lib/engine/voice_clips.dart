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

  static String _code = '';
  static Map<String, String> _index = const {};

  static bool get available => _index.isNotEmpty;

  /// Loads the recordings list for [code] (empty for other languages).
  static Future<void> load(String code) async {
    if (code == _code) return;
    _code = code;
    _index = const {};
    if (!languages.contains(code)) return;
    try {
      final raw = await rootBundle
          .loadString('assets/voices/clips/$code/index.json');
      final index = (jsonDecode(raw) as Map).cast<String, String>();
      if (_code == code) _index = index;
    } catch (_) {/* No recordings: the device voice speaks. */}
  }

  /// For tests.
  static void useIndex(String code, Map<String, String> index) {
    _code = code;
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
    if (whole != null) return ['voices/clips/$_code/$whole'];
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
          clips.add('voices/clips/$_code/$file');
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
