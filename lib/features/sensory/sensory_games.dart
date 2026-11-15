import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;
import 'dart:ui' as ui;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../engine/i18n.dart';

part 'sensory_games_more.dart';
part 'sensory_games_3d.dart';
part 'sensory_games_satisfying.dart';

/// Sensory games for regulation and cause-and-effect play, made for
/// autistic users: slow, predictable movement, soft glowing colours, an
/// immediate answer to every touch, and nothing to win or lose. No scores,
/// timers, flashing or sudden sounds.
///
/// Every game is drawn by the app itself, so it looks and behaves the same
/// on Android, iPhone, iPad and the web, and works without internet.
class SensoryGame {
  final String id;

  /// Menu section: satisfying, play or calm.
  final String section;

  /// English board word; shown through I18n.word in the chosen language.
  final String word;
  final IconData icon;
  final Color color;
  final Widget Function() build;
  const SensoryGame(this.id, this.word, this.icon, this.color, this.build,
      {this.section = 'play'});
}

/// Turns every game sound on or off (the speaker button in the menu).
set sensorySoundsOn(bool value) => _Sound.on = value;
bool get sensorySoundsOn => _Sound.on;

final kSensoryGames = <SensoryGame>[
  // Satisfying: things to cut, squish, pour, clean and press.
  SensoryGame('kineticsand', 'kinetic sand', Icons.landscape, const Color(0xFFE88FB0),
      () => const _KineticSandGame(), section: 'satisfying'),
  SensoryGame('soap', 'soap cutting', Icons.content_cut, const Color(0xFF9FA8DA),
      () => const _SoapGame(), section: 'satisfying'),
  SensoryGame('beads', 'water beads', Icons.bubble_chart_outlined,
      const Color(0xFF4FC3F7), () => const _BeadsGame(), section: 'satisfying'),
  SensoryGame('wash', 'pressure wash', Icons.shower, const Color(0xFF26A69A),
      () => const _WashGame(), section: 'satisfying'),
  SensoryGame('cradle', 'swinging balls', Icons.sports_baseball,
      const Color(0xFF78909C), () => const _CradleGame(), section: 'satisfying'),
  SensoryGame('popit', 'pop it', Icons.grid_on, const Color(0xFFEF5350),
      () => const _PopItGame(), section: 'satisfying'),
  SensoryGame('slime', 'slime', Icons.water_drop, const Color(0xFF26C6DA),
      () => const _SlimeGame(), section: 'satisfying'),
  SensoryGame('sand', 'sand', Icons.grain, const Color(0xFFD4A04C),
      () => const _SandGame(), section: 'satisfying'),
  SensoryGame('marbling', 'paint swirl', Icons.palette, const Color(0xFF5C6BC0),
      () => const _MarblingGame(), section: 'satisfying'),
  // Play: light, water, colour and sound.
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
  // Calm down: slow, soft scenes with quiet music, for hard moments.
  SensoryGame('tunnel', 'light tunnel', Icons.lens_blur, const Color(0xFF5C6BC0),
      () => const _TunnelGame(), section: 'calm'),
  SensoryGame('aurora', 'northern lights', Icons.nights_stay, const Color(0xFF00897B),
      () => const _AuroraGame(), section: 'calm'),
  SensoryGame('jellyfish', 'jellyfish', Icons.water, const Color(0xFF3949AB),
      () => const _JellyfishGame(), section: 'calm'),
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
            child: CustomScrollView(slivers: [
              for (final (section, title) in [
                ('satisfying', I18n.t('Satisfying')),
                ('play', I18n.word('play')),
                ('calm', I18n.word('Calm down')),
              ]) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                  sliver: SliverToBoxAdapter(
                    child: Text(title,
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 17,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  sliver: SliverGrid.count(
              crossAxisCount: c.maxWidth >= 900
                  ? 4
                  : c.maxWidth >= 560
                      ? 3
                      : 2,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 1.15,
              children: [
                for (final g in kSensoryGames.where((g) => g.section == section))
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
              ],
            ]),
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
  Offset pos, vel;
  double r;
  final double phase, hue;
  int? blower; // the finger blowing it, until it is let go
  _Bubble(this.pos, this.vel, this.r, this.phase, this.hue);
}

class _Drop {
  Offset pos, vel;
  double life = 1;
  final double hue;
  _Drop(this.pos, this.vel, this.hue);
}

class _PopRing {
  final Offset pos;
  final double r;
  double age = 0;
  _PopRing(this.pos, this.r);
}

/// Soap bubbles with real rainbow film. Touch one (or sweep through
/// several) to pop it; touch empty space and hold to blow a new bubble,
/// then let go and it floats away.
class _BubblesGame extends StatefulWidget {
  const _BubblesGame();
  @override
  State<_BubblesGame> createState() => _BubblesGameState();
}

class _BubblesGameState extends _GameState<_BubblesGame> {
  final _bubbles = <_Bubble>[];
  final _drops = <_Drop>[];
  final _rings = <_PopRing>[];
  final _touch = <int, (Offset, double)>{};
  final _bokeh = <(Offset, double, double)>[];

  @override
  void step(double dt) {
    if (_bokeh.isEmpty) {
      for (var i = 0; i < 14; i++) {
        _bokeh.add((
          Offset(rng.nextDouble() * size.width, rng.nextDouble() * size.height),
          size.shortestSide * (0.05 + rng.nextDouble() * 0.12),
          rng.nextDouble() * 360
        ));
      }
    }
    final target = (size.width * size.height / 30000).clamp(6, 20).round();
    if (_bubbles.where((b) => b.blower == null).length < target &&
        rng.nextDouble() < 0.06) {
      final r = 24 + rng.nextDouble() * 40;
      _bubbles.add(_Bubble(
          Offset(rng.nextDouble() * size.width, size.height + r + 20),
          Offset(0, -(16 + rng.nextDouble() * 26)),
          r,
          rng.nextDouble() * 6.28,
          rng.nextDouble() * 360));
    }
    for (final b in _bubbles) {
      if (b.blower != null) {
        b.r = math.min(b.r + dt * 46, size.shortestSide * 0.2);
        continue;
      }
      b.vel = Offset(b.vel.dx * math.exp(-dt * 0.6) + math.sin(time * 0.7 + b.phase) * 10 * dt,
          b.vel.dy + (-22 - b.vel.dy) * (1 - math.exp(-dt * 0.5)));
      b.pos += b.vel * dt;
    }
    _bubbles.removeWhere((b) => b.pos.dy < -b.r * 2 && b.blower == null);
    for (final d in _drops) {
      d.vel += Offset(0, 300 * dt);
      d.pos += d.vel * dt;
      d.life -= dt * 1.6;
    }
    _drops.removeWhere((d) => d.life <= 0);
    for (final r in _rings) {
      r.age += dt;
    }
    _rings.removeWhere((r) => r.age > 0.35);
  }

  bool _pop(Offset p) {
    for (var i = _bubbles.length - 1; i >= 0; i--) {
      final b = _bubbles[i];
      if (b.blower != null) continue;
      if ((b.pos - p).distance < b.r + 10) {
        _bubbles.removeAt(i);
        _rings.add(_PopRing(b.pos, b.r));
        _Sound.bubble();
        for (var k = 0; k < 14; k++) {
          final a = k / 14 * 6.283 + rng.nextDouble() * 0.3;
          final v = 60 + rng.nextDouble() * 120;
          _drops.add(_Drop(b.pos + Offset(math.cos(a), math.sin(a)) * b.r,
              Offset(math.cos(a), math.sin(a)) * v, b.hue + k * 20));
        }
        tick();
        return true;
      }
    }
    return false;
  }

  @override
  void down(int pointer, Offset p) {
    _touch[pointer] = (p, time);
    if (_pop(p)) return;
    final b = _Bubble(p, Offset.zero, 10, rng.nextDouble() * 6.28, rng.nextDouble() * 360)
      ..blower = pointer;
    _bubbles.add(b);
  }

  @override
  void move(int pointer, Offset p) {
    final blown = _bubbles.where((b) => b.blower == pointer);
    if (blown.isNotEmpty) {
      final b = blown.first;
      final (before, at) = _touch[pointer] ?? (p, time);
      b.vel = (p - before) / math.max(time - at, 0.016);
      b.pos = p;
    } else {
      _pop(p);
    }
    _touch[pointer] = (p, time);
  }

  @override
  void up(int pointer) {
    for (final b in _bubbles) {
      if (b.blower == pointer) {
        b.blower = null;
        b.vel = Offset(b.vel.dx.clamp(-300.0, 300.0) * 0.4,
            math.min(-20.0, b.vel.dy.clamp(-300.0, 300.0) * 0.4));
      }
    }
    _touch.remove(pointer);
  }

  void _drawBubble(Canvas canvas, _Bubble b) {
    final wobble = 0.035 * math.sin(time * 3 + b.phase);
    final rect = Rect.fromCenter(
        center: b.pos, width: b.r * 2 * (1 + wobble), height: b.r * 2 * (1 - wobble));
    // Nearly clear inside, with a faint tint near the edge.
    canvas.drawOval(
        rect,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withValues(alpha: 0.02),
            _hue(b.hue + 180, alpha: 0.06, s: 0.4),
            _hue(b.hue, alpha: 0.18, s: 0.5),
          ], stops: const [0.0, 0.8, 1.0]).createShader(rect));
    // Thin-film rainbow swirling round the rim.
    canvas.drawOval(
        rect.deflate(b.r * 0.06),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = b.r * 0.16
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, b.r * 0.05)
          ..shader = SweepGradient(
            transform: GradientRotation(time * 0.5 + b.phase),
            colors: [
              for (var k = 0; k <= 6; k++)
                _hue(b.hue + k * 60, alpha: 0.42, s: 0.65),
            ],
          ).createShader(rect));
    canvas.drawOval(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.45));
    // A window reflection and a soft bounce light.
    canvas.save();
    canvas.translate(b.pos.dx - b.r * 0.42, b.pos.dy - b.r * 0.45);
    canvas.rotate(-0.6);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: b.r * 0.5, height: b.r * 0.22),
            Radius.circular(b.r * 0.1)),
        Paint()..color = Colors.white.withValues(alpha: 0.7));
    canvas.restore();
    canvas.drawArc(
        rect.deflate(b.r * 0.18),
        0.3,
        1.1,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = b.r * 0.06
          ..strokeCap = StrokeCap.round
          ..color = Colors.white.withValues(alpha: 0.35));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF6EC6E8), const Color(0xFF2F6FA8));
    for (final (c, r, h) in _bokeh) {
      final drift = Offset(math.sin(time * 0.1 + h) * 20, math.cos(time * 0.08 + h) * 14);
      canvas.drawCircle(
          c + drift,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              _hue(h, alpha: 0.16, s: 0.25),
              _hue(h, alpha: 0.0, s: 0.25),
            ]).createShader(Rect.fromCircle(center: c + drift, radius: r)));
    }
    for (final b in _bubbles) {
      _drawBubble(canvas, b);
    }
    for (final r in _rings) {
      final t = r.age / 0.35;
      canvas.drawCircle(
          r.pos,
          r.r * (1 + t * 0.35),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * (1 - t)
            ..color = Colors.white.withValues(alpha: 0.6 * (1 - t)));
    }
    for (final d in _drops) {
      canvas.drawCircle(d.pos, 3 * d.life + 0.8,
          Paint()..color = _hue(d.hue, alpha: d.life * 0.9, s: 0.4));
    }
  }
}

