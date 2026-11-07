import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '写作统计': 'Writing stats',
  '不催促，只记录你走过的路': 'No rush — it just keeps the path you walked',
  '总字数': 'Total words',
  '所有没有被丢掉的字': 'Every word you kept',
  '总篇数': 'Total notes',
  '日记 {d} · 作文 {e} · 随笔 {n}': 'Diary: {d} · Essay: {e} · Note: {n}',
  '连续写作': 'Writing streak',
  '天': 'day',
  '保持住，哪怕只写一句': 'Keep it going, even one line',
  '今天写下第一句吧': 'Write the first line today',
  '今日进度': "Today's progress",
  '今天的字数已经够了': "Today's word count is already there",
  '还差 {n} 字': 'Still {n} to go',
  '最近 7 天': 'Last 7 days',
  '本周 {w} 字': 'This week · {w}',
  '写作热力图': 'Writing heat',
  '最近一年': 'Past year',
  '少': 'Less',
  '多': 'More',
  '写了什么': 'What you wrote',
  '还没有内容。': 'Nothing here yet.',
  '无题': 'Untitled',
  '日记': 'Diary',
  '作文': 'Essay',
  '随笔': 'Note',
  '平均每篇 {avg} 字': 'Average per note · {avg}',
  '常用的标签': 'Top tags',
  '给文字贴上第一个标签吧。': 'Give your writing its first tag.',
  '{date}还没有文字': '{date} has no words yet',
  '{n} 篇 · {w} 字': '{n} · {w}',
  '{words} 字 · {kind}': '{words} · {kind}',
  '{date} · {words} 字': '{date} · {words}',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

/// 数量在英文里要跟着单复数变，中文则把量词留在原文里：
/// 中文只返回数字，英文返回「3 notes」这样的整体，所以 [_en] 里
/// 写成 `'本周 {w} 字': 'This week · {w}'` 就够了。
String _q(int n, String zhUnit, String enOne, [String? enMany]) =>
    I18n.isEn ? I18n.count(n, zhUnit, enOne, enMany) : '$n';

/// 月日：中文「10 月 31 日」，英文「Oct 31」。
String _monthDay(DateTime d) =>
    I18n.isEn ? DateFormat('MMM d').format(d) : '${d.month} 月 ${d.day} 日';

/// 星期缩写（周一开头）。
List<String> get _weekdayLetters => I18n.isEn
    ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
    : const ['一', '二', '三', '四', '五', '六', '日'];

