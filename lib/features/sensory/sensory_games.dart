import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../engine/i18n.dart';
import '../../engine/settings_controller.dart';
import '../../engine/speech_provider.dart';
import '../../engine/symbol_library.dart';
import '../../models/domain.dart';

part 'sensory_games_more.dart';

/// Sensory games for regulation and cause-and-effect play, made for
/// autistic users: slow, predictable movement, soft glowing colours, an
/// immediate answer to every touch, and nothing to win or lose. No scores,
/// timers, flashing or sudden sounds.
///
/// Every game is drawn by the app itself, so it looks and behaves the same
/// on Android, iPhone, iPad and the web, and works without internet.
class SensoryGame {
  final String id;

  /// English board word; shown through I18n.word in the chosen language.
  final String word;
  final IconData icon;
  final Color color;
  final Widget Function() build;
  const SensoryGame(this.id, this.word, this.icon, this.color, this.build);
}

/// Turns every game sound on or off (the speaker button in the menu).
set sensorySoundsOn(bool value) => _Sound.on = value;
bool get sensorySoundsOn => _Sound.on;

final kSensoryGames = <SensoryGame>[
  // Satisfying: things to press, squeeze, pour and swirl.
  SensoryGame('popit', 'pop it', Icons.grid_on, const Color(0xFFEF5350),
      () => const _PopItGame()),
  SensoryGame('slime', 'slime', Icons.water_drop, const Color(0xFF26C6DA),
      () => const _SlimeGame()),
  SensoryGame('sand', 'sand', Icons.grain, const Color(0xFFD4A04C),
      () => const _SandGame()),
  SensoryGame('marbling', 'paint swirl', Icons.palette, const Color(0xFF5C6BC0),
      () => const _MarblingGame()),
  SensoryGame('bubbles', 'bubbles', Icons.bubble_chart, const Color(0xFF29B6F6),
      () => const _BubblesGame()),
  SensoryGame('lights', 'light painting', Icons.auto_awesome,
      const Color(0xFFAB47BC), () => const _LightsGame()),
  SensoryGame('water', 'water ripples', Icons.water, const Color(0xFF26A69A),
      () => const _WaterGame()),
  SensoryGame('kaleidoscope', 'kaleidoscope', Icons.filter_vintage,
      const Color(0xFFEC407A), () => const _KaleidoscopeGame()),
  SensoryGame('lava', 'lava lamp', Icons.blur_on, const Color(0xFFFF7043),
      () => const _LavaGame()),
  SensoryGame('xylophone', 'xylophone', Icons.piano, const Color(0xFFFFCA28),
      () => const _XylophoneGame()),
  SensoryGame('spinner', 'spinner', Icons.toys, const Color(0xFF66BB6A),
      () => const _SpinnerGame()),
  // Nonverbal: pictures from the person's own board, spoken aloud.
  SensoryGame('hear', 'tap and hear', Icons.record_voice_over,
      const Color(0xFF42A5F5), () => const _HearGame()),
  SensoryGame('pairs', 'match pairs', Icons.style, const Color(0xFF7E57C2),
      () => const _PairsGame()),
];

/// The games menu, or one game when [game] names it (a board button).
class SensoryGamesScreen extends StatefulWidget {
  final String? game;
  const SensoryGamesScreen({super.key, this.game});

  @override
  State<SensoryGamesScreen> createState() => _SensoryGamesScreenState();
}

class _SensoryGamesScreenState extends State<SensoryGamesScreen> {
  late SensoryGame? _open = _find(widget.game);

  static SensoryGame? _find(String? id) {
    for (final g in kSensoryGames) {
      if (g.id == id) return g;
    }
    return null;
  }