// ---------------------------------------------------------------- lights

class _Seg {
  final double ax, ay, az, bx, by, bz, hue, born;
  _Seg(this.ax, this.ay, this.az, this.bx, this.by, this.bz, this.hue, this.born);
}

/// Light painting in 3D: glowing lines drawn with a finger float slowly
/// away into space and turn, so the drawing becomes a sculpture of light
/// among the stars.
class _LightsGame extends StatefulWidget {
  const _LightsGame();
  @override
  State<_LightsGame> createState() => _LightsGameState();
}

class _LightsGameState extends _GameState<_LightsGame> {
  final _segs = <_Seg>[];
  final _sparks = <_Drop>[];
  final _lastPoint = <int, Offset>{};
  final _stars = <(double, double, double)>[];
  static const _life = 9.0, _focal = 900.0;

  double get _turn => time * 0.22;

  /// Screen point to world, so it shows under the finger right now.
  (double, double, double) _world(Offset p) {
    final c = size.center(Offset.zero);
    final x = p.dx - c.dx, y = p.dy - c.dy;
    return (x * math.cos(_turn), y, x * math.sin(_turn));
  }

  (Offset, double)? _screen(double x, double y, double z, double age) {
    final t = _turn;
    final zz = z + age * 26;
    final rx = x * math.cos(t) + zz * math.sin(t);
    final rz = -x * math.sin(t) + zz * math.cos(t);
    final depth = _focal + rz;
    if (depth < 60) return null;
    final s = _focal / depth;
    return (size.center(Offset.zero) + Offset(rx, y) * s, s);
  }

