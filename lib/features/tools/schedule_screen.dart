import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../engine/i18n.dart';
import '../../engine/settings_controller.dart';
import '../../models/domain.dart';
import '../grid/grid_screen.dart';
import 'tools.dart';

/// Visual supports for the day: today's steps in pictures, First – Then,
/// and a picture timer that shows time running out.
class ScheduleScreen extends StatefulWidget {
  final GridSession session;
  final int initialTab;
  const ScheduleScreen({super.key, required this.session, this.initialTab = 0});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 3, vsync: this, initialIndex: widget.initialTab);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ToolPage(
      title: 'Schedule',
      bottom: TabBar(
        controller: _tabs,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white60,
        indicatorColor: const Color(0xFFFFB300),
        labelStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        tabs: [
          Tab(icon: const Icon(Icons.view_timeline), text: I18n.t('Today')),
          Tab(
              icon: const Icon(Icons.looks_two_outlined),
              text: I18n.t('First – Then')),
          Tab(icon: const Icon(Icons.timer_outlined), text: I18n.t('Timer')),
        ],
      ),
      body: TabBarView(controller: _tabs, children: [
        _TodayTab(session: widget.session),
        _FirstThenTab(session: widget.session),
        _TimerTab(session: widget.session),
      ]),
    );
  }
}

// ---------------------------------------------------------------- today

class _TodayTab extends StatelessWidget {
  final GridSession session;
  const _TodayTab({required this.session});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SettingsController>();
    final s = sc.settings;
    final steps = [
      for (final id in s.schedule)
        if (buttonById(session.vocabulary, id) != null)
          buttonById(session.vocabulary, id)!,
    ];
    final current = s.scheduleStep.clamp(0, steps.length).toInt();
    final wide = MediaQuery.of(context).size.width > 600;

    Future<void> edit() async {
      if (!await caregiverAllowed(context) || !context.mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: const Color(0xFF22262D),
        builder: (_) => _ScheduleEditor(session: session),
      );
    }

    if (steps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.view_timeline_outlined,
                color: Colors.white54, size: 64),
            const SizedBox(height: 12),
            Text(
                I18n.t('No steps yet. A caregiver can add the day in '
                    'pictures: breakfast, school, lunch, play…'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 17)),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: edit,
                icon: const Icon(Icons.edit),
                label: Text(I18n.t('Make the schedule'))),
          ]),
        ),
      );
    }

    void go(int step) {
      final next = step.clamp(0, steps.length);
      s.scheduleStep = next;
      sc.update();
      if (next < steps.length) {
        session.sayNow(
            '${I18n.t('Now')}: ${steps[next].speakText}');
      } else {
        session.sayNow(I18n.word('all done'));
      }
    }

    final finished = current >= steps.length;
    return Column(children: [
      Expanded(
        child: ListView(
          scrollDirection: wide ? Axis.horizontal : Axis.vertical,
          padding: const EdgeInsets.all(16),
          children: [
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (!wide)
                    SizedBox(
                      width: 44,
                      child: Text('${i + 1}',
                          style: TextStyle(
                              color: i == current
                                  ? const Color(0xFFFFB300)
                                  : Colors.white54,
                              fontSize: 26,
                              fontWeight: FontWeight.w800)),
                    ),
                  WordCard(
                    button: steps[i],
                    size: i == current ? 150 : 110,
                    highlight: i == current,
                    done: i < current,
                    onTap: () => session.sayNow(steps[i].speakText),
                  ),
                  if (i == current && !wide) ...[
                    const SizedBox(width: 12),
                    Text(I18n.t('Now'),
                        style: const TextStyle(
                            color: Color(0xFFFFB300),
                            fontSize: 24,
                            fontWeight: FontWeight.w800)),
                  ],
                ]),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Row(children: [
          IconButton(
              tooltip: I18n.t('Change the schedule'),
              onPressed: edit,
              icon: const Icon(Icons.edit, color: Colors.white70)),
          const Spacer(),
          if (current > 0)
            TextButton.icon(
                onPressed: () => go(finished ? 0 : current - 1),
                icon: Icon(finished ? Icons.replay : Icons.undo,
                    color: Colors.white),
                label: Text(I18n.t(finished ? 'Start again' : 'Back'),
                    style: const TextStyle(color: Colors.white, fontSize: 17))),
          const SizedBox(width: 8),
          if (!finished)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 18)),
              onPressed: () => go(current + 1),
              icon: const Icon(Icons.check, size: 28),
              label: Text(I18n.t('Done'),
                  style: const TextStyle(fontSize: 20)),
            )
          else
            Text(I18n.word('all done'),
                style: const TextStyle(
                    color: Color(0xFF81C784),
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
        ]),
      ),
    ]);
  }
}

