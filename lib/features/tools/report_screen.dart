import 'package:flutter/material.dart';

import '../../engine/i18n.dart';
import '../../engine/smart_words.dart';
import 'tools.dart';

/// The word-use report for a speech therapist or teacher: how often the
/// person talked and which words they used. Only on this device.
class WordUseReport extends StatefulWidget {
  final bool recording;
  const WordUseReport({super.key, required this.recording});

  static Future<void> show(BuildContext context, {required bool recording}) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
          builder: (_) => WordUseReport(recording: recording)));

  @override
  State<WordUseReport> createState() => _WordUseReportState();
}

class _WordUseReportState extends State<WordUseReport> {
  int _days = 7;

  @override
  void initState() {
    super.initState();
    WordUseLog.instance.load().then((_) {
      if (mounted) setState(() {});
    });
  }

  String _asText(
      ({int taps, int words, int activeDays, List<MapEntry<String, int>> top})
          s) {
    final b = StringBuffer()
      ..writeln('AAC Studio — ${I18n.t('Word-use report')}')
      ..writeln(I18n.t('Last {n} days').replaceAll('{n}', '$_days'))
      ..writeln('${I18n.t('Words said')}: ${s.taps}')
      ..writeln('${I18n.t('Different words')}: ${s.words}')
      ..writeln('${I18n.t('Days used')}: ${s.activeDays}')
      ..writeln();
    for (final e in s.top.take(60)) {
      b.writeln('${I18n.word(e.key)} (${e.key}): ${e.value}');
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final s = WordUseLog.instance.summary(_days);
    final most = s.top.isEmpty ? 1 : s.top.first.value;
    Widget stat(String label, int value) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: const Color(0xFF22262D),
                borderRadius: BorderRadius.circular(12)),
            child: Column(children: [
              Text('$value',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800)),
              Text(I18n.t(label),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
          ),
        );
    return ToolPage(
      title: 'Word-use report',
      actions: [
        IconButton(
            tooltip: I18n.t('Share the report'),
            onPressed: s.taps == 0
                ? null
                : () => shareText(_asText(s),
                    subject: 'AAC Studio — ${I18n.t('Word-use report')}'),
            icon: const Icon(Icons.ios_share)),
        IconButton(
          tooltip: I18n.t('Clear the record'),
          icon: const Icon(Icons.delete_outline),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: Text(I18n.t('Clear the word-use record?')),
                content: Text(I18n.t('This cannot be undone.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(I18n.t('Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(I18n.t('Clear'))),
                ],
              ),
            );
            if (ok == true) setState(WordUseLog.instance.clear);
          },
        ),
      ],
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (!widget.recording)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
                I18n.t('The record is off. Turn on "Keep a word-use record" '
                    'in Settings > Caregiver.'),
                style: const TextStyle(color: Color(0xFFFFB300), fontSize: 15)),
          ),
        Padding(
          padding: const EdgeInsets.all(4),
          child: SegmentedButton<int>(
            segments: [
              for (final d in const [1, 7, 30, 90])
                ButtonSegment(
                    value: d,
                    label: Text(d == 1
                        ? I18n.t('Today')
                        : I18n.t('{n} days').replaceAll('{n}', '$d'))),
            ],
            selected: {_days},
            onSelectionChanged: (v) => setState(() => _days = v.first),
          ),
        ),
        Row(children: [
          stat('Words said', s.taps),
          stat('Different words', s.words),
          stat('Days used', s.activeDays),
        ]),
        const SizedBox(height: 8),
        if (s.top.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(I18n.t('No words recorded in this time.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 16)),
          ),
        for (final e in s.top.take(100))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(children: [
              SizedBox(
                width: 130,
                child: Text(I18n.word(e.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: e.value / most,
                    minHeight: 14,
                    color: const Color(0xFF64B5F6),
                    backgroundColor: const Color(0xFF22262D),
                  ),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text('${e.value}',
                    textAlign: TextAlign.right,
                    style: const TextStyle(color: Colors.white70)),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Text(
            I18n.t('Kept only on this device. Nothing is sent anywhere unless '
                'you share it.'),
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