  @override
  void step(double dt) {
    if (_stars.isEmpty) {
      for (var i = 0; i < 220; i++) {
        _stars.add((
          (rng.nextDouble() - 0.5) * size.width * 3,
          (rng.nextDouble() - 0.5) * size.height * 3,
          (rng.nextDouble() - 0.5) * 2400
        ));
      }
    }
    _segs.removeWhere((s) => time - s.born > _life);
    for (final s in _sparks) {
      s.pos += s.vel * dt;
      s.vel *= math.exp(-dt * 2);
      s.life -= dt * 1.4;
    }
    _sparks.removeWhere((s) => s.life <= 0);
  }

  double _colour(int pointer) => time * 45 + pointer * 70;

  @override
  void down(int pointer, Offset p) => _lastPoint[pointer] = p;

  @override
  void move(int pointer, Offset p) {
    final from = _lastPoint[pointer] ?? p;
    if ((p - from).distance < 3) return;
    final a = _world(from), b = _world(p);
    _segs.add(_Seg(a.$1, a.$2, a.$3, b.$1, b.$2, b.$3, _colour(pointer), time));
    _lastPoint[pointer] = p;
    for (var k = 0; k < 2; k++) {
      final ang = rng.nextDouble() * 6.283;
      _sparks.add(_Drop(p, Offset(math.cos(ang), math.sin(ang)) * (30 + rng.nextDouble() * 60),
          _colour(pointer)));
    }
    if (_sparks.length > 240) _sparks.removeRange(0, _sparks.length - 240);
    if (_segs.length > 1400) _segs.removeRange(0, _segs.length - 1400);
  }

