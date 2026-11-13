import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../engine/i18n.dart';

/// Displays a snapshot of the draft so it can be read or spoken repeatedly.
Future<void> showMessage(
    BuildContext context, String message, ValueChanged<String> onSpeak) async {
  final text = message.trim();
  if (text.isEmpty) return;
  await Navigator.of(context, rootNavigator: true).push<void>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _MessageDisplay(text: text, onSpeak: () => onSpeak(text)),
  ));
}

class _MessageDisplay extends StatelessWidget {
  final String text;
  final VoidCallback onSpeak;

  const _MessageDisplay({required this.text, required this.onSpeak});

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: LayoutBuilder(builder: (context, constraints) {
                final fontSize = math
                    .min(
                      constraints.maxWidth / 6,
                      constraints.maxHeight / 3,
                    )
                    .clamp(36.0, 112.0);
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints:
                        BoxConstraints(minHeight: constraints.maxHeight),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: Text(
                          text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Row(children: [
              Expanded(
                child: FilledButton(
                  autofocus: true,
                  onPressed: () => Navigator.of(context).pop(),
                  style: _buttonStyle(
                      const Color(0xFFE9EDF2), const Color(0xFF172231)),
                  child: Text(I18n.t('Close'),
                      style: labelStyle, textAlign: TextAlign.center),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onSpeak,
                  style: _buttonStyle(const Color(0xFF205C33), Colors.white),
                  child: Text(I18n.t('Speak'),
                      style: labelStyle, textAlign: TextAlign.center),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  ButtonStyle _buttonStyle(Color background, Color foreground) =>
      FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        minimumSize: const Size(0, 64),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      );
}

/// Saved phrases and the last spoken messages, one tap to use again.
class PhrasesSheet {
  static Future<void> show(
    BuildContext context, {
    required String message,
    required List<String> phrases,
    required List<String> recent,
    required void Function(String phrase) onPick,
    required void Function(String phrase) onSave,
    required void Function(String phrase) onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF22262D),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, setState) {
        final canSave =
            message.trim().isNotEmpty && !phrases.contains(message.trim());
        Widget tile(String phrase, {bool saved = false}) => Card(
              color: const Color(0xFF2C313A),
              child: ListTile(
                title: Text(phrase,
                    style: const TextStyle(color: Colors.white, fontSize: 18)),
                leading: Icon(saved ? Icons.star : Icons.history,
                    color: saved ? Colors.amber : Colors.white54),
                trailing: saved
                    ? IconButton(
                        tooltip: I18n.t('Delete'),
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.white54),
                        onPressed: () {
                          onDelete(phrase);
                          setState(() => phrases.remove(phrase));
                        })
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onPick(phrase);
                },
              ),
            );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .7,
          maxChildSize: .95,
          builder: (context, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Text(I18n.t('Phrases'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (canSave)
                FilledButton.icon(
                  onPressed: () {
                    onSave(message.trim());
                    setState(() => phrases.insert(0, message.trim()));
                  },
                  icon: const Icon(Icons.star_border),
                  label: Text(I18n.t('Save this message')),
                ),
              const SizedBox(height: 8),
              if (phrases.isEmpty)
                Text(
                    I18n.t('No saved phrases yet. Write a message, then tap '
                        'Save this message.'),
                    style: const TextStyle(color: Colors.white60)),
              for (final p in List.of(phrases)) tile(p, saved: true),
              if (recent.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(I18n.t('Recent messages'),
                    style: const TextStyle(color: Colors.white70, fontSize: 15)),
                for (final r in recent) tile(r),
              ],
            ],
          ),
        );
      }),
    );
  }
}
