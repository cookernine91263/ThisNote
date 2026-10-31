import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../core/i18n.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/theme_reveal.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import '../services/clipboard_image.dart';
import '../services/file_drop.dart';
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

class _AppShellState extends State<AppShell>
    with WindowListener, WidgetsBindingObserver {
  bool _zen = false;
  bool _zenResetScheduled = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) windowManager.addListener(this);
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    FileDropTarget.install(
      state: context.read<AppState>(),
      onMessage: (message) {
        if (mounted) {
          showToast(context, message, icon: LucideIcons.check);
        }
      },
    );
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) windowManager.removeListener(this);
    FileDropTarget.uninstall();
    super.dispose();
  }

  /// 切后台、失焦前把没落盘的字写下去。手机上被系统回收时，
  /// 900ms 的自动保存防抖很可能还没跑完。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      context.read<AppState>().saveNow();
    }
  }

  /// 关窗先落盘再销毁，避免最后一句随窗口一起消失。
  @override
  Future<void> onWindowClose() async {
    if (!mounted) return;
    try {
      await context.read<AppState>().closeApp();
    } finally {
      await windowManager.destroy();
    }
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // 专注模式里按 Esc 直接退出。弹窗在场时让弹窗先处理 Esc。
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _zen &&
        !Navigator.of(context, rootNavigator: true).canPop()) {
      _toggleZen();
      return true;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed && !keyboard.isMetaPressed) return false;
    // 有弹窗/面板在场时不抢键：否则在标签、链接或 AI 面板里按 Ctrl+N，
    // 会在背后新建笔记并释放当前编辑会话。
    if (Navigator.of(context, rootNavigator: true).canPop()) return false;
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
    final session = state.session;
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        !keyboard.isShiftPressed) {
      // 剪贴板里只有图片时，Ctrl+V 直接贴图；有文字仍走普通粘贴。
      // 部分输入法会在引擎层拦下 Ctrl+V，这时用工具栏的「粘贴图片」。
      if (session != null &&
          session.editorFocus.hasFocus &&
          ClipboardImage.imageOnly) {
        session.pasteImageFromClipboard();
        return true;
      }
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF &&
        !keyboard.isShiftPressed) {
      if (session == null) return false;
      session.openFind();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyH) {
      if (session == null) return false;
      session.openFind(withReplace: true);
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyV &&
        keyboard.isShiftPressed) {
      // 只贴纯文本，去掉网页带来的字体和颜色。
      if (session == null || !session.editorFocus.hasFocus) return false;
      session.pastePlainText();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyF && keyboard.isShiftPressed) {
      _toggleZen();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.comma) {
      _goToView('settings');
      return true;
    }
    return false;
  }

  @override
  void onWindowMaximize() => setState(() {});
  @override
  void onWindowUnmaximize() => setState(() {});

  /// 只有编辑器这几类视图才谈得上「专注」。
  /// 日历、统计、设置都是整页面板，专注模式把它们藏起来只会把导航栏一起藏掉。
  bool _isWritingView(String view) =>
      !const ['calendar', 'stats', 'settings'].contains(view);

  /// 切换视图时同步退出专注，避免从设置/日历进入后再无入口返回。
  void _goToView(String view) {
    if (_zen && !_isWritingView(view)) {
      setState(() => _zen = false);
    }
    context.read<AppState>().setView(view);
  }

  void _toggleZen() {
    final state = context.read<AppState>();
    if (state.current == null) return;
    // 在设置/日历/统计页点「专注」时，先回到当前笔记，再进入专注，
    // 否则侧栏会被隐藏，而眼前仍是设置页，退不出去。
    if (!_isWritingView(state.view)) {
      state.setView('all');
    }
    setState(() => _zen = !_zen);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 900;
    final zen = _zen &&
        state.current != null &&
        _isWritingView(state.view);
    // 已经离开编辑器（比如从专注模式里按 Ctrl+,）时，把残留的专注状态收回去。
    if (_zen && !zen && !_zenResetScheduled) {
      _zenResetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _zenResetScheduled = false;
        if (mounted && _zen) setState(() => _zen = false);
      });
    }

    if (mobile) return _MobileShell(state: state);

    final showList =
        const ['today', 'all', 'tags', 'trash', 'search'].contains(state.view);
    final main = _buildMain(state, zen);

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
                      onGo: _goToView,
                    ),
                  ),
                  _AnimatedWidth(
                    visible: !zen && showList,
                    width: 324,
                    child: const NoteListPanel(),
                  ),
                  Expanded(
                    child: ColoredBox(
                      color: AppPalette.of(context).paper,
                      child: ClipRect(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 280),
                          reverseDuration: const Duration(milliseconds: 220),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (current, previous) =>
                              current ?? const SizedBox.shrink(),
                          transitionBuilder: (child, animation) {
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
    final items = [
      (LucideIcons.sun, _t('今日')),
      (LucideIcons.calendarDays, _t('日历')),
      (LucideIcons.chartNoAxesColumn, _t('统计')),
      (LucideIcons.settings, _t('我的')),
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
  });
  final bool visible;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: AnimatedContainer(
        duration: Motion.base,
        curve: Motion.spring,
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
    required this.onGo,
  });

  final bool zen;
  final VoidCallback onPalette;
  final VoidCallback onToggleZen;
  final ValueChanged<String> onGo;

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
            message: _t('此记 · ThisNote'),
            child: const Seal(size: 32, radius: 9),
          ),
          const SizedBox(height: 20),
          _RailItem(
            icon: LucideIcons.sun,
            label: _t('今日'),
            active: active == 'today',
            onTap: () => onGo('today'),
          ),
          _RailItem(
            icon: LucideIcons.library,
            label: _t('全部'),
            active: active == 'all',
            onTap: () => onGo('all'),
          ),
          _RailItem(
            icon: LucideIcons.calendarDays,
            label: _t('日历'),
            active: active == 'calendar',
            onTap: () => onGo('calendar'),
          ),
          _RailItem(
            icon: LucideIcons.tag,
            label: _t('标签'),
            active: active == 'tags',
            onTap: () => onGo('tags'),
          ),
          _RailItem(
            icon: LucideIcons.chartNoAxesColumn,
            label: _t('统计'),
            active: active == 'stats',
            onTap: () => onGo('stats'),
          ),
          const Spacer(),
          _RailItem(
            icon: LucideIcons.command,
            label: _t('命令'),
            active: false,
            onTap: onPalette,
            tooltip: _t('命令面板 · Ctrl K'),
          ),
          _RailItem(
            key: const Key('rail-focus'),
            icon: LucideIcons.focus,
            label: _t('专注'),
            active: zen,
            onTap: onToggleZen,
            tooltip: _t('专注模式 · Ctrl Shift F'),
          ),
          _RailItem(
            icon: state.settings.themeMode == ThemeMode.dark
                ? LucideIcons.moon
                : state.settings.themeMode == ThemeMode.light
                    ? LucideIcons.sun
                    : LucideIcons.sunMoon,
            label: _t('外观'),
            active: false,
            onTap: () {},
            onTapPosition: (origin) {
              // 外观按钮只在浅色和深色之间来回；正在跟随系统时，
              // 按当下实际的亮暗取反，点一下就是“换个明暗”。
              final next = Theme.of(context).brightness == Brightness.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              ThemeReveal.reveal(
                context: context,
                globalOrigin: origin,
                apply: () => state.setThemeMode(next),
              );
            },
            tooltip: _t('切换外观'),
          ),
          _RailItem(
            icon: LucideIcons.trash2,
            label: _t('回收'),
            active: active == 'trash',
            onTap: () => onGo('trash'),
          ),
          _RailItem(
            key: const Key('rail-settings'),
            icon: LucideIcons.settings,
            label: _t('设置'),
            active: active == 'settings',
            onTap: () => onGo('settings'),
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
                        _t('此记'),
                        style: TextStyle(
                          fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                          fontSize: 12.5,
                          letterSpacing: I18n.isEn ? 0.4 : 1,
                          color: c.inkSoft,
                        ),
                      ),
                      if (!I18n.isEn) ...[
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
                      ],
                      if (state.current != null) ...[
                        const SizedBox(width: 14),
                        Container(width: 1, height: 12, color: c.line),
                        const SizedBox(width: 14),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: Motion.fast,
                            child: Text(
                              state.current!.title.trim().isEmpty
                                  ? _t('无题')
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
            tooltip: _t(_maximized ? '还原' : '最大化'),
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
            tooltip: _t('最小化'),
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            icon: LucideIcons.x,
            tooltip: _t('关闭'),
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

/// 英文文案。键是界面里的中文原文，值是对应的英文。
const Map<String, String> _en = <String, String>{
  // 侧边栏（76px，英文标签尽量不超过 8 个字符）
  '今日': 'Today',
  '全部': 'All',
  '日历': 'Calendar',
  '标签': 'Tags',
  '统计': 'Stats',
  '命令': 'Commands',
  '专注': 'Focus',
  '外观': 'Appearance',
  '回收': 'Trash',
  '设置': 'Settings',
  // 移动端底部导航
  '我的': 'Me',
  // 悬停提示
  '此记 · ThisNote': 'ThisNote',
  '命令面板 · Ctrl K': 'Command palette · Ctrl K',
  '专注模式 · Ctrl Shift F': 'Focus mode · Ctrl Shift F',
  '切换外观': 'Toggle appearance',
  // 标题栏
  '此记': 'ThisNote',
  '无题': 'Untitled',
  '还原': 'Restore',
  '最大化': 'Maximize',
  '最小化': 'Minimize',
  '关闭': 'Close',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);


