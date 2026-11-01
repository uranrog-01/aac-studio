import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../models/domain.dart';
import '../library/symbol_browser.dart';

/// Settings sheet: speech, display, interaction (P0 accessibility set),
/// scanning, dwell, CVI, feedback, ARASAAC, restrictions, edit mode.
class SettingsSheet extends StatefulWidget {
  final SpeechEngine speech;
  final AppSettings settings;
  final VoidCallback onChanged;
  final SettingsController? settingsController;

  const SettingsSheet({
    super.key,
    required this.speech,
    required this.settings,
    required this.onChanged,
    this.settingsController,
  });

  static Future<void> show(BuildContext context,
      {required SpeechEngine speech,
      required AppSettings settings,
      required VoidCallback onChanged,
      SettingsController? settingsController}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF22262D),
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
          speech: speech,
          settings: settings,
          onChanged: onChanged,
          settingsController: settingsController),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ---- Edit mode (app mode)
          if (widget.settingsController != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: widget.settingsController!.editMode,
              onChanged: (v) async {
                final sc = widget.settingsController!;
                if (v) {
                  final ok = await sc.guardPrivileged(context);
                  if (!ok) return;
                }
                sc.settings.editMode = v;
                await sc.update();
              },
              title: const Text('✏️ Edit mode',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              subtitle: const Text('tap any button on the grid to edit it',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.grid_view, color: Colors.white70),
              title: const Text('🔍 Browse all symbols',
                  style: TextStyle(color: Colors.white70, fontSize: 14)),
              subtitle: const Text('tap to hear a word, add it to your vocabulary',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(builder: (_) => const SymbolBrowser()));
              },
            ),
            const Divider(color: Colors.white12, height: 20),
          ],

          _header('Speech'),
          _slider('Rate', 0.1, 1.0, s.rate, (v) { s.rate = v; _changed(); }),
          _slider('Pitch', 0.5, 2.0, s.pitch, (v) { s.pitch = v; _changed(); }),
          _slider('Volume', 0.0, 1.0, s.volume, (v) { s.volume = v; _changed(); }),
          Row(children: [
            FilledButton.tonal(
              onPressed: () => widget.speech.speak('Hello! This is my voice.',
                  style: VoiceStyle(rate: s.rate, pitch: s.pitch, volume: s.volume)),
              child: const Text('Test voice'),
            ),
            const SizedBox(width: 12),
            TextButton(onPressed: () {
              s.rate = 0.45; s.pitch = 1.0; s.volume = 1.0; _changed();
            }, child: const Text('Reset')),
          ]),

          _header('Display'),
          _choice<ButtonView>('Buttons show', s.buttonView, {
            ButtonView.symbolText: 'Symbol + text',
            ButtonView.symbolOnly: 'Symbol only',
            ButtonView.textOnly: 'Text only',
          }, (v) { s.buttonView = v; _changed(); }),
          _choice<LabelPosition>('Label position', s.labelPosition, {
            LabelPosition.below: 'Below symbol',
            LabelPosition.above: 'Above symbol',
            LabelPosition.hidden: 'Hidden',
          }, (v) { s.labelPosition = v; _changed(); }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.messageWindowTop,
            onChanged: (v) { s.messageWindowTop = v; _changed(); },
            title: const Text('Message window at top',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.cviMode,
            onChanged: (v) { s.cviMode = v; _changed(); },
            title: const Text('👁 CVI high-contrast mode',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            subtitle: const Text(
                'black background, yellow buttons, extra-bold text',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),

          _header('Interaction'),
          _slider('Button debounce', 0, 2000, s.inputDebounceMs.toDouble(),
              (v) { s.inputDebounceMs = v.round(); _changed(); }),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.preventExit,
            onChanged: (v) { s.preventExit = v; _changed(); },
            title: const Text('Prevent exit (kiosk)',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            subtitle: const Text('press back 3× quickly to leave',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.clearOnSpeak,
            onChanged: (v) { s.clearOnSpeak = v; _changed(); },
            title: const Text('Clear message after speaking',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.goHomeOnPress,
            onChanged: (v) { s.goHomeOnPress = v; _changed(); },
            title: const Text('Go Home after speaking a word',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.quietBuilder,
            onChanged: (v) { s.quietBuilder = v; _changed(); },
            title: const Text('Quiet builder (no auto-speak)',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.vocalizeFolders,
            onChanged: (v) { s.vocalizeFolders = v; _changed(); },
            title: const Text('Speak folder name when opened',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),

          _header('Scanning (row-column)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.scanningEnabled,
            onChanged: (v) { s.scanningEnabled = v; _changed(); },
            title: const Text('Enable scanning',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            subtitle: const Text('tap once to pick a row, again to pick a button',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          if (s.scanningEnabled)
            _slider('Scan delay', 400, 4000, s.scanDelayMs.toDouble(),
                (v) { s.scanDelayMs = v.round(); _changed(); }),

          _header('Dwell selection'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.dwellEnabled,
            onChanged: (v) { s.dwellEnabled = v; _changed(); },
            title: const Text('Hold to activate',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          if (s.dwellEnabled)
            _stepper('Hold time', 0.5, 5.0, s.dwellSeconds, 0.5,
                (v) { s.dwellSeconds = v; _changed(); }, 's'),

          _header('Feedback'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.haptics,
            onChanged: (v) { s.haptics = v; _changed(); },
            title: const Text('Vibration on press',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.audioCues,
            onChanged: (v) { s.audioCues = v; _changed(); },
            title: const Text('Click sound on press',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),

          _header('ARASAAC pictograms (online)'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.arasaacEnabled,
            onChanged: (v) { s.arasaacEnabled = v; _changed(); },
            title: const Text('Show ARASAAC results in symbol search',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          if (s.arasaacEnabled) ...[
            _choice<int>('Skin tone', s.arasaacSkin, {
              0: 'Original', 1: 'White', 2: 'Black', 3: 'Asian',
            }, (v) { s.arasaacSkin = v; _changed(); }),
            _choice<int>('Hair', s.arasaacHair, {
              0: 'Original', 1: 'Blond', 2: 'Brown', 3: 'Dark', 4: 'Red', 5: 'Gray',
            }, (v) { s.arasaacHair = v; _changed(); }),
          ],

          const Divider(color: Colors.white12, height: 28),
          // M5 restrictions — PIN defaults to 1234, changeable here
          Row(children: [
            const Icon(Icons.lock_outline, color: Colors.white54, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Restrictions (caregiver lock)',
                  style: TextStyle(color: Colors.white70)),
            ),
            Switch(
              value: s.restrictionsEnabled,
              onChanged: (v) async {
                if (v) {
                  s.restrictionsEnabled = true;
                } else {
                  final ok = await _verifyPin(s.pin);
                  if (!ok) return;
                  s.restrictionsEnabled = false;
                  s.editMode = false;
                }
                _changed();
              },
            ),
          ]),
          Row(children: [
            const SizedBox(width: 26),
            Text('Edit-mode code: ${s.pin}',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(width: 12),
            TextButton.icon(
              onPressed: () async {
                final pin = await _askPin('Set a new 4-digit code', current: s.pin);
                if (pin == null) return;
                s.pin = pin;
                _changed();
              },
              icon: const Icon(Icons.password, size: 16),
              label: const Text('Change code'),
            ),
          ]),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                color: Colors.deepOrangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1)),
      );

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Widget _slider(String label, double min, double max, double value,
      ValueChanged<double> onChanged, {String? labelOverride}) {
    return Row(children: [
      SizedBox(
          width: 96,
          child: Text(label, style: const TextStyle(color: Colors.white54))),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: (max - min) < 10 ? 40 : 40,
          label: labelOverride ?? value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
      ),
    ]);
  }

  Widget _stepper(String label, double min, double max, double value,
      double step, ValueChanged<double> onChanged, String suffix) {
    return Row(children: [
      SizedBox(width: 96, child: Text(label, style: const TextStyle(color: Colors.white54))),
      IconButton(
          onPressed: value > min ? () => onChanged((value - step)) : null,
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white70)),
      Text('${value.toStringAsFixed(1)} $suffix',
          style: const TextStyle(color: Colors.white, fontSize: 14)),
      IconButton(
          onPressed: value < max ? () => onChanged((value + step)) : null,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70)),
    ]);
  }

  Widget _choice<T>(String label, T current, Map<T, String> options,
      ValueChanged<T> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text(label, style: const TextStyle(color: Colors.white54)),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in options.entries)
            InkWell(
              onTap: () => onChanged(e.key),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: current == e.key
                      ? Colors.deepOrangeAccent.withValues(alpha: .3)
                      : const Color(0xFF31383F),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: current == e.key
                          ? Colors.deepOrangeAccent
                          : Colors.white12),
                ),
                child: Text(e.value,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ),
        ],
      ),
    ]);
  }

  Future<String?> _askPin(String title, {String? current}) async {
    final c = TextEditingController(text: current ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2E35),
        title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: '••••'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    if (ok != true) return null;
    return (c.text.length == 4) ? c.text : null;
  }

  Future<bool> _verifyPin(String correct) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A2E35),
        title: const Text('Enter PIN',
            style: TextStyle(color: Colors.white, fontSize: 16)),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('OK')),
        ],
      ),
    );
    return ok == true && c.text == correct;
  }
}
