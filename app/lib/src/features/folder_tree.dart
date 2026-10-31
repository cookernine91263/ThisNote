import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';

/// 打开文件夹菜单。优先贴着 [anchor]（文件夹行）展开，
/// 右键时用 [at] 贴着指针展开；两者都给定时以指针为准。
typedef FolderMenuOpener = Future<void> Function(
  Folder folder, {
  BuildContext? anchor,
  Offset? at,
});

class FolderTree extends StatefulWidget {
  const FolderTree({required this.state, super.key});
  final AppState state;

  @override
  State<FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<FolderTree> {
  static const double _menuWidth = 156;

  bool _open = true;

  Future<void> _create(String? parentId) async {
    final name = await _askName(
      context,
      _t(parentId == null ? '新建文件夹' : '新建子文件夹'),
    );
    if (name != null && name.trim().isNotEmpty) {
      await widget.state.createFolder(name, parentId: parentId);
      if (mounted) setState(() => _open = true);
    }
  }

  Future<String?> _askName(BuildContext context, String title) async {
    final c = AppPalette.of(context);
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          title,
          style: TextStyle(
            fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
            fontSize: 21,
            color: c.ink,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 13,
            color: c.ink,
          ),
          decoration: InputDecoration(
            hintText: _t('例如：日记 / 小说 / 读书'),
            hintStyle: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 12,
              color: c.inkMuted,
            ),
            filled: true,
            fillColor: c.paper,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(_t('取消'), style: TextStyle(color: c.inkMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.ink,
              foregroundColor: c.paper,
            ),
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(_t('建好')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// 菜单出现在文件夹行下面，右边缘和行对齐。
  /// 以前这里写死了 `RelativeRect.fromLTRB(80, 160, 0, 0)`：left 比 right 大，
  /// Flutter 会按 right 对齐，结果菜单被钉在窗口右缘、y 永远是 160，
  /// 和点的是哪个文件夹毫无关系。
  Future<void> _menu(
    Folder folder, {
    BuildContext? anchor,
    Offset? at,
  }) async {
    final c = AppPalette.of(context);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final size = overlay.size;
    final RelativeRect position;
    if (at != null) {
      position = _atPoint(at, size);
    } else if (anchor != null) {
      final box = anchor.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        position = _atPoint(const Offset(96, 160), size);
      } else {
        final edge = box.localToGlobal(
          box.size.bottomRight(Offset.zero),
          ancestor: overlay,
        );
        final maxLeft = math.max(8.0, size.width - _menuWidth - 8);
        final left = math.min(math.max(edge.dx - _menuWidth, 8.0), maxLeft);
        position = RelativeRect.fromLTRB(
          left,
          math.min(edge.dy + 4, size.height - 8),
          math.max(0.0, size.width - left - _menuWidth),
          0,
        );
      }
    } else {
      position = _atPoint(const Offset(96, 160), size);
    }

    final action = await showMenu<String>(
      context: context,
      color: c.surface,
      position: position,
      constraints: const BoxConstraints.tightFor(width: _menuWidth),
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      items: [
        PopupMenuItem(
          value: 'new',
          height: 40,
          child: Text(_t('新建子文件夹')),
        ),
        PopupMenuItem(
          value: 'rename',
          height: 40,
          child: Text(_t('重命名')),
        ),
        PopupMenuItem(
          value: 'delete',
          height: 40,
          child: Text(
            _t('删除文件夹'),
            style: TextStyle(color: c.danger),
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'new':
        await _create(folder.id);
        break;
      case 'rename':
        final name = await _askName(context, _t('重命名'));
        if (name != null && name.trim().isNotEmpty) {
          await widget.state.renameFolder(folder.id, name);
        }
        break;
      case 'delete':
        final ok = await showConfirm(
          context,
          title: _t('删除这个文件夹？'),
          message: _t('里面的笔记会移到上一层，不会被删除。'),
          confirmLabel: _t('删除'),
          danger: true,
        );
        if (ok) await widget.state.deleteFolder(folder.id);
        break;
    }
  }

  /// 右键时贴着指针展开；靠右时会自动翻到指针左侧。
  RelativeRect _atPoint(Offset point, Size overlay) => RelativeRect.fromLTRB(
    point.dx,
    point.dy,
    math.max(0.0, overlay.width - point.dx),
    math.max(0.0, overlay.height - point.dy),
  );

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = widget.state;
    final roots = state.rootFolders();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 14, 5),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: Row(
                  children: [
                    Icon(
                      _open
                          ? LucideIcons.chevronDown
                          : LucideIcons.chevronRight,
                      size: 12,
                      color: c.inkMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _t('文件夹'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        letterSpacing: 1,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SoftIconButton(
                icon: LucideIcons.folderPlus,
                tooltip: _t('新建文件夹'),
                size: 26,
                onPressed: () => _create(null),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: !_open
              ? const SizedBox(width: double.infinity)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 12, 4),
                      child: Row(
                        children: [
                          _RootChip(
                            label: _t('全部'),
                            selected: state.folderFilter == null,
                            onTap: () => state.setFolderFilter(null),
                            onDropNote: (id) =>
                                state.moveNoteToFolder(id, null),
                          ),
                          const SizedBox(width: 5),
                          _RootChip(
                            label: _t('未分类'),
                            selected: state.folderFilter == '__unfiled__',
                            onTap: () =>
                                state.setFolderFilter('__unfiled__'),
                            onDropNote: (id) =>
                                state.moveNoteToFolder(id, null),
                          ),
                        ],
                      ),
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 230),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final folder in roots)
                              _FolderNode(
                                folder: folder,
                                depth: 0,
                                state: state,
                                onMenu: _menu,
                                onSelect: (id) => state.setFolderFilter(id),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RootChip extends StatelessWidget {
  const _RootChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.onDropNote,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<String>? onDropNote;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.startsWith('note:') && onDropNote != null,
      onAcceptWithDetails: (details) {
        if (details.data.startsWith('note:')) {
          onDropNote?.call(details.data.substring(5));
        }
      },
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: hot
                  ? c.accentSoft
                  : selected
                      ? c.accentSoft
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: hot
                    ? c.accent.withValues(alpha: 0.55)
                    : selected
                        ? c.accent.withValues(alpha: 0.3)
                        : c.line,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 8.5,
                color: selected || hot ? c.accent : c.inkMuted,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FolderNode extends StatelessWidget {
  const _FolderNode({
    required this.folder,
    required this.depth,
    required this.state,
    required this.onMenu,
    required this.onSelect,
  });

  final Folder folder;
  final int depth;
  final AppState state;
  final FolderMenuOpener onMenu;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final children = state.childFolders(folder.id);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _FolderRow(
          key: ValueKey('folder-${folder.id}'),
          folder: folder,
          depth: depth,
          state: state,
          selected: state.folderFilter == folder.id,
          onMenu: onMenu,
          onSelect: onSelect,
        ),
        for (final child in children)
          _FolderNode(
            folder: child,
            depth: depth + 1,
            state: state,
            onMenu: onMenu,
            onSelect: onSelect,
          ),
      ],
    );
  }
}

/// 一行文件夹。
///
/// 拖拽目标只盖住这一行（不是整棵子树），因此父文件夹的放入区域
/// 不会和子文件夹抢指针；上面 30% / 下面 30% 是「插到前面/后面」，
/// 中间 40% 是「放进文件夹」，拖的时候会画出对应的预览。
class _FolderRow extends StatefulWidget {
  const _FolderRow({
    required this.folder,
    required this.depth,
    required this.state,
    required this.selected,
    required this.onMenu,
    required this.onSelect,
    super.key,
  });

  final Folder folder;
  final int depth;
  final AppState state;
  final bool selected;
  final FolderMenuOpener onMenu;
  final ValueChanged<String> onSelect;

  @override
  State<_FolderRow> createState() => _FolderRowState();
}

class _FolderRowState extends State<_FolderRow> {
  final GlobalKey _rowKey = GlobalKey();

  /// 拖到这一行时的预览：before / inside / after。
  String? _zone;
  bool _noteDrag = false;
  bool _hovered = false;
  bool _menuOpen = false;

  String get _id => widget.folder.id;

  bool get _desktop => const {
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  }.contains(Theme.of(context).platform);

  bool _accepts(String data) {
    if (data.startsWith('note:')) return true;
    if (!data.startsWith('folder:')) return false;
    final sourceId = data.substring(7);
    if (sourceId == _id) return false;
    // 不能把文件夹拖进自己的子树：那会形成环。
    return !widget.state.folderTreeIds(sourceId).contains(_id);
  }

  void _onMove(DragTargetDetails<String> details) {
    if (!_accepts(details.data)) return;
    final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final isNote = details.data.startsWith('note:');
    String zone;
    if (isNote) {
      // 笔记只有一个去处：放进这个文件夹。
      zone = 'inside';
    } else {
      final y = box.globalToLocal(details.offset).dy / box.size.height;
      zone = y < 0.3
          ? 'before'
          : y > 0.7
              ? 'after'
              : 'inside';
    }
    if (zone == _zone && isNote == _noteDrag) return;
    setState(() {
      _zone = zone;
      _noteDrag = isNote;
    });
  }

  void _clear() {
    if (_zone == null && !_noteDrag) return;
    setState(() {
      _zone = null;
      _noteDrag = false;
    });
  }

  Future<void> _accept(DragTargetDetails<String> details) async {
    final zone = _zone ?? 'inside';
    _clear();
    final data = details.data;
    if (data.startsWith('note:')) {
      await widget.state.moveNoteToFolder(data.substring(5), _id);
    } else if (data.startsWith('folder:')) {
      await widget.state.moveFolder(data.substring(7), _id, mode: zone);
    }
  }

  Future<void> _openMenu({Offset? at}) async {
    setState(() => _menuOpen = true);
    await widget.onMenu(widget.folder, anchor: _rowKey.currentContext, at: at);
    if (mounted) setState(() => _menuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final count = widget.state.folderCount(_id);
    final row = _row(c, count);

    final feedback = Material(
      color: Colors.transparent,
      child: _FolderGhost(folder: widget.folder, count: count),
    );
    final dragging = Opacity(opacity: 0.35, child: row);
    final draggable = _desktop
        ? Draggable<String>(
            data: 'folder:$_id',
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedbackOffset: const Offset(-14, -12),
            feedback: feedback,
            childWhenDragging: dragging,
            child: row,
          )
        : LongPressDraggable<String>(
            data: 'folder:$_id',
            delay: const Duration(milliseconds: 220),
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedbackOffset: const Offset(-14, -12),
            feedback: feedback,
            childWhenDragging: dragging,
            child: row,
          );

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: _onMove,
      onLeave: (_) => _clear(),
      onAcceptWithDetails: _accept,
      builder: (context, candidate, rejected) => draggable,
    );
  }

  Widget _row(AppPalette c, int count) {
    final selected = widget.selected;
    final inside = _zone == 'inside';
    final hot = _zone != null || _menuOpen;
    final bg = inside
        ? c.accentSoft
        : selected
            ? c.accentSoft.withValues(alpha: c.isDark ? 0.9 : 0.65)
            : _hovered
                ? c.surface
                : Colors.transparent;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onSelect(_id),
      onSecondaryTapUp: (details) => _openMenu(at: details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              key: _rowKey,
              duration: Motion.fast,
              margin: const EdgeInsets.fromLTRB(12, 1, 10, 1),
              padding: EdgeInsets.fromLTRB(8 + widget.depth * 13, 4, 4, 4),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: inside
                      ? c.accent.withValues(alpha: 0.55)
                      : hot
                          ? c.accent.withValues(alpha: 0.22)
                          : Colors.transparent,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected || inside
                        ? LucideIcons.folderOpen
                        : LucideIcons.folder,
                    size: 13,
                    color: selected || inside ? c.accent : c.inkMuted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        color: selected || inside ? c.accent : c.inkSoft,
                      ),
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 8,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  _moreButton(c, selected || _hovered || _menuOpen),
                ],
              ),
            ),
            if (_zone == 'before')
              Positioned(
                left: 20.0 + widget.depth * 13,
                right: 12,
                top: -1,
                child: const _InsertLine(),
              ),
            if (_zone == 'after')
              Positioned(
                left: 20.0 + widget.depth * 13,
                right: 12,
                bottom: -1,
                child: const _InsertLine(),
              ),
          ],
        ),
      ),
    );
  }