class _ScheduleEditor extends StatelessWidget {
  final GridSession session;
  const _ScheduleEditor({required this.session});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SettingsController>();
    final s = sc.settings;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          ListTile(
            title: Text(I18n.t('Today\'s steps'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700)),
            trailing: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(I18n.t('Done'))),
          ),
          Expanded(
            child: ReorderableListView(
              onReorderItem: (from, to) {
                final id = s.schedule.removeAt(from);
                s.schedule.insert(to, id);
                sc.update();
              },
              children: [
                for (var i = 0; i < s.schedule.length; i++)
                  ListTile(
                    key: ValueKey('${s.schedule[i]}#$i'),
                    leading: Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 18)),
                    title: Text(
                        buttonById(session.vocabulary, s.schedule[i])
                                ?.shownLabel ??
                            '?',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 17)),
                    trailing: IconButton(
                      tooltip: I18n.t('Remove'),
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.white70),
                      onPressed: () {
                        s.schedule.removeAt(i);
                        s.scheduleStep = 0;
                        sc.update();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 10, children: [
              FilledButton.icon(
                onPressed: () async {
                  final b = await pickBoardWord(context, session,
                      title: 'Add a step');
                  if (b == null) return;
                  s.schedule.add(b.id);
                  sc.update();
                },
                icon: const Icon(Icons.add),
                label: Text(I18n.t('Add a step')),
              ),
              TextButton.icon(
                onPressed: s.schedule.isEmpty
                    ? null
                    : () {
                        s.schedule.clear();
                        s.scheduleStep = 0;
                        sc.update();
                      },
                icon: const Icon(Icons.delete_outline),
                label: Text(I18n.t('Clear all')),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- first-then

class _FirstThenTab extends StatelessWidget {
  final GridSession session;
  const _FirstThenTab({required this.session});

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SettingsController>();
    final s = sc.settings;
    final first = buttonById(session.vocabulary, s.firstId);
    final then = buttonById(session.vocabulary, s.thenId);
    final size =
        math.min(MediaQuery.of(context).size.width / 2 - 40, 240).toDouble();

    Future<void> choose(bool isFirst) async {
      if (!await caregiverAllowed(context) || !context.mounted) return;
      final b = await pickBoardWord(context, session,
          title: isFirst ? 'First' : 'Then');
      if (b == null) return;
      if (isFirst) {
        s.firstId = b.id;
      } else {
        s.thenId = b.id;
      }
      sc.update();
    }

    Widget side(String title, VocabButton? b, bool isFirst) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(I18n.t(title),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            b == null
                ? SizedBox(
                    width: size,
                    height: size * 1.12,
                    child: OutlinedButton(
                      onPressed: () => choose(isFirst),
                      style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white38, width: 2),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: const Icon(Icons.add_photo_alternate_outlined,
                          size: 56, color: Colors.white54),
                    ),
                  )
                : WordCard(
                    button: b,
                    size: size,
                    onTap: () => session.sayNow(b.speakText)),
            if (b != null)
              TextButton(
                  onPressed: () => choose(isFirst),
                  child: Text(I18n.t('Change'))),
          ],
        );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              side('First', first, true),
              const Padding(
                padding: EdgeInsets.only(top: 120, left: 8, right: 8),
                child: Icon(Icons.arrow_forward_rounded,
                    color: Colors.white70, size: 44),
              ),
              side('Then', then, false),
            ],
          ),
          const SizedBox(height: 18),
          if (first != null && then != null)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2E7D32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 16)),
              onPressed: () => session.sayNow(
                  '${I18n.t('First')} ${first.speakText}, '
                  '${I18n.t('then')} ${then.speakText}'),
              icon: const Icon(Icons.volume_up),
              label: Text(I18n.t('Say it'), style: const TextStyle(fontSize: 18)),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------- timer

class _TimerTab extends StatefulWidget {
  final GridSession session;
  const _TimerTab({required this.session});

  @override
  State<_TimerTab> createState() => _TimerTabState();
}

class _TimerTabState extends State<_TimerTab> {
  Timer? _timer;
  int _total = 0; // seconds
  int _left = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _start(int minutes) {
    _timer?.cancel();
    setState(() {
      _total = minutes * 60;
      _left = _total;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _left--);
      if (_left == 60 && _total > 120) {
        widget.session.sayNow(I18n.t('One more minute'));
      }
      if (_left <= 0) {
        t.cancel();
        widget.session.sayNow(I18n.word('all done'));
      }
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _total = 0;
      _left = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final running = _total > 0;
    final finished = running && _left <= 0;
    final fraction = running ? (_left / _total).clamp(0.0, 1.0) : 1.0;
    final side = math.min(MediaQuery.of(context).size.shortestSide * 0.62, 360.0);
    final mm = (_left ~/ 60).toString();
    final ss = (_left % 60).toString().padLeft(2, '0');
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: side,
            height: side,
            child: CustomPaint(
              painter: _TimerPainter(fraction, finished),
              child: Center(
                child: Text(
                  !running
                      ? I18n.t('Choose a time')
                      : finished
                          ? I18n.word('all done')
                          : '$mm:$ss',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: running && !finished ? 44 : 24,
                      fontWeight: FontWeight.w800,
                      shadows: const [Shadow(blurRadius: 6)]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
              children: [
            for (final m in const [1, 2, 5, 10, 15])
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF3949AB),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                onPressed: () => _start(m),
                child: Text(
                    I18n.t(m == 1 ? '1 minute' : '{n} minutes')
                        .replaceAll('{n}', '$m'),
                    style: const TextStyle(fontSize: 17)),
              ),
            if (running)
              OutlinedButton.icon(
                onPressed: _stop,
                icon: const Icon(Icons.stop, color: Colors.white),
                label: Text(I18n.t('Stop'),
                    style: const TextStyle(color: Colors.white, fontSize: 17)),
              ),
          ]),
        ]),
      ),
    );
  }
}

/// A red disc that shrinks as time runs out (no numbers needed).
class _TimerPainter extends CustomPainter {
  final double fraction;
  final bool finished;
  _TimerPainter(this.fraction, this.finished);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF3A3F48));
    if (finished) {
      canvas.drawCircle(c, r * 0.96, Paint()..color = const Color(0xFF2E7D32));
      return;
    }
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.96), -math.pi / 2,
        2 * math.pi * fraction, true, Paint()..color = const Color(0xFFE53935));
    canvas.drawCircle(c, r * 0.96,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white24);
  }

  @override
  bool shouldRepaint(_TimerPainter old) =>
      old.fraction != fraction || old.finished != finished;
}
