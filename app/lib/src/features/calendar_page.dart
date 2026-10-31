import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/icons.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '日历': 'Calendar',
  '在时间里回看写下的句子': 'Look back at what you wrote, through time',
  '本月 {n} 篇 · {w} 字': 'This month · {n} · {w}',
  '上个月': 'Previous month',
  '下个月': 'Next month',
  '回到今天': 'Back to today',
  '在这一天写一篇': 'Write something on this day',
  '这一天还是空白': 'This day is still blank',
  '无题': 'Untitled',
  '{words} 字 · {time}': '{words} · {time}',
  '那年今日': 'On this day',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

/// 数量在英文里要跟着单复数变，中文则把量词留在原文里：
/// 中文只返回数字，英文返回「3 notes」这样的整体，所以 [_en] 里
/// 写成 `'本月 {n} 篇 · {w} 字': 'This month · {n} · {w}'` 就够了。
String _q(int n, String zhUnit, String enOne, [String? enMany]) =>
    I18n.isEn ? I18n.count(n, zhUnit, enOne, enMany) : '$n';

/// 月日：中文「10 月 31 日」，英文「Oct 31」。
String _monthDay(DateTime d) =>
    I18n.isEn ? DateFormat('MMM d').format(d) : '${d.month} 月 ${d.day} 日';

