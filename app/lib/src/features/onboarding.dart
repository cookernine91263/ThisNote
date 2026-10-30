import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/motion.dart';
import '../core/motion_choice.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import 'splash.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _index = 0;

  static const _pages = [
    (
      LucideIcons.feather,
      '把日子写下来',
      '日记、随笔、作文，都在同一张安静的纸上。\n不必完美，先让第一句话落下。',
      '写一句',
    ),
    (
      LucideIcons.move3d,
      '选一种翻页手感',
      'PPT 里的「平滑」被搬到了这里：\n旧页收拢、新页展开；也可以选轻快的滑入。',
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
    final welcome = state.notes.where((n) => n.id == 'seed-welcome');
    if (welcome.isNotEmpty) {
      await state.openNote(welcome.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final page = _pages[_index];
    return Scaffold(
      backgroundColor: c.paper,
      body: Stack(
        children: [
          Positioned.fill(child: PaperGrain(color: c.ink, opacity: c.grain * 1.2)),
          Positioned(
            right: 42,
            top: 28,
            bottom: 28,
            child: IgnorePointer(
              child: Column(
                children: [
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
                            page.$2,
                            style: TextStyle(
                              fontFamily: 'WenKai',
                              fontSize: 34,
                              letterSpacing: 2,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            page.$3,
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
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 470),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: MotionChoice(
                                      value: 'slide',
                                      selected:
                                          state.settings.motionStyle == 'slide',
                                      onTap: () => state.setMotionStyle('slide'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: MotionChoice(
                                      value: 'morph',
                                      selected:
                                          state.settings.motionStyle == 'morph',
                                      onTap: () => state.setMotionStyle('morph'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
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
                            if (_index < _pages.length - 1) {
                              setState(() => _index++);
                            } else {
                              await _finish();
                            }
                          },
                          child: Text(
                            _index == _pages.length - 1 ? '开始写' : '下一步',
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
                            '跳过',
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
                      '此记 · 本地优先的写作空间',
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
