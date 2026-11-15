part of 'sensory_games.dart';

// ---------------------------------------------------------------- shared

/// A soft noise burst: sand being cut, soap crunching, water spraying.
void _crunch(String id, {double length = 0.07, double pitch = 2600}) => _Sound.play(
    id,
    () => _Sound.wav(length, (t) => pitch * math.exp(-t * 18) + 300,
        (t) => math.exp(-t * (6 / length)),
        noise: 0.85),
    volume: 0.35);

/// A clear metal click (swinging balls).
void _click(double loudness) => _Sound.play(
    'click',
    () => _Sound.wav(0.05, (t) => 2900 - t * 9000, (t) => math.exp(-t * 120),
        noise: 0.25),
    volume: (0.12 + loudness * 0.4).clamp(0.1, 0.5));

/// Shades a colour for a surface facing [light] (0 dark .. 1 bright).
Color _shade(Color c, double light) {
  final f = light.clamp(0.0, 1.6);
  int ch(double v) => (v * 255 * f).round().clamp(0, 255);
  return Color.fromARGB(255, ch(c.r), ch(c.g), ch(c.b));
}

// ---------------------------------------------------------------- kinetic sand

class _Crumb {
  Offset pos, vel;
  final double r;
  final Color colour;
  double life = 1;
  _Crumb(this.pos, this.vel, this.r, this.colour);
}

class _SandBall {
  final Offset at; // where it lands (screen)
  double fall = 0; // 0 high up .. 1 landed
  _SandBall(this.at);
}

/// Kinetic sand, like the satisfying videos: a soft block of coloured sand
/// in a tray. Slide a finger to cut it, hold to squish it, tap to drop a
/// ball of sand that lands with a soft thud. The corner button pours a new
/// block in the next colour.
class _KineticSandGame extends StatefulWidget {
  const _KineticSandGame();
  @override
  State<_KineticSandGame> createState() => _KineticSandGameState();
}

class _KineticSandGameState extends _GameState<_KineticSandGame> {
  static const _cols = 76, _rows = 46;
  static const _colours = [
    Color(0xFFF7A6C1), // pink
    Color(0xFF9EDCF5), // blue
    Color(0xFFB9E8A2), // mint
    Color(0xFFD3B8F2), // lavender
    Color(0xFFFFD48A), // apricot
    Color(0xFFEFE3CF), // natural
  ];
  int _colour = 0;
  final _h = Float32List(_cols * _rows);
  final _target = Float32List(_cols * _rows);
  final _grain = Float32List(_cols * _rows);
  double _pour = 1; // < 1 while a new block is poured
  Rect _tray = Rect.zero;
  final _crumbs = <_Crumb>[];
  final _balls = <_SandBall>[];
  final _fingers = <int, ({Offset at, Offset last, double since, bool moved})>{};
  double _lastCutSound = 0;

  double get _maxH => _tray.height * 0.22;
  double get _cw => _tray.width / (_cols - 1);
  double get _ch => _tray.height / (_rows - 1);