  void _close() {
    // A game opened from its own board button goes straight back to the
    // board; one opened from the menu goes back to the menu.
    if (_open != null && _find(widget.game) == null) {
      setState(() => _open = null);
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return PopScope(
      canPop: open == null || _find(widget.game) != null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF10161D),
        body: SafeArea(
          child: Stack(children: [
            Positioned.fill(
                child: open == null
                    ? _menu(context)
                    : KeyedSubtree(
                        key: ValueKey(open.id), child: open.build())),
            PositionedDirectional(
              top: 8,
              start: 8,
              child: Material(
                color: Colors.black45,
                shape: const CircleBorder(),
                child: IconButton(
                  iconSize: 30,
                  tooltip: I18n.t('Back'),
                  icon: Icon(open == null ? Icons.close : Icons.arrow_back,
                      color: Colors.white),
                  onPressed: _close,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _menu(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Column(children: [
          SizedBox(
            height: 62,
            child: Stack(children: [
              Center(
                child: Text(I18n.word('Games'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
              ),
              // Every game sound is soft; this turns them all off.
              PositionedDirectional(
                top: 8,
                end: 8,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 30,
                    tooltip: I18n.t('Sound'),
                    icon: Icon(_Sound.on ? Icons.volume_up : Icons.volume_off,
                        color: Colors.white),
                    onPressed: () => setState(() => _Sound.on = !_Sound.on),
                  ),
                ),
              ),
            ]),
          ),
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
              crossAxisCount: c.maxWidth >= 900
                  ? 4
                  : c.maxWidth >= 560
                      ? 3
                      : 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
              children: [
                for (final g in kSensoryGames)
                  Material(
                    color: g.color,
                    borderRadius: BorderRadius.circular(26),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => setState(() => _open = g),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(g.icon, size: 64, color: Colors.white),
                            const SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(I18n.word(g.word),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ]),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      );
}

// ---------------------------------------------------------------- engine

/// One animated, touchable canvas. Subclasses move things in [step], draw
/// them in [paint] and answer fingers in [down] / [move] / [up] (every
/// finger is followed, so two hands or two people can play).
abstract class _GameState<T extends StatefulWidget> extends State<T>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double time = 0;
  Size size = Size.zero;
  final rng = math.Random();

  void step(double dt) {}
  void paint(Canvas canvas, Size size);
  void down(int pointer, Offset p) {}
  void move(int pointer, Offset p) {}
  void up(int pointer) {}

  /// Extra controls drawn over the canvas (e.g. Clear).
  List<Widget> overlay(BuildContext context) => const [];

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
      _last = elapsed;
      time += dt;
      if (!mounted) return;
      if (size != Size.zero) step(dt);
      setState(() {});
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void tick() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {/* No vibration on this device. */}
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        size = c.biggest;
        return Stack(children: [
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (e) => down(e.pointer, e.localPosition),
              onPointerMove: (e) => move(e.pointer, e.localPosition),
              onPointerUp: (e) => up(e.pointer),
              onPointerCancel: (e) => up(e.pointer),
              child: RepaintBoundary(
                child: CustomPaint(
                    painter: _GamePainter(this),
                    child: const SizedBox.expand()),
              ),
            ),
          ),
          ...overlay(context),
        ]);
      });
}

class _GamePainter extends CustomPainter {
  final _GameState game;
  _GamePainter(this.game);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    game.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Color _hue(double hue, {double alpha = 1, double s = 1, double v = 1}) =>
    HSVColor.fromAHSV(alpha.clamp(0.0, 1.0), hue % 360, s, v).toColor();

void _background(Canvas canvas, Size size, Color top, Color bottom) {
  final rect = Offset.zero & size;
  canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [top, bottom]).createShader(rect));
}

// ---------------------------------------------------------------- bubbles

class _Bubble {
  Offset pos;
  final double r, speed, phase, hue;
  _Bubble(this.pos, this.r, this.speed, this.phase, this.hue);
}

class _Drop {
  Offset pos, vel;
  double life = 1;
  final double hue;
  _Drop(this.pos, this.vel, this.hue);
}

/// Soap bubbles drift up slowly; touch one (or sweep a finger through
/// several) and it pops into droplets.
class _BubblesGame extends StatefulWidget {
  const _BubblesGame();
  @override
  State<_BubblesGame> createState() => _BubblesGameState();
}

class _BubblesGameState extends _GameState<_BubblesGame> {
  final _bubbles = <_Bubble>[];
  final _drops = <_Drop>[];

  @override
  void step(double dt) {
    final target = (size.width * size.height / 26000).clamp(8, 26).round();
    if (_bubbles.length < target && rng.nextDouble() < 0.08) {
      final r = 26 + rng.nextDouble() * 38;
      _bubbles.add(_Bubble(
          Offset(rng.nextDouble() * size.width,
              size.height + r + rng.nextDouble() * 60),
          r,
          18 + rng.nextDouble() * 30,
          rng.nextDouble() * 6.28,
          170 + rng.nextDouble() * 130));
    }
    for (final b in _bubbles) {
      b.pos = Offset(b.pos.dx + math.sin(time * 0.8 + b.phase) * 14 * dt,
          b.pos.dy - b.speed * dt);
    }
    _bubbles.removeWhere((b) => b.pos.dy < -b.r - 8);
    for (final d in _drops) {
      d.vel += Offset(0, 260 * dt);
      d.pos += d.vel * dt;
      d.life -= dt * 1.6;
    }
    _drops.removeWhere((d) => d.life <= 0);
  }

  void _pop(Offset p) {
    for (var i = _bubbles.length - 1; i >= 0; i--) {
      final b = _bubbles[i];
      if ((b.pos - p).distance < b.r + 14) {
        _bubbles.removeAt(i);
        _Sound.bubble();
        for (var k = 0; k < 12; k++) {
          final a = k / 12 * 6.283 + rng.nextDouble() * 0.4;
          final v = 70 + rng.nextDouble() * 110;
          _drops.add(_Drop(b.pos + Offset(math.cos(a), math.sin(a)) * b.r * 0.8,
              Offset(math.cos(a), math.sin(a)) * v, b.hue));
        }
        tick();
        return;
      }
    }
  }

  @override
  void down(int pointer, Offset p) => _pop(p);
  @override
  void move(int pointer, Offset p) => _pop(p);

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF0B2A4A), const Color(0xFF0E5E6F));
    for (final b in _bubbles) {
      final rect = Rect.fromCircle(center: b.pos, radius: b.r);
      // Thin soap film: almost clear in the middle, coloured at the rim.
      canvas.drawCircle(
          b.pos,
          b.r,
          Paint()
            ..shader = RadialGradient(colors: [
              Colors.white.withValues(alpha: 0.03),
              _hue(b.hue, alpha: 0.16, s: 0.6),
              _hue(b.hue + 60, alpha: 0.45, s: 0.55),
              Colors.white.withValues(alpha: 0.75),
            ], stops: const [
              0.55,
              0.82,
              0.95,
              1.0
            ]).createShader(rect));
      canvas.drawOval(
          Rect.fromCenter(
              center: b.pos + Offset(-b.r * 0.38, -b.r * 0.42),
              width: b.r * 0.42,
              height: b.r * 0.26),
          Paint()..color = Colors.white.withValues(alpha: 0.7));
      canvas.drawCircle(b.pos + Offset(b.r * 0.42, b.r * 0.46), b.r * 0.07,
          Paint()..color = Colors.white.withValues(alpha: 0.4));
    }
    for (final d in _drops) {
      canvas.drawCircle(d.pos, 3.5 * d.life + 1,
          Paint()..color = _hue(d.hue, alpha: d.life, s: 0.35));
    }
  }
}

// ---------------------------------------------------------------- lights

class _Glow {
  final Offset a, b;
  final double hue;
  double life = 1;
  _Glow(this.a, this.b, this.hue);
}

/// Light painting: every finger draws a glowing line that slowly changes
/// colour and fades away.
class _LightsGame extends StatefulWidget {
  const _LightsGame();
  @override
  State<_LightsGame> createState() => _LightsGameState();
}

class _LightsGameState extends _GameState<_LightsGame> {
  final _lines = <_Glow>[];
  final _sparks = <_Drop>[];
  final _lastPoint = <int, Offset>{};

  @override
  void step(double dt) {
    for (final l in _lines) {
      l.life -= dt / 5;
    }
    _lines.removeWhere((l) => l.life <= 0);
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel *= math.exp(-dt * 2);
      s.life -= dt * 1.4;
    }
    _sparks.removeWhere((s) => s.life <= 0);
  }

  @override
  void down(int pointer, Offset p) {
    _lastPoint[pointer] = p;
    _lines.add(_Glow(p, p + const Offset(0.1, 0.1), _colour(pointer)));
  }

  double _colour(int pointer) => time * 45 + pointer * 70;

  @override
  void move(int pointer, Offset p) {
    final from = _lastPoint[pointer] ?? p;
    if ((p - from).distance < 3) return;
    _lines.add(_Glow(from, p, _colour(pointer)));
    _lastPoint[pointer] = p;
    for (var k = 0; k < 2; k++) {
      final a = rng.nextDouble() * 6.283;
      _sparks.add(_Drop(
          p,
          Offset(math.cos(a), math.sin(a)) * (30 + rng.nextDouble() * 60),
          _colour(pointer)));
    }
    if (_sparks.length > 240) _sparks.removeRange(0, _sparks.length - 240);
    if (_lines.length > 900) _lines.removeRange(0, _lines.length - 900);
  }

  @override
  void up(int pointer) => _lastPoint.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF05060B));
    final glow = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 26
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
    final core = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 7;
    for (final l in _lines) {
      glow.color = _hue(l.hue, alpha: l.life * 0.45);
      canvas.drawLine(l.a, l.b, glow);
    }
    for (final l in _lines) {
      core.color = _hue(l.hue, alpha: l.life, s: 0.35);
      canvas.drawLine(l.a, l.b, core);
    }
    for (final s in _sparks) {
      canvas.drawCircle(s.pos, 1.5 + 2.5 * s.life,
          Paint()..color = _hue(s.hue, alpha: s.life, s: 0.25));
    }
  }
}

