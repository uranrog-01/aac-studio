import 'package:flutter/material.dart';

import '../../engine/i18n.dart';

/// Shows the message full screen in very large letters, to show someone
/// (a shop, a doctor, a noisy place). "Turn around" flips it for the person
/// sitting opposite; tapping the text speaks it.
Future<void> showBigMessage(
    BuildContext context, String message, VoidCallback onSpeak) {
  return Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _BigMessage(message: message, onSpeak: onSpeak),
  ));
}

class _BigMessage extends StatefulWidget {
  final String message;
  final VoidCallback onSpeak;
  const _BigMessage({required this.message, required this.onSpeak});
  @override
  State<_BigMessage> createState() => _BigMessageState();
}

class _BigMessageState extends State<_BigMessage> {
  bool _flipped = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.message.trim().isEmpty ? '…' : widget.message.trim();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: Semantics(
              button: true,
              label: I18n.t('Speak message'),
              value: text,
              excludeSemantics: true,
              child: InkWell(
                onTap: widget.onSpeak,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: _flipped ? 2 : 0,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 900),
                          child: Text(text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 96,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: _bigButton(Icons.close, I18n.t('Back'),
                    () => Navigator.of(context).pop(), const Color(0xFF3A4049)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigButton(
                    Icons.screen_rotation_alt,
                    I18n.t('Turn around'),
                    () => setState(() => _flipped = !_flipped),
                    const Color(0xFF1565C0)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bigButton(Icons.volume_up, I18n.t('Speak'),
                    widget.onSpeak, const Color(0xFF2E7D32)),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _bigButton(
          IconData icon, String label, VoidCallback onTap, Color color) =>
      SizedBox(
        height: 64,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: color,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12))),
          onPressed: onTap,
          icon: Icon(icon),
          label: FittedBox(child: Text(label)),
        ),
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
