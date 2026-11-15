import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../engine/i18n.dart';
import '../../engine/settings_controller.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';
import '../grid/grid_screen.dart';
import 'listen_screen.dart';
import 'pain_screen.dart';
import 'scenes_screen.dart';
import 'schedule_screen.dart';

export 'report_screen.dart';

/// The tool screens a board button (ActionKind.openTool) or More opens.
class ToolScreens {
  static const names = ['schedule', 'firstthen', 'timer', 'pain', 'scenes', 'listen'];

  static Widget build(String tool, GridSession session, SymbolLibrary? library) {
    switch (tool) {
      case 'pain':
        return PainScreen(session: session);
      case 'scenes':
        return ScenesScreen(session: session);
      case 'listen':
        return ListenScreen(session: session);
      case 'firstthen':
        return ScheduleScreen(session: session, initialTab: 1);
      case 'timer':
        return ScheduleScreen(session: session, initialTab: 2);
      case 'schedule':
      default:
        return ScheduleScreen(session: session);
    }
  }
}

/// Shares text with another app (Messages, WhatsApp, email, notes).
Future<void> shareText(String text, {String? subject}) async {
  if (text.trim().isEmpty) return;
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  } catch (_) {
    // Nothing to share with on this device; the message stays as it is.
  }
}

/// Dark page frame shared by the tools: a big title and a close button.
class ToolPage extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;
  const ToolPage(
      {super.key,
      required this.title,
      required this.body,
      this.actions = const [],
      this.bottom});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2B2F36),
      appBar: AppBar(
        backgroundColor: const Color(0xFF22262D),
        foregroundColor: Colors.white,
        title: Text(I18n.t(title)),
        actions: actions,
        bottom: bottom,
      ),
      body: SafeArea(child: body),
    );
  }
}

/// A big picture card for a board word.
class WordCard extends StatelessWidget {
  final VocabButton button;
  final double size;
  final bool highlight;
  final bool done;
  final VoidCallback? onTap;
  const WordCard(
      {super.key,
      required this.button,
      this.size = 120,
      this.highlight = false,
      this.done = false,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = kWordClassColors[button.wordClass] ?? const Color(0xFFEEEEEE);
    return Opacity(
      opacity: done ? 0.45 : 1,
      child: Material(
        color: button.kind == ButtonKind.folder ? const Color(0xFFFFF3C4) : bg,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            width: size,
            height: size * 1.12,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: highlight ? const Color(0xFFFFB300) : Colors.black26,
                  width: highlight ? 6 : 1),
            ),
            child: Stack(children: [
              Column(children: [
                Expanded(
                  child: LayoutBuilder(
                      builder: (_, c) => SymbolLibrary.resolve(button.symbol,
                          size: c.biggest.shortestSide)),
                ),
                Text(button.shownLabel,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: size > 110 ? 17 : 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87)),
              ]),
              if (done)
                const Positioned(
                    right: 0,
                    top: 0,
                    child: Icon(Icons.check_circle,
                        color: Color(0xFF2E7D32), size: 30)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Finds a board button by id anywhere on the board.
VocabButton? buttonById(Vocabulary vocabulary, String id) {
  for (final views in vocabulary.viewsByFolder.values) {
    for (final view in views) {
      for (final c in view.cells) {
        if (c.button.id == id) return c.button;
      }
    }
  }
  return null;
}

/// Lets a caregiver pick a word (with its picture) from the board.
Future<VocabButton?> pickBoardWord(BuildContext context, GridSession session,
    {String title = 'Choose a word'}) {
  return showDialog<VocabButton>(
    context: context,
    builder: (context) => _WordPicker(session: session, title: title),
  );
}

class _WordPicker extends StatefulWidget {
  final GridSession session;
  final String title;
  const _WordPicker({required this.session, required this.title});

  @override
  State<_WordPicker> createState() => _WordPickerState();
}

class _WordPickerState extends State<_WordPicker> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim();
    final results = q.isEmpty
        ? [
            for (final w in const [
              'breakfast', 'lunch', 'dinner', 'school', 'toilet', 'bath',
              'brush teeth', 'get dressed', 'play', 'tv', 'park', 'sleep',
              'car', 'bus', 'snack', 'music', 'book', 'outside', 'home',
              'doctor', 'shop', 'tablet', 'walk', 'swim',
            ])
              if (widget.session.buttonForLabel(w) != null)
                widget.session.buttonForLabel(w)!,
          ]
        : [
            for (final r in widget.session.findWords(q, limit: 40))
              if (r.button.kind == ButtonKind.item) r.button,
          ];
    return Dialog(
      backgroundColor: const Color(0xFF22262D),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 640,
        height: 560,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text(I18n.t(widget.title),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _query,
              autofocus: false,
              style: const TextStyle(color: Colors.white, fontSize: 17),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                hintText: I18n.t('Find a word'),
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF2B2F36),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: GridView.extent(
              maxCrossAxisExtent: 110,
              padding: const EdgeInsets.all(12),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.88,
              children: [
                for (final b in results)
                  WordCard(
                      button: b,
                      size: 100,
                      onTap: () => Navigator.pop(context, b)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Caregiver changes in the tools ask for the code when the app is
/// locked or restricted.
Future<bool> caregiverAllowed(BuildContext context) async {
  final sc = context.read<SettingsController>();
  if (sc.restrictionsEnabled || sc.settings.lockApp) {
    return sc.guardPrivileged(context);
  }
  return true;
}
