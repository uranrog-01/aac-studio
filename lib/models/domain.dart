/// Domain model — original AAC Studio model, informed by the P2G 2.3 study.
///
/// Mirrors the studied concepts (vocabulary → folder → view → element →
/// button(+actions), display styles, word classes) with original naming.
library;

import 'dart:ui' show Color;

import '../engine/i18n.dart';

/// Word classes (studied: 19 kAWSpeakableItemKind categories).
enum WordClass {
  other,
  adjective,
  adverb,
  article,
  noun,
  pronoun,
  verb,
  preposition,
  conjunction,
  number,
  interjection,
  properNoun,
  phrase,
  letter,
  punctuation,
  question,
  social,
  unknown;

  static WordClass fromName(String? n) => WordClass.values.firstWhere(
        (w) => w.name.toLowerCase() == (n ?? '').toLowerCase(),
        orElse: () => WordClass.unknown,
      );
}

/// Modified Fitzgerald Key (Goossens, Crain & Elder 1992) — the color system
/// used by mainstream AAC vocabularies (Super Core, Avaz, …):
/// yellow=pronouns, green=verbs, orange=nouns, blue=descriptors,
/// pink=social, white=prepositions/conjunctions, purple=questions.
/// Consistency across the vocabulary supports motor planning for minimally
/// verbal autistic learners.
const Map<WordClass, Color> kWordClassColors = {
  WordClass.pronoun: Color(0xFFFFF176), // yellow — pronouns
  WordClass.verb: Color(0xFF81C784), // green — verbs
  WordClass.noun: Color(0xFFFFB74D), // orange — nouns
  WordClass.properNoun: Color(0xFFFFB74D), // orange — nouns
  WordClass.adjective: Color(0xFF64B5F6), // blue — descriptors
  WordClass.adverb: Color(0xFF64B5F6), // blue — descriptors
  WordClass.social: Color(0xFFF8BBD0), // pink — social words
  WordClass.interjection: Color(0xFFF8BBD0), // pink — social
  WordClass.question: Color(0xFFCE93D8), // purple — questions
  WordClass.preposition: Color(0xFFF5F5F5), // white — the rest of speech
  WordClass.conjunction: Color(0xFFF5F5F5),
  WordClass.article: Color(0xFFF5F5F5),
  WordClass.number: Color(0xFFF5F5F5),
  WordClass.phrase: Color(0xFFFFE0B2), // light orange — phrases
  WordClass.other: Color(0xFFEEEEEE),
  WordClass.letter: Color(0xFFEEEEEE),
  WordClass.punctuation: Color(0xFFEEEEEE),
  WordClass.unknown: Color(0xFFEEEEEE),
};

/// Action verbs behind buttons (studied: 18 P2G action types) + our sensory
/// games extension (autism regulation feature).
enum ActionKind {
  addText,
  speakNow,
  speakMessage,
  clearMessage,
  gotoFolder,
  launchUrl,
  sensoryGames
}

class VocabAction {
  final ActionKind kind;

  /// Text for addText/speakNow; folder id (as int-as-string) for gotoFolder;
  /// URL for launchUrl.
  final String data;
  const VocabAction(this.kind, {this.data = ''});
}

/// M3: optional per-button voice override (null = app default).
class VoiceStyle {
  final double? rate;
  final double? pitch;
  final double? volume;
  const VoiceStyle({this.rate, this.pitch, this.volume});

  VoiceStyle copyWith(
          {double? rate, double? pitch, double? volume, bool clear = false}) =>
      VoiceStyle(
        rate: clear ? null : rate ?? this.rate,
        pitch: clear ? null : pitch ?? this.pitch,
        volume: clear ? null : volume ?? this.volume,
      );

  Map<String, dynamic> toJson() => {
        if (rate != null) 'rate': rate,
        if (pitch != null) 'pitch': pitch,
        if (volume != null) 'volume': volume,
      };

  static VoiceStyle? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : VoiceStyle(
          rate: (j['rate'] as num?)?.toDouble(),
          pitch: (j['pitch'] as num?)?.toDouble(),
          volume: (j['volume'] as num?)?.toDouble(),
        );
}

/// What a button shows.
class SymbolRef {
  /// Emoji, or key resolved by a symbol provider (PNG path in explorer mode).
  final String emoji;
  final String? imagePath; // absolute file path (explorer PNG symbols)
  /// Bundled open symbol pack: 'twemoji' | 'noto' | 'openmoji' | 'mulberry'.
  final String? pack;