// ---------------------------------------------------------------- water

class _Ring {
  final Offset pos;
  double age = 0;
  _Ring(this.pos);
}

class _Fish {
  Offset pos;
  double angle, speed, turn = 0;
  final double hue, length;
  _Fish(this.pos, this.angle, this.speed, this.hue, this.length);
}

/// A calm pond: touching the water sends out ripples, and the fish swim
/// gently away from them.
class _WaterGame extends StatefulWidget {
  const _WaterGame();
  @override
  State<_WaterGame> createState() => _WaterGameState();
}

class _WaterGameState extends _GameState<_WaterGame> {
  final _rings = <_Ring>[];
  final _fish = <_Fish>[];
  final _lastRing = <int, double>{};

  @override
  void step(double dt) {
    if (_fish.isEmpty) {
      for (var i = 0; i < 6; i++) {
        _fish.add(_Fish(
            Offset(
                rng.nextDouble() * size.width, rng.nextDouble() * size.height),
            rng.nextDouble() * 6.283,
            24 + rng.nextDouble() * 18,
            const [18.0, 30.0, 45.0, 0.0, 22.0, 38.0][i],
            46 + rng.nextDouble() * 26));
      }
    }
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age > 3.6);
    for (final f in _fish) {
      // Wander slowly; turn back before the edge; swim away from new ripples.
      f.turn += (rng.nextDouble() - 0.5) * 1.6 * dt;
      f.turn = f.turn.clamp(-0.6, 0.6);
      var steer = f.turn;
      final ahead = f.pos + Offset(math.cos(f.angle), math.sin(f.angle)) * 90;
      if (ahead.dx < 30 ||
          ahead.dy < 30 ||
          ahead.dx > size.width - 30 ||
          ahead.dy > size.height - 30) {
        final home = size.center(Offset.zero) - f.pos;
        final want = math.atan2(home.dy, home.dx);
        steer = _wrap(want - f.angle).clamp(-1.6, 1.6);
      }
      var speed = f.speed;
      for (final r in _rings) {
        final away = f.pos - r.pos;
        if (r.age < 1.2 && away.distance < 170) {
          steer =
              _wrap(math.atan2(away.dy, away.dx) - f.angle).clamp(-3.0, 3.0);
          speed = f.speed * 2.6;
        }
      }
      f.angle += steer * dt;
      f.pos += Offset(math.cos(f.angle), math.sin(f.angle)) * speed * dt;
      f.pos = Offset(f.pos.dx.clamp(-40.0, size.width + 40),
          f.pos.dy.clamp(-40.0, size.height + 40));
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
    if (!force && time - (_lastRing[pointer] ?? -1) < 0.14) return;
    _lastRing[pointer] = time;
    _rings.add(_Ring(p));
    if (_rings.length > 60) _rings.removeAt(0);
  }

