import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/icons.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/theme_reveal.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import 'editor/code_block.dart';
import 'export_sheet.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '命令面板': 'Command palette',
  '此记 · 命令面板': 'ThisNote · Command palette',
  '搜索命令、页面或动作…': 'Search commands, pages or actions…',
  '没有匹配的命令': 'No matching command',
  '选择': 'Select',
  '点击选择': 'Tap to select',
  '打开': 'Open',
  '关闭': 'Close',
  '无题': 'Untitled',
  '打开：{title}': 'Open: {title}',
  '{n} 字': '{n}',
  '笔记': 'Notes',
  '新建': 'New',
  '前往': 'Go to',
  '编辑': 'Edit',
  '操作': 'Actions',
  '格式': 'Format',
  '新建日记': 'New diary',
  '新建随笔': 'New note',
  '新建作文': 'New essay',
  '前往今日': 'Go to today',
  '全部笔记': 'All notes',
  '日历': 'Calendar',
  '标签': 'Tags',
  '回收站': 'Trash',
  '删除的文字会保留在这里': 'Deleted words stay here',
  '写作统计': 'Writing stats',
  '设置': 'Settings',
  '查找': 'Find',
  '目录': 'Outline',
  '整理排版': 'Tidy formatting',
  '导出当前笔记…': 'Export current note…',
  '加粗': 'Bold',
  '倾斜': 'Italic',
  '下划线': 'Underline',
  '标题 1': 'Heading 1',
  '标题 2': 'Heading 2',
  '无序列表': 'Bullet list',
  '有序列表': 'Numbered list',
  '引用': 'Quote',
  '代码块': 'Code block',
  '选择语言并高亮显示': 'Pick a language and highlight it',
  '外观：浅色': 'Appearance: Light',
  '外观：深色': 'Appearance: Dark',
  '外观：跟随系统': 'Appearance: System',
  '立即锁定': 'Lock now',
  '天气 · 心情 · 三件小事': 'Weather · Mood · Three small things',
  '一张空白纸': 'A blank sheet',
  '题目 · 开头 · 正文 · 结尾': 'Title · Opening · Body · Ending',
  '今天写下的文字': 'What you wrote today',
  '所有写下的日子': 'All the days you wrote',
  '按日期回看': 'Look back by date',
  '按主题整理': 'Organize by topic',
  '连续天数与热力图': 'Streak and heatmap',
  '外观 · 编辑器 · 数据': 'Appearance · Editor · Data',
  '当前笔记内查找与替换': 'Find and replace in this note',
  '按标题 1–3 生成大纲': 'Build an outline from headings 1–3',
  '中英空格 · 半角标点 · 省略号': 'CJK spacing · Half-width marks · Ellipses',
  'Word / PDF / 图片 / Markdown': 'Word / PDF / Image / Markdown',
  '需要先设置密码': 'Set a passcode first',
  '这段文字已经很整齐了': 'This text is already tidy',
  '已整理 {n} 段排版': 'Tidied {n}',
  '命令总得做点什么': 'A command has to do something',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

/// 数量在英文里要跟着单复数变，中文则把量词留在原文里：
/// 中文只返回数字，英文返回「3 paragraphs」这样的整体，所以 [_en] 里
/// 写成 `'已整理 {n} 段排版': 'Tidied {n}'` 就够了。
String _q(int n, String zhUnit, String enOne, [String? enMany]) =>
    I18n.isEn ? I18n.count(n, zhUnit, enOne, enMany) : '$n';

Future<void> showCommandPalette(BuildContext context) async {
  final host = context;
  // 主题类命令不在面板里当场执行：先等面板彻底退场，
  // 再由这里接手做圆孔揭示，截图里才不会有残留的面板。
  final request = await showGeneralDialog<_ThemeRequest>(
    context: context,
    barrierDismissible: true,
    barrierLabel: _t('命令面板'),
    barrierColor: Colors.black.withValues(alpha: 0.18),
    transitionDuration: Motion.base,
    pageBuilder: (context, _, _) => _CommandDialog(hostContext: host),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.spring);
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
  if (request == null || !context.mounted) return;
  // 已经是这个外观了：不演那段看不见的扩散，也不挡输入。
  if (context.read<AppState>().settings.themeMode == request.mode) return;
  await WidgetsBinding.instance.endOfFrame;
  if (!context.mounted) return;
  await ThemeReveal.reveal(
    context: context,
    globalOrigin: request.origin ?? _centerOf(context),
    apply: () => context.read<AppState>().setThemeMode(request.mode),
  );
}

/// 没有行坐标时的兜底：从当前这块区域中心扩散。
Offset _centerOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(box.size.center(Offset.zero));
  }
  return Offset.zero;
}