  /// 拖拽手柄换成「更多」按钮：长按整行已经能拖，这个位置留给菜单。
  Widget _moreButton(AppPalette c, bool active) {
    return Tooltip(
      message: _t('文件夹选项'),
      waitDuration: const Duration(milliseconds: 600),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _openMenu(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 24,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.surfaceAlt : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Icon(
              LucideIcons.ellipsis,
              size: 14,
              color: active ? c.ink : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _InsertLine extends StatelessWidget {
  const _InsertLine();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      height: 2,
      decoration: BoxDecoration(
        color: c.accent,
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.28),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
    );
  }
}

class _FolderGhost extends StatelessWidget {
  const _FolderGhost({required this.folder, required this.count});
  final Folder folder;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.folder, size: 13, color: c.accent),
          const SizedBox(width: 6),
          Text(
            folder.name,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 10,
              color: c.ink,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(fontSize: 8, color: c.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// 英文文案。键是界面里的中文原文，值是对应的英文。
const Map<String, String> _en = <String, String>{
  '新建文件夹': 'New folder',
  '新建子文件夹': 'New subfolder',
  '例如：日记 / 小说 / 读书': 'e.g. Diary / Novel / Reading',
  '取消': 'Cancel',
  '建好': 'Create',
  '重命名': 'Rename',
  '删除文件夹': 'Delete folder',
  '删除这个文件夹？': 'Delete this folder?',
  '里面的笔记会移到上一层，不会被删除。':
      'The notes inside move up a level; nothing gets deleted.',
  '删除': 'Delete',
  '文件夹': 'Folder',
  '文件夹选项': 'Folder options',
  '全部': 'All',
  '未分类': 'Unfiled',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);
