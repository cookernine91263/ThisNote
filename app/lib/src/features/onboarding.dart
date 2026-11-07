import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import 'splash.dart';

/// 项目主页。引导页、设置页和 README 用的是同一个地址。
const thisNoteRepoUrl = 'https://github.com/cookernine91263/ThisNote';

Future<void> _openRepo() async {
  await launchUrl(
    Uri.parse(thisNoteRepoUrl),
    mode: LaunchMode.externalApplication,
  );
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  /// 文案以中文为源，英文放在 [_en] 里，切换语言时整页即时刷新。
  static const _en = <String, String>{
    '把日子写下来': 'Write your days down',
    '日记、随笔、作文，都在同一张安静的纸上。\n不必完美，先让第一句话落下。':
        'Diary, note, essay — all on the same quiet sheet.\nIt doesn\'t have to be perfect. Just let the first line land.',
    '写一句': 'Write a line',
    '把日子连成一条线': 'Link the days together',
    '日历里能翻回任何一天：\n写作热力、心情与天气、那年今日，都还在。':
        'The calendar walks back to any day:\nwriting heat, mood and weather, and “On this day”.',
    '继续': 'Continue',
    '写得好，也排得美': 'Write well, set it beautifully',
    '像 Word 一样加粗、倾斜、变细、配色；\n选中一句话，点一下花字，让它郑重一点。':
        'Bold, italic, light and color — like Word.\nSelect a sentence, tap Flower Text, and give it a little ceremony.',
    '试试花字': 'Try Flower Text',
    '所有字，都在你手里': 'Every word stays with you',
    '本地优先，不需要账号。\n自动保存、历史版本、密码锁与备份，都由你掌握。':
        'Local-first. No account needed.\nAuto-save, version history, a passcode and backups are all yours to keep.',
    '开始写': 'Start writing',
    '下一步': 'Next',
    '跳过': 'Skip',
    '此记 · 本地优先的写作空间': 'ThisNote · A local-first writing space',
    '喜欢此记？去 GitHub 点个 Star': 'Enjoying ThisNote? Star it on GitHub',
    '如果它帮你安静地写下了几句话，就给它一颗小星星吧 ♡':
        'If it helped you write a few quiet lines, leave it a little star ♡',
  };

  static const _pages = [
    (
      LucideIcons.feather,
      '把日子写下来',
      '日记、随笔、作文，都在同一张安静的纸上。\n不必完美，先让第一句话落下。',
      '写一句',
    ),
    (
      LucideIcons.calendarDays,
      '把日子连成一条线',
      '日历里能翻回任何一天：\n写作热力、心情与天气、那年今日，都还在。',
      '继续',
    ),
    (
      LucideIcons.sparkles,
      '写得好，也排得美',
      '像 Word 一样加粗、倾斜、变细、配色；\n选中一句话，点一下花字，让它郑重一点。',
      '试试花字',
    ),
    (
      LucideIcons.shield,
      '所有字，都在你手里',
      '本地优先，不需要账号。\n自动保存、历史版本、密码锁与备份，都由你掌握。',
      '开始写',
    ),
  ];

  Future<void> _finish() async {
    final state = context.read<AppState>();
    await state.updateSettings((s) => s.onboardingDone = true);
    // 首次启动时把欢迎页打开；从设置里「重新查看引导」回来时，
    // 用户手里可能正开着别的笔记，不要把他拽走。
    if (state.current != null) return;
    final welcome = state.notes.where((n) => n.id == 'seed-welcome');
    if (welcome.isNotEmpty) {
      await state.openNote(welcome.first.id);
    }
  }

  /// 最后一页的「点个 Star」：不吵，只是把门留在那儿。
  Widget _starPlea(BuildContext context) {
    final c = AppPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        HoverBuilder(
          builder: (context, hovered, t) => GestureDetector(
            onTap: _openRepo,
            child: AnimatedContainer(
              duration: Motion.fast,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: hovered
                    ? c.accentSoft
                    : c.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hovered ? c.accent.withValues(alpha: 0.45) : c.line,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.star,
                    size: 14,
                    color: hovered ? c.accent : c.inkSoft,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    tr('喜欢此记？去 GitHub 点个 Star', null, _en),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 11.5,
                      color: hovered ? c.accent : c.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(LucideIcons.arrowUpRight, size: 12, color: c.inkMuted),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr('如果它帮你安静地写下了几句话，就给它一颗小星星吧 ♡', null, _en),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 9,
            height: 1.6,
            color: c.inkMuted.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final page = _pages[_index];
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: c.paper,
      body: Stack(
        children: [
          Positioned.fill(child: PaperGrain(color: c.ink, opacity: c.grain * 1.2)),
          // 语言选择放在第一页右上角，任何一步都能切。
          // 用状态栏高度做偏移，避免胶囊压住时间与电池图标。
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 24,
            child: LanguageToggle(
              value: state.settings.language,
              onChanged: state.setLanguage,
            ),
          ),
          Positioned(
            right: 42,
            top: 96,
            bottom: 28,
            child: IgnorePointer(
              child: Column(
                children: [
                  if (!I18n.isEn)
                    for (final ch in '此记'.split(''))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          ch,
                          style: TextStyle(
                            fontFamily: 'WenKai',
                            fontSize: 18,
                            color: c.inkMuted.withValues(alpha: 0.28),
                          ),
                        ),
                      ),
                  const Spacer(),
                  const Seal(size: 26, radius: 7),
                ],
              ),
            ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: Motion.slow,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_index),
                        children: [
                          Container(
                            width: 74,
                            height: 74,
                            decoration: BoxDecoration(
                              color: c.accentSoft,
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: Icon(page.$1, size: 28, color: c.accent),
                          ),
                          const SizedBox(height: 26),
                          Text(
                            tr(page.$2, null, _en),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                              fontSize: I18n.isEn ? 30 : 34,
                              letterSpacing: I18n.isEn ? 0.4 : 2,
                              fontWeight: I18n.isEn ? FontWeight.w600 : null,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            tr(page.$3, null, _en),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 13,
                              height: 2,
                              color: c.inkSoft,
                            ),
                          ),
                          if (_index == 1) ...[
                            const SizedBox(height: 22),
                          ],
                        ],
                      ),
                    ),
                    if (last) ...[
                      const SizedBox(height: 18),
                      _starPlea(context),
                    ],
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < _pages.length; i++)
                          AnimatedContainer(
                            duration: Motion.fast,
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: i == _index ? 20 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _index ? c.accent : c.lineStrong,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () async {
                            if (!last) {
                              setState(() => _index++);
                            } else {
                              await _finish();
                            }
                          },
                          child: Text(
                            tr(last ? '开始写' : '下一步', null, _en),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 12,
                              color: c.accent,
                            ),
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: _finish,
                          child: Text(
                            tr('跳过', null, _en),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 11,
                              color: c.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('此记 · 本地优先的写作空间', null, _en),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9,
                        letterSpacing: 0.8,
                        color: c.inkMuted.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 中英切换的小胶囊。引导页和设置页共用。
class LanguageToggle extends StatelessWidget {
  const LanguageToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LangChip(
            label: '中文',
            active: value != 'en',
            compact: compact,
            onTap: () => onChanged('zh'),
          ),
          _LangChip(
            label: 'English',
            active: value == 'en',
            compact: compact,
            onTap: () => onChanged('en'),
          ),
        ],
      ),
    );
  }
}

class _LangChip extends StatelessWidget {
  const _LangChip({
    required this.label,
    required this.active,
    required this.onTap,
    required this.compact,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 13,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: active ? c.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: compact ? 10 : 11,
            letterSpacing: 0.3,
            color: active ? c.paper : c.inkMuted,
          ),
        ),
      ),
    );
  }
}