  void _newBlock() {
    final r = math.Random(_colour * 31 + 7);
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        // A rounded block with soft, slightly uneven edges.
        final dx = ((x - (_cols - 1) / 2).abs() - (_cols / 2 - 7)).clamp(0.0, 99.0);
        final dy = ((y - (_rows - 1) / 2).abs() - (_rows / 2 - 6)).clamp(0.0, 99.0);
        final edge = math.sqrt(dx * dx + dy * dy);
        final v = (1 - edge / 2.6).clamp(0.0, 1.0);
        _target[y * _cols + x] = _maxH * v * (0.96 + r.nextDouble() * 0.04);
        _grain[y * _cols + x] = r.nextDouble();
      }
    }
    _h.fillRange(0, _h.length, 0);
    _pour = 0;
  }

  @override
  void step(double dt) {
    final tray = Rect.fromCenter(
        center: size.center(Offset(0, size.height * 0.08)),
        width: size.width * 0.84,
        height: math.min(size.height * 0.56, size.width * 0.84 * 0.62));
    if (tray != _tray) {
      _tray = tray;
      _newBlock();
    }
    if (_pour < 1) {
      _pour = math.min(1, _pour + dt * 0.9);
      // Sand pours in from the middle outward.
      for (var i = 0; i < _h.length; i++) {
        final x = i % _cols, y = i ~/ _cols;
        final d = (Offset(x / _cols - 0.5, y / _rows - 0.5)).distance;
        final local = ((_pour * 1.6 - d) * 2).clamp(0.0, 1.0);
        _h[i] = _target[i] * local;
      }
      if (rng.nextDouble() < 0.5) {
        _crumbs.add(_Crumb(
            Offset(_tray.center.dx + (rng.nextDouble() - 0.5) * 40, _tray.top - 80),
            Offset((rng.nextDouble() - 0.5) * 60, 200),
            2 + rng.nextDouble() * 3,
            _colours[_colour]));
      }
    }
    for (final entry in _fingers.entries.toList()) {
      final f = entry.value;
      final held = f.since + dt;
      _fingers[entry.key] = (at: f.at, last: f.last, since: held, moved: f.moved);
      if (!f.moved && held > 0.28) _squish(f.at, dt);
    }
    for (final b in _balls) {
      b.fall += dt * 2.4;
      if (b.fall >= 1) {
        _mound(b.at);
        _Sound.squish();
        tick();
      }
    }
    _balls.removeWhere((b) => b.fall >= 1);
    for (final c in _crumbs) {
      c.vel += Offset(0, 900 * dt);
      c.pos += c.vel * dt;
      c.life -= dt * 0.9;
    }
    _crumbs.removeWhere((c) => c.life <= 0 || c.pos.dy > size.height + 20);
  }

  (int, int)? _cell(Offset p) {
    final x = ((p.dx - _tray.left) / _cw).round();
    final y = ((p.dy - _tray.top) / _ch).round();
    if (x < 0 || y < 0 || x >= _cols || y >= _rows) return null;
    return (x, y);
  }

  /// Cuts a clean line through the sand, pushing a little to the sides.
  void _cut(Offset a, Offset b) {
    final steps = math.max(1, ((b - a).distance / (_cw * 0.5)).ceil());
    final dir = b - a;
    final side = dir.distance > 0
        ? Offset(-dir.dy, dir.dx) / dir.distance
        : const Offset(0, 1);
    var removed = 0.0;
    for (var s = 0; s <= steps; s++) {
      final p = Offset.lerp(a, b, s / steps)!;
      final cell = _cell(p);
      if (cell == null) continue;
      final (cx, cy) = cell;
      for (var y = cy - 1; y <= cy + 1; y++) {
        for (var x = cx - 1; x <= cx + 1; x++) {
          if (x < 0 || y < 0 || x >= _cols || y >= _rows) continue;
          final i = y * _cols + x;
          final d = (Offset(x * _cw, y * _ch) + _tray.topLeft - p).distance;
          if (d > _cw * 1.1) continue;
          if (_h[i] > 1) removed += _h[i];
          _h[i] *= 0.05;
        }
      }
      // Some sand rises up beside the blade.
      for (final sgn in const [-1.0, 1.0]) {
        final q = _cell(p + side * sgn * _cw * 2.2);
        if (q == null) continue;
        final i = q.$2 * _cols + q.$1;
        if (_h[i] > 2) _h[i] = math.min(_h[i] + _maxH * 0.05, _maxH * 1.15);
      }
    }
    if (removed > _maxH * 2) {
      for (var k = 0; k < 3; k++) {
        _crumbs.add(_Crumb(
            b + Offset((rng.nextDouble() - 0.5) * 16, -_maxH * 0.5),
            Offset((rng.nextDouble() - 0.5) * 120, -60 - rng.nextDouble() * 80),
            1.8 + rng.nextDouble() * 2.6,
            _colours[_colour]));
      }
      if (time - _lastCutSound > 0.09) {
        _lastCutSound = time;
        _crunch('sand-cut', length: 0.09, pitch: 1500);
      }
    }
  }

  /// Pressing in slowly makes a soft dent with a raised rim.
  void _squish(Offset p, double dt) {
    final cell = _cell(p);
    if (cell == null) return;
    final (cx, cy) = cell;
    const r = 5;
    for (var y = cy - r - 2; y <= cy + r + 2; y++) {
      for (var x = cx - r - 2; x <= cx + r + 2; x++) {
        if (x < 0 || y < 0 || x >= _cols || y >= _rows) continue;
        final i = y * _cols + x;
        final d = math.sqrt(((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble());
        if (_h[i] < 1) continue;
        if (d <= r) {
          _h[i] -= _h[i] * (1 - d / r * 0.5) * dt * 2.2;
        } else if (d <= r + 2) {
          _h[i] = math.min(_h[i] + _maxH * dt * 0.35, _maxH * 1.2);
        }
      }
    }
  }

  /// A dropped ball of sand lands as a soft mound.
  void _mound(Offset p) {
    final cell = _cell(p);
    if (cell == null) return;
    final (cx, cy) = cell;
    const r = 6.0;
    for (var y = cy - 8; y <= cy + 8; y++) {
      for (var x = cx - 8; x <= cx + 8; x++) {
        if (x < 0 || y < 0 || x >= _cols || y >= _rows) continue;
        final d2 = ((x - cx) * (x - cx) + (y - cy) * (y - cy)).toDouble();
        final add = _maxH * 0.55 * math.exp(-d2 / (r * r * 0.5));
        final i = y * _cols + x;
        _h[i] = math.min(_h[i] + add, _maxH * 1.6);
      }
    }
    for (var k = 0; k < 10; k++) {
      final a = rng.nextDouble() * 6.28;
      _crumbs.add(_Crumb(p, Offset(math.cos(a) * 140, -80 - rng.nextDouble() * 120),
          1.5 + rng.nextDouble() * 2, _colours[_colour]));
    }
  }

  @override
  void down(int pointer, Offset p) =>
      _fingers[pointer] = (at: p, last: p, since: 0, moved: false);

  @override
  void move(int pointer, Offset p) {
    final f = _fingers[pointer];
    if (f == null) return;
    final moved = f.moved || (p - f.at).distance > 14;
    if (moved && !(f.since > 0.28 && !f.moved)) _cut(f.last, p);
    _fingers[pointer] = (at: p, last: p, since: f.since, moved: moved);
  }

  @override
  void up(int pointer) {
    final f = _fingers.remove(pointer);
    if (f != null && !f.moved && f.since < 0.28 && _tray.inflate(10).contains(f.at)) {
      _balls.add(_SandBall(f.at));
    }
  }

  @override
  List<Widget> overlay(BuildContext context) => [
        _cornerButton(Icons.refresh, 'Start again', () {
          setState(() {
            _colour = (_colour + 1) % _colours.length;
            _newBlock();
          });
          _Sound.squish();
        }),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFFEDE7E3), const Color(0xFFCFC6BF));
    if (_tray == Rect.zero) return;
    const lift = 0.85; // how far height shows as rising up the screen
    // The tray: a light wooden board with a soft shadow.
    final board = _tray.inflate(_cw * 2.2).translate(0, _ch);
    canvas.drawRRect(
        RRect.fromRectAndRadius(board.translate(0, 14), const Radius.circular(22)),
        Paint()
          ..color = const Color(0x44000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    canvas.drawRRect(
        RRect.fromRectAndRadius(board, const Radius.circular(22)),
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFE9D3B2), Color(0xFFCDAF85)])
              .createShader(board));
    final base = _colours[_colour];
    final pos = Float32List(_cols * _rows * 2);
    final col = Int32List(_cols * _rows);
    const light = (-0.45, -0.65, 0.62);
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        final i = y * _cols + x;
        final h = _h[i];
        pos[i * 2] = _tray.left + x * _cw;
        pos[i * 2 + 1] = _tray.top + y * _ch - h * lift;
        final hl = _h[y * _cols + math.max(0, x - 1)];
        final hr = _h[y * _cols + math.min(_cols - 1, x + 1)];
        final hu = _h[math.max(0, y - 1) * _cols + x];
        final hd = _h[math.min(_rows - 1, y + 1) * _cols + x];
        var nx = (hl - hr) / (2 * _cw), ny = (hu - hd) / (2 * _ch), nz = 1.0;
        final len = math.sqrt(nx * nx + ny * ny + nz * nz);
        nx /= len;
        ny /= len;
        nz /= len;
        final diffuse = (nx * light.$1 + ny * light.$2 + nz * light.$3).clamp(0.0, 1.0);
        // Grooves and dents get darker (less light reaches them).
        final cavity = ((hl + hr + hu + hd) / 4 - h).clamp(-_maxH, _maxH) / _maxH;
        var shade = 0.48 + 0.62 * diffuse - cavity * 0.35;
        shade *= 0.94 + _grain[i] * 0.12;
        final sand = _shade(base, shade);
        final onFloor = (h / 3).clamp(0.0, 1.0);
        final floor = _shade(const Color(0xFFDCC29C), 0.92 + _grain[i] * 0.08);
        col[i] = Color.lerp(floor, sand, onFloor)!.toARGB32();
      }
    }
    final idx = Uint16List((_cols - 1) * (_rows - 1) * 6);
    var k = 0;
    for (var y = 0; y < _rows - 1; y++) {
      for (var x = 0; x < _cols - 1; x++) {
        final a = y * _cols + x;
        idx[k++] = a;
        idx[k++] = a + 1;
        idx[k++] = a + _cols;
        idx[k++] = a + 1;
        idx[k++] = a + _cols + 1;
        idx[k++] = a + _cols;
      }
    }
    canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: col, indices: idx),
        BlendMode.dst,
        Paint());
    // Balls of sand on their way down, with a growing shadow below.
    for (final b in _balls) {
      final r = _cw * 4.2;
      final height = (1 - b.fall) * size.height * 0.5;
      canvas.drawOval(
          Rect.fromCenter(center: b.at, width: r * 2 * (0.5 + b.fall * 0.5), height: r * (0.5 + b.fall * 0.5)),
          Paint()..color = Color.fromARGB((60 * b.fall).round(), 0, 0, 0));
      final c = b.at - Offset(0, height + r * 0.5);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(
                    center: const Alignment(-0.35, -0.4),
                    colors: [_shade(base, 1.2), _shade(base, 0.62)])
                .createShader(Rect.fromCircle(center: c, radius: r)));
    }
    for (final c in _crumbs) {
      canvas.drawCircle(c.pos, c.r,
          Paint()..color = _shade(c.colour, 0.8 + c.life * 0.3).withValues(alpha: c.life.clamp(0.0, 1.0)));
    }
  }
}

