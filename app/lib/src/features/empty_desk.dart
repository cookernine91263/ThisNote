import 'dart:math' as math;

import 'package:flutter/material.dart';
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
import 'new_note_sheet.dart';
import 'splash.dart';

class EmptyDesk extends StatelessWidget {
  const EmptyDesk({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final now = DateTime.now();
    final recent = state.visibleNotes.take(4).toList();
    return Stack(
      children: [
        Positioned(
          right: 52,
          top: 44,
          bottom: 44,
          child: IgnorePointer(
            child: Column(
              children: [
                if (!I18n.isEn)
                  for (final ch in '落笔即心安'.split(''))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Text(
                        ch,
                        style: TextStyle(
                          fontFamily: 'WenKai',
                          fontSize: 19,
                          color: c.inkMuted.withValues(alpha: 0.32),
                        ),
                      ),
                    ),
                if (!I18n.isEn) ... [
                  const SizedBox(height: 18),
                  Container(
                    width: 1,
                    height: 30,
                    color: c.line.withValues(alpha: 0.8),
                  ),
                  const SizedBox(height: 14),
                ],
                const Seal(size: 24, radius: 7),
              ],
            ),
          ),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(56, 46, 56, 60),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Reveal(
                  child: Row(
                    children: [
                      Text(
                        dateLabel(now),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11,
                          letterSpacing: 0.8,
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Dot(size: 2.5, color: c.lineStrong),
                      const SizedBox(width: 10),
                      Text(
                        _t('{g}，适合写一点', {'g': greeting(now)}),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11,
                          color: c.inkMuted,
                        ),
                      ),
                      const Spacer(),
                      _GoalRing(
                        words: state.todayWords,
                        goal: state.settings.dailyGoal,
                        streak: state.streak,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 52),
                Reveal(
                  delay: const Duration(milliseconds: 60),
                  child: Text(
                    _t('今天，写点什么？'),
                    style: TextStyle(
                      fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                      fontSize: I18n.isEn ? 38 : 43,
                      height: 1.25,
                      letterSpacing: I18n.isEn ? 0.5 : 2,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Reveal(
                  delay: const Duration(milliseconds: 110),
                  child: SizedBox(
                    width: 460,
                    child: Text(
                      _t('不必等到有灵感。先写下一句，纸会接住剩下的。'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 13,
                        height: 1.9,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 38),
                Reveal(
                  delay: const Duration(milliseconds: 160),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StartCard(
                        icon: LucideIcons.calendarHeart,
                        title: _t('写日记'),
                        subtitle: _t('天气、心情与三件小事'),
                        onTap: () => state.createNote(
                          kind: NoteKind.diary,
                        ),
                      ),
                      _StartCard(
                        icon: LucideIcons.penLine,
                        title: _t('写随笔'),
                        subtitle: _t('想到哪里，写到哪里'),
                        onTap: () => state.createNote(kind: NoteKind.note),
                      ),
                      _StartCard(
                        icon: LucideIcons.feather,
                        title: _t('写作文'),
                        subtitle: _t('题目、结构与完整的表达'),
                        onTap: () => state.createNote(kind: NoteKind.essay),
                      ),
                      _StartCard(
                        icon: LucideIcons.sparkles,
                        title: _t('看模板'),
                        subtitle: _t('换一种开始的方式'),
                        onTap: () => showNewNoteSheet(context),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 50),
                if (recent.isNotEmpty)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SectionLabel(
                        _t('最近写过'),
                        trailing: GestureDetector(
                          onTap: () => state.setView('all'),
                          child: Text(
                            _t('全部'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10.5,
                              color: c.inkMuted,
                            ),
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: c.line)),
                        ),
                        child: Column(
                          children: [
                            for (final note in recent)
                              _RecentRow(note: note),
                          ],
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 38),
                Center(
                  child: Column(
                    children: [
                      Text(
                        _t('“写作是把散落的自己，一页一页收回来。”'),
                        style: TextStyle(
                          fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                          fontSize: 12.5,
                          color: c.inkMuted,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _t('Ctrl / ⌘ + K 打开命令面板'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted.withValues(alpha: 0.75),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.base,
            curve: Motion.spring,
            transform: Matrix4.translationValues(0, hovered ? -3 : 0, 0),
            width: 172,
            padding: const EdgeInsets.fromLTRB(15, 14, 13, 13),
            decoration: BoxDecoration(
              color: hovered ? c.surface : c.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: hovered ? c.lineStrong : c.line),
              boxShadow: hovered
                  ? [
                      BoxShadow(
                        color: c.shadow.withValues(alpha: 0.07),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 17, color: c.accent),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.note});
  final NoteMeta note;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.read<AppState>();
    return HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: () => state.openNote(note.id),
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.line)),
              color: hovered ? c.surface.withValues(alpha: 0.6) : Colors.transparent,
            ),
            child: Row(
              children: [
                Icon(kindIcon(note.kind), size: 13, color: c.inkMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    note.title.trim().isEmpty ? _t('无题') : note.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12.5,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Text(
                  shortDate(note.updatedAt),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  I18n.count(note.words, '字', 'word'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(width: 10),
                AnimatedOpacity(
                  opacity: hovered ? 1 : 0,
                  duration: Motion.fast,
                  child: Icon(LucideIcons.arrowUpRight, size: 12, color: c.accent),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GoalRing extends StatelessWidget {
  const _GoalRing({
    required this.words,
    required this.goal,
    required this.streak,
  });

  final int words;
  final int goal;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final progress = goal <= 0 ? 0.0 : (words / goal).clamp(0.0, 1.0);
    return Row(
      children: [
        Text(
          streak > 0 ? _t('连续 {n} 天', {'n': streak}) : _t('从今天开始'),
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 10,
            color: streak > 0 ? c.accent : c.inkMuted,
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 34,
          height: 34,
          child: CustomPaint(
            painter: _RingPainter(progress, c.accent, c.line),
            child: Center(
              child: Text(
                '${(progress * 100).round()}',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 8.5,
                  color: c.inkMuted,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          '$words / $goal',
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 9.5,
            color: c.inkMuted,
          ),
        ),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.progress, this.accent, this.track);
  final double progress;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2 - 2;
    final bg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = track;
    canvas.drawCircle(center, radius, bg);
    final fg = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = accent;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      fg,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.accent != accent || old.track != track;
}

/// 英文文案。键是界面里的中文原文，值是对应的英文。
const Map<String, String> _en = <String, String>{
  '{g}，适合写一点': '{g} — a good time to write a little',
  '今天，写点什么？': 'What will you write today?',
  '不必等到有灵感。先写下一句，纸会接住剩下的。':
      'No need to wait for inspiration. Write the first line and the page catches the rest.',
  '写日记': 'Write a diary',
  '天气、心情与三件小事': 'Weather, mood, 3 things',
  '写随笔': 'Write a note',
  '想到哪里，写到哪里': 'Follow the thought',
  '写作文': 'Write an essay',
  '题目、结构与完整的表达': 'Topic, structure, finish',
  '看模板': 'Browse templates',
  '换一种开始的方式': 'Start a different way',
  '最近写过': 'Recently written',
  '全部': 'All',
  '“写作是把散落的自己，一页一页收回来。”':
      '“Writing gathers the scattered self back, one page at a time.”',
  'Ctrl / ⌘ + K 打开命令面板': 'Ctrl / Cmd + K opens the command palette',
  '无题': 'Untitled',
  '连续 {n} 天': '{n}-day streak',
  '从今天开始': 'Start today',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

