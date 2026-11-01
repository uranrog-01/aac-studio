import 'dart:async';
import 'dart:io';

/// Wireless install server: serves the built Android APK (and optionally a
/// packaged iOS IPA) over the local network so a phone/tablet can download
/// them by scanning a QR code — no USB needed. Same concept as the studied
/// app's embedded web server.
///
/// iOS note: Safari can download the .ipa, but it cannot self-install it —
/// the file still needs signing via Sideloadly/AltStore (free Apple ID) or
/// TestFlight (paid). True OTA install (itms-services) requires a paid
/// Apple Developer account with a trusted HTTPS certificate.
class InstallServer {
  HttpServer? _server;
  final String apkPath;
  final String? ipaPath;
  int port = 8770;

  InstallServer({required this.apkPath, this.ipaPath});

  bool get running => _server != null;
  /// URL override: when the PC is on several networks, the UI picks the IP
  /// matching the phone's network; the server itself binds all interfaces.
  String? urlOverride;
  String? get url {
    if (_server == null) return null;
    final ip = (urlOverride != null && urlOverride!.isNotEmpty)
        ? urlOverride!
        : _lanIp;
    return ip == null ? null : 'http://$ip:$port';
  }

  String? get apkUrl => url == null ? null : '$url/apk';
  String? get ipaUrl => (url == null || ipaPath == null) ? null : '$url/ipa';

  static String? _lanIp;

  /// A LAN IPv4 + the adapter it belongs to, so the user can pick the
  /// network their phone is actually on (PCs often have several).
  static Future<List<({String address, String adapter})>> lanIps() async {
    final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    final out = <({String address, String adapter})>[];
    for (final i in ifs) {
      for (final a in i.addresses) {
        if (a.isLoopback) continue;
        final o = a.address.split('.');
        if (o.length != 4) continue;
        final first = int.tryParse(o[0]) ?? 0;
        final second = int.tryParse(o[1]) ?? 0;
        final isPrivate = (first == 192 && second == 168) ||
            first == 10 ||
            (first == 172 && second >= 16 && second <= 31);
        if (isPrivate) {
          out.add((address: a.address, adapter: i.name));
        }
      }
    }
    // Virtual adapters (Hyper-V/WSL "vEthernet", loopbacks) are never the
    // right choice for a phone — sort them to the end.
    int rank(String adapter) =>
        adapter.toLowerCase().contains('vethernet') ||
                adapter.toLowerCase().contains('virtual') ||
                adapter.toLowerCase().contains('loopback')
            ? 1
            : 0;
    out.sort((a, b) => rank(a.adapter).compareTo(rank(b.adapter)));
    return out;
  }

  static Future<String?> lanIp() async {
    final ips = await lanIps();
    if (ips.isEmpty) return null;
    // prefer a home-style 192.168.x when several networks exist
    for (final e in ips) {
      if (e.address.startsWith('192.168.')) return e.address;
    }
    return ips.first.address;
  }

  Future<String> start() async {
    if (_server != null) return url!;
    // resolve a LAN IPv4 for the QR/URL (re-resolve each start)
    _lanIp = await lanIp();
    // find a free port starting at 8770
    HttpServer? server;
    var p = port;
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        server = await HttpServer.bind(InternetAddress.anyIPv4, p);
        break;
      } on SocketException {
        p++;
      }
    }
    if (server == null) throw const SocketException('no free port');
    _server = server;
    port = p;
    server.listen(_handle);
    return url!;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  void _handle(HttpRequest req) async {
    try {
      final path = req.uri.path;
      if (path == '/ipa') {
        final f = File(ipaPath ?? '');
        if (ipaPath == null || !await f.exists()) {
          req.response.statusCode = 404;
          req.response.write(
              'IPA not found. Package it first: see codemagic.yaml ios-ipa-unsigned.');
          await req.response.close();
          return;
        }
        final len = await f.length();
        req.response.headers
          ..contentType = ContentType('application', 'octet-stream')
          ..contentLength = len
          ..set('Content-Disposition',
              'attachment; filename="AACStudio-unsigned.ipa"');
        await f.openRead().pipe(req.response);
        await req.response.close();
        return;
      }
      if (path == '/apk' || path == '/app-release.apk') {
        final f = File(apkPath);
        if (!await f.exists()) {
          req.response.statusCode = 404;
          req.response.write(
              'APK not found. Build it first:\nflutter build apk --release');
          await req.response.close();
          return;
        }
        final len = await f.length();
        req.response.headers
          ..contentType = ContentType('application', 'vnd.android.package-archive')
          ..contentLength = len
          ..set('Content-Disposition',
              'attachment; filename="aac_studio.apk"');
        await f.openRead().pipe(req.response);
        await req.response.close();
        return;
      }
      // download page (adapts to what has actually been built)
      final apkExists = await File(apkPath).exists();
      final ipa = ipaPath;
      final ipaExists = ipa != null && await File(ipa).exists();
      final apkBtn = apkExists
          ? '<a class="btn green" href="/apk">⬇ Download for Android (.apk)</a>'
          : '';
      final ipaBtn = ipaExists
          ? '<a class="btn" href="/ipa">⬇ Download for iPhone (.ipa)</a>'
          : '';
      final html = '''
<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>AAC Studio install</title>
<style>body{font-family:system-ui;background:#14161a;color:#fff;display:flex;
min-height:100vh;align-items:center;justify-content:center;margin:0}
.c{max-width:420px;padding:28px;text-align:center}
a.btn{display:block;background:#ff7043;color:#fff;text-decoration:none;
font-size:20px;font-weight:700;padding:18px;border-radius:14px;margin:18px 0}
a.btn.green{background:#43a047}
ol{text-align:left;color:#ccc;line-height:1.6;font-size:14px}
.note{color:#999;font-size:12px;line-height:1.5}</style></head>
<body><div class="c"><h1>AAC Studio</h1><p>Open-source AAC app</p>
$apkBtn
$ipaBtn
<ol><li><b>Android:</b> tap Download, open the file, allow
"Install unknown apps" when asked.</li>
<li><b>iPhone/iPad:</b> the .ipa downloads but will not self-install —
sideload it with Sideloadly or AltStore (free Apple ID), or TestFlight
(paid developer account).</li></ol>
<p class="note">Same-Wi-Fi transfer — nothing leaves your network.</p>
</div></body></html>''';
      req.response.headers.contentType = ContentType.html;
      req.response.write(html);
      await req.response.close();
    } catch (_) {
      req.response.statusCode = 500;
      try {
        await req.response.close();
      } catch (_) {}
    }
  }
}
