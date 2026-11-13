part of 'sensory_games.dart';

// ---------------------------------------------------------------- sounds

/// Soft sounds made by the app itself (no files, no internet). Every game
/// sound is short and quiet, and the speaker button in the games menu turns
/// them all off.
class _Sound {
  static bool on = true;
  static final _cache = <String, Source>{};
  static final _players = <AudioPlayer>[];
  static int _next = 0;

  /// A WAV of [seconds]: a tone whose pitch follows [freq] and loudness
  /// [amp], with [noise] (0..1) of soft hiss mixed in.
  static Uint8List wav(double seconds, double Function(double t) freq,
      double Function(double t) amp,
      {double noise = 0, int rate = 22050}) {
    final count = (rate * seconds).round();
    final data = ByteData(44 + count * 2);
    void text(int at, String s) {
      for (var i = 0; i < s.length; i++) {
        data.setUint8(at + i, s.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    data.setUint32(4, 36 + count * 2, Endian.little);
    text(8, 'WAVEfmt ');
    data.setUint32(16, 16, Endian.little);
    data.setUint16(20, 1, Endian.little);
    data.setUint16(22, 1, Endian.little);
    data.setUint32(24, rate, Endian.little);
    data.setUint32(28, rate * 2, Endian.little);
    data.setUint16(32, 2, Endian.little);
    data.setUint16(34, 16, Endian.little);
    text(36, 'data');
    data.setUint32(40, count * 2, Endian.little);
    final rng = math.Random(7);
    var phase = 0.0;
    var hiss = 0.0;
    for (var i = 0; i < count; i++) {
      final t = i / rate;
      phase += 2 * math.pi * freq(t) / rate;
      hiss = hiss * 0.82 + (rng.nextDouble() * 2 - 1) * 0.18;
      final attack = (t / 0.003).clamp(0.0, 1.0);
      final s = (math.sin(phase) * (1 - noise) + hiss * noise * 2.2) *
          amp(t) *
          attack;
      data.setInt16(
          44 + i * 2, (s * 26000).round().clamp(-32768, 32767), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Future<void> play(String id, Uint8List Function() make,
      {double volume = 0.55}) async {
    if (!on) return;
    try {
      final source = _cache.putIfAbsent(id, () {
        final bytes = make();
        return kIsWeb
            ? UrlSource('data:audio/wav;base64,${base64Encode(bytes)}')
            : BytesSource(bytes, mimeType: 'audio/wav');
      });
      if (_players.length < 5) _players.add(AudioPlayer());
      final player = _players[_next++ % _players.length];
      await player.stop();
      await player.play(source, volume: volume);
    } catch (_) {/* No sound on this device: the picture still answers. */}
  }

  /// A silicone pop (pop-it, bubble wrap). [high] for popping back up.
  static void pop({bool high = false}) => play(
      high ? 'pop-up' : 'pop',
      () => wav(
          0.09,
          (t) => (high ? 760 : 520) * math.exp(-t * 26) + (high ? 220 : 150),
          (t) => math.exp(-t * 48),
          noise: 0.15));

  /// A soap bubble bursting: tiny and high.
  static void bubble() => play(
      'bubble',
      () => wav(
          0.06, (t) => 1300 * math.exp(-t * 34) + 420, (t) => math.exp(-t * 70),
          noise: 0.3),
      volume: 0.35);

  /// A water drop: a short rising "bloop".
  static void drop() => play(
      'drop',
      () => wav(0.16, (t) => 520 + 1400 * (t / 0.16) * (t / 0.16),
          (t) => math.exp(-t * 24) * (1 - math.exp(-t * 400))),
      volume: 0.45);

  /// Slime being squeezed: low and soft.
  static void squish() => play(
      'squish',
      () => wav(
          0.2, (t) => 170 * math.exp(-t * 4) + 70, (t) => math.exp(-t * 14),
          noise: 0.45),
      volume: 0.4);

  /// Two matching pictures found: two bright notes.
  static void chime() => play(
      'chime',
      () => wav(0.5, (t) => t < 0.12 ? 784 : 1047,
          (t) => math.exp(-(t < 0.12 ? t : t - 0.12) * 7)),
      volume: 0.4);
}

// ---------------------------------------------------------------- pop-it

/// A silicone pop-it board: press a bubble down with a soft pop, slide a
/// finger to pop a whole row. When every bubble is down the board turns
/// over and they all spring back up in a wave.
class _PopItGame extends StatefulWidget {
  const _PopItGame();
  @override
  State<_PopItGame> createState() => _PopItGameState();
}

class _PopItGameState extends _GameState<_PopItGame> {
  static const _cols = 6, _rows = 6;
  static const _rowHues = [2.0, 28.0, 50.0, 125.0, 200.0, 270.0];
  final _down = List<bool>.filled(_cols * _rows, false);
  final _press = List<double>.filled(_cols * _rows, 0);
  final _finger = <int, int?>{};
  double _waveStart = -1;
  double _flip = 0;

  Rect get _board {
    final side = math.min(size.width * 0.92, size.height * 0.86);
    return Rect.fromCenter(
        center: size.center(Offset.zero), width: side, height: side);
  }

  int? _cellAt(Offset p) {
    final b = _board.deflate(_board.width * 0.04);
    if (!b.contains(p)) return null;
    final c = ((p.dx - b.left) / b.width * _cols).floor().clamp(0, _cols - 1);
    final r = ((p.dy - b.top) / b.height * _rows).floor().clamp(0, _rows - 1);
    return r * _cols + c;
  }

  void _set(int i, bool down) {
    if (_down[i] == down || _waveStart >= 0) return;
    _down[i] = down;
    tick();
    _Sound.pop(high: !down);
    if (_down.every((d) => d)) _waveStart = time + 0.6;
  }

  @override
  void down(int pointer, Offset p) {
    final i = _cellAt(p);
    _finger[pointer] = i;
    if (i != null) _set(i, !_down[i]);
  }

  @override
  void move(int pointer, Offset p) {
    final i = _cellAt(p);
    if (i == null || i == _finger[pointer]) return;
    _finger[pointer] = i;
    _set(i, true); // sliding pops the bubbles it crosses
  }

  @override
  void up(int pointer) => _finger.remove(pointer);

  @override
  void step(double dt) {
    for (var i = 0; i < _press.length; i++) {
      final target = _down[i] ? 1.0 : 0.0;
      _press[i] += (target - _press[i]) * (1 - math.exp(-dt * 22));
    }
    if (_waveStart >= 0 && time >= _waveStart) {
      // The board turns over; the bubbles come back up row by row.
      _flip = ((time - _waveStart) / 0.5).clamp(0.0, 1.0);
      for (var i = 0; i < _down.length; i++) {
        final r = i ~/ _cols, c = i % _cols;
        if (time - _waveStart > 0.25 + (r + c) * 0.045 && _down[i]) {
          _down[i] = false;
        }
      }
      if (_down.every((d) => !d)) {
        _waveStart = -1;
        _flip = 0;
        tick();
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFFF4EEE6), const Color(0xFFE2D8CB));
    final board = _board;
    canvas.save();
    // A quick squash while the board "turns over".
    final squash = 1 - math.sin(_flip * math.pi) * 0.12;
    canvas.translate(board.center.dx, board.center.dy);
    canvas.scale(1, squash);
    canvas.translate(-board.center.dx, -board.center.dy);
    final shape =
        RRect.fromRectAndRadius(board, Radius.circular(board.width * 0.12));
    canvas.drawRRect(
        shape.shift(const Offset(0, 10)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16));
    canvas.save();
    canvas.clipRRect(shape);
    final inner = board.deflate(board.width * 0.04);
    final cell = inner.width / _cols;
    for (var r = 0; r < _rows; r++) {
      canvas.drawRect(
          Rect.fromLTWH(
              board.left,
              inner.top + r * cell - (r == 0 ? board.width * 0.04 : 0),
              board.width,
              cell + (r == 0 || r == _rows - 1 ? board.width * 0.04 : 0)),
          Paint()..color = _hue(_rowHues[r], s: 0.62, v: 0.93));
    }
    canvas.restore();
    for (var i = 0; i < _down.length; i++) {
      final r = i ~/ _cols, c = i % _cols;
      final centre =
          Offset(inner.left + (c + 0.5) * cell, inner.top + (r + 0.5) * cell);
      final radius = cell * 0.36;
      final p = _press[i];
      final base = _hue(_rowHues[r], s: 0.66, v: 0.95);
      final rect = Rect.fromCircle(center: centre, radius: radius);
      // Shadow ring around a raised dome, a dark rim around a pressed one.
      canvas.drawCircle(
          centre + Offset(0, radius * 0.1 * (1 - p)),
          radius * 1.04,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.16 + 0.1 * p)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
      canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..shader = RadialGradient(
              center: Alignment(-0.3 + 0.6 * p, -0.35 + 0.8 * p),
              radius: 0.95,
              colors: [
                Color.lerp(Color.lerp(base, Colors.white, 0.45)!,
                    Color.lerp(base, Colors.black, 0.22)!, p)!,
                base,
                Color.lerp(base, Colors.black, 0.18 - 0.1 * p)!,
              ],
              stops: const [0.0, 0.6, 1.0],
            ).createShader(rect));
      // Glossy highlight on a raised dome; a soft crescent on a pressed one.
      canvas.drawOval(
          Rect.fromCenter(
              center: centre +
                  Offset(-radius * 0.3, -radius * 0.38 + radius * 0.7 * p),
              width: radius * 0.62,
              height: radius * (0.34 - 0.18 * p)),
          Paint()..color = Colors.white.withValues(alpha: 0.55 - 0.3 * p));
    }
    canvas.restore();
  }
}

// ---------------------------------------------------------------- slime

/// A big blob of slime: pull it to stretch it, press it to squish it, and
/// it wobbles slowly back. The colour buttons change the slime.
class _SlimeGame extends StatefulWidget {
  const _SlimeGame();
  @override
  State<_SlimeGame> createState() => _SlimeGameState();
}

class _SlimeGameState extends _GameState<_SlimeGame> {
  static const _n = 64;
  static const _colours = [
    Color(0xFF3DDC97),
    Color(0xFFFF7EB6),
    Color(0xFF7AB8FF),
    Color(0xFFFFC94D),
    Color(0xFFB58CFF),
  ];
  final _off = List<Offset>.filled(_n, Offset.zero);
  final _vel = List<Offset>.filled(_n, Offset.zero);
  final _fingers = <int, Offset>{};
  final _lastAt = <int, Offset>{};
  Color _colour = _colours.first;
  Color _shown = _colours.first;
  double _squeeze = 0;

  double get _radius => size.shortestSide * 0.3;
  Offset get _centre => size.center(Offset.zero) + const Offset(0, -10);

  Offset _rest(int i) {
    final a = i / _n * 2 * math.pi;
    final r = _radius * (1 + 0.025 * math.sin(3 * a + time * 0.9));
    return _centre + Offset(math.cos(a), math.sin(a) * 0.86) * r;
  }

  Offset _point(int i) => _rest(i) + _off[i];

  @override
  void down(int pointer, Offset p) {
    _fingers[pointer] = p;
    _lastAt[pointer] = p;
    if ((p - _centre).distance < _radius * 1.2) {
      _squeeze = 1;
      _Sound.squish();
      tick();
    }
  }

  @override
  void move(int pointer, Offset p) => _fingers[pointer] = p;

  @override
  void up(int pointer) {
    _fingers.remove(pointer);
    _lastAt.remove(pointer);
  }

  @override
  void step(double dt) {
    final reach = _radius * 0.75;
    for (final entry in _fingers.entries) {
      final p = entry.value;
      final moved = p - (_lastAt[entry.key] ?? p);
      _lastAt[entry.key] = p;
      for (var i = 0; i < _n; i++) {
        final d = (_point(i) - p).distance;
        final w = math.exp(-(d / reach) * (d / reach));
        // Drag: the slime near the finger follows it (stretch).
        _off[i] += moved * w * 0.9;
        // Press: the slime under the finger is pushed out (squish).
        final away = _point(i) - p;
        if (away.distance > 1 && (p - _centre).distance < _radius) {
          _off[i] += away / away.distance * w * 70 * dt;
        }
      }
    }
    // Springs back to its shape, smoothed by its neighbours, slowly damped.
    for (var i = 0; i < _n; i++) {
      final prev = _off[(i - 1 + _n) % _n], next = _off[(i + 1) % _n];
      final force = -_off[i] * 9 + (prev + next - _off[i] * 2) * 28;
      _vel[i] = (_vel[i] + force * dt) * math.exp(-dt * 3.2);
    }
    for (var i = 0; i < _n; i++) {
      _off[i] += _vel[i] * dt;
      if (_off[i].distance > _radius * 1.6) {
        _off[i] = _off[i] / _off[i].distance * _radius * 1.6;
      }
    }
    _squeeze = math.max(0, _squeeze - dt * 2);
    _shown = Color.lerp(_shown, _colour, 1 - math.exp(-dt * 6))!;
  }

  @override
  List<Widget> overlay(BuildContext context) => [
        Positioned(
          left: 0,
          right: 0,
          bottom: 18,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final c in _colours)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _colour = c),
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.white, width: c == _colour ? 5 : 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black26, blurRadius: 6)
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF2A2F3A), const Color(0xFF161A22));
    final pts = [for (var i = 0; i < _n; i++) _point(i)];
    final path = Path();
    Offset mid(Offset a, Offset b) => (a + b) / 2;
    path.moveTo(mid(pts.last, pts.first).dx, mid(pts.last, pts.first).dy);
    for (var i = 0; i < _n; i++) {
      final m = mid(pts[i], pts[(i + 1) % _n]);
      path.quadraticBezierTo(pts[i].dx, pts[i].dy, m.dx, m.dy);
    }
    path.close();
    final bounds = path.getBounds();
    canvas.drawPath(
        path.shift(const Offset(0, 14)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.25, -0.35),
            radius: 0.95,
            colors: [
              Color.lerp(_shown, Colors.white, 0.45 + 0.15 * _squeeze)!,
              _shown,
              Color.lerp(_shown, Colors.black, 0.3)!,
            ],
            stops: const [0.0, 0.55, 1.0],
          ).createShader(bounds));
    // Tiny bubbles inside the slime move with it.
    canvas.save();
    canvas.clipPath(path);
    final average = _off.reduce((a, b) => a + b) / _n.toDouble();
    final rng = math.Random(3);
    for (var i = 0; i < 26; i++) {
      final a = rng.nextDouble() * 2 * math.pi;
      final d = math.sqrt(rng.nextDouble()) * _radius * 0.85;
      final p = _centre +
          Offset(math.cos(a), math.sin(a) * 0.86) * d +
          average * 0.8 +
          Offset(math.sin(time * 0.7 + i) * 3, math.cos(time * 0.5 + i) * 3);
      canvas.drawCircle(p, 2 + rng.nextDouble() * 4,
          Paint()..color = Colors.white.withValues(alpha: 0.28));
    }
    canvas.restore();
    // Wet shine.
    canvas.drawOval(
        Rect.fromCenter(
            center: Offset(bounds.left + bounds.width * 0.33,
                bounds.top + bounds.height * 0.22),
            width: bounds.width * 0.3,
            height: bounds.height * 0.12),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
  }
}

// ---------------------------------------------------------------- sand

/// Coloured sand pours from every finger and piles up, sliding down the
/// slopes like real sand. The colour changes slowly as you pour.
class _SandGame extends StatefulWidget {
  const _SandGame();
  @override
  State<_SandGame> createState() => _SandGameState();
}

class _SandGameState extends _GameState<_SandGame> {
  int _cols = 0, _rows = 0;
  double _cell = 6;
  Uint16List _grid = Uint16List(0);
  final _fingers = <int, Offset>{};