// ---------------------------------------------------------------- 3D boxes

/// A tiny 3D view for box-shaped things (soap, the cradle's frame): a
/// camera looking down from the front, and shaded faces drawn far to near.
class _View3 {
  final Offset centre;
  final double scale;
  static const _pitch = 0.62, _yaw = -0.32;
  _View3(this.centre, this.scale);

  /// World (x right, y up, z toward the viewer) to the camera.
  static (double, double, double) _cam(double x, double y, double z) {
    final cy = math.cos(_yaw), sy = math.sin(_yaw);
    final x1 = x * cy + z * sy, z1 = -x * sy + z * cy;
    final cp = math.cos(_pitch), sp = math.sin(_pitch);
    final y2 = y * cp - z1 * sp, z2 = y * sp + z1 * cp;
    return (x1, y2, z2);
  }

  Offset project(double x, double y, double z) {
    final (cx, cy, cz) = _cam(x, y, z);
    final p = 1 / (1 - cz * 0.00035);
    return centre + Offset(cx, -cy) * scale * p;
  }

  double depth(double x, double y, double z) => _cam(x, y, z).$3;
}

class _Face {
  final List<Offset> points;
  final double depth;
  final Color colour;
  final double light;
  final bool inner;
  _Face(this.points, this.depth, this.colour, this.light, this.inner);
}

/// A box with its own rotation about the x and z axes, around [pivot].
class _Box {
  double x, y, z; // centre
  final double w, h, d; // size
  double rx = 0, rz = 0; // rotation (radians)
  final Color colour;
  final Set<int> innerFaces; // faces made by a cut (lighter, matt)
  _Box(this.x, this.y, this.z, this.w, this.h, this.d, this.colour,
      [this.innerFaces = const {}]);

  (double, double, double) _rot(double px, double py, double pz) {
    // Around x, then around z.
    final cx = math.cos(rx), sx = math.sin(rx);
    final y1 = py * cx - pz * sx, z1 = py * sx + pz * cx;
    final cz = math.cos(rz), sz = math.sin(rz);
    final x2 = px * cz - y1 * sz, y2 = px * sz + y1 * cz;
    return (x2, y2, z1);
  }

  static const _corners = [
    (-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
    (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1),
  ];
  // Faces as corner indices, outward: -x, +x, -y, +y, -z, +z.
  static const _faces = [
    [0, 4, 7, 3], [1, 2, 6, 5], [0, 1, 5, 4], [3, 7, 6, 2], [0, 3, 2, 1], [4, 5, 6, 7],
  ];
  static const _normals = [
    (-1.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, -1.0, 0.0), (0.0, 1.0, 0.0),
    (0.0, 0.0, -1.0), (0.0, 0.0, 1.0),
  ];

  void faces(_View3 view, List<_Face> out) {
    final pts = <(double, double, double)>[];
    for (final c in _corners) {
      final r = _rot(c.$1 * w / 2, c.$2 * h / 2, c.$3 * d / 2);
      pts.add((x + r.$1, y + r.$2, z + r.$3));
    }
    for (var f = 0; f < 6; f++) {
      final n = _normals[f];
      final rn = _rot(n.$1, n.$2, n.$3);
      // Facing the camera?
      final camN = _View3._cam(rn.$1, rn.$2, rn.$3);
      if (camN.$3 <= 0.02) continue;
      final light = (rn.$1 * -0.35 + rn.$2 * 0.85 + rn.$3 * 0.45).clamp(-1.0, 1.0);
      final corners = _faces[f];
      var depth = 0.0;
      final points = <Offset>[];
      for (final i in corners) {
        final p = pts[i];
        points.add(view.project(p.$1, p.$2, p.$3));
        depth += view.depth(p.$1, p.$2, p.$3);
      }
      out.add(_Face(points, depth / 4, colour, light, innerFaces.contains(f)));
    }
  }
}

void _drawFaces(Canvas canvas, List<_Face> faces, {double gloss = 0.25}) {
  faces.sort((a, b) => a.depth.compareTo(b.depth));
  for (final f in faces) {
    final path = Path()..addPolygon(f.points, true);
    final shade = f.inner ? 0.78 + f.light * 0.22 : 0.62 + f.light * 0.42;
    final fill = _shade(f.colour, shade);
    final bounds = path.getBounds();
    canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(fill, Colors.white, f.inner ? 0.05 : gloss * math.max(0, f.light))!,
                fill,
              ]).createShader(bounds));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _shade(f.colour, shade * 0.85).withValues(alpha: 0.6));
  }
}

// ---------------------------------------------------------------- soap cutting

