import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/motion.dart';
import '../core/theme.dart';
import '../core/theme_reveal.dart';
import '../core/trash_fly.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import 'calendar_page.dart';
import 'command_palette.dart';
import 'editor/editor_page.dart';
import 'empty_desk.dart';
import 'note_list.dart';
import 'settings_page.dart';
import 'splash.dart';
import 'stats_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WindowListener {
  bool _zen = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) windowManager.addListener(this);
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    if (Platform.isWindows) windowManager.removeListener(this);
    super.dispose();
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return false;
    final state = context.read<AppState>();
    if (event.logicalKey == LogicalKeyboardKey.keyK) {
      showCommandPalette(context);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyN) {
      state.createNote();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyS) {
      state.saveNow();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF && keyboard.isShiftPressed) {
      _toggleZen();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.comma) {
      state.setView('settings');
      return true;
    }
    return false;
  }

  @override
  void onWindowMaximize() => setState(() {});
  @override
  void onWindowUnmaximize() => setState(() {});

  void _toggleZen() {
    setState(() => _zen = !_zen);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 900;
    final zen = _zen && state.current != null;

    if (mobile) return _MobileShell(state: state);

    final showList =
        const ['today', 'all', 'tags', 'trash', 'search'].contains(state.view);
    final main = _buildMain(state, zen);
    final morph = state.settings.motionStyle == 'morph';

    return Focus(
      autofocus: true,
      child: Scaffold(
        backgroundColor: AppPalette.of(context).paper,
        body: Column(
          children: [
            if (!zen && Platform.isWindows) const WindowTitleBar(),
            Expanded(
              child: Row(
                children: [
                  _AnimatedWidth(
                    visible: !zen,
                    width: 76,
                    child: _Rail(
                      zen: zen,
                      onPalette: () => showCommandPalette(context),
                      onToggleZen: _toggleZen,
                    ),
                  ),
                  _AnimatedWidth(
                    visible: !zen && showList,
                    width: 324,
                    duration: morph
                        ? const Duration(milliseconds: 430)
                        : Motion.base,
                    curve: morph ? Curves.easeInOutCubic : Motion.spring,
                    child: const NoteListPanel(),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: AppPalette.of(context).paper,
                      child: ClipRect(
                      child: AnimatedSwitcher(
                        key: ValueKey('motion-${state.settings.motionStyle}'),
                        duration: Duration(milliseconds: morph ? 430 : 280),
                        reverseDuration:
                            Duration(milliseconds: morph ? 360 : 220),
                        switchInCurve: morph
                            ? Curves.easeInOutCubic
                            : Curves.easeOutCubic,
                        switchOutCurve: morph
                            ? Curves.easeInOutCubic
                            : Curves.easeInCubic,
                        layoutBuilder: (current, previous) =>
                            current ?? const SizedBox.shrink(),
                        transitionBuilder: (child, animation) {
                          if (morph) {
                            final curve = CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                              reverseCurve: Curves.easeInOutCubic,
                            );
                            return FadeTransition(
                              opacity: curve,
                              child: ScaleTransition(
                                alignment: Alignment.topCenter,
                                scale: Tween<double>(
                                  begin: 0.968,
                                  end: 1,
                                ).animate(curve),
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.012),
                                    end: Offset.zero,
                                  ).animate(curve),
                                  child: child,
                                ),
                              ),
                            );
                          }
                          final slide = Tween<Offset>(
                            begin: const Offset(0.018, 0),
                            end: Offset.zero,
                          ).animate(animation);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: slide,
                              child: child,
                            ),
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey(
                            '${state.view}-${state.current?.id ?? 'desk'}',
                          ),
                          child: main,
                        ),
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
    );
  }

  Widget _buildMain(AppState state, bool zen) {
    switch (state.view) {
      case 'calendar':
        return const CalendarPage();
      case 'stats':
        return const StatsPage();
      case 'settings':
        return const SettingsPage();
      default:
        if (state.current != null) {
          return EditorPage(
            mobile: false,
            zen: zen,
            onToggleZen: _toggleZen,
          );
        }
        return const EmptyDesk();
    }
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    if (state.current != null) {
      return EditorPage(
        mobile: true,
        onBack: () => state.closeEditor(),
      );
    }
    final tab = switch (state.view) {
      'calendar' => 1,
      'stats' => 2,
      'settings' => 3,
      _ => 0,
    };
    return Scaffold(
      backgroundColor: c.paper,
      body: IndexedStack(
        index: tab,
        children: const [
          SafeArea(bottom: false, child: NoteListPanel(embedded: true)),
          CalendarPage(mobile: true),
          StatsPage(),
          SettingsPage(),
        ],
      ),
      bottomNavigationBar: _MobileNav(
        current: tab,
        onTap: (i) {
          state.setView(switch (i) {
            1 => 'calendar',
            2 => 'stats',
            3 => 'settings',
            _ => 'today',
          });
        },
      ),
    );
  }
}

class _MobileNav extends StatelessWidget {
  const _MobileNav({required this.current, required this.onTap});
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final items = const [
      (LucideIcons.sun, '今日'),
      (LucideIcons.calendarDays, '日历'),
      (LucideIcons.chartNoAxesColumn, '统计'),
      (LucideIcons.settings, '我的'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.only(
        top: 7,
        bottom: MediaQuery.paddingOf(context).bottom + 9,
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: Motion.fast,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: current == i ? c.accentSoft : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        items[i].$1,
                        size: 18,
                        color: current == i ? c.accent : c.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      items[i].$2,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        color: current == i ? c.accent : c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AnimatedWidth extends StatelessWidget {
  const _AnimatedWidth({
    required this.visible,
    required this.width,
    required this.child,
    this.duration = Motion.base,
    this.curve = Motion.spring,
  });
  final bool visible;
  final double width;
  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        width: visible ? width : 0,
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          minWidth: width,
          maxWidth: width,
          child: child,
        ),
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.zen,
    required this.onPalette,
    required this.onToggleZen,
  });

  final bool zen;
  final VoidCallback onPalette;
  final VoidCallback onToggleZen;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final active = state.view;
    return Container(
      width: 76,
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Tooltip(
            message: '此记 · ThisNote',
            child: const Seal(size: 32, radius: 9),
          ),
          const SizedBox(height: 20),
          _RailItem(
            icon: LucideIcons.sun,
            label: '今日',
            active: active == 'today',
            onTap: () => state.setView('today'),
          ),
          _RailItem(
            icon: LucideIcons.library,
            label: '全部',
            active: active == 'all',
            onTap: () => state.setView('all'),
          ),
          _RailItem(
            icon: LucideIcons.calendarDays,
            label: '日历',
            active: active == 'calendar',
            onTap: () => state.setView('calendar'),
          ),
          _RailItem(
            icon: LucideIcons.tag,
            label: '标签',
            active: active == 'tags',
            onTap: () => state.setView('tags'),
          ),
          _RailItem(
            icon: LucideIcons.chartNoAxesColumn,
            label: '统计',
            active: active == 'stats',
            onTap: () => state.setView('stats'),
          ),
          const Spacer(),
          _RailItem(
            icon: LucideIcons.command,
            label: '命令',
            active: false,
            onTap: onPalette,
            tooltip: '命令面板 · Ctrl K',
          ),
          _RailItem(
            icon: LucideIcons.focus,
            label: '专注',
            active: zen,
            onTap: onToggleZen,
            tooltip: '专注模式 · Ctrl Shift F',
          ),
          _RailItem(
            icon: state.settings.themeMode == ThemeMode.dark
                ? LucideIcons.moon
                : state.settings.themeMode == ThemeMode.light
                    ? LucideIcons.sun
                    : LucideIcons.sunMoon,
            label: '外观',
            active: false,
            onTap: () {},
            onTapPosition: (origin) {
              final next = switch (state.settings.themeMode) {
                ThemeMode.system => ThemeMode.light,
                ThemeMode.light => ThemeMode.dark,
                ThemeMode.dark => ThemeMode.system,
              };
              ThemeReveal.reveal(
                context: context,
                globalOrigin: origin,
                apply: () => state.setThemeMode(next),
              );
            },
            tooltip: '切换外观',
          ),
          _RailItem(
            key: TrashFly.targetKey,
            icon: LucideIcons.trash2,
            label: '回收',
            active: active == 'trash',
            onTap: () => state.setView('trash'),
          ),
          _RailItem(
            icon: LucideIcons.settings,
            label: '设置',
            active: active == 'settings',
            onTap: () => state.setView('settings'),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.onTapPosition,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onTapPosition;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: tooltip ?? label,
        child: HoverBuilder(
          builder: (context, hovered, t) {
            return GestureDetector(
              onTapUp: onTapPosition == null
                  ? null
                  : (details) => onTapPosition!(details.globalPosition),
              onTap: onTap,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  AnimatedContainer(
                    duration: Motion.fast,
                    width: 56,
                    height: 48,
                    margin: const EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      color: active
                          ? c.accentSoft
                          : hovered
                              ? c.surface
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          icon,
                          size: 18,
                          color: active
                              ? c.accent
                              : hovered
                                  ? c.ink
                                  : c.inkMuted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 9,
                            height: 1.1,
                            letterSpacing: 0.2,
                            color: active
                                ? c.accent
                                : hovered
                                    ? c.inkSoft
                                    : c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    duration: Motion.fast,
                    opacity: active ? 1 : 0,
                    child: Container(
                      width: 2.5,
                      height: 18,
                      decoration: BoxDecoration(
                        color: c.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key});

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximized = v);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(bottom: BorderSide(color: c.line.withValues(alpha: 0.7))),
      ),
      child: Row(
        children: [
          Expanded(
            child: DragToMoveArea(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onDoubleTap: () async {
                  if (await windowManager.isMaximized()) {
                    await windowManager.unmaximize();
                  } else {
                    await windowManager.maximize();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      const Seal(size: 21, radius: 6),
                      const SizedBox(width: 8),
                      Text(
                        '此记',
                        style: TextStyle(
                          fontFamily: 'WenKai',
                          fontSize: 12.5,
                          letterSpacing: 1,
                          color: c.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'ThisNote',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9,
                          letterSpacing: 0.6,
                          color: c.inkMuted,
                        ),
                      ),
                      if (state.current != null) ...[
                        const SizedBox(width: 14),
                        Container(width: 1, height: 12, color: c.line),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: Motion.fast,
                            child: Text(
                              state.current!.title.trim().isEmpty
                                  ? '无题'
                                  : state.current!.title.trim(),
                              key: ValueKey(state.current!.id),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 10.5,
                                color: c.inkMuted,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          _CaptionButton(
            icon: _maximized ? LucideIcons.minimize : LucideIcons.maximize,
            tooltip: _maximized ? '还原' : '最大化',
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _CaptionButton(
            icon: LucideIcons.minus,
            tooltip: '最小化',
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            icon: LucideIcons.x,
            tooltip: '关闭',
            close: true,
            onTap: () => windowManager.close(),
          ),
          const SizedBox(width: 6),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.close = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool close;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered, t) {
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              width: 44,
              height: 30,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: close && hovered
                    ? const Color(0xFFC24A3A)
                    : hovered
                        ? c.surfaceAlt
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                icon,
                size: 14,
                color: close && hovered ? Colors.white : c.inkSoft,
              ),
            ),
          );
        },
      ),
    );
  }
}