  void _fit() {
    final cell = math.max(5.0, size.shortestSide / 110);
    final cols = (size.width / cell).floor(),
        rows = (size.height / cell).floor();
    if (cols == _cols && rows == _rows) return;
    _cell = cell;
    _cols = cols;
    _rows = rows;
    _grid = Uint16List(cols * rows);
  }

  @override
  void down(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void move(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void up(int pointer) => _fingers.remove(pointer);

  @override
  List<Widget> overlay(BuildContext context) => [
        PositionedDirectional(
          top: 8,
          end: 8,
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: IconButton(
              iconSize: 30,
              tooltip: I18n.t('Clear'),
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () =>
                  setState(() => _grid.fillRange(0, _grid.length, 0)),
            ),
          ),
        ),
      ];

  @override
  void step(double dt) {
    _fit();
    if (_cols < 3 || _rows < 3) return;
    for (final entry in _fingers.entries) {
      final hue = (time * 36 + entry.key * 70) % 360;
      final cx = (entry.value.dx / _cell).floor(),
          cy = (entry.value.dy / _cell).floor();
      for (var k = 0; k < 7; k++) {
        final x = cx + rng.nextInt(5) - 2, y = cy + rng.nextInt(3) - 1;
        if (x < 0 || y < 0 || x >= _cols || y >= _rows) continue;
        final i = y * _cols + x;
        if (_grid[i] == 0) _grid[i] = hue.round() + 1;
      }
    }
    for (var pass = 0; pass < 2; pass++) {
      for (var y = _rows - 2; y >= 0; y--) {
        final leftFirst = rng.nextBool();
        for (var k = 0; k < _cols; k++) {
          final x = leftFirst ? k : _cols - 1 - k;
          final i = y * _cols + x;
          final v = _grid[i];
          if (v == 0) continue;
          final below = i + _cols;
          if (_grid[below] == 0) {
            _grid[below] = v;
            _grid[i] = 0;
            continue;
          }
          final dir = rng.nextBool() ? 1 : -1;
          for (final d in [dir, -dir]) {
            final nx = x + d;
            if (nx < 0 || nx >= _cols) continue;
            if (_grid[below + d] == 0 && _grid[i + d] == 0) {
              _grid[below + d] = v;
              _grid[i] = 0;
              break;
            }
          }
        }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF1D2B3A), const Color(0xFF0F1720));
    if (_grid.isEmpty) return;
    // Grains grouped by colour band and a little shading, drawn in batches.
    final buckets = <int, List<double>>{};
    for (var y = 0; y < _rows; y++) {
      for (var x = 0; x < _cols; x++) {
        final v = _grid[y * _cols + x];
        if (v == 0) continue;
        final shade = (x * 7 + y * 13) % 3;
        buckets
            .putIfAbsent(((v - 1) ~/ 12) * 3 + shade, () => [])
            .addAll([(x + 0.5) * _cell, (y + 0.5) * _cell]);
      }
    }
    final paint = Paint()
      ..strokeWidth = _cell + 0.6
      ..strokeCap = StrokeCap.square;
    for (final entry in buckets.entries) {
      final hue = (entry.key ~/ 3) * 12.0 + 6;
      paint.color = _hue(hue, s: 0.55, v: 0.98 - (entry.key % 3) * 0.07);
      canvas.drawRawPoints(
          PointMode.points, Float32List.fromList(entry.value), paint);
    }
  }
}

// ---------------------------------------------------------------- marbling

class _Ink {
  List<Offset> pts;
  final Color colour;
  final Offset centre;
  double radius, target;
  _Ink(this.pts, this.colour, this.centre, this.radius, this.target);
}

/// Paint marbling on water: every touch drops paint that spreads and
/// pushes the older colours into rings; dragging a finger combs them into
/// swirls, like the real craft.
class _MarblingGame extends StatefulWidget {
  const _MarblingGame();
  @override
  State<_MarblingGame> createState() => _MarblingGameState();
}

class _MarblingGameState extends _GameState<_MarblingGame> {
  static const _palette = [
    Color(0xFF1F6FB2),
    Color(0xFFF2B33D),
    Color(0xFFD9485F),
    Color(0xFF2FA67F),
    Color(0xFF6A4C93),
    Color(0xFFF7F3EA),
    Color(0xFF16324F),
    Color(0xFFEF8A3C),
  ];
  final _inks = <_Ink>[];
  final _lastAt = <int, Offset>{};
  int _next = 0;

