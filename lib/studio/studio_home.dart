import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../engine/install_server.dart';
import '../engine/settings_controller.dart';
import '../engine/speech.dart';
import '../features/modes.dart';
import '../features/settings/settings_sheet.dart';
import 'device_frame.dart';

/// M0 studio shell: device picker, mode picker, live preview, M3/M5 controls.
class StudioHome extends StatefulWidget {
  const StudioHome({super.key});

  @override
  State<StudioHome> createState() => _StudioHomeState();
}

enum _Mode { myApp, p2gExplorer }

class _StudioHomeState extends State<StudioHome> {
  _Mode mode = _Mode.myApp;
  InstallServer? _installServer;
  String? _installUrl;
  String? _installError;

  DeviceMode get device =>
      context.watch<ValueNotifier<DeviceMode?>>().value ??
      DeviceMode(kDevices[0]);

  void _setDevice(DeviceMode d) =>
      context.read<ValueNotifier<DeviceMode?>>().value = d;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: const Color(0xFF14161A),
      body: Row(
        children: [
          _panel(dark),
          const VerticalDivider(width: 1, color: Colors.black26),
          Expanded(
            child: Container(
              color: const Color(0xFF1D2026),
              padding: const EdgeInsets.all(14),
              child: DeviceFrame(
                spec: device.spec,
                landscape: device.landscape,
                child: mode == _Mode.myApp
                    ? const MyAppHome()
                    : P2gExplorer(config: P2gConfig.localDefault()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel(ColorScheme dark) {
    return Container(
      width: 250,
      color: const Color(0xFF14161A),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('AAC STUDIO',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: 1.2)),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 8, bottom: 10),
            child: Text('original app + live IPA research viewer',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ),
          const _Section('Preview as'),
          for (final d in kDevices)
            _RadioTile(
              selected: device.spec == d,
              title: '${d.emoji}  ${d.name}',
              subtitle: '${d.logical.width.toInt()}×${d.logical.height.toInt()} · ≤${d.maxGridColumns} cols',
              onTap: () => _setDevice(DeviceMode(d, landscape: device.landscape)),
            ),
          SwitchListTile(
            value: device.landscape,
            onChanged: (v) =>
                _setDevice(DeviceMode(device.spec, landscape: v)),
            title: const Text('Landscape',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ),
          const Divider(color: Colors.white12),
          const _Section('Mode'),
          _RadioTile(
            selected: mode == _Mode.myApp,
            title: '✨ My AAC (original)',
            subtitle: 'M0–M2 sample vocabulary, emoji symbols',
            onTap: () => setState(() => mode = _Mode.myApp),
          ),
          _RadioTile(
            selected: mode == _Mode.p2gExplorer,
            title: '🔬 P2G Explorer',
            subtitle: 'Live render of extracted IPA data (research)',
            onTap: () => setState(() => mode = _Mode.p2gExplorer),
          ),
          const Divider(color: Colors.white12),
          const _Section('Controls'),
          // M5 edit mode (PIN-gated when restrictions are on)
          SwitchListTile(
            value: context.watch<SettingsController>().editMode,
            onChanged: (v) async {
              final sc = context.read<SettingsController>();
              await sc.setEditMode(v, context);
            },
            title: const Text('✏️ Edit mode',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            subtitle: const Text('tap a button to edit it',
                style: TextStyle(color: Colors.white30, fontSize: 10.5)),
          ),
          // M3 speech settings + M5 restrictions
          ListTile(
            dense: true,
            leading: const Icon(Icons.tune, color: Colors.white54, size: 18),
            title: const Text('⚙️ Speech & restrictions',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            onTap: () => SettingsSheet.show(
              context,
              speech: context.read<SpeechEngine>(),
              settings: context.read<SettingsController>().settings,
              onChanged: () {
                final sc = context.read<SettingsController>();
                final speech = context.read<SpeechEngine>();
                speech
                  ..rate = sc.settings.rate
                  ..pitch = sc.settings.pitch
                  ..volume = sc.settings.volume;
                sc.update();
              },
            ),
          ),
          const Divider(color: Colors.white12),
          const _Section('Install on device'),
          _installSection(),
          const Divider(color: Colors.white12),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Explorer reads the extracted IPA databases and pre-rendered '
              'symbols from this machine only. Study tooling — the app\'s '
              'code, symbols and voices remain copyrighted.',
              style: TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  /// 📲 Wireless install: serves the built APK over the LAN and shows a QR
  /// code — scan with the phone/tablet to download and install, no USB.
  Widget _installSection() {
    final s = this;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          FilledButton.icon(
            onPressed: () async {
              if (s._installServer?.running ?? false) {
                await s._installServer!.stop();
                s._installServer = null;
                s._installUrl = null;
                setState(() {});
                return;
              }
              final apk = _findApk();
              if (apk == null) {
                s._installError =
                    'APK not found. Run:  flutter build apk --release';
                setState(() {});
                return;
              }
              final server = InstallServer(apkPath: apk);
              try {
                final url = await server.start();
                s._installServer = server;
                s._installUrl = url;
                s._installError = null;
              } catch (e) {
                s._installError = 'Server failed: $e';
              }
              setState(() {});
            },
            icon: Icon(s._installServer?.running ?? false
                ? Icons.stop
                : Icons.wifi_tethering),
            label: Text(s._installServer?.running ?? false
                ? 'Stop server'
                : 'Start Wi-Fi install'),
          ),
        ]),
        if (s._installError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(s._installError!,
                style: const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
          ),
        if (s._installUrl != null) ...[
          const SizedBox(height: 8),
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: QrImageView(
                data: s._installUrl!,
                size: 150,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: SelectableText(
              s._installUrl!,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4, right: 4),
            child: Text(
              'Scan with the phone/tablet camera (same Wi-Fi), open the link, '
              'download the APK and install it. Android may ask to allow '
              '"Install unknown apps" for your browser — that is normal for '
              'sideloading. Nothing leaves your network.',
              style: TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ),
        ] else ...[
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Serve the built Android APK over your Wi-Fi: start the server, '
              'scan the QR code with the device, download, install — no USB.',
              style: TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ),
        ],
      ]),
    );
  }

  String? _findApk() {
    // Project root = 5 levels up from the Windows exe dir
    // (build/windows/x64/runner/Release); direct path when run via flutter run.
    const rel = 'build\\app\\outputs\\flutter-apk\\app-release.apk';
    final candidates = <String>[
      rel, // running from project dir (flutter run)
      '..\\..\\..\\..\\..\\$rel', // built exe in build/windows/x64/runner/Release
      'C:\\Users\\zer0ne_LP_Local\\Desktop\\Proloquo2Go\\studio\\$rel',
    ];
    for (final c in candidates) {
      final f = File(c);
      if (f.existsSync()) return f.absolute.path;
    }
    return null;
  }
}

class _Section extends StatelessWidget {
  final String t;
  const _Section(this.t);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w700)),
      );
}

class _RadioTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _RadioTile({required this.selected, required this.title, this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.deepOrangeAccent.withValues(alpha: .18) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? Colors.deepOrangeAccent : Colors.white10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
          if (subtitle != null)
            Text(subtitle!, style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
        ]),
      ),
    );
  }
}
