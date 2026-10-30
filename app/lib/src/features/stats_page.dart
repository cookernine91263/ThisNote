import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/motion.dart';
import '../core/morph.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final days = state.last7Days;
    final maxWords = days.fold(0, (m, d) => math.max(m, d.words)).toInt();
    final total = state.diaryCount + state.essayCount + state.noteCount;
    final avg = state.activeNotes.isEmpty
        ? 0
        : (state.totalWords / state.activeNotes.length).round();
    final weekWords = days.fold(0, (s, d) => s + d.words);
    final content = MorphGroup(
      id: 'stats',
      tags: const ['stats-title', 'main'],
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MorphBlock(
                  tag: 'title',
                  child: Text(
                    '写作统计',
                    style: TextStyle(
                      fontFamily: 'WenKai',
                      fontSize: 30,
                      letterSpacing: 2,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '不催促，只记录你走过的路',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10.5,
                    color: c.inkMuted,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              dateLabel(DateTime.now()),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10,
                color: c.inkMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Reveal(
          delay: const Duration(milliseconds: 60),
          child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Metric(
              icon: LucideIcons.penLine,
              label: '总字数',
              value: '${state.totalWords}',
              hint: '所有没有被丢掉的字',
            ),
            _Metric(
              icon: LucideIcons.library,
              label: '总篇数',
              value: '${state.activeNotes.length}',
              hint: '日记 ${state.diaryCount} · 作文 ${state.essayCount} · 随笔 ${state.noteCount}',
              onTap: () => state.setView('all'),
            ),
            _Metric(
              icon: LucideIcons.flame,
              label: '连续写作',
              value: '${state.streak}',
              suffix: ' 天',
              hint: state.streak > 0 ? '保持住，哪怕只写一句' : '今天写下第一句吧',
            ),
            _Metric(
              icon: LucideIcons.target,
              label: '今日进度',
              value: '${state.todayWords}',
              suffix: ' / ${state.settings.dailyGoal}',
              hint: state.todayWords >= state.settings.dailyGoal
                  ? '今天的字数已经够了'
                  : '还差 ${math.max(0, state.settings.dailyGoal - state.todayWords)} 字',
            ),
          ],
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          delay: const Duration(milliseconds: 120),
          child: PaperSurface(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          radius: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(
                '最近 7 天',
                trailing: Text(
                  '本周 $weekWords 字',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.inkMuted,
                  ),
                ),
              ),
              SizedBox(
                height: 150,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final d in days)
                      Expanded(
                        child: _Bar(
                          stat: d,
                          maxWords: maxWords == 0 ? 1 : maxWords,
                          isToday: dayKey(d.date) == dayKey(DateTime.now()),
                          onTap: () => _showDay(context, state, d.date),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          delay: const Duration(milliseconds: 180),
          child: PaperSurface(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
          radius: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel(
                '写作热力图',
                trailing: Text(
                  '最近一年',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.inkMuted,
                  ),
                ),
              ),
              _Heatmap(
                data: state.heatmap,
                onDayTap: (day) => _showDay(context, state, day),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Spacer(),
                  Text(
                    '少',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(width: 5),
                  for (var i = 0; i < 4; i++)
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: Color.lerp(
                          c.surfaceAlt,
                          c.accent,
                          0.18 + i * 0.24,
                        ),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  const SizedBox(width: 3),
                  Text(
                    '多',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          delay: const Duration(milliseconds: 240),
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PaperSurface(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                radius: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('写了什么'),
                    if (total == 0)
                      Text(
                        '还没有内容。',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11,
                          color: c.inkMuted,
                        ),
                      )
                    else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(5),
                        child: SizedBox(
                          height: 11,
                          child: Row(
                            children: [
                              if (state.diaryCount > 0)
                                Expanded(
                                  flex: state.diaryCount,
                                  child: Container(color: c.accent),
                                ),
                              if (state.essayCount > 0)
                                Expanded(
                                  flex: state.essayCount,
                                  child: Container(color: c.gold),
                                ),
                              if (state.noteCount > 0)
                                Expanded(
                                  flex: state.noteCount,
                                  child: Container(color: c.sage),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Legend(color: c.accent, label: '日记', count: state.diaryCount),
                      _Legend(color: c.gold, label: '作文', count: state.essayCount),
                      _Legend(color: c.sage, label: '随笔', count: state.noteCount),
                      const SizedBox(height: 4),
                      Text(
                        '平均每篇 $avg 字',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PaperSurface(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                radius: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionLabel('常用的标签'),
                    if (state.tagCounts.isEmpty)
                      Text(
                        '给文字贴上第一个标签吧。',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11,
                          color: c.inkMuted,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final entry in state.tagCounts.entries.take(9))
                            TagChip(
                              label: entry.key,
                              count: entry.value,
                              onTap: () => state.selectTag(entry.key),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );

    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 900 ? 16 : 34,
          MediaQuery.sizeOf(context).width < 900 ? 12 : 30,
          MediaQuery.sizeOf(context).width < 900 ? 16 : 30,
          30,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: content,
          ),
        ),
      ),
    );
  }

  Future<void> _showDay(
    BuildContext context,
    AppState state,
    DateTime day,
  ) async {
    final notes = state.activeNotes
        .where((n) => dayKey(n.updatedAt) == dayKey(day))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (notes.isEmpty) {
      showToast(context, '${day.month} 月 ${day.day} 日还没有文字');
      return;
    }
    var total = 0;
    for (final note in notes) {
      total += note.words;
    }
    final c = AppPalette.of(context);
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.24),
      builder: (context) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430, maxHeight: 520),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${day.month} 月 ${day.day} 日',
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 24,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${notes.length} 篇 · $total 字',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 10,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final note in notes)
                          _DayNoteRow(
                            note: note,
                            onTap: () async {
                              Navigator.of(context).pop();
                              await state.openNote(note.id);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayNoteRow extends StatelessWidget {
  const _DayNoteRow({required this.note, required this.onTap});
  final NoteMeta note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            decoration: BoxDecoration(
              color: hovered ? c.paper : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                Icon(
                  note.kind == NoteKind.diary
                      ? LucideIcons.calendarHeart
                      : note.kind == NoteKind.essay
                          ? LucideIcons.penLine
                          : LucideIcons.feather,
                  size: 14,
                  color: c.accent,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        note.title.trim().isEmpty ? '无题' : note.title.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11.5,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${note.words} 字 · ${note.kind.label}',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 8.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.arrowUpRight,
                  size: 13,
                  color: c.inkMuted,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.hint,
    this.suffix = '',
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String suffix;
  final String hint;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return AnimatedScale(
          scale: hovered && onTap != null ? 1.012 : 1,
          duration: const Duration(milliseconds: 140),
          child: GestureDetector(
            onTap: onTap,
            child: SizedBox(
              width: 205,
              child: PaperSurface(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
                radius: 12,
                child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 12, color: c.accent),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                RollingNumber(
                  int.tryParse(value) ?? 0,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 26,
                    fontWeight: FontWeight.w300,
                    height: 1,
                    color: c.ink,
                  ),
                ),
                if (suffix.isNotEmpty)
                  Text(
                    suffix,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10,
                      color: c.inkMuted,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 8.5,
                color: c.inkMuted,
              ),
            ),
          ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.stat,
    required this.maxWords,
    required this.isToday,
    required this.onTap,
  });

  final DayStat stat;
  final int maxWords;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final ratio = (stat.words / maxWords).clamp(0.0, 1.0);
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
      message: '${stat.date.month}月${stat.date.day}日 · ${stat.words} 字',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            stat.words == 0 ? '' : '${stat.words}',
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 8,
              color: isToday ? c.accent : c.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: ratio),
            duration: Motion.slow,
            curve: Motion.enter,
            builder: (context, value, _) => Container(
              width: 18,
              height: 96 * value + 2,
              decoration: BoxDecoration(
                color: isToday
                    ? c.accent
                    : c.accent.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            weekdays[stat.date.weekday - 1],
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 8.5,
              color: isToday ? c.accent : c.inkMuted,
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.data, this.onDayTap});
  final Map<String, int> data;
  final ValueChanged<DateTime>? onDayTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final weekCount = constraints.maxWidth > 620 ? 52 : 20;
        final today = DateTime.now();
        final monday = today.subtract(Duration(days: today.weekday - 1));
        final weeks = <List<DateTime>>[];
        for (var w = weekCount - 1; w >= 0; w--) {
          final start = monday.subtract(Duration(days: w * 7));
          weeks.add(List.generate(7, (i) => start.add(Duration(days: i))));
        }
        final max = data.values.isEmpty
            ? 1
            : data.values.reduce((a, b) => math.max(a, b));
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Column(
                children: [
                  for (var i = 0; i < 7; i++)
                    SizedBox(
                      height: 14,
                      width: 10,
                      child: Text(
                        i.isEven ? ['一', '', '三', '', '五', '', '日'][i] : '',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 7.5,
                          height: 1,
                          color: c.inkMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (final week in weeks)
                    Expanded(
                      child: Column(
                        children: [
                          for (final day in week)
                            Tooltip(
                              message:
                                  '${day.month}月${day.day}日 · ${data[dayKey(day)] ?? 0} 字',
                              waitDuration: const Duration(milliseconds: 250),
                              child: GestureDetector(
                                onTap: day.isAfter(today)
                                    ? null
                                    : () => onDayTap?.call(day),
                                child: Container(
                                  height: 11,
                                  margin: const EdgeInsets.all(1.2),
                                  decoration: BoxDecoration(
                                    color: day.isAfter(today)
                                        ? Colors.transparent
                                        : _color(
                                            c,
                                            data[dayKey(day)] ?? 0,
                                            max,
                                          ),
                                    borderRadius: BorderRadius.circular(2.2),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Color _color(AppPalette c, int words, int max) {
    if (words <= 0) return c.surfaceAlt;
    final t = (words / max).clamp(0.15, 1.0);
    return Color.lerp(c.surfaceAlt, c.accent, 0.2 + t * 0.8)!;
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, required this.count});
  final Color color;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 10.5,
              color: c.inkSoft,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 10.5,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