class _ThemeRequest {
  const _ThemeRequest(this.mode, this.origin);
  final ThemeMode mode;
  final Offset? origin;
}

class _CommandDialog extends StatefulWidget {
  const _CommandDialog({required this.hostContext});

  /// 面板退场后仍可用的宿主 context，用来做导出、提示这类动作。
  final BuildContext hostContext;

  @override
  State<_CommandDialog> createState() => _CommandDialogState();
}

class _CommandDialogState extends State<_CommandDialog> {
  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final ScrollController _scroll = ScrollController();
  int _selected = 0;

  List<_Command> _commands = [];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() => _selected = 0));
    _commands = _buildCommands(context.read<AppState>());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<_Command> _buildCommands(AppState state) {
    final session = state.session;
    final notes = state.activeNotes.take(40).toList();
    return [
      for (final note in notes)
        _Command(
          icon: kindIcon(note.kind),
          label: _t('打开：{title}', {
            'title': note.title.trim().isEmpty ? _t('无题') : note.title.trim(),
          }),
          group: _t('笔记'),
          hint: note.excerpt.isEmpty
              ? _t('{n} 字', {'n': _q(note.words, '字', 'word')})
              : note.excerpt,
          isNote: true,
          action: () => state.openNote(note.id),
        ),
      _Command(
        icon: LucideIcons.calendarHeart,
        label: _t('新建日记'),
        group: _t('新建'),
        hint: _t('天气 · 心情 · 三件小事'),
        shortcut: 'Ctrl N',
        action: () => state.createNote(kind: NoteKind.diary),
      ),
      _Command(
        icon: LucideIcons.penLine,
        label: _t('新建随笔'),
        group: _t('新建'),
        hint: _t('一张空白纸'),
        action: () => state.createNote(kind: NoteKind.note),
      ),
      _Command(
        icon: LucideIcons.feather,
        label: _t('新建作文'),
        group: _t('新建'),
        hint: _t('题目 · 开头 · 正文 · 结尾'),
        action: () => state.createNote(kind: NoteKind.essay),
      ),
      _Command(
        icon: LucideIcons.sun,
        label: _t('前往今日'),
        group: _t('前往'),
        hint: _t('今天写下的文字'),
        action: () => state.setView('today'),
      ),
      _Command(
        icon: LucideIcons.library,
        label: _t('全部笔记'),
        group: _t('前往'),
        hint: _t('所有写下的日子'),
        action: () => state.setView('all'),
      ),
      _Command(
        icon: LucideIcons.calendarDays,
        label: _t('日历'),
        group: _t('前往'),
        hint: _t('按日期回看'),
        action: () => state.setView('calendar'),
      ),
      _Command(
        icon: LucideIcons.tag,
        label: _t('标签'),
        group: _t('前往'),
        hint: _t('按主题整理'),
        action: () => state.setView('tags'),
      ),
      _Command(
        icon: LucideIcons.recycle,
        label: _t('回收站'),
        group: _t('前往'),
        hint: _t('删除的文字会保留在这里'),
        action: () => state.setView('trash'),
      ),
      _Command(
        icon: LucideIcons.chartNoAxesColumn,
        label: _t('写作统计'),
        group: _t('前往'),
        hint: _t('连续天数与热力图'),
        action: () => state.setView('stats'),
      ),
      _Command(
        icon: LucideIcons.settings,
        label: _t('设置'),
        group: _t('前往'),
        hint: _t('外观 · 编辑器 · 数据'),
        shortcut: 'Ctrl ,',
        action: () => state.setView('settings'),
      ),
      if (session != null) ...[
        _Command(
          icon: LucideIcons.search,
          label: _t('查找'),
          group: _t('编辑'),
          hint: _t('当前笔记内查找与替换'),
          shortcut: 'Ctrl F',
          action: session.openFind,
        ),
        _Command(
          icon: LucideIcons.listTree,
          label: _t('目录'),
          group: _t('编辑'),
          hint: _t('按标题 1–3 生成大纲'),
          action: session.toggleOutline,
        ),
        _Command(
          icon: LucideIcons.wandSparkles,
          label: _t('整理排版'),
          group: _t('编辑'),
          hint: _t('中英空格 · 半角标点 · 省略号'),
          action: () => _applyTypography(state),
        ),
        _Command(
          icon: LucideIcons.fileText,
          label: _t('导出当前笔记…'),
          group: _t('操作'),
          hint: _t('Word / PDF / 图片 / Markdown'),
          action: () => showExportSheet(widget.hostContext),
        ),
        _Command(
          icon: LucideIcons.bold,
          label: _t('加粗'),
          group: _t('格式'),
          shortcut: 'Ctrl B',
          action: () => _toggleFormat(session, Attribute.bold),
        ),
        _Command(
          icon: LucideIcons.italic,
          label: _t('倾斜'),
          group: _t('格式'),
          shortcut: 'Ctrl I',
          action: () => _toggleFormat(session, Attribute.italic),
        ),
        _Command(
          icon: LucideIcons.underline,
          label: _t('下划线'),
          group: _t('格式'),
          shortcut: 'Ctrl U',
          action: () => _toggleFormat(session, Attribute.underline),
        ),
        _Command(
          icon: LucideIcons.heading1,
          label: _t('标题 1'),
          group: _t('格式'),
          action: () => _setHeader(session, 1),
        ),
        _Command(
          icon: LucideIcons.heading2,
          label: _t('标题 2'),
          group: _t('格式'),
          action: () => _setHeader(session, 2),
        ),
        _Command(
          icon: LucideIcons.list,
          label: _t('无序列表'),
          group: _t('格式'),
          action: () => _toggleList(session, 'bullet'),
        ),
        _Command(
          icon: LucideIcons.listOrdered,
          label: _t('有序列表'),
          group: _t('格式'),
          action: () => _toggleList(session, 'ordered'),
        ),
        _Command(
          icon: LucideIcons.textQuote,
          label: _t('引用'),
          group: _t('格式'),
          action: () => _toggleFormat(session, Attribute.blockQuote),
        ),
        _Command(
          icon: LucideIcons.code,
          label: _t('代码块'),
          group: _t('格式'),
          hint: _t('选择语言并高亮显示'),
          action: () => showCodeBlockDialog(context, session.controller),
        ),
      ],
      _Command(
        icon: LucideIcons.sun,
        label: _t('外观：浅色'),
        group: _t('操作'),
        themeMode: ThemeMode.light,
      ),
      _Command(
        icon: LucideIcons.moon,
        label: _t('外观：深色'),
        group: _t('操作'),
        themeMode: ThemeMode.dark,
      ),
      _Command(
        icon: LucideIcons.sunMoon,
        label: _t('外观：跟随系统'),
        group: _t('操作'),
        themeMode: ThemeMode.system,
      ),
      _Command(
        icon: LucideIcons.lock,
        label: _t('立即锁定'),
        group: _t('操作'),
        hint: _t('需要先设置密码'),
        action: () {
          if (state.settings.lockEnabled) state.lock();
        },
      ),
    ];
  }

  void _toggleFormat(EditorSession session, Attribute attr) {
    final has = session.controller.getSelectionStyle().attributes.containsKey(attr.key);
    session.controller.formatSelection(
      has ? Attribute.clone(attr, null) : attr,
    );
    session.editorFocus.requestFocus();
  }

  void _setHeader(EditorSession session, int level) {
    session.controller.formatSelection(
      Attribute('header', AttributeScope.block, level),
    );
    session.editorFocus.requestFocus();
  }

  void _toggleList(EditorSession session, String kind) {
    final current = session.controller
        .getSelectionStyle()
        .attributes[Attribute.list.key]
        ?.value;
    session.controller.formatSelection(
      current == kind
          ? Attribute.clone(Attribute.ul, null)
          : Attribute('list', AttributeScope.block, kind),
    );
    session.editorFocus.requestFocus();
  }

  void _applyTypography(AppState state) {
    final count = state.session?.normalizeTypography() ?? 0;
    showToast(
      widget.hostContext,
      count == 0
          ? _t('这段文字已经很整齐了')
          : _t('已整理 {n} 段排版', {
              'n': _q(count, '段', 'paragraph', 'paragraphs'),
            }),
    );
  }
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final filtered = _filtered;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() => _selected = (filtered.isEmpty ? 0 : (_selected + 1) % filtered.length));
      _ensureVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() => _selected = (filtered.isEmpty ? 0 : (_selected - 1 + filtered.length) % filtered.length));
      _ensureVisible();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (filtered.isNotEmpty) _run(filtered[_selected.clamp(0, filtered.length - 1)]);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _ensureVisible() {
    final filtered = _filtered;
    if (filtered.isEmpty) return;
    final index = _selected.clamp(0, filtered.length - 1);
    final target = (index * 54).toDouble();
    if (_scroll.hasClients) {
      _scroll.animateTo(
        target.clamp(0, _scroll.position.maxScrollExtent),
        duration: Motion.fast,
        curve: Motion.enter,
      );
    }
  }

  List<_Command> get _filtered {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) {
      // 没输入时只露出最近几篇，别让笔记淹掉命令。
      var notes = 0;
      return _commands.where((command) {
        if (!command.isNote) return true;
        notes++;
        return notes <= 6;
      }).toList();
    }
    return _commands.where((c) {
      return c.label.toLowerCase().contains(q) ||
          c.group.toLowerCase().contains(q) ||
          (c.hint?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// 每行一个 key，用来取被选中那一行的位置——圆孔从那里扩散。
  final Map<_Command, GlobalKey> _rowKeys = {};

  Offset? _rowOrigin(_Command command) {
    final box = _rowKeys[command]?.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(box.size.center(Offset.zero));
    }
    return null;
  }

  void _run(_Command command) {
    final mode = command.themeMode;
    if (mode != null) {
      // 外观类命令交给 showCommandPalette：等面板退场后再做揭示。
      Navigator.of(context).pop(_ThemeRequest(mode, _rowOrigin(command)));
      return;
    }
    Navigator.of(context).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) => command.action?.call());
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final filtered = _filtered;
    final groups = <String, List<_Command>>{};
    for (final command in filtered) {
      groups.putIfAbsent(command.group, () => []).add(command);
    }
    var flatIndex = 0;
    final rows = <Widget>[];
    for (final entry in groups.entries) {
      rows.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 5),
        child: Text(
          entry.key,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 9.5,
            letterSpacing: 1.2,
            color: c.inkMuted,
          ),
        ),
      ));
      for (final command in entry.value) {
        final index = flatIndex++;
        rows.add(_CommandRow(
          key: _rowKeys.putIfAbsent(command, () => GlobalKey()),
          command: command,
          selected: index == _selected,
          onTap: () => _run(command),
          onHover: () {
            if (_selected != index) setState(() => _selected = index);
          },
        ));
      }
    }
    final mobile = MediaQuery.sizeOf(context).width < 900;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.only(
        left: mobile ? 12 : 24,
        right: mobile ? 12 : 24,
        top: mobile ? 16 : MediaQuery.sizeOf(context).height * 0.14,
        bottom: mobile ? 12 : 24,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 580,
          maxHeight: mobile ? MediaQuery.sizeOf(context).height * 0.82 : 900,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: 0.2),
                blurRadius: 60,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 12, 8),
                child: Row(
                  children: [
                    Icon(LucideIcons.command, size: 17, color: c.inkMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focus,
                        autofocus: true,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 14.5,
                          color: c.ink,
                        ),
                        decoration: InputDecoration(
                          hintText: _t('搜索命令、页面或动作…'),
                          hintStyle: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 14.5,
                            color: c.inkMuted,
                          ),
                        ),
                      ),
                    ),
                    const Kbd('Esc'),
                    const SizedBox(width: 4),
                    SoftIconButton(
                      icon: LucideIcons.x,
                      size: 28,
                      tooltip: _t('关闭'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.line),
              if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 44),
                  child: Text(
                    _t('没有匹配的命令'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12,
                      color: c.inkMuted,
                    ),
                  ),
                )
              else
                Flexible(
                  child: Scrollbar(
                    controller: _scroll,
                    child: ListView(
                      controller: _scroll,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      children: rows,
                    ),
                  ),
                ),
              Divider(height: 1, color: c.line),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                child: Row(
                  children: [
                    if (mobile)
                      Text(
                        _t('点击选择'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      )
                    else ...[
                      const Kbd('↑'),
                      const SizedBox(width: 4),
                      const Kbd('↓'),
                      const SizedBox(width: 6),
                      Text(
                        _t('选择'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Kbd('Enter'),
                      const SizedBox(width: 6),
                      Text(
                        _t('打开'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      _t('此记 · 命令面板'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9,
                        color: c.inkMuted.withValues(alpha: 0.6),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Command {
  _Command({
    required this.icon,
    required this.label,
    required this.group,
    this.action,
    this.themeMode,
    this.hint,
    this.shortcut,
    this.isNote = false,
  }) : assert(action != null || themeMode != null, _t('命令总得做点什么'));

  final IconData icon;
  final String label;
  final String group;
  final String? hint;
  final String? shortcut;

  /// 是「打开某篇笔记」而不是普通命令；空搜索时只显示最近几篇。
  final bool isNote;

  /// 普通命令：面板关掉之后直接执行。
  final FutureOrValue? action;

  /// 外观命令：面板关掉之后再走圆孔揭示。
  final ThemeMode? themeMode;
}

typedef FutureOrValue = void Function();

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.selected,
    required this.onTap,
    required this.onHover,
    super.key,
  });

  final _Command command;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                command.icon,
                size: 16,
                color: selected ? c.accent : c.inkMuted,
              ),
              const SizedBox(width: 12),
              Text(
                command.label,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 12.5,
                  color: c.ink,
                ),
              ),
              if (command.hint != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    command.hint!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10,
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              if (command.shortcut != null) Kbd(command.shortcut!),
            ],
          ),
        ),
      ),
    );
  }
}