  static List<Offset> _circle(Offset c, double r, [int n = 140]) => [
        for (var i = 0; i < n; i++)
          c +
              Offset(math.cos(i / n * 2 * math.pi),
                      math.sin(i / n * 2 * math.pi)) *
                  r
      ];

  final _startAt = <int, Offset>{};
  final _combing = <int>{};

  /// A tap drops paint; a drag only combs, like drawing a stick through
  /// the paint.
  @override
  void down(int pointer, Offset p) {
    _lastAt[pointer] = p;
    _startAt[pointer] = p;
    _combing.remove(pointer);
  }

  void _drop(Offset p) {
    final target = size.shortestSide * (0.09 + rng.nextDouble() * 0.06);
    _inks.add(
        _Ink(_circle(p, 1), _palette[_next++ % _palette.length], p, 1, target));
    if (_inks.length > 36) _inks.removeAt(0);
    _Sound.drop();
    tick();
  }

  @override
  void move(int pointer, Offset p) {
    final start = _startAt[pointer] ?? p;
    if (!_combing.contains(pointer)) {
      if ((p - start).distance < 10) return;
      _combing.add(pointer);
    }
    final a = _lastAt[pointer] ?? p;
    if ((p - a).distance < 3) return;
    _lastAt[pointer] = p;
    _comb(a, p);
  }