  @override
  void down(int pointer, Offset p) {
    _ripple(pointer, p, force: true);
    _Sound.drop();
    tick();
  }

  @override
  void move(int pointer, Offset p) => _ripple(pointer, p);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(-0.2, -0.3),
                  radius: 1.2,
                  colors: const [Color(0xFF1C8FA6), Color(0xFF0A3F5C)])
              .createShader(rect));
    for (final f in _fish) {
      canvas.save();
      canvas.translate(f.pos.dx, f.pos.dy);
      canvas.rotate(f.angle);
      final l = f.length;
      final wag = math.sin(time * 5 + f.hue) * 0.35;
      final body = Paint()..color = _hue(f.hue, s: 0.85, v: 1);
      final tail = Path()
        ..moveTo(-l * 0.42, 0)
        ..lineTo(-l * 0.85, -l * 0.26 + wag * l * 0.3)
        ..lineTo(-l * 0.72, wag * l * 0.2)
        ..lineTo(-l * 0.85, l * 0.26 + wag * l * 0.3)
        ..close();
      canvas.drawPath(tail, Paint()..color = _hue(f.hue, alpha: 0.85, s: 0.7));
      canvas.drawOval(
          Rect.fromCenter(center: Offset.zero, width: l, height: l * 0.4),
          body);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(l * 0.08, 0), width: l * 0.36, height: l * 0.24),
          Paint()..color = Colors.white.withValues(alpha: 0.85));
      canvas.drawCircle(Offset(l * 0.36, -l * 0.08), l * 0.035,
          Paint()..color = Colors.black87);
      canvas.restore();
    }
    // A thin veil of water over the fish, with sunlight moving through it.
    canvas.drawRect(rect, Paint()..color = const Color(0x3310506A));
    for (var i = 0; i < 7; i++) {
      final c = Offset(
          size.width * (0.5 + 0.42 * math.sin(time * 0.11 * (i + 1) + i * 1.7)),
          size.height * (0.5 + 0.42 * math.cos(time * 0.09 * (i + 2) + i)));
      final r = size.shortestSide * (0.22 + 0.06 * math.sin(time * 0.4 + i));
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = RadialGradient(colors: [
              Colors.white.withValues(alpha: 0.10),
              Colors.white.withValues(alpha: 0.0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
    for (final r in _rings) {
      final fade = (1 - r.age / 3.6).clamp(0.0, 1.0);
      for (var i = 0; i < 3; i++) {
        final radius = r.age * 95 - i * 22;
        if (radius <= 2) continue;
        ring
          ..strokeWidth = 3.2 - i * 0.7
          ..color = Colors.white.withValues(alpha: fade * (0.6 - i * 0.15));
        canvas.drawCircle(r.pos, radius, ring);
      }
    }
  }
}

// ---------------------------------------------------------------- kaleidoscope

class _Stroke {
  final Offset a, b;
  final double hue;
  _Stroke(this.a, this.b, this.hue);
}

/// Kaleidoscope: one finger line becomes a turning flower of sixteen.
class _KaleidoscopeGame extends StatefulWidget {
  const _KaleidoscopeGame();
  @override
  State<_KaleidoscopeGame> createState() => _KaleidoscopeGameState();
}

class _KaleidoscopeGameState extends _GameState<_KaleidoscopeGame> {
  static const _slices = 8;
  final _strokes = <_Stroke>[];
  final _lastPoint = <int, Offset>{};
  bool _seeded = false;

  Offset get _centre => size.center(Offset.zero);

  /// The finger position in the picture's own (slowly turning) frame.
  Offset _local(Offset p) {
    final d = p - _centre;
    final a = -time * 0.06;
    return Offset(d.dx * math.cos(a) - d.dy * math.sin(a),
        d.dx * math.sin(a) + d.dy * math.cos(a));
  }

  @override
  void step(double dt) {
    if (_seeded) return;
    _seeded = true;
    // Something to look at before the first touch.
    final r = size.shortestSide * 0.36;
    for (var i = 0; i < 26; i++) {
      final t0 = i / 26, t1 = (i + 1) / 26;
      Offset at(double t) =>
          Offset(r * (0.25 + 0.75 * t), math.sin(t * 6.283) * r * 0.16);
      _strokes.add(_Stroke(at(t0), at(t1), 200 + i * 6));
    }
  }

  @override
  void down(int pointer, Offset p) => _lastPoint[pointer] = _local(p);

  @override
  void move(int pointer, Offset p) {
    final to = _local(p);
    final from = _lastPoint[pointer] ?? to;
    if ((to - from).distance < 4) return;
    _strokes.add(_Stroke(from, to, time * 50 + pointer * 90));
    _lastPoint[pointer] = to;
    if (_strokes.length > 520) _strokes.removeRange(0, _strokes.length - 520);
  }

  @override
  void up(int pointer) => _lastPoint.remove(pointer);

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
              onPressed: () => setState(_strokes.clear),
            ),
          ),
        ),
      ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFF08080F));
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(time * 0.06);
    final line = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 6;
    for (var k = 0; k < _slices; k++) {
      for (final mirror in const [1.0, -1.0]) {
        canvas.save();
        canvas.rotate(k * 2 * math.pi / _slices);
        canvas.scale(1, mirror);
        for (var i = 0; i < _strokes.length; i++) {
          final s = _strokes[i];
          // The oldest lines fade out as new ones are drawn.
          final age = (_strokes.length - i) / 520;
          line.color = _hue(s.hue, alpha: 1 - age * 0.75, s: 0.8);
          canvas.drawLine(s.a, s.b, line);
        }
        canvas.restore();
      }
    }
    canvas.restore();
  }
}