  /// Key within the pack (codepoint hex for emoji packs, filename for mulberry).
  final String? key;
  const SymbolRef(this.emoji, {this.imagePath, this.pack, this.key});

  Map<String, dynamic> toJson() => {
        'emoji': emoji,
        if (imagePath != null) 'imagePath': imagePath,
        if (pack != null) 'pack': pack,
        if (key != null) 'key': key,
      };

  static SymbolRef fromJson(Map<String, dynamic>? j) => j == null
      ? const SymbolRef('⬛')
      : SymbolRef((j['emoji'] ?? '⬛') as String,
          imagePath: j['imagePath'] as String?,
          pack: j['pack'] as String?,
          key: j['key'] as String?);
}

class VocabButton {
  final String id;
  final String label; // displayed + default spoken text
  final String? spokenText; // overrides label for the message window
  final ButtonKind kind;
  final WordClass wordClass;
  final SymbolRef symbol;
  final List<VocabAction> actions;
  final VoiceStyle? voice;
  final bool favorite;
  final bool userEdited;
  const VocabButton({
    required this.id,
    required this.label,
    required this.kind,
    required this.wordClass,
    required this.symbol,
    this.spokenText,
    this.actions = const [],
    this.voice,
    this.favorite = false,
    this.userEdited = false,
  });

  /// The label in the chosen app language (the board keeps English).
  String get shownLabel =>
      // Letters and numbers stay as they are (the letter "I" is not the
      // word "I"); the voice reads them in the chosen language.
      wordClass == WordClass.letter || wordClass == WordClass.number
          ? label
          : I18n.word(label);

  String get speakText =>
      (spokenText != null && spokenText!.isNotEmpty) ? spokenText! : shownLabel;

  /// Text an addText action adds: the button's own word follows the
  /// chosen language; custom text stays as written.
  String textFor(VocabAction a) =>
      a.data.isEmpty || a.data == label ? speakText : a.data;

  VocabButton copyWith({
    String? label,
    String? spokenText,
    WordClass? wordClass,
    SymbolRef? symbol,
    List<VocabAction>? actions,
    VoiceStyle? voice,
    bool clearVoice = false,
    bool? favorite,
    bool? userEdited,
  }) =>
      VocabButton(
        id: id,
        label: label ?? this.label,
        spokenText: spokenText ?? this.spokenText,
        kind: kind,
        wordClass: wordClass ?? this.wordClass,
        symbol: symbol ?? this.symbol,
        actions: actions ?? this.actions,
        voice: clearVoice ? null : voice ?? this.voice,
        favorite: favorite ?? this.favorite,
        userEdited: userEdited ?? this.userEdited,
      );
}

enum ButtonKind { item, folder, action }

/// One grid: ordered cells (column grid system, studied gridsystemtype 1)
/// or explicit positions (pixel grid, studied type 2).
class VocabView {
  final String id;
  final String folderId;
  final int columns; // column_grid width; 0 = auto
  final List<GridCell> cells;
  const VocabView(
      {required this.id,
      required this.folderId,
      required this.columns,
      required this.cells});
}

class GridCell {
  final VocabButton button;
  final int? col; // 1-based explicit position (pixel grid)
  final int? row;
  final int span; // cells wide (default 1)
  final bool hidden;
  final bool dimmed;
  const GridCell(this.button,
      {this.col,
      this.row,
      this.span = 1,
      this.hidden = false,
      this.dimmed = false});
}

class VocabFolder {
  final String id;
  final String label;
  final SymbolRef symbol;
  const VocabFolder(this.id, this.label, this.symbol);
}

class Vocabulary {
  final String id;
  final String label;
  final String rootFolderId;
  final Map<String, VocabFolder> folders;
  final Map<String, List<VocabView>> viewsByFolder; // in priority order
  final Set<String> removedIds;

  /// Version of the board file this was read from (null: not a pack file).
  /// Saved back unchanged, so a board is only marked as upgraded by the
  /// upgrade itself, never by the app's own version number.
  final int? packVersion;
  Vocabulary({
    required this.id,
    required this.label,
    required this.rootFolderId,
    required this.folders,
    required this.viewsByFolder,
    Set<String>? removedIds,
    this.packVersion,
  }) : removedIds = removedIds ?? <String>{};

  VocabFolder? folderOf(String id) => folders[id];
}