/// 日历表头与周条上的星期缩写。
List<String> get _weekdayLetters => I18n.isEn
    ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
    : const ['一', '二', '三', '四', '五', '六', '日'];

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key, this.mobile = false});
  final bool mobile;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    final state = context.read<AppState>();
    _selected = state.selectedDay ?? DateTime.now();
    _month = DateTime(_selected.year, _selected.month);
  }

  void _shift(int months) {
    setState(() {
      _month = DateTime(_month.year, _month.month + months);
    });
  }

  void _select(DateTime day) {
    setState(() => _selected = day);
    context.read<AppState>().selectDay(day);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final byDay = <String, List<NoteMeta>>{};
    for (final n in state.activeNotes) {
      byDay.putIfAbsent(n.day, () => []).add(n);
    }
    final monthNotes = state.activeNotes
        .where((n) =>
            parseDay(n.day).year == _month.year &&
            parseDay(n.day).month == _month.month)
        .toList();
    final monthWords = monthNotes.fold(0, (s, n) => s + n.words);
    final selectedNotes = byDay[dayKey(_selected)] ?? const <NoteMeta>[];
    final onThisDay = _onThisDay(state);

    final header = _CalendarHeader(
      month: _month,
      onPrev: () => _shift(-1),
      onNext: () => _shift(1),
      onToday: () {
        final now = DateTime.now();
        setState(() {
          _month = DateTime(now.year, now.month);
          _selected = now;
        });
        state.selectDay(now);
      },
      monthNotes: monthNotes.length,
      monthWords: monthWords,
    );

    final grid = PaperSurface(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      radius: 14,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              for (final w in _weekdayLetters)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        color: c.inkMuted,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _MonthGrid(
            month: _month,
            selected: _selected,
            byDay: byDay,
            onSelect: _select,
          ),
        ],
      ),
    );

    final side = _DaySidebar(
      selected: _selected,
      notes: selectedNotes,
      onThisDay: onThisDay,
      onCreate: () async {
        if (!widget.mobile) state.setView('all');
        await state.createNote(kind: NoteKind.diary, day: _selected);
      },
      onOpen: (id) async {
        if (!widget.mobile) state.setView('all');
        await state.openNote(id);
      },
    );

    if (widget.mobile) {
      return SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
          children: [
            header,
            const SizedBox(height: 14),
            grid,
            const SizedBox(height: 14),
            side,
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(34, 30, 30, 30),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 22),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: grid),
                  const SizedBox(width: 18),
                  SizedBox(width: 310, child: side),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<int, NoteMeta> _onThisDay(AppState state) {
    final map = <int, NoteMeta>{};
    for (final n in state.activeNotes) {
      final d = parseDay(n.day);
      if (d.month == _selected.month &&
          d.day == _selected.day &&
          d.year < _selected.year) {
        map[d.year] = n;
      }
    }
    return map;
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.monthNotes,
    required this.monthWords,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final int monthNotes;
  final int monthWords;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('日历'),
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
              _t('在时间里回看写下的句子'),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: c.inkMuted,
              ),
            ),
          ],
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _t('本月 {n} 篇 · {w} 字', {
                'n': _q(monthNotes, '篇', 'note'),
                'w': _q(monthWords, '字', 'word'),
              }),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                SoftIconButton(
                  icon: LucideIcons.chevronLeft,
                  size: 30,
                  tooltip: _t('上个月'),
                  onPressed: onPrev,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: Text(
                      monthTitle(month),
                      key: ValueKey(month),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: c.ink,
                      ),
                    ),
                  ),
                ),
                SoftIconButton(
                  icon: LucideIcons.chevronRight,
                  size: 30,
                  tooltip: _t('下个月'),
                  onPressed: onNext,
                ),
                const SizedBox(width: 6),
                SoftButton(
                  label: _t('回到今天'),
                  dense: true,
                  onPressed: onToday,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.byDay,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final Map<String, List<NoteMeta>> byDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final offset = (first.weekday + 6) % 7;
    final start = first.subtract(Duration(days: offset));
    final today = DateTime.now();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var week = 0; week < 6; week++)
          Row(
            children: [
              for (var weekday = 0; weekday < 7; weekday++)
                Expanded(
                  child: _DayCell(
                    day: start.add(Duration(days: week * 7 + weekday)),
                    inMonth: start.add(Duration(days: week * 7 + weekday)).month == month.month,
                    selected: dayKey(start.add(Duration(days: week * 7 + weekday))) ==
                        dayKey(selected),
                    today: dayKey(start.add(Duration(days: week * 7 + weekday))) ==
                        dayKey(today),
                    notes: byDay[dayKey(start.add(Duration(days: week * 7 + weekday)))] ??
                        const [],
                    onTap: onSelect,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.notes,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool selected;
  final bool today;
  final List<NoteMeta> notes;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final words = notes.fold(0, (s, n) => s + n.words);
    final intensity = math.min(words / 900.0, 1.0);
    Mood? mood;
    for (final n in notes) {
      final m = MoodX.fromScore(n.mood);
      if (m != null) {
        mood = m;
        break;
      }
    }
    return AspectRatio(
      aspectRatio: 1.45,
      child: HoverBuilder(
        builder: (context, hovered, t) {
          return GestureDetector(
            onTap: () => onTap(day),
            child: AnimatedContainer(
              duration: Motion.fast,
              margin: const EdgeInsets.all(2),
              padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
              decoration: BoxDecoration(
                color: selected
                    ? c.accentSoft
                    : words > 0
                        ? c.accent.withValues(alpha: 0.025 + intensity * 0.1)
                        : hovered
                            ? c.surfaceAlt
                            : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected
                      ? c.accent.withValues(alpha: 0.45)
                      : hovered
                          ? c.line
                          : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: today ? c.accent : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        color: !inMonth
                            ? c.inkMuted.withValues(alpha: 0.4)
                            : today
                                ? c.onAccent
                                : c.inkSoft,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (notes.isNotEmpty)
                    Row(
                      children: [
                        if (mood != null)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: mood.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(
                          '${notes.length}',
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 7.5,
                            color: c.inkMuted,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 12,
                          height: 2,
                          decoration: BoxDecoration(
                            color: c.accent.withValues(
                              alpha: 0.25 + intensity * 0.6,
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DaySidebar extends StatelessWidget {
  const _DaySidebar({
    required this.selected,
    required this.notes,
    required this.onThisDay,
    required this.onCreate,
    required this.onOpen,
  });

  final DateTime selected;
  final List<NoteMeta> notes;
  final Map<int, NoteMeta> onThisDay;
  final VoidCallback onCreate;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PaperSurface(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _monthDay(selected),
                style: TextStyle(
                  fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                  fontSize: 21,
                  fontWeight: I18n.isEn ? FontWeight.w600 : null,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                weekdayLabel(selected),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9.5,
                  color: c.inkMuted,
                ),
              ),
              const Spacer(),
              SoftIconButton(
                icon: LucideIcons.penLine,
                size: 28,
                tooltip: _t('在这一天写一篇'),
                onPressed: onCreate,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (notes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 22),
              child: Center(
                child: Column(
                  children: [
                    InkEmpty(size: 86),
                    const SizedBox(height: 8),
                    Text(
                      _t('这一天还是空白'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 10.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final note in notes)
              HoverBuilder(
                builder: (context, hovered, t) => GestureDetector(
                  onTap: () => onOpen(note.id),
                  child: AnimatedContainer(
                    duration: Motion.fast,
                    margin: const EdgeInsets.only(bottom: 2),
                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                    decoration: BoxDecoration(
                      color: hovered ? c.paper : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      children: [
                        Icon(kindIcon(note.kind), size: 12, color: c.inkMuted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                note.title.isEmpty ? _t('无题') : note.title,
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
                                _t('{words} 字 · {time}', {
                                  'words': _q(note.words, '字', 'word'),
                                  'time': timeLabel(note.updatedAt),
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
                        Icon(LucideIcons.arrowUpRight, size: 11, color: c.inkMuted),
                      ],
                    ),
                  ),
                ),
              ),
          if (onThisDay.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: c.line),
            const SizedBox(height: 10),
            Text(
              _t('那年今日'),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9,
                letterSpacing: 1.2,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(height: 6),
            for (final entry in onThisDay.entries)
              GestureDetector(
                onTap: () => onOpen(entry.value.id),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Text(
                        '${entry.key}',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 10,
                          color: c.gold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.value.title.isEmpty
                              ? _t('无题')
                              : entry.value.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 10,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