class _Piece {
  final _Box box;
  double vy = 0, spin, rest; // falling
  double age = 0;
  _Piece(this.box, this.spin, this.rest);
}

/// Soap cutting: a soft bar of layered soap. Swipe across it to score
/// lines; swipe down through it to cut a slice, which tips over and
/// breaks into little cubes with a crisp crunch.
class _SoapGame extends StatefulWidget {
  const _SoapGame();
  @override
  State<_SoapGame> createState() => _SoapGameState();
}

class _SoapGameState extends _GameState<_SoapGame> {
  static const _sets = [
    [Color(0xFFF8BBD0), Color(0xFFFFF59D), Color(0xFFB3E5FC)],
    [Color(0xFFC5E1A5), Color(0xFFFFFFFF), Color(0xFFCE93D8)],
    [Color(0xFFFFCC80), Color(0xFFF48FB1), Color(0xFFFFF9C4)],
    [Color(0xFF80DEEA), Color(0xFFB39DDB), Color(0xFFFFF59D)],
  ];
  int _set = 0;
  double _barLeft = -150, _barRight = 150; // what is left of the bar (x)
  static const _w = 300.0, _layer = 34.0, _depth = 110.0;
  final _scores = <double>[]; // z positions of scored lines
  final _pieces = <_Piece>[];
  final _lines = <int, Offset>{};
  final _starts = <int, Offset>{};
  _View3 _view = _View3(Offset.zero, 1);
  double _slide = 0; // a new bar slides in

  @override
  void step(double dt) {
    final scale = math.min(size.width / 480, size.height / 430);
    _view = _View3(size.center(Offset(0, size.height * 0.06)), scale);
    _slide = math.max(0, _slide - dt * 1.5);
    for (final p in _pieces) {
      p.age += dt;
      final b = p.box;
      if (b.y > p.rest) {
        p.vy -= 900 * dt;
        b.y = math.max(p.rest, b.y + p.vy * dt);
        b.rz = math.max(-math.pi / 2, b.rz - p.spin * dt);
      } else {
        b.rz += (-math.pi / 2 - b.rz) * (1 - math.exp(-dt * 10));
      }
    }
    _pieces.removeWhere((p) => p.age > 14);
    if (_barRight - _barLeft < 12 && _slide == 0) {
      // The bar is used up: a fresh one slides in.
      _set = (_set + 1) % _sets.length;
      _barLeft = -_w / 2;
      _barRight = _w / 2;
      _scores.clear();
      _slide = 1;
    }
  }

  /// Screen point to the bar's top surface (x, z).
  (double, double) _onTop(Offset p) {
    // Search the top face for the closest projected point (cheap grid).
    var best = (0.0, 0.0);
    var bestD = double.infinity;
    for (var i = 0; i <= 30; i++) {
      for (var j = 0; j <= 12; j++) {
        final x = -_w / 2 - 40 + i * (_w + 80) / 30;
        final z = -_depth / 2 - 20 + j * (_depth + 40) / 12;
        final d = (_view.project(x, _layer * 3, z) - p).distanceSquared;
        if (d < bestD) {
          bestD = d;
          best = (x, z);
        }
      }
    }
    return best;
  }

  void _slice(double x) {
    x = x.clamp(_barLeft + 8, _barRight);
    final width = _barRight - x;
    if (width < 6) return;
    final colours = _sets[_set];
    // The slice falls to the right and breaks along the scored lines.
    final cuts = [-_depth / 2, ..._scores.where((z) => z.abs() < _depth / 2 - 6), _depth / 2]
      ..sort();
    for (var l = 0; l < 3; l++) {
      for (var c = 0; c < cuts.length - 1; c++) {
        final z0 = cuts[c], z1 = cuts[c + 1];
        final piece = _Box(x + width / 2, _layer * (l + 0.5), (z0 + z1) / 2, width,
            _layer, z1 - z0 - 1.5, colours[l], const {0, 4, 5});
        _pieces.add(_Piece(piece, 2.2 + rng.nextDouble() * 1.2, width / 2 + 2)
          ..box.x += 40 + l * 22.0 + rng.nextDouble() * 8
          ..box.y += 4);
      }
    }
    _barRight = x;
    _crunch('soap', length: 0.12, pitch: 3400);
    tick();
  }

  @override
  void down(int pointer, Offset p) {
    _starts[pointer] = p;
    _lines[pointer] = p;
  }

  @override
  void move(int pointer, Offset p) => _lines[pointer] = p;

  @override
  void up(int pointer) {
    final a = _starts.remove(pointer);
    final b = _lines.remove(pointer);
    if (a == null || b == null || (b - a).distance < 30) return;
    final (ax, az) = _onTop(a);
    final (bx, bz) = _onTop(b);
    final across = (bx - ax).abs(), deep = (bz - az).abs();
    if (deep > across) {
      // Front-to-back swipe: cut a slice.
      _slice((ax + bx) / 2);
    } else {
      // Side-to-side swipe: score a line along the bar.
      final z = ((az + bz) / 2).clamp(-_depth / 2 + 10, _depth / 2 - 10);
      if (_scores.length < 4 && !_scores.any((s) => (s - z).abs() < 14)) {
        _scores.add(z);
        _crunch('score', length: 0.06, pitch: 4200);
        tick();
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFFF3EFEA), const Color(0xFFD9D2CB));
    // Cutting board.
    final faces = <_Face>[];
    _Box(0, -6, 0, _w + 260, 12, _depth + 120, const Color(0xFFD7B48A)).faces(_view, faces);
    _drawFaces(canvas, faces, gloss: 0.1);
    faces.clear();
    final colours = _sets[_set];
    final offset = _slide * -360;
    if (_barRight - _barLeft > 1) {
      for (var l = 0; l < 3; l++) {
        _Box((_barLeft + _barRight) / 2 + offset, _layer * (l + 0.5), 0,
                _barRight - _barLeft, _layer, _depth, colours[l],
                _barRight < _w / 2 - 1 ? const {1} : const {})
            .faces(_view, faces);
      }
    }
    for (final p in _pieces) {
      p.box.faces(_view, faces);
    }
    _drawFaces(canvas, faces);
    // Scored lines on the top of the bar.
    final score = Paint()
      ..color = const Color(0x55000000)
      ..strokeWidth = 1.6;
    for (final z in _scores) {
      canvas.drawLine(_view.project(_barLeft + offset, _layer * 3, z),
          _view.project(_barRight + offset, _layer * 3, z), score);
    }
    // The blade follows each finger.
    for (final p in _lines.values) {
      final blade = Path()
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx + 16, p.dy - 70)
        ..lineTo(p.dx + 34, p.dy - 66)
        ..close();
      canvas.drawPath(
          blade,
          Paint()
            ..shader = const LinearGradient(
                    colors: [Color(0xFFF5F7FA), Color(0xFF9AA4AE)])
                .createShader(blade.getBounds()));
      canvas.drawLine(Offset(p.dx + 25, p.dy - 68), Offset(p.dx + 34, p.dy - 110),
          Paint()
            ..color = const Color(0xFF5D4037)
            ..strokeWidth = 10
            ..strokeCap = StrokeCap.round);
    }
  }
}