  @override
  void up(int pointer) {
    final start = _startAt.remove(pointer);
    if (start != null && !_combing.contains(pointer)) _drop(start);
    _lastAt.remove(pointer);
    _combing.remove(pointer);
  }

  /// A tine drawn from [a] to [b]: paint near the line is carried along
  /// with it, less the further away it is.
  void _comb(Offset a, Offset b) {
    final m = b - a;
    final length = m.distance;
    final u = m / length;
    final lambda = size.shortestSide * 0.05;
    for (final ink in _inks) {
      if (ink.radius < ink.target) continue;
      final pts = ink.pts;
      for (var i = 0; i < pts.length; i++) {
        final v = pts[i];
        final t = ((v - a).dx * u.dx + (v - a).dy * u.dy).clamp(0.0, length);
        final d = (v - (a + u * t)).distance;
        pts[i] = v + u * (length * lambda / (d + lambda));
      }
      _refine(ink);
    }
  }

  /// Stretched edges get extra points so curves stay smooth.
  void _refine(_Ink ink) {
    if (ink.pts.length > 700) return;
    final out = <Offset>[];
    final pts = ink.pts;
    for (var i = 0; i < pts.length; i++) {
      final a = pts[i], b = pts[(i + 1) % pts.length];
      out.add(a);
      if ((b - a).distance > 9) out.add((a + b) / 2);
    }
    ink.pts = out;
  }

