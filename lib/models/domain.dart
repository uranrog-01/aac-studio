/// Domain model — original AAC Studio model, informed by the P2G 2.3 study.
///
/// Mirrors the studied concepts (vocabulary → folder → view → element →
/// button(+actions), display styles, word classes) with original naming.
library;

import 'dart:ui' show Color;

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
        (w) => w.name == (n ?? '').toLowerCase(),
        orElse: () => WordClass.unknown,
      );
}

/// Approximate P2G-style color coding per word class (study approximation).
const Map<WordClass, Color> kWordClassColors = {
  WordClass.pronoun: Color(0xFFFFFF66), // yellow
  WordClass.verb: Color(0xFF66DD66), // green
  WordClass.noun: Color(0xFFFF9955), // orange
  WordClass.adjective: Color(0xFF5599FF), // blue
  WordClass.adverb: Color(0xFFCC99FF), // purple
  WordClass.social: Color(0xFFFF6666), // red
  WordClass.question: Color(0xFF66EEEE), // cyan
  WordClass.preposition: Color(0xFF88CC66), // lime
  WordClass.article: Color(0xFFCCCCCC), // gray
  WordClass.conjunction: Color(0xFFDD9955), // tan
  WordClass.number: Color(0xFF44DDAA), // teal
  WordClass.interjection: Color(0xFFFFAA88), // peach
  WordClass.other: Color(0xFFEEEEEE),
  WordClass.unknown: Color(0xFFEEEEEE),
  WordClass.phrase: Color(0xFFEEEEEE),
  WordClass.letter: Color(0xFFEEEEEE),
  WordClass.punctuation: Color(0xFFEEEEEE),
  WordClass.properNoun: Color(0xFFEEEEEE),
};

/// Action verbs behind buttons (studied: 18 P2G action types).
enum ActionKind { addText, speakNow, speakMessage, clearMessage, gotoFolder, launchUrl }

class VocabAction {
  final ActionKind kind;
  /// Text for addText/speakNow; folder id (as int-as-string) for gotoFolder;
  /// URL for launchUrl.
  final String data;
  const VocabAction(this.kind, {this.data = ''});
}

/// What a button shows.
class SymbolRef {
  /// Emoji, or key resolved by a symbol provider (PNG path in explorer mode).
  final String emoji;
  final String? imagePath; // absolute file path (explorer PNG symbols)
  const SymbolRef(this.emoji, {this.imagePath});
}

class VocabButton {
  final String id;
  final String label; // displayed + default spoken text
  final String? spokenText; // overrides label for the message window
  final ButtonKind kind;
  final WordClass wordClass;
  final SymbolRef symbol;
  final List<VocabAction> actions;
  const VocabButton({
    required this.id,
    required this.label,
    required this.kind,
    required this.wordClass,
    required this.symbol,
    this.spokenText,
    this.actions = const [],
  });

  String get speakText => (spokenText != null && spokenText!.isNotEmpty) ? spokenText! : label;
}

enum ButtonKind { item, folder, action }

/// One grid: ordered cells (column grid system, studied gridsystemtype 1)
/// or explicit positions (pixel grid, studied type 2).
class VocabView {
  final String id;
  final String folderId;
  final int columns; // column_grid width; 0 = auto
  final List<GridCell> cells;
  const VocabView({required this.id, required this.folderId, required this.columns, required this.cells});
}

class GridCell {
  final VocabButton button;
  final int? col; // 1-based explicit position (pixel grid)
  final int? row;
  final int span; // cells wide (default 1)
  final bool hidden;
  final bool dimmed;
  const GridCell(this.button, {this.col, this.row, this.span = 1, this.hidden = false, this.dimmed = false});
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
  const Vocabulary({
    required this.id,
    required this.label,
    required this.rootFolderId,
    required this.folders,
    required this.viewsByFolder,
  });

  VocabFolder? folderOf(String id) => folders[id];
}