// ---------------------------------------------------------------- water beads

class _Bead {
  Offset pos, vel;
  final double r;
  final Color colour;
  double squash = 0;
  _Bead(this.pos, this.vel, this.r, this.colour);
}

/// Water beads: hundreds of shiny, squishy jelly beads in a tray. Slide a
/// finger through them to stir and push them; tap to pour more in.
class _BeadsGame extends StatefulWidget {
  const _BeadsGame();
  @override
  State<_BeadsGame> createState() => _BeadsGameState();
}

class _BeadsGameState extends _GameState<_BeadsGame> {
  static const _colours = [
    Color(0xFFFF8FB1), Color(0xFF7FD1FF), Color(0xFF9CF59A), Color(0xFFFFE07A),
    Color(0xFFC59BFF), Color(0xFFFFB37A), Color(0xFFE8F6FF),
  ];
  final _beads = <_Bead>[];
  final _fingers = <int, (Offset, Offset)>{}; // now, before
  final _pour = <(Offset, double)>[]; // where beads are being poured, time left
  double _plip = 0;

  double get _r => size.shortestSide * 0.028;

  void _add(Offset at) {
    final r = _r * (0.85 + rng.nextDouble() * 0.3);
    _beads.add(_Bead(at, Offset((rng.nextDouble() - 0.5) * 60, 80), r,
        _colours[rng.nextInt(_colours.length)]));
    if (_beads.length > 260) _beads.removeAt(0);
  }

  @override
  void step(double dt) {
    if (_beads.isEmpty) {
      final n = (size.width * size.height / (_r * _r * 9)).clamp(60, 200).round();
      for (var i = 0; i < n; i++) {
        _add(Offset(_r + rng.nextDouble() * (size.width - _r * 2),
            size.height * (0.45 + rng.nextDouble() * 0.55)));
      }
    }
    for (var i = _pour.length - 1; i >= 0; i--) {
      final (at, left) = _pour[i];
      if (rng.nextDouble() < 0.7) _add(at + Offset((rng.nextDouble() - 0.5) * 30, 0));
      _pour[i] = (at, left - dt);
      if (left - dt <= 0) _pour.removeAt(i);
    }
    const sub = 3;
    final h = dt / sub;
    for (var s = 0; s < sub; s++) {
      for (final b in _beads) {
        b.vel += Offset(0, 1100 * h);
        b.pos += b.vel * h;
        b.squash *= math.exp(-h * 10);
      }
      // Fingers push the beads aside like a hand in a bowl.
      for (final (now, before) in _fingers.values) {
        final push = (now - before) / math.max(dt, 0.001);
        for (final b in _beads) {
          final d = b.pos - now;
          final reach = _r * 3.2 + b.r;
          final dist = d.distance;
          if (dist < reach && dist > 0.01) {
            b.pos = now + d / dist * reach;
            b.vel = b.vel * 0.6 + push * 0.35 + d / dist * 60;
            b.squash = 0.25;
          }
        }
      }
      _collide();
      for (final b in _beads) {
        if (b.pos.dy > size.height - b.r) {
          b.pos = Offset(b.pos.dx, size.height - b.r);
          if (b.vel.dy > 260 && time - _plip > 0.06) {
            _plip = time;
            _Sound.bubble();
          }
          b.vel = Offset(b.vel.dx * 0.9, -b.vel.dy * 0.25);
        }
        if (b.pos.dx < b.r) {
          b.pos = Offset(b.r, b.pos.dy);
          b.vel = Offset(-b.vel.dx * 0.4, b.vel.dy);
        }
        if (b.pos.dx > size.width - b.r) {
          b.pos = Offset(size.width - b.r, b.pos.dy);
          b.vel = Offset(-b.vel.dx * 0.4, b.vel.dy);
        }
      }
    }
    for (final k in _fingers.keys.toList()) {
      final (now, _) = _fingers[k]!;
      _fingers[k] = (now, now);
    }
  }

  void _collide() {
    final cell = _r * 2.4;
    final grid = <int, List<_Bead>>{};
    for (final b in _beads) {
      final key = (b.pos.dx / cell).floor() * 10007 + (b.pos.dy / cell).floor();
      (grid[key] ??= []).add(b);
    }
    for (final b in _beads) {
      final gx = (b.pos.dx / cell).floor(), gy = (b.pos.dy / cell).floor();
      for (var x = gx - 1; x <= gx + 1; x++) {
        for (var y = gy - 1; y <= gy + 1; y++) {
          for (final o in grid[x * 10007 + y] ?? const <_Bead>[]) {
            if (identical(o, b) || o.hashCode < b.hashCode) continue;
            final d = o.pos - b.pos;
            final dist = d.distance;
            final min = b.r + o.r;
            if (dist >= min || dist < 0.001) continue;
            final n = d / dist;
            final push = (min - dist) / 2;
            b.pos -= n * push;
            o.pos += n * push;
            final rel = (o.vel - b.vel).dx * n.dx + (o.vel - b.vel).dy * n.dy;
            if (rel < 0) {
              final j = n * rel * 0.55;
              b.vel += j;
              o.vel -= j;
            }
          }
        }
      }
    }
  }

  @override
  void down(int pointer, Offset p) {
    final crowded = _beads.where((b) => (b.pos - p).distance < _r * 4).length;
    if (crowded < 2) {
      _pour.add((Offset(p.dx, -_r * 2), 0.6));
    }
    _fingers[pointer] = (p, p);
  }

  @override
  void move(int pointer, Offset p) {
    final before = _fingers[pointer]?.$2 ?? p;
    _fingers[pointer] = (p, before);
  }