  @override
  void step(double dt) {
    for (final ink in _inks) {
      if (ink.radius >= ink.target) continue;
      final r = math.min(ink.target, ink.radius + ink.target * dt * 2.8);
      final grow = r * r - ink.radius * ink.radius;
      ink.radius = r;
      ink.pts = _circle(ink.centre, r);
      // The spreading drop pushes all other paint outward, keeping its area.
      for (final other in _inks) {
        if (identical(other, ink)) continue;
        final pts = other.pts;
        for (var i = 0; i < pts.length; i++) {
          final d = pts[i] - ink.centre;
          final d2 = d.dx * d.dx + d.dy * d.dy;
          if (d2 < 0.01) continue;
          pts[i] = ink.centre + d * math.sqrt(1 + grow / d2);
        }
        _refine(other);
      }
    }
  }

  @override
  List<Widget> overlay(BuildContext context) => [
        PositionedDirectional(
          top: 8,
          end: 8,
          child: Material(
            color: Colors.black45,
            shape: const CircleBorder(),
            child: IconButton(
              iconSize: 30,
              tooltip: I18n.t('Clear'),
              icon: const Icon(Icons.refresh, color: Colors.white),
              onPressed: () => setState(_inks.clear),
            ),
          ),
        ),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFFF1EADB), const Color(0xFFE6DCC8));
    for (final ink in _inks) {
      canvas.drawPath(
          Path()..addPolygon(ink.pts, true), Paint()..color = ink.colour);
    }
    // A faint sheen of water over the paint.
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.0),
              Colors.white.withValues(alpha: 0.06),
            ],
          ).createShader(Offset.zero & size));
  }
}

