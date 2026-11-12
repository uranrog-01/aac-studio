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
  List<({String address, String adapter})> _lanIps = const [];
  String? _selectedIp;
  bool _showCloudQr = false;

  /// Cloud install: stable GitHub Releases URL — always points at the newest
  /// published APK (asset name is version-independent: AACStudio-android.apk),
  /// so this QR keeps working for future versions and works on ANY network.
  static const kCloudApkUrl =
      'https://github.com/uranrog-01/aac-studio/releases/latest/download/'
      'AACStudio-android.apk';

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
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child:
                    Image.asset('assets/app_icon.png', width: 40, height: 40),
              ),
              const SizedBox(width: 10),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AAC STUDIO',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                            letterSpacing: 1.2)),
                    Text('v1.9.1 · modern flat',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ]),
            ]),
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
              subtitle:
                  '${d.logical.width.toInt()}×${d.logical.height.toInt()} · ≤${d.maxGridColumns} cols',
              onTap: () =>
                  _setDevice(DeviceMode(d, landscape: device.landscape)),
            ),
          SwitchListTile(
            value: device.landscape,
            onChanged: (v) => _setDevice(DeviceMode(device.spec, landscape: v)),
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
          if (_isDesktop)
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
            title: const Text('⚙️ Settings',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            onTap: () => SettingsSheet.show(
              context,
              speech: context.read<SpeechEngine>(),
              settings: context.read<SettingsController>().settings,
              onChanged: () {
                final sc = context.read<SettingsController>();
                context.read<SpeechEngine>().configure(sc.settings);
                sc.update();
              },
            ),
          ),
          if (_isDesktop) ...[
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
        ],
      ),
    );
  }

  /// Desktop-only studio features (Wi-Fi install server, P2G Explorer) need
  /// local file paths and a server socket — hidden on phones/tablets where
  /// the app runs standalone.
  static bool get _isDesktop => !Platform.isAndroid && !Platform.isIOS;

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
              final ipa = _findIpa();
              if (apk == null && ipa == null) {
                s._installError =
                    'No build found. Run:  flutter build apk --release  '
                    '(Android) — or get AACStudio-unsigned.ipa from Codemagic (iOS).';
                setState(() {});
                return;
              }
              final server = InstallServer(apkPath: apk ?? ipa!, ipaPath: ipa);
              try {
                await server.start();
                // PC may be on several networks (Wi-Fi + hotspot + …):
                // let the user pick the IP that matches the phone's network.
                s._lanIps = await InstallServer.lanIps();
                s._selectedIp =
                    s._lanIps.isNotEmpty ? s._lanIps.first.address : null;
                server.urlOverride = s._selectedIp;
                s._installServer = server;
                s._installUrl = server.url;
                s._installError = s._lanIps.length > 1
                    ? 'PC is on ${s._lanIps.length} networks — pick the one '
                        'your phone/tablet is using:'
                    : null;
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
                style:
                    const TextStyle(color: Colors.orangeAccent, fontSize: 11)),
          ),
        if ((s._installServer?.running ?? false) && s._lanIps.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final e in s._lanIps)
                InkWell(
                  onTap: () {
                    setState(() {
                      s._selectedIp = e.address;
                      s._installServer!.urlOverride = e.address;
                      s._installUrl = s._installServer!.url;
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: s._selectedIp == e.address
                          ? Colors.deepOrangeAccent.withValues(alpha: .25)
                          : const Color(0xFF3A4049),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: s._selectedIp == e.address
                              ? Colors.deepOrangeAccent
                              : Colors.white12),
                    ),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(e.address,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600)),
                          Text(e.adapter,
                              style: const TextStyle(
                                  color: Colors.white38, fontSize: 9)),
                        ]),
                  ),
                ),
            ]),
          ),
        ],
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
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4, right: 4),
            child: Text(
              'Pick the network your phone/tablet is on (above), then scan. '
              'Both devices must be on the SAME network. If the page says '
              '"offline", allow AAC Studio through Windows Firewall '
              '(there is a "Fix firewall" button below) and rescan. Android '
              'may ask to allow "Install unknown apps" — normal for '
              'sideloading. Nothing leaves your network.',
              style: TextStyle(color: Colors.white30, fontSize: 10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: OutlinedButton.icon(
              onPressed: _fixFirewall,
              icon: const Icon(Icons.security, size: 16),
              label: const Text('Fix firewall (allow port 8770-8789)'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _showCloudQr = !_showCloudQr),
              icon: const Icon(Icons.cloud_download, size: 16),
              label: Text(_showCloudQr
                  ? 'Hide internet QR'
                  : '☁ Internet install (any network)'),
            ),
          ),
          if (_showCloudQr) ...[
            const SizedBox(height: 8),
            Center(
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: QrImageView(
                    data: kCloudApkUrl,
                    size: 150,
                    backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 6),
            const Center(
              child: Text('Downloads the newest release from GitHub.',
                  style: TextStyle(color: Colors.white38, fontSize: 10)),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 4, left: 4, right: 4),
              child: Text(
                'Works from ANY network — the tablet only needs internet '
                '(no same-Wi-Fi requirement, no firewall issues). The same '
                'QR serves every future version.',
                style: TextStyle(color: Colors.white30, fontSize: 10),
              ),
            ),
          ],
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

  /// Adds a Windows Firewall inbound rule for the install server's ports.
  /// Requires one UAC approval (the elevation dialog is shown to the user).
  Future<void> _fixFirewall() async {
    const ps = "Start-Process netsh -ArgumentList "
        "'advfirewall firewall add rule name=\"AAC Studio Install Server\" "
        "dir=in action=allow protocol=TCP localport=8770-8789 "
        "profile=any' -Verb RunAs -Wait";
    try {
      final r = await Process.run('powershell', ['-NoProfile', '-Command', ps]);
      final ok = r.exitCode == 0;
      setState(() {
        _installError = ok
            ? null
            : 'Firewall rule was not added (exit ${r.exitCode}). '
                'Add it manually: run PowerShell as Administrator and:\n'
                'netsh advfirewall firewall add rule name="AAC Studio Install '
                'Server" dir=in action=allow protocol=TCP localport=8770-8789';
      });
    } catch (e) {
      setState(() => _installError = 'Firewall fix failed: $e');
    }
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

  /// Finds a packaged unsigned iOS IPA, if one was copied into dist/.
  String? _findIpa() {
    const rel = 'dist\\AACStudio-unsigned.ipa';
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
                color: Colors.white38,
                fontSize: 11,
                fontWeight: FontWeight.w700)),
      );
}

class _RadioTile extends StatelessWidget {
  final bool selected;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  const _RadioTile(
      {required this.selected,
      required this.title,
      this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color:
              selected ? Colors.deepOrangeAccent.withValues(alpha: .18) : null,
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
            Text(subtitle!,
                style: const TextStyle(color: Colors.white38, fontSize: 10.5)),
        ]),
      ),
    );
  }
}