  @override
  void up(int pointer) => _fingers.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFFF6F8FB), const Color(0xFFDCE3EC));
    final shadow = Paint()
      ..color = const Color(0x22000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final b in _beads) {
      canvas.drawOval(
          Rect.fromCenter(
              center: b.pos + Offset(b.r * 0.25, b.r * 0.55),
              width: b.r * 2.0,
              height: b.r * 1.2),
          shadow);
    }
    for (final b in _beads) {
      final rect = Rect.fromCenter(
          center: b.pos,
          width: b.r * 2 * (1 + b.squash * 0.5),
          height: b.r * 2 * (1 - b.squash * 0.5));
      // A clear jelly ball: darker rim, light shining through the bottom.
      canvas.drawOval(
          rect,
          Paint()
            ..shader = RadialGradient(
                center: const Alignment(0.15, 0.25),
                radius: 0.85,
                colors: [
                  Color.lerp(b.colour, Colors.white, 0.55)!,
                  b.colour.withValues(alpha: 0.85),
                  _shade(b.colour, 0.6),
                ],
                stops: const [0.0, 0.6, 1.0]).createShader(rect));
      canvas.drawArc(
          rect.deflate(b.r * 0.22),
          0.35,
          2.4,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = b.r * 0.16
            ..strokeCap = StrokeCap.round
            ..color = Colors.white.withValues(alpha: 0.32));
      canvas.drawOval(
          Rect.fromCenter(
              center: b.pos + Offset(-b.r * 0.36, -b.r * 0.4),
              width: b.r * 0.62,
              height: b.r * 0.38),
          Paint()..color = Colors.white.withValues(alpha: 0.85));
    }
  }
}

// ---------------------------------------------------------------- pressure wash

/// Pressure washing: a dirty patio, deck or brick path. Slide a finger to
/// blast the dirt away with a jet of water and watch the clean surface
/// appear. When it is spotless it shines, then a new dirty one comes.
class _WashGame extends StatefulWidget {
  const _WashGame();
  @override
  State<_WashGame> createState() => _WashGameState();
}

class _WashGameState extends _GameState<_WashGame> {
  static const _cell = 7.0;
  int _cols = 0, _rows = 0;
  Float32List _dirt = Float32List(0);
  Float32List _wet = Float32List(0);
  Float32List _tint = Float32List(0);
  int _surface = 0;
  ui.Picture? _clean;
  Size _cleanSize = Size.zero;
  final _jets = <int, Offset>{};
  final _spray = <_Crumb>[];
  double _shine = -1; // > 0 while the clean surface shines
  double _hiss = 0;
  double _left = 1;