// ---------------------------------------------------------------- picture games

/// One picture from the person's own board, in the chosen language.
class _Picture {
  final String word;
  final SymbolRef symbol;
  const _Picture(this.word, this.symbol);
}

class _Topic {
  final String name;
  final SymbolRef symbol;
  final List<_Picture> pictures;
  const _Topic(this.name, this.symbol, this.pictures);
}

/// Pictures for the nonverbal games come from the board (so they match the
/// pictures the person already knows); without a board, a small built-in
/// set is used.
List<_Topic> _topics(BuildContext context) {
  const folders = ['feelings', 'animals', 'fruits', 'food', 'toys', 'vehicles'];
  final topics = <_Topic>[];
  try {
    final vocabulary =
        Provider.of<PackController>(context, listen: false).vocabulary;
    if (vocabulary != null) {
      for (final id in folders) {
        final folder = vocabulary.folders[id];
        final views = vocabulary.viewsByFolder[id];
        if (folder == null || views == null || views.isEmpty) continue;
        final seen = <String>{};
        final pictures = <_Picture>[
          for (final cell in views.first.cells)
            if (!cell.hidden &&
                cell.button.kind == ButtonKind.item &&
                seen.add(cell.button.shownLabel))
              _Picture(cell.button.shownLabel, cell.button.symbol)
        ];
        if (pictures.length >= 6) {
          topics.add(
              _Topic(I18n.word(folder.label, id: id), folder.symbol, pictures));
        }
      }
    }
  } catch (_) {/* No board here: use the built-in pictures. */}
  if (topics.isNotEmpty) return topics;
  const builtIn = [
    ('dog', '🐶'),
    ('cat', '🐱'),
    ('fish', '🐟'),
    ('bird', '🐦'),
    ('apple', '🍎'),
    ('banana', '🍌'),
    ('ball', '⚽'),
    ('car', '🚗'),
    ('happy', '😄'),
    ('sad', '😢'),
    ('bus', '🚌'),
    ('flower', '🌸'),
  ];
  return [
    _Topic(I18n.word('Animals'), const SymbolRef('🐶'), [
      for (final (word, emoji) in builtIn)
        _Picture(I18n.word(word), SymbolRef(emoji))
    ]),
  ];
}

