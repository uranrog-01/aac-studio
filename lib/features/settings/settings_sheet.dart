import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../models/domain.dart';

/// M3 + M5 settings sheet: speech defaults (rate/pitch/volume) and the
/// restrictions lock (PIN-gated edit mode).
class SettingsSheet extends StatefulWidget {
  final SpeechEngine speech;
  final AppSettings settings;
  final VoidCallback onChanged;

  const SettingsSheet({
    super.key,
    required this.speech,
    required this.settings,
    required this.onChanged,
  });

  static Future<void> show(BuildContext context,
      {required SpeechEngine speech,
      required AppSettings settings,
      required VoidCallback onChanged}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF22262D),
      isScrollControlled: true,
      builder: (_) => SettingsSheet(
          speech: speech, settings: settings, onChanged: onChanged),
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
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Speech settings',
              style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          _slider('Rate', 0.1, 1.0, s.rate,
              (v) { s.rate = v; _changed(); }),
          _slider('Pitch', 0.5, 2.0, s.pitch,
              (v) { s.pitch = v; _changed(); }),
          _slider('Volume', 0.0, 1.0, s.volume,
              (v) { s.volume = v; _changed(); }),
          Row(children: [
            FilledButton.tonal(
              onPressed: () =>
                  widget.speech.speak('Hello! This is my voice.',
                      style: VoiceStyle(rate: s.rate, pitch: s.pitch, volume: s.volume)),
              child: const Text('Test voice'),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () {
                s.rate = 0.45; s.pitch = 1.0; s.volume = 1.0;
                _changed();
              },
              child: const Text('Reset'),
            ),
          ]),
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
                final pin = await _askPin('Set a new 4-digit code',
                    current: s.pin);
                if (pin == null) return;
                s.pin = pin;
                _changed();
              },
              icon: const Icon(Icons.password, size: 16),
              label: const Text('Change code'),
            ),
          ]),
          if (s.restrictionsEnabled)
            const Padding(
              padding: EdgeInsets.only(left: 26),
              child: Text(
                  'Edit mode and turning restrictions off now require the code.',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ),
          const SizedBox(height: 10),
        ]),
      ),
    );
  }

  void _changed() {
    setState(() {});
    widget.onChanged();
  }

  Widget _slider(String label, double min, double max, double value,
      ValueChanged<double> onChanged) {
    return Row(children: [
      SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(color: Colors.white54))),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: 40,
          label: value.toStringAsFixed(2),
          onChanged: onChanged,
        ),
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