// ---------------------------------------------------------------- lava lamp

class _Blob {
  Offset pos;
  final double r, speed, phase, hue;
  double direction;
  _Blob(this.pos, this.r, this.speed, this.phase, this.hue, this.direction);
}

/// Lava lamp: warm blobs rise and sink very slowly and melt into each
/// other. A finger draws the nearest ones gently toward it.
class _LavaGame extends StatefulWidget {
  const _LavaGame();
  @override
  State<_LavaGame> createState() => _LavaGameState();
}

class _LavaGameState extends _GameState<_LavaGame> {
  final _blobs = <_Blob>[];
  final _fingers = <int, Offset>{};

  @override
  void step(double dt) {
    if (_blobs.isEmpty) {
      final count = (size.width / 70).clamp(7, 14).round();
      for (var i = 0; i < count; i++) {
        _blobs.add(_Blob(
            Offset(
                (i + 0.5) / count * size.width, rng.nextDouble() * size.height),
            size.shortestSide * (0.09 + rng.nextDouble() * 0.09),
            10 + rng.nextDouble() * 16,
            rng.nextDouble() * 6.283,
            rng.nextDouble() * 50 - 10,
            rng.nextBool() ? 1 : -1));
      }
    }
    for (final b in _blobs) {
      if (b.pos.dy < b.r * 0.6) b.direction = 1;
      if (b.pos.dy > size.height - b.r * 0.6) b.direction = -1;
      var v =
          Offset(math.sin(time * 0.35 + b.phase) * 9, b.direction * b.speed);
      for (final f in _fingers.values) {
        final to = f - b.pos;
        if (to.distance < 260 && to.distance > 4) {
          v += to / to.distance * 70;
        }
      }
      b.pos += v * dt;
      b.pos =
          Offset(b.pos.dx.clamp(b.r * 0.4, size.width - b.r * 0.4), b.pos.dy);
    }
  }