/// 热力图左侧只标周一、三、五、日。
List<String> get _heatmapRows => I18n.isEn
    ? const ['M', '', 'W', '', 'F', '', 'S']
    : const ['一', '', '三', '', '五', '', '日'];

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.read<AppState>();
    // 只在笔记/活动/目标变化时重算，不被保存状态点刷新。
    context.select<AppState, (int, int)>(
      (value) => (value.dataRevision, value.settings.dailyGoal),
    );
    final days = state.last7Days;
    final maxWords = days.fold(0, (m, d) => math.max(m, d.words)).toInt();
    final total = state.diaryCount + state.essayCount + state.noteCount;
    final avg = state.activeNotes.isEmpty
        ? 0
        : (state.totalWords / state.activeNotes.length).round();
    final weekWords = days.fold(0, (s, d) => s + d.words);
    final compact = MediaQuery.sizeOf(context).width < 720;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _t('写作统计'),
          style: TextStyle(
            fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
            fontSize: I18n.isEn ? 26 : 30,
            fontWeight: I18n.isEn ? FontWeight.w600 : null,
            letterSpacing: I18n.isEn ? 0.3 : 2,
            color: c.ink,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          _t('不催促，只记录你走过的路'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 10.5,
            color: c.inkMuted,
          ),
        ),
      ],
    );
    final date = Text(
      dateLabel(DateTime.now()),
      style: TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 10,
        color: c.inkMuted,
      ),
    );
    final summaryCard = PaperSurface(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(_t('写了什么')),
          if (total == 0)
            Text(
              _t('还没有内容。'),
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
            _Legend(
              color: c.accent,
              label: _t('日记'),
              count: state.diaryCount,
            ),
            _Legend(
              color: c.gold,
              label: _t('作文'),
              count: state.essayCount,
            ),
            _Legend(
              color: c.sage,
              label: _t('随笔'),
              count: state.noteCount,
            ),
            const SizedBox(height: 4),
            Text(
              _t('平均每篇 {avg} 字', {
                'avg': _q(avg, '字', 'word'),
              }),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
                color: c.inkMuted,
              ),
            ),
            if (state.totalWritingSeconds > 0) ...[
              const SizedBox(height: 3),
              Text(
                writingTimeLabel(state.totalWritingSeconds, state.totalWords),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ],
        ],
      ),
    );
    final tagsCard = PaperSurface(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(_t('常用的标签')),
          if (state.tagCounts.isEmpty)
            Text(
              _t('给文字贴上第一个标签吧。'),
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
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleBlock,
              const SizedBox(height: 4),
              date,
            ],
          )
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              titleBlock,
              const Spacer(),
              date,
            ],
          ),
        const SizedBox(height: 20),
        Reveal(
          delay: const Duration(milliseconds: 60),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth;
              final columns = available >= 880
                  ? 4
                  : available >= 620
                      ? 3
                      : available >= 420
                          ? 2
                          : 1;
              final metricWidth =
                  (available - 10.0 * (columns - 1)) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Metric(
                    width: metricWidth,
                    icon: LucideIcons.penLine,
                    label: _t('总字数'),
                    value: '${state.totalWords}',
                    hint: _t('所有没有被丢掉的字'),
                  ),
                  _Metric(
                    width: metricWidth,
                    icon: LucideIcons.library,
                    label: _t('总篇数'),
                    value: '${state.activeNotes.length}',
                    hint: _t('日记 {d} · 作文 {e} · 随笔 {n}', {
                      'd': state.diaryCount,
                      'e': state.essayCount,
                      'n': state.noteCount,
                    }),
                    onTap: () => state.setView('all'),
                  ),
                  _Metric(
                    width: metricWidth,
                    icon: LucideIcons.flame,
                    label: _t('连续写作'),
                    value: '${state.streak}',
                    suffix: I18n.isEn
                        ? ' ${I18n.plural(state.streak, _t('天'))}'
                        : ' 天',
                    hint: state.streak > 0
                        ? _t('保持住，哪怕只写一句')
                        : _t('今天写下第一句吧'),
                  ),
                  _Metric(
                    width: metricWidth,
                    icon: LucideIcons.target,
                    label: _t('今日进度'),
                    value: '${state.todayWords}',
                    suffix: ' / ${state.settings.dailyGoal}',
                    hint: state.todayWords >= state.settings.dailyGoal
                        ? _t('今天的字数已经够了')
                        : _t('还差 {n} 字', {
                            'n': _q(
                              math.max(
                                0,
                                state.settings.dailyGoal - state.todayWords,
                              ),
                              '字',
                              'word',
                            ),
                          }),
                  ),
                ],
              );
            },
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
                _t('最近 7 天'),
                trailing: Text(
                  _t('本周 {w} 字', {'w': _q(weekWords, '字', 'word')}),
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
                _t('写作热力图'),
                trailing: Text(
                  _t('最近一年'),
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
                    _t('少'),
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
                    _t('多'),
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summaryCard,
                    const SizedBox(height: 12),
                    tagsCard,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: summaryCard),
                  const SizedBox(width: 12),
                  Expanded(child: tagsCard),
                ],
              );
            },
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
      showToast(
        context,
        _t('{date}还没有文字', {'date': _monthDay(day)}),
      );
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
                      _monthDay(day),
                      style: TextStyle(
                        fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                        fontSize: 24,
                        fontWeight: I18n.isEn ? FontWeight.w600 : null,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _t('{n} 篇 · {w} 字', {
                        'n': _q(notes.length, '篇', 'note'),
                        'w': _q(total, '字', 'word'),
                      }),
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
                        note.title.trim().isEmpty ? _t('无题') : note.title.trim(),
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
                        _t('{words} 字 · {kind}', {
                          'words': _q(note.words, '字', 'word'),
                          'kind': note.kind.label,
                        }),
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
    this.width = 205,
    this.suffix = '',
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String suffix;
  final String hint;
  final double width;
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
              width: width,
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
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      color: c.inkMuted,
                      letterSpacing: 0.5,
                    ),
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
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
      message: _t('{date} · {words} 字', {
        'date': _monthDay(stat.date),
        'words': _q(stat.words, '字', 'word'),
      }),
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
            _weekdayLetters[stat.date.weekday - 1],
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
                        i.isEven ? _heatmapRows[i] : '',
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
                              message: _t('{date} · {words} 字', {
                                'date': _monthDay(day),
                                'words': _q(
                                  data[dayKey(day)] ?? 0,
                                  '字',
                                  'word',
                                ),
                              }),
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
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: c.inkSoft,
              ),
            ),
          ),
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