  @override
  void up(int pointer) => _lastPoint.remove(pointer);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const RadialGradient(
                  colors: [Color(0xFF141238), Color(0xFF03030A)], radius: 0.9)
              .createShader(rect));
    final star = Paint();
    for (final (x, y, z) in _stars) {
      final s = _screen(x, y, z, 0);
      if (s == null) continue;
      star.color = Colors.white.withValues(alpha: (0.25 + 0.5 * s.$2).clamp(0.0, 0.9));
      canvas.drawCircle(s.$1, (1.4 * s.$2).clamp(0.4, 2.2), star);
    }
    final glow = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
    final core = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (final pass in const [0, 1]) {
      for (final g in _segs) {
        final age = time - g.born;
        final a = _screen(g.ax, g.ay, g.az, age);
        final b = _screen(g.bx, g.by, g.bz, age);
        if (a == null || b == null) continue;
        final fade = (1 - age / _life).clamp(0.0, 1.0);
        final s = (a.$2 + b.$2) / 2;
        if (pass == 0) {
          glow
            ..strokeWidth = 22 * s
            ..color = _hue(g.hue, alpha: 0.32 * fade);
          canvas.drawLine(a.$1, b.$1, glow);
        } else {
          core
            ..strokeWidth = 5 * s
            ..color = _hue(g.hue, alpha: fade, s: 0.3);
          canvas.drawLine(a.$1, b.$1, core);
        }
      }
    }
    for (final s in _sparks) {
      canvas.drawCircle(s.pos, 1.5 + 2.5 * s.life,
          Paint()..color = _hue(s.hue, alpha: s.life, s: 0.25));
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
    // Coloured glass behind the mirrors, slowly breathing.
    final glassR = size.longestSide * 0.75;
    canvas.drawCircle(
        Offset.zero,
        glassR,
        Paint()
          ..shader = SweepGradient(
            transform: GradientRotation(-time * 0.04),
            colors: [
              for (var k = 0; k <= 8; k++)
                _hue(k * 45 + time * 6, alpha: 0.10, s: 0.7),
            ],
          ).createShader(Rect.fromCircle(center: Offset.zero, radius: glassR)));
    final breathe = 1 + 0.03 * math.sin(time * 0.5);
    canvas.scale(breathe);
    final glow = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 16
      ..blendMode = BlendMode.plus
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final line = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 5
      ..blendMode = BlendMode.plus;
    for (final pass in const [0, 1]) {
      for (var k = 0; k < _slices; k++) {
        for (final mirror in const [1.0, -1.0]) {
          canvas.save();
          canvas.rotate(k * 2 * math.pi / _slices);
          canvas.scale(1, mirror);
          for (var i = 0; i < _strokes.length; i++) {
            final s = _strokes[i];
            // The oldest lines fade out as new ones are drawn.
            final age = (_strokes.length - i) / 520;
            if (pass == 0) {
              glow.color = _hue(s.hue, alpha: (1 - age * 0.8) * 0.35, s: 0.8);
              canvas.drawLine(s.a, s.b, glow);
            } else {
              line.color = _hue(s.hue, alpha: 1 - age * 0.75, s: 0.55);
              canvas.drawLine(s.a, s.b, line);
            }
          }
          canvas.restore();
        }
      }
    }
    canvas.restore();
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

  void _spinnerBody(Canvas canvas, Offset centre, double angle, double reach,
      double ball, double alpha) {
    final rect = Rect.fromCircle(center: centre, radius: reach + ball * 1.3);
    // Anodised metal: a rainbow sheen that turns with the spinner.
    final metal = Paint()
      ..shader = SweepGradient(
        transform: GradientRotation(angle),
        colors: [
          for (var k = 0; k <= 6; k++)
            _hue(200 + k * 60, alpha: alpha, s: 0.55, v: 0.95),
        ],
      ).createShader(rect)
      ..strokeCap = StrokeCap.round;
    for (var arm = 0; arm < 3; arm++) {
      final dir = angle + arm * 2 * math.pi / 3;
      final end = centre + Offset(math.cos(dir), math.sin(dir)) * reach;
      canvas.drawLine(centre, end, metal..strokeWidth = ball * 1.15);
      canvas.drawCircle(end, ball * 1.25, metal);
    }
    canvas.drawCircle(centre, ball * 1.3, metal);
  }

  void _bearing(Canvas canvas, Offset c, double r, double spin) {
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF5F7FA), Color(0xFF8A939C), Color(0xFFE0E4E8)])
              .createShader(rect));
    canvas.drawCircle(c, r * 0.72, Paint()..color = const Color(0xFF2B3036));
    for (var k = 0; k < 7; k++) {
      final a = spin + k / 7 * 2 * math.pi;
      final bc = c + Offset(math.cos(a), math.sin(a)) * r * 0.5;
      canvas.drawCircle(
          bc,
          r * 0.17,
          Paint()
            ..shader = RadialGradient(
                    center: const Alignment(-0.4, -0.4),
                    colors: const [Color(0xFFFFFFFF), Color(0xFF7D868F)])
                .createShader(Rect.fromCircle(center: bc, radius: r * 0.17)));
    }
    canvas.drawCircle(
        c,
        r * 0.3,
        Paint()
          ..shader = RadialGradient(
                  center: const Alignment(-0.3, -0.3),
                  colors: const [Color(0xFFF0F2F4), Color(0xFF8B949D)])
              .createShader(Rect.fromCircle(center: c, radius: r * 0.3)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    _background(canvas, size, const Color(0xFF1C2833), const Color(0xFF0A0F14));
    final centre = size.center(Offset.zero);
    final reach = size.shortestSide * 0.3;
    final ball = size.shortestSide * 0.1;
    // Soft shadow on the table.
    canvas.drawCircle(
        centre + Offset(ball * 0.35, ball * 0.55),
        reach + ball,
        Paint()
          ..color = const Color(0x66000000)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, ball * 0.6));
    // Fast spinning blurs into a soft disc of colour.
    final blur = (_speed.abs() / 6).clamp(0.0, 1.0);
    final copies = 1 + (blur * 6).round();
    for (var c = copies - 1; c >= 1; c--) {
      _spinnerBody(canvas, centre, _angle - _speed.sign * c * 0.09, reach, ball,
          0.18 * (1 - c / copies));
    }
    _spinnerBody(canvas, centre, _angle, reach, ball, 1);
    // A light from the top left gives the metal its roundness.
    final rect = Rect.fromCircle(center: centre, radius: reach + ball * 1.3);
    canvas.drawCircle(
        centre,
        reach + ball * 1.3,
        Paint()
          ..blendMode = BlendMode.softLight
          ..shader = const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xCCFFFFFF), Color(0x00FFFFFF), Color(0x99000000)])
              .createShader(rect));
    for (var arm = 0; arm < 3; arm++) {
      final dir = _angle + arm * 2 * math.pi / 3;
      _bearing(canvas, centre + Offset(math.cos(dir), math.sin(dir)) * reach, ball * 0.85,
          _angle * 2.5);
    }
    _bearing(canvas, centre, ball * 0.95, -_angle * 0.4);
  }
}