  @override
  void down(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void move(int pointer, Offset p) => _fingers[pointer] = p;
  @override
  void up(int pointer) => _fingers.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF1B0B2E), const Color(0xFF3A0D2B));
    for (final b in _blobs) {
      final pulse = 1 + math.sin(time * 0.6 + b.phase) * 0.08;
      final r = b.r * pulse;
      final rect = Rect.fromCircle(center: b.pos, radius: r * 1.5);
      canvas.drawCircle(
          b.pos,
          r * 1.5,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = RadialGradient(colors: [
              _hue(b.hue + 30, alpha: 0.95, s: 0.75),
              _hue(b.hue, alpha: 0.75),
              _hue(b.hue - 25, alpha: 0),
            ], stops: const [
              0.0,
              0.55,
              1.0
            ]).createShader(rect));
    }
  }
}

// ---------------------------------------------------------------- xylophone

/// Eight coloured bars. Touch one, or slide across them, to hear its note
/// and see it ring. Sounds are soft and short.
class _XylophoneGame extends StatefulWidget {
  const _XylophoneGame();
  @override
  State<_XylophoneGame> createState() => _XylophoneGameState();
}

class _XylophoneGameState extends _GameState<_XylophoneGame> {
  // C major, one octave: C D E F G A B C.
  static const _notes = [
    261.63,
    293.66,
    329.63,
    349.23,
    392.0,
    440.0,
    493.88,
    523.25
  ];
  final _ring = List<double>.filled(_notes.length, 0);
  final _under = <int, int>{};
  final _players = <int, AudioPlayer>{};
  final _sounds = <int, Source>{};

