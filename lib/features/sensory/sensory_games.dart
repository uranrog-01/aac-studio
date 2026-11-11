import '../../engine/i18n.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Sensory regulation games — informed by research on calming techniques for
/// autistic children: paced breathing ("smell the flower, blow out the
/// candle") and slow, predictable visual input (bubble-tube inspired).
/// No scores, no timers, no failure states — regulation, not performance.
class SensoryGamesScreen extends StatelessWidget {
  const SensoryGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFF26323C),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1E2730),
          title: const Text('Calm corner',
              style: TextStyle(color: Colors.white, fontSize: 18)),
          leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: TabBar(
            indicatorColor: Colors.deepOrangeAccent,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white38,
            tabs: [
              Tab(
                  icon: const Icon(Icons.bubble_chart),
                  text: I18n.t('Bubbles')),
              Tab(
                  icon: const Icon(Icons.self_improvement),
                  text: I18n.t('Breathe')),
            ],
          ),
        ),
        body: const TabBarView(children: [_BubblesGame(), _BreatheGame()]),
      ),
    );
  }
}

/// Slow drifting bubbles; tap to pop with a soft ripple. Predictable,
/// low-stimulation, no sound required.
class _BubblesGame extends StatefulWidget {
  const _BubblesGame();
  @override
  State<_BubblesGame> createState() => _BubblesGameState();
}

class _Bubble {
  Offset pos;
  double r;
  double speed;
  Color color;
  _Bubble(this.pos, this.r, this.speed, this.color);
}

class _BubblesGameState extends State<_BubblesGame>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final List<_Bubble> _bubbles = [];
  final List<_Ripple> _ripples = [];
  Size _size = Size.zero;
  final math.Random _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    if (!mounted || _size == Size.zero) return;
    for (final b in _bubbles) {
      b.pos = Offset(b.pos.dx, b.pos.dy - b.speed);
      b.pos = Offset(
        b.pos.dx + math.sin(d.inMicroseconds / 900000 + b.speed * 7) * 0.4,
        b.pos.dy,
      );
    }
    _bubbles.removeWhere((b) => b.pos.dy < -b.r - 10);
    if (_bubbles.length < 14 && _rng.nextDouble() < 0.06) {
      _bubbles.add(_Bubble(
        Offset(_rng.nextDouble() * _size.width,
            _size.height + _rng.nextDouble() * 40),
        16 + _rng.nextDouble() * 26,
        0.6 + _rng.nextDouble() * 1.0,
        Color.fromARGB(120, 130 + _rng.nextInt(120),
            190 + _rng.nextInt(60), 230),
      ));
    }
    for (final r in _ripples) {
      r.grow();
    }
    _ripples.removeWhere((r) => r.done);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cons) {
      _size = cons.biggest;
      return GestureDetector(
        onTapUp: (t) {
          setState(() {
            for (final b in List<_Bubble>.from(_bubbles)) {
              if ((b.pos - t.localPosition).distance < b.r + 12) {
                _bubbles.remove(b);
                _ripples.add(_Ripple(b.pos, b.r));
                break;
              }
            }
          });
        },
        child: CustomPaint(
          size: _size,
          painter: _BubblesPainter(_bubbles, _ripples),
          child: const SizedBox.expand(),
        ),
      );
    });
  }
}

class _Ripple {
  Offset pos;
  double r;
  double opacity = 0.6;
  bool get done => opacity <= 0;
  _Ripple(this.pos, this.r);
  void grow() {
    r += 1.6;
    opacity -= 0.02;
  }
}

class _BubblesPainter extends CustomPainter {
  final List<_Bubble> bubbles;
  final List<_Ripple> ripples;
  _BubblesPainter(this.bubbles, this.ripples);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0E2233));
    final paint = Paint();
    for (final b in bubbles) {
      paint
        ..color = b.color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);
      canvas.drawCircle(b.pos, b.r, paint);
      paint
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = null;
      canvas.drawCircle(
          b.pos - Offset(b.r * 0.35, b.r * 0.35), b.r * 0.22, paint);
    }
    for (final r in ripples) {
      canvas.drawCircle(
          r.pos, r.r, Paint()..color = Colors.white.withValues(alpha: r.opacity));
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// Paced breathing: "smell the flower … blow out the candle". The circle
/// grows on inhale (4s), holds (2s), shrinks on exhale (4s). Research-backed
/// calming strategy for autistic children.
class _BreatheGame extends StatefulWidget {
  const _BreatheGame();
  @override
  State<_BreatheGame> createState() => _BreatheGameState();
}

class _BreatheGameState extends State<_BreatheGame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 10))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value; // 0..1 over 10s
        // phases: 0-0.4 inhale, 0.4-0.6 hold, 0.6-1.0 exhale
        final double scale;
        String label;
        if (t < 0.4) {
          scale = 0.55 + 0.45 * Curves.easeInOut.transform(t / 0.4);
          label = 'smell the flower…';
        } else if (t < 0.6) {
          scale = 1.0;
          label = 'hold it gently';
        } else {
          scale = 1.0 - 0.45 * Curves.easeInOut.transform((t - 0.6) / 0.4);
          label = 'blow out the candle…';
        }
        return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Center(
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const RadialGradient(colors: [
                        Color(0xFFFFCDD2),
                        Color(0xFFE57373),
                      ]),
                      boxShadow: [
                        BoxShadow(
                            color: const Color(0xFFE57373)
                                .withValues(alpha: 0.35 * scale),
                            blurRadius: 60 * scale)
                      ],
                    ),
                    child: const Icon(Icons.local_florist,
                        size: 64, color: Colors.white),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 20,
                    fontStyle: FontStyle.italic)),
          ]),
        );
      },
    );
  }
}