void _say(BuildContext context, String word) {
  try {
    SpeechEngineProvider.of(context).speak(word, interrupt: true);
  } catch (_) {/* No voice here: the picture still answers. */}
}

/// Tap and hear: big pictures from one topic; touching one makes it bounce
/// and says its word. Practises "I touch a picture, it speaks" with no
/// right or wrong answers.
class _HearGame extends StatefulWidget {
  const _HearGame();
  @override
  State<_HearGame> createState() => _HearGameState();
}

class _HearGameState extends State<_HearGame> {
  List<_Topic> _all = const [];
  int _topic = 0;
  List<_Picture> _shown = const [];
  int? _bouncing;
  final _rng = math.Random();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_all.isEmpty) {
      _all = _topics(context);
      _pick(0);
    }
  }

  void _pick(int topic) {
    final pictures = [..._all[topic].pictures]..shuffle(_rng);
    setState(() {
      _topic = topic;
      _shown = pictures.take(6).toList();
      _bouncing = null;
    });
  }

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFF3F6FA),
        padding: const EdgeInsets.fromLTRB(12, 64, 12, 12),
        child: Column(children: [
          SizedBox(
            height: 64,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < _all.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: i == _topic,
                      onSelected: (_) => _pick(i),
                      avatar: SizedBox(
                          width: 30,
                          height: 30,
                          child:
                              SymbolLibrary.resolve(_all[i].symbol, size: 30)),
                      label: Text(_all[i].name,
                          style: const TextStyle(fontSize: 17)),
                    ),
                  ),
                IconButton(
                  iconSize: 34,
                  tooltip: I18n.word('again'),
                  icon: const Icon(Icons.shuffle, color: Color(0xFF1565C0)),
                  onPressed: () => _pick(_topic),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > c.maxHeight ? 3 : 2;
              final rows = (_shown.length / cols).ceil();
              final ratio = (c.maxWidth / cols) / (c.maxHeight / rows);
              return GridView.count(
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: cols,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: ratio.clamp(0.6, 2.2),
                children: [
                  for (var i = 0; i < _shown.length; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _bouncing = i);
                        _say(context, _shown[i].word);
                        try {
                          HapticFeedback.selectionClick();
                        } catch (_) {}
                      },
                      child: AnimatedScale(
                        scale: _bouncing == i ? 1.06 : 1,
                        duration: const Duration(milliseconds: 160),
                        curve: Curves.easeOutBack,
                        onEnd: () {
                          if (mounted && _bouncing == i) {
                            setState(() => _bouncing = null);
                          }
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                                color: _bouncing == i
                                    ? const Color(0xFFFFB300)
                                    : const Color(0xFFDCE3EC),
                                width: _bouncing == i ? 5 : 2),
                            boxShadow: const [
                              BoxShadow(
                                  color: Color(0x22000000),
                                  blurRadius: 8,
                                  offset: Offset(0, 3))
                            ],
                          ),
                          padding: const EdgeInsets.all(10),
                          child: Column(children: [
                            Expanded(
                                child: SymbolLibrary.resolve(_shown[i].symbol)),
                            const SizedBox(height: 6),
                            Text(_shown[i].word,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w700)),
                          ]),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        ]),
      );
}