  /// A soft mallet tone: the note with two quiet overtones, fading out.
  static Uint8List _tone(double frequency) {
    const rate = 22050;
    const seconds = 0.9;
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
      final attack = (t / 0.006).clamp(0.0, 1.0);
      final wave = math.sin(2 * math.pi * frequency * t) +
          0.28 * math.sin(2 * math.pi * frequency * 2 * t) * math.exp(-9 * t) +
          0.12 * math.sin(2 * math.pi * frequency * 4 * t) * math.exp(-14 * t);
      final sample = wave / 1.4 * attack * math.exp(-4.2 * t) * 0.8;
      data.setInt16(44 + i * 2, (sample * 32767).round().clamp(-32768, 32767),
          Endian.little);
    }
    return data.buffer.asUint8List();
  }

  Future<void> _play(int bar) async {
    _ring[bar] = 1;
    tick();
    if (!_Sound.on) return;
    try {
      final source = _sounds.putIfAbsent(bar, () {
        final bytes = _tone(_notes[bar]);
        // Browsers play it from a data address; phones from memory.
        return kIsWeb
            ? UrlSource('data:audio/wav;base64,${base64Encode(bytes)}')
            : BytesSource(bytes, mimeType: 'audio/wav');
      });
      final player = _players.putIfAbsent(bar, AudioPlayer.new);
      await player.stop();
      await player.play(source, volume: 0.9);
    } catch (_) {/* No sound on this device: the bar still rings on screen. */}
  }

  int? _barAt(Offset p) {
    if (size.width <= 0) return null;
    final gap = size.width / _notes.length;
    final bar = (p.dx / gap).floor();
    if (bar < 0 || bar >= _notes.length) return null;
    return _barRect(bar).inflate(6).contains(p) ? bar : null;
  }

  Rect _barRect(int bar) {
    final gap = size.width / _notes.length;
    final height = size.height * (0.82 - bar * 0.05);
    return Rect.fromCenter(
        center: Offset(gap * (bar + 0.5), size.height / 2),
        width: gap * 0.78,
        height: height);
  }

  void _touch(int pointer, Offset p) {
    final bar = _barAt(p);
    if (bar == _under[pointer]) return;
    if (bar == null) {
      _under.remove(pointer);
    } else {
      _under[pointer] = bar;
      _play(bar);
    }
  }

  @override
  void down(int pointer, Offset p) => _touch(pointer, p);
  @override
  void move(int pointer, Offset p) => _touch(pointer, p);
  @override
  void up(int pointer) => _under.remove(pointer);

  @override
  void step(double dt) {
    for (var i = 0; i < _ring.length; i++) {
      _ring[i] = (_ring[i] - dt * 1.8).clamp(0.0, 1.0);
    }
  }

  @override
  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF1A2230), const Color(0xFF0F141C));
    for (var i = 0; i < _notes.length; i++) {
      final ring = _ring[i];
      final rect = _barRect(i).inflate(ring * 5);
      final colour = _hue(i * 38.0, s: 0.72, v: 1);
      final shape = RRect.fromRectAndRadius(rect, const Radius.circular(18));
      if (ring > 0) {
        canvas.drawRRect(
            shape.inflate(10),
            Paint()
              ..color = colour.withValues(alpha: ring * 0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      }
      canvas.drawRRect(
          shape,
          Paint()
            ..shader = LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(colour, Colors.white, 0.3 + ring * 0.4)!,
                  colour
                ]).createShader(rect));
      for (final y in [rect.top + 22, rect.bottom - 22]) {
        canvas.drawCircle(Offset(rect.center.dx, y), 6,
            Paint()..color = Colors.black.withValues(alpha: 0.35));
      }
    }
  }
}

