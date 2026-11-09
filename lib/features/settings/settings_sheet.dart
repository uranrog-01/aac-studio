import 'package:flutter/foundation.dart';
import '../web/web_tools.dart';
import 'backup_tools.dart';
import 'package:flutter/material.dart';

import '../../engine/i18n.dart';
import '../../engine/screen_mode.dart';
import 'package:flutter/services.dart';

import '../../engine/settings_controller.dart';
import '../../engine/speech.dart';
import '../../engine/storage.dart';
import '../../models/domain.dart';
import '../library/symbol_browser.dart';

/// Settings sheet in five plain-language groups: Voice, When a button is
/// tapped, Buttons & screen, Access, Caregiver. Only Voice starts open.
class SettingsSheet extends StatefulWidget {
  final SpeechEngine speech;
  final AppSettings settings;
  final VoidCallback onChanged;
  final SettingsController? settingsController;
  final ScrollController? scrollController;

  const SettingsSheet({
    super.key,
    required this.speech,
    required this.settings,
    required this.onChanged,
    this.settingsController,
    this.scrollController,
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
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .85,
        maxChildSize: .95,
        builder: (_, controller) => SettingsSheet(
            speech: speech,
            settings: settings,
            onChanged: onChanged,
            settingsController: settingsController,
            scrollController: controller),
      ),
    );
  }

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  static const _sample = 'Hello! This is my voice.';

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    final iOS = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
              child: Text(I18n.t('Settings'),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
              child: Text(I18n.t('Changes are saved automatically.'),
                  style: const TextStyle(color: Colors.white54, fontSize: 13)),
            ),
            // 1. Language & voice: what the person hears.
            _group(Icons.record_voice_over, 'Language & voice',
                'Language, voice, speed and loudness',
                initiallyExpanded: true,
                children: [
                  _languagePicker(),
                  _voiceStatus(),
                  const Divider(color: Colors.white12, height: 24),
                  _VoicePicker(
                      speech: widget.speech,
                      settings: s,
                      onPicked: () {
                        _changed();
                        _test();
                      }),
                  ValueListenableBuilder<String>(
                    valueListenable: widget.speech.status,
                    builder: (context, status, _) => Padding(
                      padding: const EdgeInsets.only(top: 6, bottom: 4),
                      child: Text(status,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                    ),
                  ),
                  _slider('Speed', 'Slow', 'Fast', 0.1, 1.0, s.rate, (v) {
                    s.rate = v;
                    _changed();
                  }),
                  _slider('Volume', 'Quiet', 'Loud', 0.0, 1.0, s.volume, (v) {
                    s.volume = v;
                    _changed();
                  }),
                  _slider('Pitch', 'Low', 'High', 0.5, 2.0, s.pitch, (v) {
                    s.pitch = v;
                    _changed();
                  }),
                  if (s.usePiper && s.pitch != 1.0)
                    Text(
                        I18n.t('The offline voice cannot change pitch, so the '
                            'device voice is used while pitch is not in the '
                            'middle.'),
                        style: const TextStyle(
                            color: Colors.amberAccent, fontSize: 12)),
                  Wrap(spacing: 8, children: [
                    FilledButton.icon(
                      onPressed: _test,
                      icon: const Icon(Icons.play_arrow),
                      label: Text(I18n.t('Test voice')),
                    ),
                    TextButton(
                        onPressed: () {
                          s.rate = 0.45;
                          s.pitch = 1.0;
                          s.volume = 1.0;
                          _changed();
                        },
                        child: Text(I18n.t('Reset speed, pitch, volume'))),
                    if (s.usePiper)
                      TextButton(
                          onPressed: () => widget.speech.warmOfflineVoice(),
                          child: Text(I18n.t('Retry offline voice'))),
                  ]),
                  if (iOS)
                    _switch(
                        'Speak into phone and FaceTime calls',
                        s.callSpeech,
                        (v) => s.callSpeech = v,
                        'The other person hears the voice. Start the call, '
                            'then open AAC Studio (iOS 13 or newer).'),
                  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
                    _note('During a phone call, turn on the speakerphone so '
                        'the other person hears the voice. Android does not '
                        'let apps speak into calls directly.'),
                ]),
            // 2. Speaking: when the voice talks.
            _group(Icons.chat_bubble_outline, 'Speaking',
                'When words are spoken',
                children: [
                  _switch(
                      'Say each word when tapped',
                      !s.quietBuilder,
                      (v) => s.quietBuilder = !v,
                      'Off: words are added silently; tap the message to speak'),
                  _switch('Say the category name when opened',
                      s.vocalizeFolders, (v) => s.vocalizeFolders = v),
                  _choice<String>('Speak while typing (Type)', s.typingSpeech, {
                    'letters': 'Each letter and word',
                    'words': 'Each word',
                    'off': 'Off',
                  }, (v) {
                    s.typingSpeech = v;
                    _changed();
                  }),
                  _switch('Clear the message after speaking it', s.clearOnSpeak,
                      (v) => s.clearOnSpeak = v),
                  _switch('Go back to Home after a word', s.goHomeOnPress,
                      (v) => s.goHomeOnPress = v),
                ]),
            // 3. Screen & look.
            _group(Icons.palette_outlined, 'Screen & look',
                'Full screen, pictures, words, contrast',
                children: [
                  _switch(
                      'Full screen',
                      s.fullScreen,
                      (v) {
                        s.fullScreen = v;
                        ScreenMode.apply(v);
                      },
                      kIsWeb
                          ? 'Hides the browser bars where the browser allows it. '
                              'On iPhone, add the app to the Home Screen.'
                          : 'Hides the status and navigation bars. Swipe from '
                              'the edge to see them for a moment.'),
                  _choice<ButtonView>('Buttons show', s.buttonView, {
                    ButtonView.symbolText: 'Picture + word',
                    ButtonView.symbolOnly: 'Picture only',
                    ButtonView.textOnly: 'Word only',
                  }, (v) {
                    s.buttonView = v;
                    _changed();
                  }),
                  if (s.buttonView == ButtonView.symbolText)
                    _choice<LabelPosition>('Word position', s.labelPosition, {
                      LabelPosition.below: 'Under picture',
                      LabelPosition.above: 'Over picture',
                    }, (v) {
                      s.labelPosition = v;
                      _changed();
                    }),
                  _choice<String>('Skin tone for people', s.skinTone, {
                    '': 'Default',
                    'light': 'Light',
                    'medium-light': 'Medium light',
                    'medium': 'Medium',
                    'medium-dark': 'Medium dark',
                    'dark': 'Dark',
                  }, (v) {
                    s.skinTone = v;
                    _changed();
                  }),
                  _switch('Message bar at the top', s.messageWindowTop,
                      (v) => s.messageWindowTop = v),
                  _switch(
                      'High contrast (CVI)',
                      s.cviMode,
                      (v) => s.cviMode = v,
                      'Black background, yellow buttons, bold words'),
                ]),
            // 4. Touch & access.
            _group(Icons.accessibility_new, 'Touch & access',
                'Hold to select, switch scanning, extra taps, vibration',
                children: [
                  _switch(
                      'Hold to select',
                      s.dwellEnabled,
                      (v) => s.dwellEnabled = v,
                      'Press and hold a button until the circle fills'),
                  if (s.dwellEnabled)
                    _stepper('Hold time', 0.5, 5.0, s.dwellSeconds, 0.5, (v) {
                      s.dwellSeconds = v;
                      _changed();
                    }, 's'),
                  _switch(
                      'Switch scanning',
                      s.scanningEnabled,
                      (v) => s.scanningEnabled = v,
                      'Adds a Scan button: tap once for a row, again for a button'),
                  if (s.scanningEnabled)
                    _stepper('Scan speed', 0.4, 4.0, s.scanDelayMs / 1000, 0.2,
                        (v) {
                      s.scanDelayMs = (v * 1000).round();
                      _changed();
                    }, 's'),
                  _stepper('Ignore extra taps for', 0, 2.0,
                      s.inputDebounceMs / 1000, 0.25, (v) {
                    s.inputDebounceMs = (v * 1000).round();
                    _changed();
                  }, 's'),
                  _switch('Vibrate', s.haptics, (v) => s.haptics = v),
                  _switch('Click sound', s.audioCues, (v) => s.audioCues = v),
                  _switch(
                      'Stay in the app',
                      s.preventExit,
                      (v) => s.preventExit = v,
                      'Press Back 3 times quickly to leave'),
                ]),
            // 5. Offline & backup.
            if (kIsWeb)
              const WebTools()
            else
              _group(Icons.cloud_off_outlined, 'Offline & backup',
                  'Works without internet; save and restore boards',
                  children: [
                    _note('All pictures and words are built into the app, so '
                        'it works without internet. Only the online picture '
                        'search needs a connection.'),
                    const BackupTools(),
                  ]),
            // 6. Caregiver.
            _group(Icons.lock_outline, 'Caregiver',
                'Edit buttons, pictures, lock code',
                children: [
                  if (widget.settingsController != null) ...[
                    _asyncSwitch(
                        'Edit mode',
                        widget.settingsController!.editMode,
                        'Tap any button to change it', (v) async {
                      final sc = widget.settingsController!;
                      if (v && !await sc.guardPrivileged(context)) return;
                      sc.settings.editMode = v;
                      await sc.update();
                      setState(() {});
                    }),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading:
                          const Icon(Icons.image_search, color: Colors.white70),
                      title: Text(I18n.t('Browse all pictures'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15)),
                      subtitle: Text(I18n.t('Hear a word, add it to Home'),
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12)),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                                builder: (_) => const SymbolBrowser()));
                      },
                    ),
                  ],
                  _asyncSwitch('Lock settings with a code',
                      // The code itself is never shown: the person using
                      // the board could read it here.
                      s.restrictionsEnabled,
                      'Asks for the code before Settings and edit mode',
                      (v) async {
                    if (!v && !await _verifyPin(s.pin)) return;
                    s.restrictionsEnabled = v;
                    if (!v) s.editMode = false;
                    _changed();
                  }),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () async {
                        final pin = await _askPin(
                            I18n.t('Set a new 4-digit code'),
                            current: s.pin);
                        if (pin == null) return;
                        s.pin = pin;
                        _changed();
                      },
                      icon: const Icon(Icons.password, size: 18),
                      label: Text(I18n.t('Change code')),
                    ),
                  ),
                  _switch('Online ARASAAC pictures in search', s.arasaacEnabled,
                      (v) => s.arasaacEnabled = v),
                  if (s.arasaacEnabled) ...[
                    _choice<int>('Skin', s.arasaacSkin, {
                      0: 'Original',
                      1: 'White',
                      2: 'Black',
                      3: 'Asian',
                    }, (v) {
                      s.arasaacSkin = v;
                      _changed();
                    }),
                    _choice<int>('Hair', s.arasaacHair, {
                      0: 'Original',
                      1: 'Blond',
                      2: 'Brown',
                      3: 'Dark',
                      4: 'Red',
                      5: 'Gray',
                    }, (v) {
                      s.arasaacHair = v;
                      _changed();
                    }),
                  ],
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: _resetAll,
                        child: Text(I18n.t('Reset all settings'),
                            style: const TextStyle(color: Colors.redAccent))),
                    TextButton(
                        onPressed: () => showLicensePage(
                            context: context,
                            applicationName: 'AAC Studio',
                            applicationVersion: '1.8.1'),
                        child: Text(I18n.t('Voice and software licenses'))),
                  ]),
                ]),
          ]),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(I18n.t(text),
            style: const TextStyle(color: Colors.white60, fontSize: 13)),
      );

  /// Back to the defaults, keeping the language, lock code and saved
  /// phrases (the board itself is not touched).
  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(I18n.t('Reset all settings?')),
        content: Text(I18n.t('Voice, speaking, screen and access settings go '
            'back to how they were at the start. Words, pictures, the '
            'language and the lock code stay.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(I18n.t('Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(I18n.t('Reset'))),
        ],
      ),
    );
    if (ok != true) return;
    final s = widget.settings;
    final fresh = AppSettings(
      language: s.language,
      pin: s.pin,
      restrictionsEnabled: s.restrictionsEnabled,
      phrases: s.phrases,
    );
    final json = fresh.toJson();
    final keep = AppSettings.fromJson(json);
    // Copy every field back onto the live settings object.
    s
      ..usePiper = keep.usePiper
      ..voiceName = null
      ..voiceLocale = null
      ..rate = keep.rate
      ..pitch = keep.pitch
      ..volume = keep.volume
      ..quietBuilder = keep.quietBuilder
      ..vocalizeFolders = keep.vocalizeFolders
      ..inputDebounceMs = keep.inputDebounceMs
      ..preventExit = keep.preventExit
      ..clearOnSpeak = keep.clearOnSpeak
      ..goHomeOnPress = keep.goHomeOnPress
      ..buttonView = keep.buttonView
      ..labelPosition = keep.labelPosition
      ..messageWindowTop = keep.messageWindowTop
      ..scanningEnabled = keep.scanningEnabled
      ..scanDelayMs = keep.scanDelayMs
      ..dwellEnabled = keep.dwellEnabled
      ..dwellSeconds = keep.dwellSeconds
      ..cviMode = keep.cviMode
      ..skinTone = keep.skinTone
      ..haptics = keep.haptics
      ..audioCues = keep.audioCues
      ..typingSpeech = keep.typingSpeech
      ..fullScreen = keep.fullScreen
      ..callSpeech = keep.callSpeech;
    ScreenMode.apply(s.fullScreen);
    _changed();
  }

  void _test() => widget.speech.speak(_sample,
      style: VoiceStyle(
          rate: widget.settings.rate,
          pitch: widget.settings.pitch,
          volume: widget.settings.volume));

  void _changed() {
    widget.speech.configure(widget.settings);
    setState(() {});
    widget.onChanged();
  }

  /// Language of the board's words, the app's text and the voice. Every
  /// language's words are built into the app, so they work offline.
  Widget _languagePicker() {
    final s = widget.settings;
    final current = languageFor(s.language);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(I18n.t('Language'),
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        initialValue: current.code,
        isExpanded: true,
        dropdownColor: const Color(0xFF2C313A),
        decoration: const InputDecoration(
            isDense: true, border: OutlineInputBorder()),
        items: [
          for (final lang in kLanguages)
            DropdownMenuItem(
                value: lang.code,
                child: Text(
                    lang.code == 'en'
                        ? lang.nativeName
                        : '${lang.nativeName}  ·  ${lang.name}',
                    style: const TextStyle(color: Colors.white))),
        ],
        onChanged: (code) {
          if (code == null || code == s.language) return;
          s.language = code;
          // A voice chosen for the old language would read the new words
          // wrongly: use the device voice for the new one.
          s.voiceName = null;
          s.voiceLocale = null;
          if (code != 'en') s.usePiper = false;
          _changed();
          Navigator.of(context).maybePop();
        },
      ),
    ]);
  }

  /// Whether this device can speak the chosen language, and how to add it.
  Widget _voiceStatus() {
    final lang = languageFor(widget.settings.language);
    return FutureBuilder<List<DeviceVoice>>(
      future: widget.speech.deviceVoices(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox(height: 8);
        final prefix = lang.code == 'hr' ? ['hr', 'bs', 'sr'] : [lang.code];
        final has = snapshot.data!.any((v) => prefix
            .any((p) => v.locale.toLowerCase().replaceAll('_', '-').startsWith(p)));
        final howTo = kIsWeb
            ? 'This browser uses the voices installed on the device.'
            : defaultTargetPlatform == TargetPlatform.iOS
                ? 'To add one: Settings > Accessibility > Spoken Content > '
                    'Voices, then download a voice. It then works offline.'
                : 'To add one: Settings > System > Languages > Text-to-speech '
                    '> Preferred engine settings > Install voice data. It then '
                    'works offline.';
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(has ? Icons.check_circle : Icons.info_outline,
                size: 20,
                color: has ? Colors.lightGreenAccent : Colors.amberAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                  has
                      ? I18n.t('A voice for this language is on this device.')
                      : '${I18n.t('No voice for this language on this device yet.')} '
                          '${I18n.t(howTo)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ]),
        );
      },
    );
  }

  Widget _group(IconData icon, String title, String subtitle,
          {required List<Widget> children, bool initiallyExpanded = false}) =>
      Card(
        color: const Color(0xFF2C313A),
        margin: const EdgeInsets.symmetric(vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: Colors.deepOrangeAccent, size: 28),
          title: Text(I18n.t(title),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(I18n.t(subtitle),
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          iconColor: Colors.white70,
          collapsedIconColor: Colors.white70,
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      );

  Widget _switch(String title, bool value, void Function(bool) onChanged,
          [String? subtitle]) =>
      _asyncSwitch(title, value, subtitle, (v) async {
        onChanged(v);
        _changed();
      });

  Widget _asyncSwitch(String title, bool value, String? subtitle,
          Future<void> Function(bool) onChanged) =>
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        title: Text(I18n.t(title),
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        subtitle: subtitle == null
            ? null
            : Text(I18n.t(subtitle),
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );

  Widget _slider(String label, String low, String high, double min, double max,
      double value, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(I18n.t(label),
            style: const TextStyle(color: Colors.white, fontSize: 15)),
        Row(children: [
          SizedBox(
              width: 44,
              child: Text(low,
                  style: const TextStyle(color: Colors.white54, fontSize: 12))),
          Expanded(
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: 20,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
              width: 40,
              child: Text(high,
                  textAlign: TextAlign.end,
                  style: const TextStyle(color: Colors.white54, fontSize: 12))),
        ]),
      ]),
    );
  }

  Widget _stepper(String label, double min, double max, double value,
      double step, ValueChanged<double> onChanged, String suffix) {
    final shown = value <= 0
        ? 'Off'
        : '${value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '')} $suffix';
    return Row(children: [
      Expanded(
          child: Text(I18n.t(label),
              style: const TextStyle(color: Colors.white, fontSize: 15))),
      IconButton(
          onPressed: value > min + 1e-9
              ? () => onChanged((value - step).clamp(min, max))
              : null,
          icon: const Icon(Icons.remove_circle_outline, color: Colors.white70)),
      SizedBox(
        width: 56,
        child: Text(shown,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      IconButton(
          onPressed: value < max - 1e-9
              ? () => onChanged((value + step).clamp(min, max))
              : null,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white70)),
    ]);
  }

  Widget _choice<T>(String label, T current, Map<T, String> options,
      ValueChanged<T> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(I18n.t(label),
            style: const TextStyle(color: Colors.white, fontSize: 15)),
      ),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final e in options.entries)
            ChoiceChip(
              label: Text(I18n.t(e.value)),
              selected: current == e.key,
              onSelected: (_) => onChanged(e.key),
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
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
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
        title: const Text('Enter code',
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

/// Pick who speaks: the bundled offline voice, the device default, or any
/// installed device voice (English first; other languages on request).
class _VoicePicker extends StatefulWidget {
  final SpeechEngine speech;
  final AppSettings settings;
  final VoidCallback onPicked;
  const _VoicePicker(
      {required this.speech, required this.settings, required this.onPicked});

  @override
  State<_VoicePicker> createState() => _VoicePickerState();
}

class _VoicePickerState extends State<_VoicePicker> {
  late final Future<List<DeviceVoice>> _voices = widget.speech.deviceVoices();
  bool _allLanguages = false;

  void _pick({required bool piper, DeviceVoice? voice}) {
    final s = widget.settings;
    s.usePiper = piper;
    s.voiceName = voice?.name;
    s.voiceLocale = voice?.locale;
    widget.onPicked();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return FutureBuilder<List<DeviceVoice>>(
      future: _voices,
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <DeviceVoice>[];
        final english = all.where((v) => v.isEnglish).toList();
        final shown = _allLanguages || english.isEmpty ? all : english;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!kIsWeb)
            _option('Offline voice', 'US English · works without internet',
                Icons.offline_bolt, s.usePiper, () => _pick(piper: true)),
          _option(
              'Device voice',
              kIsWeb
                  ? 'Safari voices; offline availability depends on your device'
                  : 'This phone or tablet\'s default voice',
              Icons.smartphone,
              !s.usePiper && s.voiceName == null,
              () => _pick(piper: false)),
          if (snapshot.connectionState != ConnectionState.done)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(),
            )
          else if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                  'No other voices found. Add voices in the device\'s '
                  'text-to-speech settings.',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text('More voices on this device (${shown.length})',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240),
              child: ListView(shrinkWrap: true, children: [
                for (final v in shown)
                  _option(
                      v.name,
                      [v.locale, if (v.needsInternet) 'needs internet']
                          .where((t) => t.isNotEmpty)
                          .join(' · '),
                      Icons.record_voice_over,
                      !s.usePiper &&
                          s.voiceName == v.name &&
                          (s.voiceLocale ?? '') == v.locale,
                      () => _pick(piper: false, voice: v)),
              ]),
            ),
            if (english.isNotEmpty && english.length != all.length)
              TextButton(
                onPressed: () => setState(() => _allLanguages = !_allLanguages),
                child: Text(_allLanguages
                    ? 'Show English voices only'
                    : 'Show all languages'),
              ),
          ],
        ]);
      },
    );
  }

  Widget _option(String title, String subtitle, IconData icon, bool selected,
          VoidCallback onTap) =>
      Card(
        color: selected
            ? Colors.deepOrangeAccent.withValues(alpha: .25)
            : const Color(0xFF353B45),
        margin: const EdgeInsets.symmetric(vertical: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: selected ? Colors.deepOrangeAccent : Colors.transparent,
              width: 2),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(selected ? Icons.check_circle : icon,
              color: selected ? Colors.deepOrangeAccent : Colors.white54),
          title: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
          subtitle: Text(subtitle,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          onTap: onTap,
        ),
      );
}