/// Match pairs: six cards, three pairs. Turn two over; the same picture
/// stays up, says its word and glows. No time limit and no wrong answer:
/// two different pictures simply turn back.
class _PairsGame extends StatefulWidget {
  const _PairsGame();
  @override
  State<_PairsGame> createState() => _PairsGameState();
}

class _PairsGameState extends State<_PairsGame> {
  final _rng = math.Random();
  List<_Picture> _cards = const [];
  final _up = <int>{};
  final _done = <int>{};
  final _timers = <Timer>[];
  bool _celebrate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cards.isEmpty) _deal();
  }

  void _deal() {
    final topics = _topics(context);
    final topic = topics[_rng.nextInt(topics.length)];
    final pictures = [...topic.pictures]..shuffle(_rng);
    setState(() {
      _cards = [...pictures.take(3), ...pictures.take(3)]..shuffle(_rng);
      _up.clear();
      _done.clear();
      _celebrate = false;
    });
  }

  void _later(int ms, VoidCallback f) =>
      _timers.add(Timer(Duration(milliseconds: ms), () {
        if (mounted) f();
      }));

  void _tap(int i) {
    if (_up.contains(i) || _done.contains(i) || _up.length >= 2) return;
    setState(() => _up.add(i));
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
    if (_up.length < 2) return;
    final a = _up.first, b = _up.last;
    if (_cards[a].word == _cards[b].word) {
      _later(450, () {
        setState(() {
          _done.addAll([a, b]);
          _up.clear();
        });
        _Sound.chime();
        _say(context, _cards[a].word);
        if (_done.length == _cards.length) {
          _later(700, () => setState(() => _celebrate = true));
          _later(2600, _deal);
        }
      });
    } else {
      _later(1100, () => setState(_up.clear));
    }
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  Widget _card(int i) {
    final faceUp = _up.contains(i) || _done.contains(i);
    final matched = _done.contains(i);
    return GestureDetector(
      onTap: () => _tap(i),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: faceUp ? 1 : 0),
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
        builder: (context, v, _) {
          final front = v > 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0014)
              ..rotateY(v * math.pi),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(front ? math.pi : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                decoration: BoxDecoration(
                  color: front ? Colors.white : const Color(0xFF3F6FD8),
                  gradient: front
                      ? null
                      : const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF5B8DEF), Color(0xFF3557B7)]),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: matched ? const Color(0xFF43A047) : Colors.white,
                      width: matched ? 6 : 3),
                  boxShadow: [
                    BoxShadow(
                        color: matched
                            ? const Color(0x8843A047)
                            : const Color(0x33000000),
                        blurRadius: matched ? 18 : 8,
                        offset: const Offset(0, 3)),
                  ],
                ),
                padding: const EdgeInsets.all(10),
                child: front
                    ? Column(children: [
                        Expanded(
                            child: SymbolLibrary.resolve(_cards[i].symbol)),
                        Text(_cards[i].word,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                      ])
                    : const Center(
                        child: Icon(Icons.star_rounded,
                            color: Colors.white70, size: 54)),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFEFF3F8),
        padding: const EdgeInsets.fromLTRB(14, 64, 14, 14),
        child: Stack(children: [
          LayoutBuilder(builder: (context, c) {
            final cols = c.maxWidth > c.maxHeight ? 3 : 2;
            final rows = (_cards.length / cols).ceil();
            final ratio = (c.maxWidth / cols) / (c.maxHeight / rows);
            return GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: cols,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: ratio.clamp(0.55, 2.2),
              children: [for (var i = 0; i < _cards.length; i++) _card(i)],
            );
          }),
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _celebrate ? 1 : 0,
              duration: const Duration(milliseconds: 400),
              child: const Center(
                child: Icon(Icons.star_rounded,
                    size: 220, color: Color(0xFFFFC107)),
              ),
            ),
          ),
        ]),
      );
}
