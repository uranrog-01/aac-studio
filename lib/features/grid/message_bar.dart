import 'package:flutter/material.dart';

import '../../engine/i18n.dart';

/// The white message box shared by Home and Type: tap it to hear the whole
/// message (again), and the red button on its right removes the last word.
class MessageBar extends StatelessWidget {
  final String message;
  final String placeholder;
  final VoidCallback onSpeak;
  final VoidCallback onDeleteWord;
  final VoidCallback? onShow;

  /// Switch scanning: 0 none, 1 its group is highlighted, 2 it is selected.
  final int deleteHighlight;

  /// Shows a typing cursor after the text (Type screen).
  final bool showCursor;

  const MessageBar({
    super.key,
    required this.message,
    required this.placeholder,
    required this.onSpeak,
    required this.onDeleteWord,
    this.onShow,
    this.deleteHighlight = 0,
    this.showCursor = false,
  });

  @override
  Widget build(BuildContext context) {
    final canDelete = message.trim().isNotEmpty;
    final show = canDelete ? onShow : null;
    const style = TextStyle(fontSize: 22, color: Colors.black87);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      // Lets the delete button take the full height of the message text.
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Semantics(
              button: true,
              label: I18n.t('Speak message'),
              value: message,
              excludeSemantics: true,
              child: InkWell(
                onTap: onSpeak,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 72),
                  padding: const EdgeInsets.all(16),
                  alignment: Alignment.centerLeft,
                  child: message.isEmpty
                      ? Text(I18n.t(placeholder),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: style.copyWith(
                              color: showCursor
                                  ? Colors.black45
                                  : Colors.black87))
                      : Text.rich(
                          TextSpan(text: message, children: [
                            if (showCursor)
                              const TextSpan(
                                  text: '|',
                                  style: TextStyle(
                                      color: Color(0xFF1E88E5),
                                      fontWeight: FontWeight.w300)),
                          ]),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: style),
                ),
              ),
            ),
          ),
          if (onShow != null)
            SizedBox(
              width: 64,
              child: Semantics(
                button: true,
                label: I18n.t('Show message'),
                enabled: show != null,
                onTap: show,
                excludeSemantics: true,
                child: Tooltip(
                  message: I18n.t('Show message'),
                  child: TextButton(
                    onPressed: show,
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFE4EFFA),
                      foregroundColor: const Color(0xFF153E68),
                      disabledBackgroundColor: const Color(0xFFF4F6F8),
                      disabledForegroundColor: const Color(0xFF65717D),
                      padding: const EdgeInsets.all(4),
                      shape: const RoundedRectangleBorder(),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.fit_screen, size: 22),
                      const SizedBox(height: 2),
                      Text(I18n.t('Show'),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                ),
              ),
            ),
          Semantics(
            button: true,
            label: I18n.t('Delete last word'),
            enabled: canDelete,
            excludeSemantics: true,
            child: InkWell(
              onTap: canDelete ? onDeleteWord : null,
              child: Container(
                width: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFEBEE),
                  border: deleteHighlight == 0
                      ? null
                      : Border.all(
                          width: 4,
                          color: deleteHighlight == 2
                              ? Colors.lightBlueAccent
                              : Colors.lightGreen),
                ),
                child: Opacity(
                  opacity: canDelete ? 1 : .35,
                  child: const Icon(Icons.backspace_outlined,
                      size: 34, color: Color(0xFFC62828)),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// One large toolbar control (Back, Home, Type, Speak, Clear, More).
class ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final bool active;
  final int scanHighlight;

  const ToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.color,
    this.active = false,
    this.scanHighlight = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Semantics(
          button: true,
          label: I18n.t(label),
          enabled: onTap != null,
          excludeSemantics: true,
          child: Material(
            color: active
                ? Colors.deepOrangeAccent.withValues(alpha: .35)
                : (color ?? const Color(0xFF3A4049)),
            borderRadius: BorderRadius.circular(12),
            shape: scanHighlight == 0
                ? null
                : RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        width: 4,
                        color: scanHighlight == 2
                            ? Colors.lightBlueAccent
                            : Colors.lightGreen)),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(12),
              child: Opacity(
                opacity: onTap == null ? .4 : 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: Colors.white, size: 26),
                    FittedBox(
                      child: Text(I18n.t(label),
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
