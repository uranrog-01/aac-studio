part of 'sensory_games.dart';

// ---------------------------------------------------------------- GPU shaders

/// The games' GPU shaders (shaders/*.frag), each loaded once. A device
/// that cannot run one gets the game's simpler drawing instead.
class _Shaders {
  static final _programs = <String, Future<ui.FragmentProgram?>>{};

  static Future<ui.FragmentProgram?> load(String name) =>
      _programs.putIfAbsent(name, () async {
        try {
          return await ui.FragmentProgram.fromAsset('shaders/$name.frag');
        } catch (_) {
          return null;
        }
      });
}

/// Sets a shader's uniforms in the order they are declared.
class _Uniforms {
  final ui.FragmentShader shader;
  int _i = 0;
  _Uniforms(this.shader);
  void f(double v) => shader.setFloat(_i++, v);
  void v2(double a, double b) => this
    ..f(a)
    ..f(b);
  void v3(double a, double b, double c) => this
    ..f(a)
    ..f(b)
    ..f(c);
  void v4(double a, double b, double c, double d) => this
    ..v2(a, b)
    ..v2(c, d);
  void colour(Color c) => v3(c.r, c.g, c.b);
}

/// A game drawn (partly) by GPU shaders. [shaders] are loaded when the
/// game opens; [shader] hands out one instance per drawing pass.
mixin _ShaderGame<T extends StatefulWidget> on _GameState<T> {
  List<String> get shaders;
  final _programs = <String, ui.FragmentProgram>{};
  final _instances = <String, ui.FragmentShader>{};

  @override
  void initState() {
    super.initState();
    for (final name in shaders) {
      _Shaders.load(name).then((p) {
        if (p != null && mounted) _programs[name] = p;
      });
    }
  }

  /// A shader for [pass] of [name], or null while it loads (or when the
  /// device cannot run it).
  ui.FragmentShader? shader(String name, [String pass = '']) {
    final program = _programs[name];
    if (program == null) return null;
    return _instances.putIfAbsent('$name$pass', program.fragmentShader);
  }

  void drawShader(Canvas canvas, Size size, ui.FragmentShader s) =>
      canvas.drawRect(Offset.zero & size, Paint()..shader = s);
}

// ---------------------------------------------------------------- ambient

/// Soft, slow music for the calm games: a few pure tones that swell and
/// fade, looping without a seam. Quiet, and off with the speaker button.
class _Ambient {
  static AudioPlayer? _player;
  static final _cache = <String, Source>{};

  static Uint8List _pad(List<double> freqs, {double seconds = 8}) {
    const rate = 22050;
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
    for (var i = 0; i < count; i++) {
      final t = i / rate;
      var s = 0.0;
      for (var k = 0; k < freqs.length; k++) {
        // Every tone and swell repeats a whole number of times in the
        // loop, so the end meets the start smoothly.
        final swell = 0.6 + 0.4 * math.sin(2 * math.pi * (0.125 * (k + 1)) * t + k);
        s += math.sin(2 * math.pi * freqs[k] * t) * swell;
        s += 0.25 * math.sin(2 * math.pi * freqs[k] * 2 * t) * swell;
      }
      s /= freqs.length * 1.25;
      data.setInt16(44 + i * 2, (s * 9000).round(), Endian.little);
    }
    return data.buffer.asUint8List();
  }

  static Future<void> start(String id, List<double> freqs) async {
    if (!_Sound.on) return;
    try {
      final source = _cache.putIfAbsent(id, () {
        final bytes = _pad(freqs);
        return kIsWeb
            ? UrlSource('data:audio/wav;base64,${base64Encode(bytes)}')
            : BytesSource(bytes, mimeType: 'audio/wav');
      });
      final player = _player ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.loop);
      await player.play(source, volume: 0.28);
    } catch (_) {/* No sound here: the pictures are still calming. */}
  }

  static Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}

/// Calm games play soft music while they are open.
mixin _CalmMusic<T extends StatefulWidget> on _GameState<T> {
  String get musicId;
  List<double> get chord;

  @override
  void initState() {
    super.initState();
    _Ambient.start(musicId, chord);
  }

  @override
  void dispose() {
    _Ambient.stop();
    super.dispose();
  }
}