  void _dirty() {
    _cols = (size.width / _cell).ceil() + 1;
    _rows = (size.height / _cell).ceil() + 1;
    _dirt = Float32List(_cols * _rows);
    _wet = Float32List(_cols * _rows);
    _tint = Float32List(_cols * _rows);
    final seed = rng.nextDouble() * 100;
    double noise(double x, double y) =>
        0.5 + 0.25 * math.sin(x * 0.11 + seed) * math.cos(y * 0.13 - seed) +
        0.15 * math.sin((x + y) * 0.31 + seed * 2) + 0.1 * math.sin(x * 0.7 - y * 0.6);
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        _dirt[y * _cols + x] = (0.72 + noise(x * 1.0, y * 1.0) * 0.35).clamp(0.0, 1.0);
        _tint[y * _cols + x] = noise(x * 0.6 + 40, y * 0.6);
      }
    }
    _left = 1;
    _shine = -1;
  }

  ui.Picture _drawClean(Size size) {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = math.Random(_surface * 13 + 1);
    switch (_surface % 3) {
      case 0: // Wooden deck.
        final plank = size.height / 9;
        for (var i = 0; i < 10; i++) {
          final rect = Rect.fromLTWH(0, i * plank, size.width, plank - 3);
          final base = Color.lerp(const Color(0xFFC08A55), const Color(0xFFD9A46B), r.nextDouble())!;
          c.drawRect(rect, Paint()..color = base);
          for (var g = 0; g < 7; g++) {
            final y = rect.top + r.nextDouble() * plank;
            c.drawLine(Offset(0, y), Offset(size.width, y + (r.nextDouble() - 0.5) * 8),
                Paint()
                  ..color = _shade(base, 0.86).withValues(alpha: 0.5)
                  ..strokeWidth = 1 + r.nextDouble());
          }
          for (var n = 0; n < 2; n++) {
            final x = r.nextDouble() * size.width;
            c.drawLine(Offset(x, rect.top), Offset(x, rect.bottom),
                Paint()
                  ..color = const Color(0x55402010)
                  ..strokeWidth = 2);
          }
        }
      case 1: // Stone patio tiles.
        c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF9E9A92));
        final tile = size.shortestSide / 4.2;
        for (var y = 0.0; y < size.height; y += tile) {
          for (var x = 0.0; x < size.width; x += tile) {
            final rect = Rect.fromLTWH(x + 3, y + 3, tile - 6, tile - 6);
            final base = Color.lerp(const Color(0xFFE6DFD3), const Color(0xFFCFC6B8), r.nextDouble())!;
            c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(4)),
                Paint()
                  ..shader = LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color.lerp(base, Colors.white, 0.25)!, base])
                      .createShader(rect));
          }
        }
      default: // Brick path.
        c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFBDB3A6));
        final bh = size.shortestSide / 9, bw = bh * 2.1;
        var row = 0;
        for (var y = 0.0; y < size.height; y += bh, row++) {
          for (var x = row.isOdd ? -bw / 2 : 0.0; x < size.width; x += bw) {
            final rect = Rect.fromLTWH(x + 2, y + 2, bw - 4, bh - 4);
            final base = Color.lerp(const Color(0xFFC0583A), const Color(0xFFA9462C), r.nextDouble())!;
            c.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)),
                Paint()
                  ..shader = LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color.lerp(base, Colors.white, 0.18)!, base])
                      .createShader(rect));
          }
        }
    }
    return rec.endRecording();
  }

  @override
  void step(double dt) {
    if (_cols == 0 || size != _cleanSize) {
      _cleanSize = size;
      _clean = _drawClean(size);
      _dirty();
    }
    for (var i = 0; i < _wet.length; i++) {
      if (_wet[i] > 0) _wet[i] = math.max(0, _wet[i] - dt * 0.12);
    }
    for (final p in _jets.values) {
      _blast(p, dt);
      for (var k = 0; k < 4; k++) {
        final a = rng.nextDouble() * 6.28;
        final v = 140 + rng.nextDouble() * 260;
        _spray.add(_Crumb(p, Offset(math.cos(a) * v, math.sin(a) * v * 0.6 - 120),
            1 + rng.nextDouble() * 2.2, Colors.white));
      }
      if (time - _hiss > 0.16) {
        _hiss = time;
        _crunch('spray', length: 0.2, pitch: 5200);
      }
    }
    for (final s in _spray) {
      s.vel += Offset(0, 700 * dt);
      s.pos += s.vel * dt;
      s.life -= dt * 2.2;
    }
    _spray.removeWhere((s) => s.life <= 0);
    if (_spray.length > 400) _spray.removeRange(0, _spray.length - 400);
    if (_jets.isNotEmpty || _left > 0.02) {
      var sum = 0.0;
      for (final d in _dirt) {
        sum += d;
      }
      _left = sum / math.max(1, _dirt.length);
      if (_left < 0.02 && _shine < 0) {
        _shine = 0;
        _Sound.chime();
      }
    }
    if (_shine >= 0) {
      _shine += dt;
      if (_shine > 3.5) {
        _surface++;
        _clean = _drawClean(size);
        _dirty();
      }
    }
  }

  /// The jet strips the dirt where it hits, fastest in the middle.
  void _blast(Offset p, double seconds) {
    if (_cols == 0) return;
    final reach = size.shortestSide * 0.06;
    final cx = (p.dx / _cell).round(), cy = (p.dy / _cell).round();
    final rc = (reach / _cell).ceil();
    for (var y = cy - rc; y <= cy + rc; y++) {
      for (var x = cx - rc; x <= cx + rc; x++) {
        if (x < 0 || y < 0 || x >= _cols || y >= _rows) continue;
        final d = (Offset(x * _cell, y * _cell) - p).distance;
        if (d > reach) continue;
        final i = y * _cols + x;
        final power = 1 - d / reach;
        _dirt[i] = math.max(0, _dirt[i] - seconds * 26 * power);
        _wet[i] = math.min(1, _wet[i] + seconds * 6 * power);
      }
    }
  }

  @override
  void down(int pointer, Offset p) => _jets[pointer] = p;

  @override
  void move(int pointer, Offset p) {
    // A quick sweep cleans the whole line, not just a few dots.
    final from = _jets[pointer] ?? p;
    final steps = ((p - from).distance / 6).ceil();
    for (var s = 1; s <= steps; s++) {
      _blast(Offset.lerp(from, p, s / steps)!, 0.035);
    }
    _jets[pointer] = p;
  }

  @override
  void up(int pointer) => _jets.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    final clean = _clean;
    if (clean == null || _cols == 0) return;
    canvas.drawPicture(clean);
    final pos = Float32List(_cols * _rows * 2);
    final wet = Int32List(_cols * _rows);
    final dirt = Int32List(_cols * _rows);
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        final i = y * _cols + x;
        pos[i * 2] = x * _cell;
        pos[i * 2 + 1] = y * _cell;
        wet[i] = Color.fromARGB((_wet[i] * 45).round(), 20, 30, 40).toARGB32();
        final grime = Color.lerp(const Color(0xFF3B2E1E), const Color(0xFF3F4A22), _tint[i])!;
        // Crisp edges: half-cleaned grime fades quickly.
        final d = _dirt[i];
        final cover = d <= 0.12 ? 0.0 : d >= 0.5 ? 1.0 : (d - 0.12) / 0.38;
        dirt[i] = grime.withValues(alpha: 0.95 * cover).toARGB32();
      }
    }
    final idx = Uint16List((_cols - 1) * (_rows - 1) * 6);
    var k = 0;
    for (var y = 0; y < _rows - 1; y++) {
      for (var x = 0; x < _cols - 1; x++) {
        final a = y * _cols + x;
        idx[k++] = a;
        idx[k++] = a + 1;
        idx[k++] = a + _cols;
        idx[k++] = a + 1;
        idx[k++] = a + _cols + 1;
        idx[k++] = a + _cols;
      }
    }
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: wet, indices: idx),
        BlendMode.dst, Paint());
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: dirt, indices: idx),
        BlendMode.dst, Paint());
    // The nozzle and its jet.
    for (final p in _jets.values) {
      final from = Offset(size.width * 0.92, size.height * 1.05);
      final dir = (p - from) / (p - from).distance;
      final nozzle = p - dir * 120;
      canvas.drawLine(from, nozzle,
          Paint()
            ..color = const Color(0xFF263238)
            ..strokeWidth = 14
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(nozzle, nozzle + dir * 26,
          Paint()
            ..color = const Color(0xFFFFC107)
            ..strokeWidth = 18
            ..strokeCap = StrokeCap.round);
      final side = Offset(-dir.dy, dir.dx);
      final jet = Path()
        ..moveTo(nozzle.dx + dir.dx * 26, nozzle.dy + dir.dy * 26)
        ..lineTo(p.dx + side.dx * 18, p.dy + side.dy * 18)
        ..lineTo(p.dx - side.dx * 18, p.dy - side.dy * 18)
        ..close();
      canvas.drawPath(jet, Paint()..color = const Color(0x88E3F6FF));
      canvas.drawCircle(p, 26,
          Paint()
            ..color = const Color(0x66FFFFFF)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
    }
    for (final s in _spray) {
      canvas.drawCircle(s.pos, s.r,
          Paint()..color = Colors.white.withValues(alpha: (s.life * 0.7).clamp(0.0, 1.0)));
    }
    if (_shine >= 0) {
      // A band of shine sweeps across the spotless surface.
      final x = (_shine / 1.6) * (size.width + 300) - 150;
      final band = Rect.fromLTWH(x - 120, 0, 240, size.height);
      canvas.drawRect(
          band,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = const LinearGradient(colors: [
              Color(0x00FFFFFF),
              Color(0x55FFFFFF),
              Color(0x00FFFFFF),
            ]).createShader(band));
    }
  }
}

// ---------------------------------------------------------------- swinging balls

/// Swinging balls (Newton's cradle): pull a shiny ball out and let go; it
/// clicks into the row and the ball at the far end swings out. Try two.
class _CradleGame extends StatefulWidget {
  const _CradleGame();
  @override
  State<_CradleGame> createState() => _CradleGameState();
}

class _CradleGameState extends _GameState<_CradleGame> {
  static const _n = 5;
  final _angle = List<double>.filled(_n, 0);
  final _speed = List<double>.filled(_n, 0);
  final _held = <int, int>{}; // pointer → ball
  double _r = 30, _len = 200;
  Offset _top = Offset.zero;
  bool _started = false;

