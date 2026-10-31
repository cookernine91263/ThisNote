import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';

class FolderTree extends StatefulWidget {
  const FolderTree({required this.state, super.key});
  final AppState state;

  @override
  State<FolderTree> createState() => _FolderTreeState();
}

class _FolderTreeState extends State<FolderTree> {
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

  Future<void> _menu(Folder folder) async {
    final c = AppPalette.of(context);
    final action = await showMenu<String>(
      context: context,
      color: c.surface,
      position: const RelativeRect.fromLTRB(80, 160, 0, 0),
      items: [
        PopupMenuItem(value: 'new', child: Text(_t('新建子文件夹'))),
        PopupMenuItem(value: 'rename', child: Text(_t('重命名'))),
        PopupMenuItem(value: 'delete', child: Text(_t('删除文件夹'))),
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
      builder: (context, candidate, rejected) => GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: selected ? c.accent.withValues(alpha: 0.3) : c.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 8.5,
            color: selected ? c.accent : c.inkMuted,
          ),
        ),
      ),
      ),
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
  final ValueChanged<Folder> onMenu;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final children = state.childFolders(folder.id);
    final count = state.folderCount(folder.id);
    final selected = state.folderFilter == folder.id;
    return Column(
      children: [
        DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            final data = details.data;
            return data.startsWith('note:') ||
                (data.startsWith('folder:') &&
                    data != 'folder:${folder.id}' &&
                    !state.folderTreeIds(folder.id).contains(data.substring(7)));
          },
          onAcceptWithDetails: (details) async {
            final data = details.data;
            if (data.startsWith('note:')) {
              await state.moveNoteToFolder(data.substring(5), folder.id);
            } else if (data.startsWith('folder:')) {
              final id = data.substring(7);
              final box = context.findRenderObject() as RenderBox?;
              final localY = box == null
                  ? 0.5
                  : box.globalToLocal(details.offset).dy / box.size.height;
              final mode = localY < 0.28
                  ? 'before'
                  : localY > 0.72
                      ? 'after'
                      : 'inside';
              await state.moveFolder(id, folder.id, mode: mode);
            }
          },
          builder: (context, candidate, rejected) {
            final hot = candidate.isNotEmpty;
            return LongPressDraggable<String>(
              data: 'folder:${folder.id}',
              feedback: Material(
                color: Colors.transparent,
                child: _FolderGhost(folder: folder, count: count),
              ),
              childWhenDragging: Opacity(
                opacity: 0.35,
                child: _folderRow(context, c, count, selected, hot),
              ),
              child: GestureDetector(
                onTap: () => onSelect(folder.id),
                onSecondaryTap: () => onMenu(folder),
                child: _folderRow(context, c, count, selected, hot),
              ),
            );
          },
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

  Widget _folderRow(
    BuildContext context,
    AppPalette c,
    int count,
    bool selected,
    bool hot,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      margin: const EdgeInsets.fromLTRB(12, 1, 10, 1),
      padding: EdgeInsets.fromLTRB(8 + depth * 13, 6, 8, 6),
      decoration: BoxDecoration(
        color: hot
            ? c.accentSoft
            : selected
                ? c.accentSoft.withValues(alpha: 0.65)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: hot ? c.accent.withValues(alpha: 0.45) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(
            selected ? LucideIcons.folderOpen : LucideIcons.folder,
            size: 13,
            color: selected ? c.accent : c.inkMuted,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
                color: selected ? c.accent : c.inkSoft,
              ),
            ),
          ),
          if (count > 0)
            Text(
              '$count',
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 8,
                color: c.inkMuted,
              ),
            ),
          const SizedBox(width: 3),
          Icon(LucideIcons.gripVertical, size: 11, color: c.inkMuted),
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
  '全部': 'All',
  '未分类': 'Unfiled',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);