/// A round button in the top corner (colour, start again).
Widget _cornerButton(IconData icon, String tooltip, VoidCallback onPressed) =>
    PositionedDirectional(
      top: 8,
      end: 8,
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        child: IconButton(
          iconSize: 30,
          tooltip: I18n.t(tooltip),
          icon: Icon(icon, color: Colors.white),
          onPressed: onPressed,
        ),
      ),
    );

// ---------------------------------------------------------------- lava lamp

class _Wax {
  double x, y, vx = 0, vy = 0, heat;
  final double r, phase;
  _Wax(this.x, this.y, this.r, this.heat, this.phase);
}

/// A real lava lamp: wax is heated by the bulb, rises slowly, cools at the
/// top and sinks again; blobs stretch, join and split. A finger warms the
/// wax near it so it lifts toward the finger. The corner button changes
/// the colours.
class _LavaGame extends StatefulWidget {
  const _LavaGame();
  @override
  State<_LavaGame> createState() => _LavaGameState();
}

class _LavaGameState extends _GameState<_LavaGame> with _ShaderGame {
  @override
  List<String> get shaders => const ['lava'];

  static const _themes = [
    (Color(0xFFFF5A1F), Color(0xFFFFB13B)), // red wax, yellow liquid
    (Color(0xFFFF4FA3), Color(0xFF6A2BD9)), // pink wax, purple liquid
    (Color(0xFF39E6A6), Color(0xFF1F5FD6)), // green wax, blue liquid
    (Color(0xFFFFE14D), Color(0xFFE3381E)), // yellow wax, red liquid
    (Color(0xFFB7F7FF), Color(0xFF2A1F7A)), // pale blue wax, indigo liquid
  ];
  int _theme = 0;
  final _wax = <_Wax>[];
  final _fingers = <int, Offset>{};

  static const _top = -0.33, _bottom = 0.27;

  double get _unit => math.min(size.height * 0.94, size.width * 1.9);

  static double _halfWidth(double y) {
    final t = ((y - _top) / (_bottom - _top)).clamp(0.0, 1.0);
    return 0.058 + (0.128 - 0.058) * t + 0.012 * math.sin(t * math.pi);
  }

  Offset _toLamp(Offset p) => (p - size.center(Offset.zero)) / _unit;

  @override
  void step(double dt) {
    if (_wax.isEmpty) {
      for (var i = 0; i < 8; i++) {
        final r = 0.026 + rng.nextDouble() * 0.026;
        final y = i < 3 ? _bottom - 0.03 : _top + 0.08 + rng.nextDouble() * 0.45;
        _wax.add(_Wax((rng.nextDouble() - 0.5) * _halfWidth(y), y, r,
            rng.nextDouble(), rng.nextDouble() * 6.28));
      }
    }
    final fingers = [for (final f in _fingers.values) _toLamp(f)];
    for (final w in _wax) {
      // The bulb heats the bottom; the top of the lamp is cooler.
      if (w.y > 0.17) {
        w.heat += dt * 0.16;
      } else if (w.y < -0.21) {
        w.heat -= dt * 0.09;
      } else {
        w.heat -= dt * 0.012;
      }
      for (final f in fingers) {
        final d = (Offset(w.x, w.y) - f).distance;
        if (d < 0.16) {
          w.heat += dt * 0.9;
          w.vx += (f.dx - w.x) * 0.5 * dt;
        }
      }
      w.heat = w.heat.clamp(0.0, 1.0);
      // Warm wax is lighter than the liquid and rises; cool wax sinks.
      w.vy += -(w.heat - 0.5) * 0.08 * dt;
      w.vy *= math.exp(-dt * 1.1);
      w.vy = w.vy.clamp(-0.045, 0.045);
      w.vx += math.sin(time * 0.3 + w.phase) * 0.004 * dt;
      w.vx *= math.exp(-dt * 1.5);
      w.x += w.vx * dt;
      w.y += w.vy * dt;
      if (w.y < _top + w.r * 0.7) {
        w.y = _top + w.r * 0.7;
        w.vy = 0;
      }
      if (w.y > _bottom - w.r * 0.35) {
        w.y = _bottom - w.r * 0.35;
        w.vy = 0;
      }
      final limit = math.max(0.0, _halfWidth(w.y) - w.r * 0.75);
      w.x = w.x.clamp(-limit, limit);
    }
  }