// ---------------------------------------------------------------- spinner

/// A spinner: push it round with a finger and it keeps turning, slowing
/// down smoothly by itself.
class _SpinnerGame extends StatefulWidget {
  const _SpinnerGame();
  @override
  State<_SpinnerGame> createState() => _SpinnerGameState();
}

class _SpinnerGameState extends _GameState<_SpinnerGame> {
  double _angle = 0, _speed = 1.2;
  int? _finger;
  double _fingerAngle = 0, _fingerTime = 0;

  double _angleOf(Offset p) {
    final d = p - size.center(Offset.zero);
    return math.atan2(d.dy, d.dx);
  }

  @override
  void down(int pointer, Offset p) {
    _finger = pointer;
    _fingerAngle = _angleOf(p);
    _fingerTime = time;
    _speed = 0;
  }

  @override
  void move(int pointer, Offset p) {
    if (pointer != _finger) return;
    final a = _angleOf(p);
    var delta = a - _fingerAngle;
    if (delta > math.pi) delta -= 2 * math.pi;
    if (delta < -math.pi) delta += 2 * math.pi;
    _angle += delta;
    final dt = (time - _fingerTime).clamp(0.008, 0.2);
    _speed = (_speed * 0.6 + delta / dt * 0.4).clamp(-22.0, 22.0);
    _fingerAngle = a;
    _fingerTime = time;
  }

  @override
  void up(int pointer) {
    if (pointer == _finger) _finger = null;
  }

  @override
  void step(double dt) {
    if (_finger != null) return;
    _angle += _speed * dt;
    _speed *= math.exp(-0.45 * dt);
    // It never quite stops: a slow idle turn keeps it alive.
    if (_speed.abs() < 0.25) _speed = _speed < 0 ? -0.25 : 0.25;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF14202B), const Color(0xFF0B1118));
    final centre = size.center(Offset.zero);
    final reach = size.shortestSide * 0.36;
    final ball = size.shortestSide * 0.115;
    // Faster turning leaves a longer, softer trail.
    final trail = (_speed.abs() / 4).clamp(0.0, 1.0);
    final steps = 1 + (trail * 7).round();
    for (var s = steps - 1; s >= 0; s--) {
      final a = _angle - _speed.sign * s * 0.07 * (1 + trail);
      final alpha = s == 0 ? 1.0 : 0.16 * (1 - s / steps);
      for (var arm = 0; arm < 3; arm++) {
        final dir = a + arm * 2 * math.pi / 3;
        final end = centre + Offset(math.cos(dir), math.sin(dir)) * reach;
        final colour = _hue(arm * 120.0 + 200, alpha: alpha, s: 0.75);
        canvas.drawLine(
            centre,
            end,
            Paint()
              ..color = colour
              ..strokeWidth = ball * 0.9
              ..strokeCap = StrokeCap.round);
        canvas.drawCircle(end, ball, Paint()..color = colour);
        if (s == 0) {
          canvas.drawCircle(end, ball * 0.5,
              Paint()..color = Colors.white.withValues(alpha: 0.85));
        }
      }
    }
    canvas.drawCircle(
        centre, ball * 0.8, Paint()..color = const Color(0xFFECEFF1));
    canvas.drawCircle(
        centre, ball * 0.4, Paint()..color = const Color(0xFF455A64));
  }
}