  double _pivot(int i) => _top.dx + (i - (_n - 1) / 2) * _r * 2;
  Offset _ball(int i) =>
      Offset(_pivot(i) + math.sin(_angle[i]) * _len, _top.dy + math.cos(_angle[i]) * _len);

  @override
  void step(double dt) {
    _r = size.shortestSide * 0.06;
    _len = size.height * 0.42;
    _top = Offset(size.width / 2, size.height * 0.16);
    if (!_started) {
      _started = true;
      _angle[0] = -0.7; // start with one ball out
    }
    const sub = 12;
    final h = dt / sub;
    final g = 9.8 * 160 / _len;
    for (var s = 0; s < sub; s++) {
      for (var i = 0; i < _n; i++) {
        if (_held.containsValue(i)) {
          _speed[i] = 0;
          continue;
        }
        _speed[i] += -g * math.sin(_angle[i]) * h;
        _speed[i] *= math.exp(-h * 0.06);
        _angle[i] += _speed[i] * h;
      }
      // Touching neighbours pass their swing on (equal balls: they swap).
      for (var pass = 0; pass < _n; pass++) {
        for (var i = 0; i < _n - 1; i++) {
          final a = _ball(i), b = _ball(i + 1);
          if (b.dx - a.dx < _r * 2 - 0.2) {
            final closing = _speed[i] - _speed[i + 1];
            if (closing > 0) {
              final ai = _held.containsValue(i), bi = _held.containsValue(i + 1);
              if (!ai && !bi) {
                final t = _speed[i];
                _speed[i] = _speed[i + 1] * 0.995;
                _speed[i + 1] = t * 0.995;
              }
              if (closing > 0.6 && pass == 0) _click((closing / 6).clamp(0.0, 1.0));
            }
            // Keep them from overlapping.
            final overlap = (_r * 2 - (b.dx - a.dx)) / 2 / _len;
            if (!_held.containsValue(i)) _angle[i] -= overlap;
            if (!_held.containsValue(i + 1)) _angle[i + 1] += overlap;
          }
        }
      }
    }
  }

  @override
  void down(int pointer, Offset p) {
    var best = -1;
    var bestD = _r * 2.2;
    for (var i = 0; i < _n; i++) {
      final d = (_ball(i) - p).distance;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (best < 0) return;
    // Only an end ball (or the row next to it) can be pulled out.
    _held[pointer] = best;
    move(pointer, p);
  }

  @override
  void move(int pointer, Offset p) {
    final i = _held[pointer];
    if (i == null) return;
    final dx = (p.dx - _pivot(i)) / _len;
    var a = math.asin(dx.clamp(-0.95, 0.95));
    // A ball can be pulled outward but not through the others.
    final left = i < (_n - 1) / 2;
    a = left ? math.min(a, 0) : math.max(a, 0);
    _angle[i] = a.clamp(-1.0, 1.0);
    // Balls on the outside of the held one come along.
    if (left) {
      for (var k = 0; k < i; k++) {
        _angle[k] = math.min(_angle[k], _angle[i]);
      }
    } else {
      for (var k = i + 1; k < _n; k++) {
        _angle[k] = math.max(_angle[k], _angle[i]);
      }
    }
  }

  @override
  void up(int pointer) => _held.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF2E3440), const Color(0xFF14171D));
    final baseY = _top.dy + _len + _r * 2.2;
    final halfW = _r * (_n + 2.2);
    // Wooden base with a soft reflection.
    final base = Rect.fromLTRB(_top.dx - halfW - 30, baseY, _top.dx + halfW + 30, baseY + _r * 1.1);
    canvas.drawRRect(
        RRect.fromRectAndRadius(base, const Radius.circular(10)),
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF8D5A3B), Color(0xFF4E2F1E)])
              .createShader(base));
    // Chrome frame: two posts and the top bar.
    final chrome = Paint()
      ..shader = const LinearGradient(
              colors: [Color(0xFF6B7178), Color(0xFFF2F4F6), Color(0xFF7A8087)])
          .createShader(Rect.fromLTWH(_top.dx - halfW - 6, 0, 14, 10))
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    for (final x in [_top.dx - halfW, _top.dx + halfW]) {
      canvas.drawLine(Offset(x, _top.dy - 6), Offset(x, baseY), chrome);
    }
    canvas.drawLine(Offset(_top.dx - halfW, _top.dy - 6), Offset(_top.dx + halfW, _top.dy - 6),
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFF5F7F9), Color(0xFF6D737A)])
              .createShader(Rect.fromLTWH(0, _top.dy - 11, 10, 10))
          ..strokeWidth = 9
          ..strokeCap = StrokeCap.round);
    for (var i = 0; i < _n; i++) {
      final c = _ball(i);
      // Shadow on the base.
      canvas.drawOval(
          Rect.fromCenter(center: Offset(c.dx, baseY + 4), width: _r * 1.9, height: _r * 0.4),
          Paint()
            ..color = const Color(0x55000000)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      // Two strings to the bar (front and back), seen from slightly above.
      final string = Paint()
        ..color = const Color(0xAAE0E0E0)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(_pivot(i) - _r * 0.5, _top.dy - 4), c - Offset(0, _r), string);
      canvas.drawLine(Offset(_pivot(i) + _r * 0.5, _top.dy - 4), c - Offset(0, _r), string);
      // A chrome ball: sky and floor reflected, one bright highlight.
      final rect = Rect.fromCircle(center: c, radius: _r);
      canvas.drawCircle(
          c,
          _r,
          Paint()
            ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFFF7F9FB),
                  Color(0xFFB9C0C8),
                  Color(0xFF3C4148),
                  Color(0xFF8B6A55),
                  Color(0xFFD2D6DB),
                ],
                stops: [0.0, 0.42, 0.52, 0.8, 1.0]).createShader(rect));
      canvas.drawCircle(
          c,
          _r,
          Paint()
            ..shader = RadialGradient(
                center: const Alignment(-0.4, -0.45),
                radius: 0.9,
                colors: [Colors.white.withValues(alpha: 0.0), Colors.black.withValues(alpha: 0.35)],
                stops: const [0.6, 1.0]).createShader(rect));
      canvas.drawOval(
          Rect.fromCenter(center: c + Offset(-_r * 0.35, -_r * 0.42), width: _r * 0.5, height: _r * 0.3),
          Paint()..color = Colors.white.withValues(alpha: 0.95));
    }
  }
}