  @override
  void down(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void move(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void up(int pointer) => _fingers.remove(pointer);

  @override
  List<Widget> overlay(BuildContext context) => [
        _cornerButton(Icons.palette, 'Change',
            () => setState(() => _theme = (_theme + 1) % _themes.length)),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final (waxColour, liquid) = _themes[_theme];
    final s = shader('lava');
    if (s == null) {
      _background(canvas, size, const Color(0xFF1B0B2E), const Color(0xFF3A0D2B));
      return;
    }
    final u = _Uniforms(s)
      ..v2(size.width, size.height)
      ..f(time)
      ..colour(waxColour)
      ..colour(liquid);
    for (var i = 0; i < 8; i++) {
      if (i < _wax.length) {
        final w = _wax[i];
        final pulse = 1 + 0.07 * math.sin(time * 0.5 + w.phase);
        u.v4(w.x, w.y, w.r * pulse, 0);
      } else {
        u.v4(0, 0, 0, 0);
      }
    }
    drawShader(canvas, size, s);
  }
}

// ---------------------------------------------------------------- pond

class _Ring {
  final Offset pos;
  final double strength;
  double age = 0;
  _Ring(this.pos, this.strength);
}

class _Fish {
  Offset pos;
  double angle, speed, turn = 0;
  final double length;
  final int pattern;
  _Fish(this.pos, this.angle, this.speed, this.length, this.pattern);
}

class _Pad {
  Offset pos, vel = Offset.zero;
  final double r, angle;
  final bool flower;
  _Pad(this.pos, this.r, this.angle, this.flower);
}

/// A clear pond seen from above: real ripples bend the light on the
/// pebbles, koi swim under the water and lily pads rock on it. Touch the
/// water, or draw through it.
class _WaterGame extends StatefulWidget {
  const _WaterGame();
  @override
  State<_WaterGame> createState() => _WaterGameState();
}

class _WaterGameState extends _GameState<_WaterGame> with _ShaderGame {
  @override
  List<String> get shaders => const ['water'];

  final _rings = <_Ring>[];
  final _fish = <_Fish>[];
  final _pads = <_Pad>[];
  final _lastRing = <int, double>{};

  static const _koi = [
    [Color(0xFFFFF8F0), Color(0xFFE8521C)],
    [Color(0xFFFF8A1F), Color(0xFFFFF3E0)],
    [Color(0xFFFFFFFF), Color(0xFF222222)],
    [Color(0xFFFFD54F), Color(0xFFFF7043)],
    [Color(0xFFF5F5F5), Color(0xFFD32F2F)],
    [Color(0xFFFFB74D), Color(0xFF212121)],
  ];

  @override
  void step(double dt) {
    if (_fish.isEmpty) {
      for (var i = 0; i < 6; i++) {
        _fish.add(_Fish(
            Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
            rng.nextDouble() * 6.283,
            26 + rng.nextDouble() * 16,
            size.shortestSide * (0.11 + rng.nextDouble() * 0.05),
            i));
      }
      for (var i = 0; i < 4; i++) {
        _pads.add(_Pad(
            Offset(size.width * (0.15 + 0.7 * rng.nextDouble()),
                size.height * (0.15 + 0.7 * rng.nextDouble())),
            size.shortestSide * (0.06 + rng.nextDouble() * 0.035),
            rng.nextDouble() * 6.283,
            i == 1));
      }
    }
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age > 4.5);
    for (final f in _fish) {
      f.turn += (rng.nextDouble() - 0.5) * 1.6 * dt;
      f.turn = f.turn.clamp(-0.6, 0.6);
      var steer = f.turn;
      final ahead = f.pos + Offset(math.cos(f.angle), math.sin(f.angle)) * 90;
      if (ahead.dx < 30 ||
          ahead.dy < 30 ||
          ahead.dx > size.width - 30 ||
          ahead.dy > size.height - 30) {
        final home = size.center(Offset.zero) - f.pos;
        steer = _wrap(math.atan2(home.dy, home.dx) - f.angle).clamp(-1.6, 1.6);
      }
      var speed = f.speed;
      for (final r in _rings) {
        final away = f.pos - r.pos;
        if (r.age < 1.0 && away.distance < 170) {
          steer = _wrap(math.atan2(away.dy, away.dx) - f.angle).clamp(-3.0, 3.0);
          speed = f.speed * 2.6;
        }
      }
      f.angle += steer * dt;
      f.pos += Offset(math.cos(f.angle), math.sin(f.angle)) * speed * dt;
      f.pos = Offset(f.pos.dx.clamp(-40.0, size.width + 40),
          f.pos.dy.clamp(-40.0, size.height + 40));
    }
    for (final pad in _pads) {
      for (final r in _rings) {
        final away = pad.pos - r.pos;
        final front = r.age * 175;
        if ((away.distance - front).abs() < 30 && away.distance > 1) {
          pad.vel += away / away.distance * 22 * dt * r.strength;
        }
      }
      pad.vel *= math.exp(-dt * 0.8);
      pad.pos += pad.vel * dt;
      pad.pos = Offset(pad.pos.dx.clamp(pad.r, size.width - pad.r),
          pad.pos.dy.clamp(pad.r, size.height - pad.r));
    }
  }

  static double _wrap(double a) {
    while (a > math.pi) {
      a -= 2 * math.pi;
    }
    while (a < -math.pi) {
      a += 2 * math.pi;
    }
    return a;
  }

  void _ripple(int pointer, Offset p, {bool force = false}) {
    if (!force && time - (_lastRing[pointer] ?? -1) < 0.16) return;
    _lastRing[pointer] = time;
    _rings.add(_Ring(p, force ? 1.0 : 0.55));
    if (_rings.length > 8) _rings.removeAt(0);
  }

  @override
  void down(int pointer, Offset p) {
    _ripple(pointer, p, force: true);
    _Sound.drop();
    tick();
  }

  @override
  void move(int pointer, Offset p) => _ripple(pointer, p);

  void _rippleUniforms(_Uniforms u) {
    for (var i = 0; i < 8; i++) {
      if (i < _rings.length) {
        final r = _rings[_rings.length - 1 - i];
        u.v4(r.pos.dx, r.pos.dy, r.age, r.strength);
      } else {
        u.v4(0, 0, -1, 0);
      }
    }
  }

  void _drawKoi(Canvas canvas, _Fish f) {
    final l = f.length;
    final colours = _koi[f.pattern % _koi.length];
    final wag = math.sin(time * 5 + f.pattern) * 0.3;
    // Shadow on the pebbles below.
    canvas.save();
    canvas.translate(f.pos.dx + l * 0.28, f.pos.dy + l * 0.36);
    canvas.rotate(f.angle);
    canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: l * 1.05, height: l * 0.36),
        Paint()
          ..color = const Color(0x40000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.restore();
    canvas.save();
    canvas.translate(f.pos.dx, f.pos.dy);
    canvas.rotate(f.angle);
    final fin = Paint()..color = colours[0].withValues(alpha: 0.55);
    // Flowing tail and side fins.
    final tail = Path()
      ..moveTo(-l * 0.4, 0)
      ..quadraticBezierTo(-l * 0.62, -l * 0.05 + wag * l * 0.2,
          -l * 0.86, -l * 0.24 + wag * l * 0.35)
      ..quadraticBezierTo(-l * 0.7, wag * l * 0.2, -l * 0.86, l * 0.24 + wag * l * 0.35)
      ..quadraticBezierTo(-l * 0.62, l * 0.05 + wag * l * 0.2, -l * 0.4, 0);
    canvas.drawPath(tail, fin);
    for (final side in const [-1.0, 1.0]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(l * 0.12, side * l * 0.2),
              width: l * 0.24,
              height: l * 0.13),
          fin);
    }
    final body = Path()
      ..moveTo(l * 0.5, 0)
      ..cubicTo(l * 0.42, -l * 0.2, -l * 0.2, -l * 0.17, -l * 0.42, 0)
      ..cubicTo(-l * 0.2, l * 0.17, l * 0.42, l * 0.2, l * 0.5, 0);
    final bounds = Rect.fromCenter(center: Offset.zero, width: l, height: l * 0.4);
    canvas.drawPath(
        body,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(0.2, -0.3),
                  colors: [Colors.white, colours[0]])
              .createShader(bounds));
    canvas.save();
    canvas.clipPath(body);
    final patch = Paint()..color = colours[1].withValues(alpha: 0.92);
    final seed = f.pattern * 1.7;
    for (var k = 0; k < 3; k++) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(l * (0.3 - k * 0.27), l * 0.06 * math.sin(seed + k)),
              width: l * (0.22 + 0.06 * math.cos(seed + k * 2)),
              height: l * 0.2),
          patch);
    }
    // A soft sheen along the back gives the body roundness.
    canvas.drawRect(
        bounds,
        Paint()
          ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x55FFFFFF), Color(0x00FFFFFF), Color(0x33000000)])
              .createShader(bounds));
    canvas.restore();
    canvas.drawCircle(Offset(l * 0.38, -l * 0.07), l * 0.025,
        Paint()..color = const Color(0xFF1A1A1A));
    canvas.drawCircle(Offset(l * 0.38, l * 0.07), l * 0.025,
        Paint()..color = const Color(0xFF1A1A1A));
    canvas.restore();
  }

  void _drawPad(Canvas canvas, _Pad pad) {
    final r = pad.r;
    canvas.save();
    canvas.translate(pad.pos.dx, pad.pos.dy);
    canvas.drawOval(
        Rect.fromCircle(center: Offset(r * 0.14, r * 0.18), radius: r),
        Paint()
          ..color = const Color(0x33000000)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.rotate(pad.angle + math.sin(time * 0.4 + r) * 0.05);
    final leaf = Path()
      ..moveTo(0, 0)
      ..arcTo(Rect.fromCircle(center: Offset.zero, radius: r), 0.18,
          2 * math.pi - 0.36, false)
      ..close();
    canvas.drawPath(
        leaf,
        Paint()
          ..shader = const RadialGradient(
                  center: Alignment(-0.3, -0.3),
                  colors: [Color(0xFF7CC66A), Color(0xFF2E7D32)])
              .createShader(Rect.fromCircle(center: Offset.zero, radius: r)));
    final vein = Paint()
      ..color = const Color(0x5532A852)
      ..strokeWidth = 1.2;
    for (var k = 1; k < 9; k++) {
      final a = 0.18 + k * (2 * math.pi - 0.36) / 9;
      canvas.drawLine(Offset.zero, Offset(math.cos(a), math.sin(a)) * r * 0.92, vein);
    }
    if (pad.flower) {
      for (var k = 0; k < 10; k++) {
        final a = k / 10 * 2 * math.pi;
        canvas.save();
        canvas.rotate(a);
        canvas.drawOval(
            Rect.fromCenter(
                center: Offset(r * 0.28, 0), width: r * 0.55, height: r * 0.22),
            Paint()
              ..shader = const LinearGradient(
                      colors: [Color(0xFFFFF1F6), Color(0xFFF48FB1)])
                  .createShader(Rect.fromLTWH(0, -r * 0.11, r * 0.56, r * 0.22)));
        canvas.restore();
      }
      canvas.drawCircle(Offset.zero, r * 0.12, Paint()..color = const Color(0xFFFFD54F));
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final floor = shader('water', 'floor');
    final surface = shader('water', 'surface');
    if (floor == null || surface == null) {
      _background(canvas, size, const Color(0xFF1C8FA6), const Color(0xFF0A3F5C));
      for (final f in _fish) {
        _drawKoi(canvas, f);
      }
      return;
    }
    final u = _Uniforms(floor)
      ..v2(size.width, size.height)
      ..f(time)
      ..f(0);
    _rippleUniforms(u);
    drawShader(canvas, size, floor);
    for (final f in _fish) {
      _drawKoi(canvas, f);
    }
    final s = _Uniforms(surface)
      ..v2(size.width, size.height)
      ..f(time)
      ..f(1);
    _rippleUniforms(s);
    drawShader(canvas, size, surface);
    for (final pad in _pads) {
      _drawPad(canvas, pad);
    }
  }
}

// ---------------------------------------------------------------- light tunnel

/// Calm: travel slowly down a tunnel of soft light toward a warm glow.
/// Holding a finger slows the journey, brightens the light and steers.
class _TunnelGame extends StatefulWidget {
  const _TunnelGame();
  @override
  State<_TunnelGame> createState() => _TunnelGameState();
}

class _TunnelGameState extends _GameState<_TunnelGame>
    with _ShaderGame, _CalmMusic {
  @override
  List<String> get shaders => const ['tunnel'];
  @override
  String get musicId => 'tunnel';
  @override
  List<double> get chord => const [130.75, 164.875, 196.0, 293.625];

  double _travel = 0, _glow = 0, _palette = 0;
  Offset _centre = Offset.zero, _target = Offset.zero;
  final _fingers = <int, Offset>{};

  @override
  void step(double dt) {
    final touching = _fingers.isNotEmpty;
    _travel += dt * (touching ? 0.45 : 1.0);
    _glow += ((touching ? 1.0 : 0.0) - _glow) * (1 - math.exp(-dt * 1.5));
    _palette += dt * 0.012;
    if (touching) {
      final f = _fingers.values.first;
      _target = Offset((f.dx / size.width - 0.5) * 2, (f.dy / size.height - 0.5) * 2);
    } else {
      _target = Offset(math.sin(time * 0.07) * 0.35, math.cos(time * 0.05) * 0.25);
    }
    _centre += (_target - _centre) * (1 - math.exp(-dt * 0.8));
  }

  @override
  void down(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void move(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void up(int pointer) => _fingers.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    final s = shader('tunnel');
    if (s == null) {
      _background(canvas, size, const Color(0xFF1A2050), const Color(0xFF0B0F24));
      return;
    }
    _Uniforms(s)
      ..v2(size.width, size.height)
      ..f(_travel)
      ..v2(_centre.dx, _centre.dy)
      ..f(_glow)
      ..f(_palette);
    drawShader(canvas, size, s);
  }
}

// ---------------------------------------------------------------- aurora

/// Calm: northern lights ripple over mountains and a still lake. A finger
/// makes the lights glow where it rests; a tap sends a shooting star.
class _AuroraGame extends StatefulWidget {
  const _AuroraGame();
  @override
  State<_AuroraGame> createState() => _AuroraGameState();
}

class _AuroraGameState extends _GameState<_AuroraGame>
    with _ShaderGame, _CalmMusic {
  @override
  List<String> get shaders => const ['aurora'];
  @override
  String get musicId => 'aurora';
  @override
  List<double> get chord => const [110.0, 130.75, 164.875, 246.875];

  Offset _touch = const Offset(0.5, 0.6);
  double _strength = 0;
  Offset _shoot = Offset.zero;
  double _shootAge = 9;
  bool _held = false;

  @override
  void step(double dt) {
    _strength += ((_held ? 1.0 : 0.0) - _strength) * (1 - math.exp(-dt * 1.2));
    _shootAge += dt;
    // Now and then a shooting star by itself.
    if (_shootAge > 14 && rng.nextDouble() < dt * 0.08) {
      _shoot = Offset(0.4 + rng.nextDouble() * 0.5, 0.7 + rng.nextDouble() * 0.25);
      _shootAge = 0;
    }
  }

  Offset _norm(Offset p) => Offset(p.dx / size.width, 1 - p.dy / size.height);

  @override
  void down(int pointer, Offset p) {
    _held = true;
    _touch = _norm(p);
    if (_shootAge > 1.4) {
      _shoot = Offset(_touch.dx + 0.15, math.max(_touch.dy, 0.55) + 0.1);
      _shootAge = 0;
    }
  }

  @override
  void move(int pointer, Offset p) => _touch = _norm(p);
  @override
  void up(int pointer) => _held = false;

  @override
  void paint(Canvas canvas, Size size) {
    final s = shader('aurora');
    if (s == null) {
      _background(canvas, size, const Color(0xFF03060F), const Color(0xFF0B1A2C));
      return;
    }
    _Uniforms(s)
      ..v2(size.width, size.height)
      ..f(time)
      ..v3(_touch.dx, _touch.dy, _strength)
      ..v3(_shoot.dx, _shoot.dy, _shootAge);
    drawShader(canvas, size, s);
  }
}

// ---------------------------------------------------------------- jellyfish

class _Jelly {
  Offset pos, vel;
  final double size, hue, period, phase, depth;
  final List<List<Offset>> tentacles;
  _Jelly(this.pos, this.vel, this.size, this.hue, this.period, this.phase,
      this.depth, this.tentacles);
}

/// Calm: glowing jellyfish drift in a deep, quiet ocean. They pulse
/// slowly; a finger draws them gently near and makes them glow brighter.
class _JellyfishGame extends StatefulWidget {
  const _JellyfishGame();
  @override
  State<_JellyfishGame> createState() => _JellyfishGameState();
}

class _JellyfishGameState extends _GameState<_JellyfishGame>
    with _ShaderGame, _CalmMusic {
  @override
  List<String> get shaders => const ['ocean'];
  @override
  String get musicId => 'ocean';
  @override
  List<double> get chord => const [87.25, 110.0, 130.75, 164.875];

  final _jellies = <_Jelly>[];
  final _fingers = <int, Offset>{};

  _Jelly _make({bool below = false}) {
    final depth = 0.55 + rng.nextDouble() * 0.45;
    final s = size.shortestSide * (0.11 + 0.1 * depth);
    final start = Offset(
        size.width * (0.1 + 0.8 * rng.nextDouble()),
        below ? size.height + s * 2 : size.height * rng.nextDouble());
    return _Jelly(
        start,
        Offset.zero,
        s,
        const [190.0, 280.0, 320.0, 200.0, 30.0][rng.nextInt(5)],
        3.2 + rng.nextDouble() * 1.4,
        rng.nextDouble() * 6.28,
        depth,
        [for (var k = 0; k < 9; k++) List.filled(14, start)]);
  }

  /// 0 relaxed .. 1 fully squeezed, a slow beat.
  double _squeeze(_Jelly j) {
    final t = ((time + j.phase) % j.period) / j.period;
    return t < 0.3 ? math.sin(t / 0.3 * math.pi / 2) : math.cos((t - 0.3) / 0.7 * math.pi / 2);
  }

  @override
  void step(double dt) {
    if (_jellies.isEmpty) {
      final count = (size.width * size.height / 90000).clamp(4, 7).round();
      for (var i = 0; i < count; i++) {
        _jellies.add(_make());
      }
      _jellies.sort((a, b) => a.depth.compareTo(b.depth));
    }
    for (var i = 0; i < _jellies.length; i++) {
      final j = _jellies[i];
      final squeeze = _squeeze(j);
      // Each beat pushes it up; between beats it sinks a little.
      var accel = Offset(math.sin(time * 0.2 + j.phase) * 4, 6) +
          Offset(0, -squeeze * 34);
      for (final f in _fingers.values) {
        final to = f - j.pos;
        if (to.distance > 10 && to.distance < 320) accel += to / to.distance * 16;
      }
      j.vel += accel * dt;
      j.vel *= math.exp(-dt * 0.9);
      j.pos += j.vel * dt * (0.6 + 0.4 * j.depth);
      if (j.pos.dy < -j.size * 2.5) _jellies[i] = _make(below: true);
      // The tentacles trail behind, each point following the one before.
      final rim = j.size * 0.5 * (1 - squeeze * 0.2);
      for (var k = 0; k < j.tentacles.length; k++) {
        final t = j.tentacles[k];
        final x = (k / (j.tentacles.length - 1) - 0.5) * rim * 1.7;
        t[0] = j.pos + Offset(x, j.size * 0.12);
        for (var s = 1; s < t.length; s++) {
          final sway = math.sin(time * 1.3 + k + s * 0.5) * 0.9;
          final want = t[s - 1] + Offset(sway, j.size * 0.11);
          t[s] = Offset.lerp(t[s], want, 1 - math.exp(-dt * 7))!;
        }
      }
    }
  }

  @override
  void down(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void move(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void up(int pointer) => _fingers.remove(pointer);

  void _drawJelly(Canvas canvas, _Jelly j) {
    final squeeze = _squeeze(j);
    var near = 0.0;
    for (final f in _fingers.values) {
      near = math.max(near, 1 - ((f - j.pos).distance / 320).clamp(0.0, 1.0));
    }
    final glow = (0.55 + 0.45 * j.depth) * (1 + near * 0.8);
    final w = j.size * (1 - squeeze * 0.2);
    final h = j.size * 0.62 * (1 + squeeze * 0.15);
    final c = j.pos;
    final colour = _hue(j.hue, s: 0.55);
    // Soft halo.
    canvas.drawCircle(
        c,
        j.size * 1.4,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(colors: [
            colour.withValues(alpha: 0.22 * glow),
            colour.withValues(alpha: 0),
          ]).createShader(Rect.fromCircle(center: c, radius: j.size * 1.4)));
    // Tentacles.
    final strand = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (final t in j.tentacles) {
      for (var s = 1; s < t.length; s++) {
        final fade = 1 - s / t.length;
        strand
          ..strokeWidth = 1.6 + fade * 1.6
          ..color = colour.withValues(alpha: 0.45 * fade * glow);
        canvas.drawLine(t[s - 1], t[s], strand);
      }
    }
    // Frilly oral arms in the middle.
    for (var k = -1; k <= 1; k++) {
      final path = Path()..moveTo(c.dx + k * w * 0.08, c.dy + h * 0.05);
      for (var s = 1; s <= 8; s++) {
        path.lineTo(
            c.dx + k * w * 0.1 + math.sin(time * 1.1 + s * 0.8 + k) * w * 0.06,
            c.dy + h * 0.05 + s * j.size * 0.09);
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 0.06
            ..strokeCap = StrokeCap.round
            ..blendMode = BlendMode.plus
            ..color = _hue(j.hue + 20, s: 0.4).withValues(alpha: 0.35 * glow));
    }
    // The bell: a translucent dome, brighter at its crown and rim.
    final bell = Path()
      ..moveTo(c.dx - w / 2, c.dy + h * 0.12)
      ..cubicTo(c.dx - w * 0.55, c.dy - h * 0.95, c.dx + w * 0.55, c.dy - h * 0.95,
          c.dx + w / 2, c.dy + h * 0.12)
      ..quadraticBezierTo(c.dx + w * 0.25, c.dy + h * 0.02 + squeeze * h * 0.08,
          c.dx, c.dy + h * 0.1)
      ..quadraticBezierTo(c.dx - w * 0.25, c.dy + h * 0.02 + squeeze * h * 0.08,
          c.dx - w / 2, c.dy + h * 0.12)
      ..close();
    final rect = Rect.fromCenter(center: c - Offset(0, h * 0.35), width: w, height: h);
    canvas.drawPath(
        bell,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
              center: const Alignment(0, -0.4),
              radius: 0.9,
              colors: [
                Colors.white.withValues(alpha: 0.55 * glow),
                colour.withValues(alpha: 0.45 * glow),
                colour.withValues(alpha: 0.18 * glow),
              ],
              stops: const [0.0, 0.5, 1.0]).createShader(rect));
    // Faint canals running from the crown to the rim.
    final canal = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..blendMode = BlendMode.plus
      ..color = Colors.white.withValues(alpha: 0.12 * glow);
    for (var k = 1; k < 8; k++) {
      final x = (k / 8 - 0.5) * w;
      canvas.drawPath(
          Path()
            ..moveTo(c.dx + x * 0.2, c.dy - h * 0.72)
            ..quadraticBezierTo(c.dx + x * 0.9, c.dy - h * 0.45, c.dx + x, c.dy + h * 0.08),
          canal);
    }
    canvas.drawPath(
        bell,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..blendMode = BlendMode.plus
          ..color = Colors.white.withValues(alpha: 0.35 * glow));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = shader('ocean');
    if (s == null) {
      _background(canvas, size, const Color(0xFF0B3C57), const Color(0xFF010A14));
    } else {
      _Uniforms(s)
        ..v2(size.width, size.height)
        ..f(time)
        ..v3(0.6, 0.75, 1.0);
      drawShader(canvas, size, s);
    }
    for (final j in _jellies) {
      _drawJelly(canvas, j);
    }
  }
}
