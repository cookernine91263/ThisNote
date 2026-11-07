import 'dart:async';
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
import 'command_palette.dart';
import 'export_sheet.dart';
import 'new_note_sheet.dart';

class NoteListPanel extends StatefulWidget {
  const NoteListPanel({
    super.key,
    this.width = 324,
    this.embedded = false,
    this.onCollapse,
  });

  final double width;
  final bool embedded;
  final VoidCallback? onCollapse;

  @override
  State<NoteListPanel> createState() => _NoteListPanelState();
}

class _NoteListPanelState extends State<NoteListPanel> {
  bool _searching = false;
  bool _searchResetScheduled = false;
  bool _showAllTags = false;
  String? _removingId;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  final ScrollController _scrollCtrl = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  /// 拖拽时的实时预览：被拖的卡片先让位，目标位置留出一张卡的空隙。
  String? _dragId;
  bool _dragIsFolder = false;
  List<_DragEntry>? _dragEntries;
  Offset? _lastDragPoint;
  _DropPreview? _preview;
  String? _lastGeneration;
  final Map<String, GlobalKey> _cardKeys = {};

  Timer? _autoScrollTimer;
  double _autoScrollSpeed = 0;
  double _dragStartScroll = 0;
  Offset _dragGrabOffset = Offset.zero;

  bool _selecting = false;
  final Set<String> _selectedIds = {};
  final Set<String> _selectedFolderIds = {};
  final GlobalKey _dropOutKey = GlobalKey();

  List<({String id, bool folder, Rect rect})> _sweepCards = const [];
  int? _sweepAnchor;
  Offset? _sweepStart;
  bool _sweepMoved = false;

  @override
  void initState() {
    super.initState();
    // 手机端从「搜索结果 → 打开笔记 → 返回」时列表会重建。
    // 把搜索框和关键词一起恢复，避免结果仍被过滤、搜索框却消失。
    final state = context.read<AppState>();
    if (state.view == 'search' && state.query.isNotEmpty) {
      _searching = true;
      _searchCtrl.text = state.query;
    }
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 列表切视图时 AnimatedSwitcher 会让新旧两份列表同时存在一会儿，
  /// 卡片的 GlobalKey 必须按这一份列表的 key 分组，否则同一个笔记
  /// 会在新旧两棵树里各挂一个同名 GlobalKey。
  String _generation(AppState state) =>
      '${state.view}-${state.folderFilter}-${state.tagFilter}';

  GlobalKey _keyFor(String generation, String id, {bool folder = false}) =>
      _cardKeys.putIfAbsent(
        '$generation::${folder ? 'f' : 'n'}::$id',
        () => GlobalKey(),
      );

  Rect? _rectOf(String generation, String id, {bool folder = false}) {
    final box = _cardKeys['$generation::${folder ? 'f' : 'n'}::$id']
        ?.currentContext
        ?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _beginDrag(String id, bool isFolder, Offset downPosition) {
    final state = context.read<AppState>();
    final entries = state.listEntries;
    Object? source;
    for (final entry in entries) {
      final entryId = entry is Folder ? entry.id : (entry as NoteMeta).id;
      if (entryId == id) {
        source = entry;
        break;
      }
    }
    if (source == null) return;
    // 固定卡片自己不参与拖动，但其它卡片仍然可以自由跨过它排序。
    if (source is NoteMeta && source.fixed) return;
    if (source is Folder && source.fixed) return;
    final generation = _generation(state);
    final sourceRect = _rectOf(generation, id, folder: isFolder);
    _dragGrabOffset = sourceRect == null
        ? Offset.zero
        : downPosition - sourceRect.topLeft;
    final sourcePinned = source is NoteMeta && source.pinned;
    final candidates = <Object>[];
    for (final entry in entries) {
      final entryId = entry is Folder ? entry.id : (entry as NoteMeta).id;
      if (entryId == id) continue;
      if (entry is NoteMeta) {
        if (entry.isTrashed) continue;
        // 置顶与普通笔记的界线不能跨；文件夹卡片不参与这条界线。
        if (entry.pinned != sourcePinned) continue;
      }
      candidates.add(entry);
    }
    setState(() {
      _dragId = id;
      _dragIsFolder = isFolder;
      _dragEntries = null;
      _lastDragPoint = null;
      _preview = null;
    });
    _dragStartScroll = _scrollCtrl.hasClients ? _scrollCtrl.offset : 0;
    if (state.view == 'all') {
      state.prepareUnifiedOrder();
    } else {
      state.prepareManualOrder();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragId != id) return;
      final rects = <_DragEntry>[];
      for (final entry in candidates) {
        final folder = entry is Folder;
        final entryId = folder ? entry.id : (entry as NoteMeta).id;
        final rect = _rectOf(generation, entryId, folder: folder);
        if (rect != null) {
          rects.add(
            _DragEntry(
              id: entryId,
              folder: folder,
              rect: rect.shift(Offset(0, _dragStartScroll - _currentScroll)),
            ),
          );
        }
      }
      setState(() => _dragEntries = rects);
      final point = _lastDragPoint;
      if (point != null) _previewAt(point);
    });
  }

  double get _currentScroll =>
      _scrollCtrl.hasClients ? _scrollCtrl.offset : _dragStartScroll;

  void _endDrag(String id, bool accepted) {
    if (_dragId != id) return;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollSpeed = 0;
    setState(() {
      _dragId = null;
      _dragIsFolder = false;
      _dragEntries = null;
      _lastDragPoint = null;
      _preview = null;
    });
  }

  void _setPreview(_DropPreview? next) {
    if (next == null && _preview == null) return;
    if (next != null &&
        next.beforeId == _preview?.beforeId &&
        next.afterId == _preview?.afterId &&
        next.insideFolderId == _preview?.insideFolderId &&
        next.targetIsFolder == _preview?.targetIsFolder) {
      return;
    }
    setState(() => _preview = next);
  }

  /// 指针在列表里移动时，按「第一张中心点在指针下方的卡片」决定空位插在哪。
  /// 文件夹卡片中间 40% 是「放进文件夹」，上下各 30% 是普通排序。
  void _previewAt(Offset global) {
    _lastDragPoint = global;
    if (_dragId == null) return;
    final strip = _dropOutKey.currentContext?.findRenderObject() as RenderBox?;
    if (strip != null && strip.hasSize) {
      final rect = strip.localToGlobal(Offset.zero) & strip.size;
      if (rect.contains(global)) {
        _setPreview(null);
        return;
      }
    }
    _updateAutoScroll(global);
    final entries = _dragEntries;
    if (entries == null) return;
    if (entries.isEmpty) {
      _setPreview(null);
      return;
    }
    final shift = _dragStartScroll - _currentScroll;
    final rects = [
      for (final entry in entries)
        _DragEntry(
          id: entry.id,
          folder: entry.folder,
          rect: entry.rect.shift(Offset(0, shift)),
        ),
    ]..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    final first = rects.first.rect;
    final last = rects.last.rect;
    // 指针拖到列表上方 / 下方时不要恢复原位：贴到首位 / 末位。
    if (global.dy < first.top) {
      _setPreview(
        _DropPreview(
          beforeId: rects.first.id,
          targetIsFolder: rects.first.folder,
        ),
      );
      return;
    }
    if (global.dy > last.bottom) {
      _setPreview(
        _DropPreview(
          afterId: rects.last.id,
          targetIsFolder: rects.last.folder,
        ),
      );
      return;
    }
    for (final entry in rects) {
      if (!entry.folder) continue;
      final rect = entry.rect;
      if (global.dx < rect.left - 10 || global.dx > rect.right + 10) continue;
      final y = (global.dy - rect.top) / math.max(1, rect.height);
      if (y >= 0.3 && y <= 0.7) {
        _setPreview(_DropPreview(insideFolderId: entry.id));
        return;
      }
    }
    for (final entry in rects) {
      if (global.dy < entry.rect.center.dy) {
        _setPreview(
          _DropPreview(
            beforeId: entry.id,
            targetIsFolder: entry.folder,
          ),
        );
        return;
      }
    }
    _setPreview(
      _DropPreview(
        afterId: rects.last.id,
        targetIsFolder: rects.last.folder,
      ),
    );
  }

  /// 拖到列表上下边缘时让列表跟着手指/指针滚动。
  void _updateAutoScroll(Offset global) {
    final box = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    const edge = 84.0;
    var speed = 0.0;
    if (global.dy < rect.top + edge) {
      speed = -((rect.top + edge - global.dy) / edge).clamp(0.0, 1.0) * 18;
    } else if (global.dy > rect.bottom - edge) {
      speed = ((global.dy - (rect.bottom - edge)) / edge).clamp(0.0, 1.0) * 18;
    }
    _autoScrollSpeed = speed;
    if (speed.abs() < 0.5) {
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
      return;
    }
    _autoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) {
        if (!mounted || _dragId == null || !_scrollCtrl.hasClients) {
          _autoScrollTimer?.cancel();
          _autoScrollTimer = null;
          return;
        }
        final position = _scrollCtrl.position;
        final target = (_scrollCtrl.offset + _autoScrollSpeed).clamp(
          0.0,
          position.maxScrollExtent,
        );
        if ((target - _scrollCtrl.offset).abs() < 0.5) return;
        _scrollCtrl.jumpTo(target);
        final point = _lastDragPoint;
        if (point != null) _previewAt(point);
        _measureMoreEntries();
      },
    );
  }

  /// 滚动后新进入视口的卡片还没进快照，补量一次，
  /// 顺便把它们的坐标换算回「开始拖动时」的坐标系。
  void _measureMoreEntries() {
    if (_dragId == null) return;
    final generation = _generation(context.read<AppState>());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragId == null) return;
      final existing = _dragEntries;
      if (existing == null) return;
      final known = {for (final entry in existing) entry.id};
      final state = context.read<AppState>();
      final shift = _dragStartScroll - _currentScroll;
      final additions = <_DragEntry>[];
      for (final entry in state.listEntries) {
        final folder = entry is Folder;
        final id = folder ? entry.id : (entry as NoteMeta).id;
        if (known.contains(id)) continue;
        final rect = _rectOf(generation, id, folder: folder);
        if (rect != null) {
          additions.add(
            _DragEntry(
              id: id,
              folder: folder,
              rect: rect.shift(Offset(0, shift)),
            ),
          );
        }
      }
      if (additions.isEmpty) return;
      setState(() {
        _dragEntries = [...existing, ...additions]
          ..sort((a, b) => a.rect.top.compareTo(b.rect.top));
      });
    });
  }

  Future<void> _commitDrop() async {
    final dragId = _dragId;
    final dragIsFolder = _dragIsFolder;
    final preview = _preview;
    if (dragId == null) return;
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    _autoScrollSpeed = 0;
    setState(() {
      _dragId = null;
      _dragIsFolder = false;
      _dragEntries = null;
      _lastDragPoint = null;
      _preview = null;
    });
    if (preview == null) {
      showToast(
        context,
        _t(
          dragIsFolder
              ? '把文件夹拖到另一张卡片的上方或下方才能调整顺序'
              : '把笔记拖到另一张卡片的上方或下方才能调整顺序',
        ),
        icon: LucideIcons.alertCircle,
      );
      return;
    }
    final state = context.read<AppState>();
    final inside = preview.insideFolderId;
    if (inside != null) {
      final folder = state.folderById(inside);
      if (dragIsFolder) {
        await state.moveFolder(dragId, inside, mode: 'inside');
      } else {
        await state.moveNoteToFolder(dragId, inside);
      }
      if (mounted && folder != null) {
        showToast(
          context,
          _t('已放入「{name}」', {'name': folder.name}),
          icon: LucideIcons.folderInput,
        );
      }
      return;
    }
    final target = preview.beforeId ?? preview.afterId;
    if (target == null) return;
    final after = preview.beforeId == null;
    final ok = state.view == 'all'
        ? await state.reorderListEntry(
            dragId,
            target,
            after: after,
            sourceIsFolder: dragIsFolder,
            targetIsFolder: preview.targetIsFolder,
          )
        : dragIsFolder
            ? false
            : await state.reorderNote(dragId, target, after: after);
    if (!ok && mounted) {
      showToast(
        context,
        _t('置顶的笔记和普通笔记之间不能调换顺序'),
        icon: LucideIcons.alertCircle,
      );
    }
  }

  /// 删除不弹确认框、不飞卡片：先让行快速收起来，再真正删除，
  /// 最后用「撤销」兜住误触。
  void _requestTrash(NoteMeta meta) {
    if (_removingId != null) return;
    setState(() => _removingId = meta.id);
  }

  Future<void> _finishTrash(NoteMeta meta) async {
    if (!mounted) return;
    final state = context.read<AppState>();
    setState(() => _removingId = null);
    await state.trashNote(meta.id);
    if (!mounted) return;
    showToast(
      context,
      _t('已移到回收站'),
      actionLabel: _t('撤销'),
      onAction: () => state.restoreNote(meta.id),
    );
  }

  void _toggleSearch() {
    if (_searching) {
      setState(() => _searching = false);
      _searchCtrl.clear();
      final state = context.read<AppState>();
      state.setQuery('');
      // 关掉搜索后回到进入搜索前的范围；旧的 _filterQuery 也在这里清掉。
      const scopes = {'today', 'all', 'time', 'favorites', 'tags', 'trash'};
      state.setView(
        scopes.contains(state.listView) ? state.listView : 'today',
      );
      return;
    }
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _searchFocus.requestFocus(),
    );
  }

  void _startSelecting({String? noteId, String? folderId}) {
    setState(() {
      _selecting = true;
      if (noteId != null) _selectedIds.add(noteId);
      if (folderId != null) _selectedFolderIds.add(folderId);
    });
  }

  void _exitSelecting() {
    setState(() {
      _selecting = false;
      _selectedIds.clear();
      _selectedFolderIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (!_selectedIds.add(id)) _selectedIds.remove(id);
    });
  }

  void _toggleSelectedFolder(String id) {
    setState(() {
      if (!_selectedFolderIds.add(id)) _selectedFolderIds.remove(id);
    });
  }

  List<NoteMeta> _selectedNotes(AppState state) => state.notes
      .where((n) => _selectedIds.contains(n.id) && !n.isTrashed)
      .toList();

  List<Folder> _selectedFolders(AppState state) => state.folders
      .where((f) => _selectedFolderIds.contains(f.id))
      .toList();

  void _selectAll(AppState state) {
    final notes = state.visibleNotes;
    final folders = state.levelFolders();
    setState(() {
      _selectedIds
        ..clear()
        ..addAll(notes.map((n) => n.id));
      _selectedFolderIds
        ..clear()
        ..addAll(folders.map((f) => f.id));
    });
  }

  /// 多选模式下按住拖动：滑过哪些卡片，就把它们连续选中。
  void _sweepDown(Offset global, List<Object> entries) {
    final generation = _generation(context.read<AppState>());
    final cards = <({String id, bool folder, Rect rect})>[];
    for (final entry in entries) {
      final String id;
      final bool folder;
      if (entry is Folder) {
        id = entry.id;
        folder = true;
      } else if (entry is NoteMeta) {
        id = entry.id;
        folder = false;
      } else {
        continue;
      }
      final rect = _rectOf(generation, id, folder: folder);
      if (rect != null) cards.add((id: id, folder: folder, rect: rect));
    }
    _sweepCards = cards
      ..sort((a, b) => a.rect.top.compareTo(b.rect.top));
    _sweepStart = global;
    _sweepAnchor = _sweepIndexAt(global.dy);
    _sweepMoved = false;
  }

  int? _sweepIndexAt(double y) {
    if (_sweepCards.isEmpty) return null;
    for (var i = 0; i < _sweepCards.length; i++) {
      final rect = _sweepCards[i].rect;
      if (y >= rect.top && y <= rect.bottom) return i;
    }
    var best = 0;
    var distance = double.infinity;
    for (var i = 0; i < _sweepCards.length; i++) {
      final d = (_sweepCards[i].rect.center.dy - y).abs();
      if (d < distance) {
        distance = d;
        best = i;
      }
    }
    return best;
  }

  void _sweepMove(Offset global) {
    final anchor = _sweepAnchor;
    if (anchor == null) return;
    final start = _sweepStart;
    if (!_sweepMoved &&
        start != null &&
        (global - start).distance < 8) {
      return;
    }
    _sweepMoved = true;
    final current = _sweepIndexAt(global.dy);
    if (current == null) return;
    final lo = math.min(anchor, current);
    final hi = math.max(anchor, current);
    final noteIds = <String>{};
    final folderIds = <String>{};
    for (var i = lo; i <= hi; i++) {
      final card = _sweepCards[i];
      (card.folder ? folderIds : noteIds).add(card.id);
    }
    final hasNew =
        noteIds.any((id) => !_selectedIds.contains(id)) ||
        folderIds.any((id) => !_selectedFolderIds.contains(id));
    if (!hasNew) return;
    setState(() {
      _selectedIds.addAll(noteIds);
      _selectedFolderIds.addAll(folderIds);
    });
  }

  void _endSweep() {
    _sweepAnchor = null;
    _sweepStart = null;
    _sweepMoved = false;
  }

  Future<void> _createFolder(String? parentId) async {
    final state = context.read<AppState>();
    final name = await _askFolderName(
      context,
      _t(parentId == null ? '新建文件夹' : '新建子文件夹'),
    );
    if (!mounted || name == null || name.trim().isEmpty) return;
    await state.createFolder(name, parentId: parentId);
    if (mounted) {
      showToast(context, _t('文件夹已建好'), icon: LucideIcons.folderPlus);
    }
  }

  Future<String?> _askFolderName(BuildContext context, String title) async {
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

  Future<void> _folderMenu(Folder folder, Offset at) async {
    final state = context.read<AppState>();
    final c = AppPalette.of(context);
    final desktop = const {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);
    final action = desktop
        ? await showMenu<String>(
            context: context,
            color: c.surface,
            position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
            items: [
              PopupMenuItem(
                value: 'pin',
                child: Text(_t(folder.pinned ? '取消置顶' : '置顶')),
              ),
              PopupMenuItem(
                value: 'fixed',
                child: Text(_t(folder.fixed ? '取消固定' : '固定')),
              ),
              PopupMenuItem(value: 'multi', child: Text(_t('多选'))),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'new',
                child: Text(_t('新建子文件夹')),
              ),
              PopupMenuItem(value: 'rename', child: Text(_t('重命名'))),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  _t('删除文件夹'),
                  style: TextStyle(color: c.danger),
                ),
              ),
            ],
          )
        : await showModalBottomSheet<String>(
            context: context,
            backgroundColor: c.surface,
            showDragHandle: true,
            builder: (context) => SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _MobileMenuRow(
                    icon: folder.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                    label: _t(folder.pinned ? '取消置顶' : '置顶'),
                    onTap: () => Navigator.of(context).pop('pin'),
                  ),
                  _MobileMenuRow(
                    icon: folder.fixed ? LucideIcons.lockOpen : LucideIcons.lock,
                    label: _t(folder.fixed ? '取消固定' : '固定'),
                    onTap: () => Navigator.of(context).pop('fixed'),
                  ),
                  _MobileMenuRow(
                    icon: LucideIcons.listChecks,
                    label: _t('多选'),
                    onTap: () => Navigator.of(context).pop('multi'),
                  ),
                  _MobileMenuRow(
                    icon: LucideIcons.folderPlus,
                    label: _t('新建子文件夹'),
                    onTap: () => Navigator.of(context).pop('new'),
                  ),
                  _MobileMenuRow(
                    icon: LucideIcons.penLine,
                    label: _t('重命名'),
                    onTap: () => Navigator.of(context).pop('rename'),
                  ),
                  _MobileMenuRow(
                    icon: LucideIcons.trash2,
                    label: _t('删除文件夹'),
                    onTap: () => Navigator.of(context).pop('delete'),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        await state.toggleFolderPin(folder);
        break;
      case 'fixed':
        await state.toggleFolderFixed(folder);
        break;
      case 'multi':
        _startSelecting(folderId: folder.id);
        break;
      case 'new':
        await _createFolder(folder.id);
        break;
      case 'rename':
        final name = await _askFolderName(context, _t('重命名'));
        if (name != null && name.trim().isNotEmpty) {
          await state.renameFolder(folder.id, name);
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
        if (ok) await state.deleteFolder(folder.id);
        break;
    }
  }

  Future<String?> _pickFolder(AppState state) async {
    final c = AppPalette.of(context);
    final rows = <Widget>[
      _MobileMenuRow(
        icon: LucideIcons.inbox,
        label: _t('未分类'),
        onTap: () => Navigator.of(context).pop('__none__'),
      ),
    ];
    void add(Folder folder, int depth) {
      rows.add(
        Padding(
          padding: EdgeInsets.only(left: depth * 14.0),
          child: _MobileMenuRow(
            icon: LucideIcons.folder,
            label: folder.name,
            onTap: () => Navigator.of(context).pop(folder.id),
          ),
        ),
      );
      for (final child in state.childFolders(folder.id)) {
        add(child, depth + 1);
      }
    }

    for (final folder in state.rootFolders()) {
      add(folder, 0);
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
                  child: Text(
                    _t('移到文件夹'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12,
                      color: c.inkMuted,
                    ),
                  ),
                ),
                ...rows,
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked == '__none__') return '';
    return picked;
  }

  Future<void> _moveNoteToFolder(NoteMeta meta) async {
    final state = context.read<AppState>();
    final picked = await _pickFolder(state);
    if (picked == null || !mounted) return;
    await state.moveNoteToFolder(meta.id, picked.isEmpty ? null : picked);
    if (mounted) {
      showToast(context, _t('已移动到文件夹'), icon: LucideIcons.folderInput);
    }
  }

  Future<void> _batchFavorite(AppState state) async {
    final notes = _selectedNotes(state);
    if (notes.isEmpty) return;
    final value = !notes.every((n) => n.favorite);
    await state.setFavoriteMany(notes.map((n) => n.id), value);
    if (mounted) {
      showToast(
        context,
        value ? _t('已收藏') : _t('已取消收藏'),
        icon: LucideIcons.heart,
      );
    }
  }

  Future<void> _batchPin(AppState state) async {
    final notes = _selectedNotes(state);
    final folders = _selectedFolders(state);
    if (notes.isEmpty && folders.isEmpty) return;
    final value = !(notes.every((n) => n.pinned) &&
        folders.every((f) => f.pinned));
    await state.setPinnedFor(
      notes.map((n) => n.id),
      folders.map((f) => f.id),
      value,
    );
    if (mounted) {
      showToast(
        context,
        value ? _t('已置顶') : _t('已取消置顶'),
        icon: LucideIcons.pin,
      );
    }
  }

  Future<void> _batchFix(AppState state) async {
    final notes = _selectedNotes(state);
    final folders = _selectedFolders(state);
    if (notes.isEmpty && folders.isEmpty) return;
    final value = !(notes.every((n) => n.fixed) &&
        folders.every((f) => f.fixed));
    await state.setFixedFor(
      notes.map((n) => n.id),
      folders.map((f) => f.id),
      value,
    );
    if (mounted) {
      showToast(
        context,
        value ? _t('已固定') : _t('已取消固定'),
        icon: LucideIcons.lock,
      );
    }
  }

  Future<void> _batchMove(AppState state) async {
    final notes = _selectedNotes(state);
    final folders = _selectedFolders(state);
    if (notes.isEmpty && folders.isEmpty) return;
    final picked = await _pickFolder(state);
    if (picked == null || !mounted) return;
    final target = picked.isEmpty ? null : picked;
    await state.moveNotesToFolder(notes.map((n) => n.id), target);
    if (folders.isNotEmpty) {
      await state.moveFoldersToFolder(folders.map((f) => f.id), target);
    }
    if (mounted) {
      _exitSelecting();
      showToast(context, _t('已移动到文件夹'), icon: LucideIcons.folderInput);
    }
  }

  Future<void> _batchTrash(AppState state) async {
    final notes = _selectedNotes(state);
    final folders = _selectedFolders(state);
    if (notes.isEmpty && folders.isEmpty) return;
    if (folders.isNotEmpty) {
      final ok = await showConfirm(
        context,
        title: _t('删除选中的文件夹？'),
        message: _t('文件夹本身会被删除，里面的笔记会移到上一层；选中的笔记会移到回收站。'),
        confirmLabel: _t('删除'),
        danger: true,
      );
      if (!ok || !mounted) return;
    }
    final ids = notes.map((n) => n.id).toList();
    final folderIds = folders.map((f) => f.id).toList();
    _exitSelecting();
    if (folderIds.isNotEmpty) await state.deleteFolders(folderIds);
    if (ids.isNotEmpty) await state.trashMany(ids);
    if (!mounted) return;
    showToast(
      context,
      folderIds.isEmpty ? _t('已移到回收站') : _t('已处理选中的项目'),
      actionLabel: folderIds.isEmpty ? _t('撤销') : null,
      onAction: folderIds.isEmpty
          ? () async {
              for (final id in ids) {
                await state.restoreNote(id);
              }
            }
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    context.select<AppState,
        (String, String?, String?, String, String, String?, int, int, int, String)>(
      (value) => (
        value.view,
        value.tagFilter,
        value.folderFilter,
        value.query,
        value.sort,
        value.current?.id,
        value.dataRevision,
        value.foldersRevision,
        value.selectedDay?.millisecondsSinceEpoch ?? 0,
        value.filterQuery,
      ),
    );
    final c = AppPalette.of(context);
    // 切到日历/设置等页面时 setView 会清掉关键词；此时把残留的搜索框
    // 一并收起，避免回来时看到一个有字、但列表并未过滤的搜索栏。
    if (_searching &&
        state.view != 'search' &&
        state.query.isEmpty &&
        _searchCtrl.text.isNotEmpty &&
        !_searchResetScheduled) {
      _searchResetScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _searchResetScheduled = false;
        if (!mounted) return;
        _searchCtrl.clear();
        if (_searching) setState(() => _searching = false);
      });
    }
    final folderName = state.folderFilter == '__unfiled__'
        ? _t('未分类')
        : state.folderById(state.folderFilter)?.name;
    final title = switch (state.view) {
      'today' => _t('今日'),
      'all' => folderName ?? _t('全部笔记'),
      'time' => _t('时间'),
      'tags' => state.tagFilter == null ? _t('标签') : '# ${state.tagFilter}',
      'favorites' => _t('收藏'),
      'trash' => _t('回收站'),
      'search' => _t('搜索'),
      'calendar' => _t('日历'),
      _ => _t('笔记'),
    };
    final subtitle = switch (state.view) {
      'today' => dateLabel(DateTime.now()),
      'time' => _t('按日期翻看写过的字'),
      'tags' => state.tagFilter == null
          ? _t('按标签整理你的文字')
          : _t('与这个标签有关的文字'),
      'favorites' => _t('写过又舍不得删的文字'),
      'trash' => _t('删除的文字会在这里保留'),
      'search' => _t('搜索标题、正文与标签'),
      'all' => state.folderFilter == null
          ? _t('所有写下的日子')
          : _t('文件夹里的文字'),
      _ => '',
    };
    final notes = state.visibleNotes;
    // 今日 / 全部 / 时间 / 标签 是同一个页面里的范围，标题样式也统一。
    final listScope = const {
      'today',
      'all',
      'time',
      'favorites',
      'tags',
    }.contains(state.view);
    final entries = _entries(state);
    final generation = _generation(state);
    if (_lastGeneration != generation) {
      _lastGeneration = generation;
      // 旧列表还在做退场动画时仍然握着旧的 GlobalKey，这里只是不再跟踪它们。
      _cardKeys.removeWhere((key, _) => !key.startsWith('$generation::'));
      if (_selecting) {
        _selecting = false;
        _selectedIds.clear();
        _selectedFolderIds.clear();
      }
    }
    final dragNote = _dragId == null || _dragIsFolder
        ? null
        : state.metaById(_dragId!);
    final dragFolder = _dragId != null && _dragIsFolder
        ? state.folderById(_dragId)
        : null;

    final Widget listBody = entries.isEmpty
        ? _empty(context, state)
        : Scrollbar(
            controller: _scrollCtrl,
            child: ListView.builder(
              key: _listKey,
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                widget.embedded ? 12 : 10,
                4,
                widget.embedded ? 12 : 10,
                24,
              ),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final item = entries[i];
                if (item is _GroupHeader) {
                  return Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      widget.embedded ? 18 : 14,
                      10,
                      7,
                    ),
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: widget.embedded ? 11 : 10,
                        letterSpacing: 1.2,
                        color: c.inkMuted,
                      ),
                    ),
                  );
                }
                if (item is Folder) {
                  return _folderRow(
                    context,
                    state,
                    item,
                    generation,
                    dragNote,
                    dragFolder,
                  );
                }
                return _noteRow(
                  context,
                  state,
                  item as NoteMeta,
                  generation,
                  dragNote,
                  dragFolder,
                );
              },
            ),
          );
    // 多选时按住往下/往上滑：滑过的卡片连续选中，不打断列表滚动。
    final Widget interactiveList = _selecting
        ? Listener(
            onPointerDown: (event) => _sweepDown(event.position, entries),
            onPointerMove: (event) => _sweepMove(event.position),
            onPointerUp: (_) => _endSweep(),
            onPointerCancel: (_) => _endSweep(),
            child: listBody,
          )
        : listBody;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            widget.embedded ? 6 : 18,
            10,
            8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selecting)
                _selectionHeader(c, state)
              else
                Row(
                  children: [
                    if (state.view == 'all' &&
                        state.folderFilter != null) ...[
                      SoftIconButton(
                        icon: LucideIcons.arrowLeft,
                        tooltip: _t('返回上一层'),
                        size: 28,
                        onPressed: () {
                          if (state.folderFilter == '__unfiled__') {
                            state.setFolderFilter(null);
                          } else {
                            final folder =
                                state.folderById(state.folderFilter);
                            state.setFolderFilter(folder?.parentId);
                          }
                        },
                      ),
                      const SizedBox(width: 2),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: listScope && !I18n.isEn
                                        ? 'WenKai'
                                        : 'NotoSansSC',
                                    fontSize: widget.embedded || listScope
                                        ? 22
                                        : 20,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: listScope ? 1 : -0.2,
                                    color: c.ink,
                                    height: 1.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (notes.isNotEmpty)
                                Text(
                                  '${notes.length}',
                                  style: TextStyle(
                                    fontFamily: 'NotoSansSC',
                                    fontSize: 11,
                                    color: c.inkMuted,
                                  ),
                                ),
                            ],
                          ),
                          if (subtitle.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'NotoSansSC',
                                  fontSize: widget.embedded ? 11 : 10.5,
                                  color: c.inkMuted,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (state.view == 'today')
                      SoftIconButton(
                        icon: LucideIcons.library,
                        tooltip: _t('全部笔记'),
                        size: 30,
                        onPressed: () => state.setView('all'),
                      ),
                    SoftIconButton(
                      icon: _searching ? LucideIcons.x : LucideIcons.search,
                      tooltip: _t('搜索'),
                      size: 30,
                      active: _searching,
                      onPressed: _toggleSearch,
                    ),
                    if (state.view == 'all') ...[
                      const SizedBox(width: 2),
                      SoftIconButton(
                        icon: LucideIcons.folderPlus,
                        tooltip: _t('新建文件夹'),
                        size: 30,
                        onPressed: () => _createFolder(
                          state.folderFilter == null ||
                                  state.folderFilter == '__unfiled__'
                              ? null
                              : state.folderFilter,
                        ),
                      ),
                    ],
                    const SizedBox(width: 2),
                    if (state.view != 'trash') ...[
                      SoftIconButton(
                        icon: LucideIcons.listChecks,
                        tooltip: _t('多选'),
                        size: 30,
                        onPressed: _startSelecting,
                      ),
                      const SizedBox(width: 2),
                    ],
                    SoftIconButton(
                      icon: LucideIcons.plus,
                      tooltip: _t('新建（Ctrl N）'),
                      size: 30,
                      onPressed: () => showNewNoteSheet(context),
                    ),
                    if (widget.embedded) ...[
                      const SizedBox(width: 2),
                      SoftIconButton(
                        icon: LucideIcons.ellipsisVertical,
                        tooltip: _t('更多'),
                        size: 30,
                        onPressed: () => _showMobileMenu(context, state),
                      ),
                    ],
                    if (widget.onCollapse != null) ...[
                      const SizedBox(width: 2),
                      SoftIconButton(
                        icon: LucideIcons.panelLeftClose,
                        tooltip: _t('收起笔记列表'),
                        size: 30,
                        onPressed: widget.onCollapse,
                      ),
                    ],
                  ],
                ),
              AnimatedSize(
                duration: Motion.base,
                curve: Motion.spring,
                alignment: Alignment.topCenter,
                child: _searching
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: c.line),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                LucideIcons.search,
                                size: 14,
                                color: c.inkMuted,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: TextField(
                                  controller: _searchCtrl,
                                  focusNode: _searchFocus,
                                  onChanged: (value) =>
                                      state.setQuery(value, debounce: true),
                                  style: TextStyle(
                                    fontFamily: 'NotoSansSC',
                                    fontSize: 12.5,
                                    color: c.ink,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _t('搜索所有文字…'),
                                    hintStyle: TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      fontSize: 12.5,
                                      color: c.inkMuted,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        if (!_searching) _scopeBar(context, state),
        if (state.view == 'tags' && state.allTags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                TagChip(
                  label: _t('全部'),
                  selected: state.tagFilter == null,
                  onTap: () => state.setView('tags'),
                ),
                for (final entry in state.tagCounts.entries.take(
                  _showAllTags ? state.tagCounts.length : 14,
                ))
                  TagChip(
                    label: entry.key,
                    count: entry.value,
                    selected: state.tagFilter == entry.key,
                    onTap: () => state.selectTag(entry.key),
                  ),
                if (state.tagCounts.length > 14)
                  TagChip(
                    label: _showAllTags
                        ? _t('收起')
                        : '+${state.tagCounts.length - 14}',
                    selected: false,
                    onTap: () => setState(() => _showAllTags = !_showAllTags),
                  ),
              ],
            ),
          ),
        if (!_searching && (state.view == 'all' || state.view == 'time'))
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in [
                    ('updated', _t('最近')),
                    ('created', _t('创建')),
                    ('title', _t('标题')),
                    ('words', _t('字数')),
                    ('manual', _t('手动')),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: GestureDetector(
                        onTap: () => state.setSort(s.$1),
                        child: AnimatedContainer(
                          duration: Motion.fast,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: state.sort == s.$1
                                ? c.ink
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.$2,
                            maxLines: 1,
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10.5,
                              color:
                                  state.sort == s.$1 ? c.paper : c.inkMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (state.view == 'all' &&
            _dragId != null &&
            state.folderFilter != null)
          _dropOutStrip(state),
        Expanded(
          child: AnimatedSwitcher(
            key: ValueKey(
              'list-${state.view}-${state.folderFilter}-${state.tagFilter}',
            ),
            duration: const Duration(milliseconds: 250),
            switchInCurve: Curves.easeOutCubic,
            layoutBuilder: (current, previous) {
              return ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [...previous, ?current],
                ),
              );
            },
            transitionBuilder: (child, animation) {
              final outgoing = animation.status == AnimationStatus.reverse;
              return SlideTransition(
                position:
                    Tween<Offset>(
                      begin: Offset(outgoing ? -0.085 : 0.085, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                child: child,
              );
            },
            child: KeyedSubtree(
              key: ValueKey(
                'list-inner-${state.view}-${state.folderFilter}-${state.tagFilter}',
              ),
              child: interactiveList,
            ),
          ),
        ),
        if (_selecting)
          Builder(
            builder: (context) {
              final selectedNotes = _selectedNotes(state);
              final selectedFolders = _selectedFolders(state);
              final total = selectedNotes.length + selectedFolders.length;
              return _SelectionBar(
                count: total,
                notesCount: selectedNotes.length,
                favorite: selectedNotes.isNotEmpty &&
                    selectedNotes.every((n) => n.favorite),
                pinned: total > 0 &&
                    selectedNotes.every((n) => n.pinned) &&
                    selectedFolders.every((f) => f.pinned),
                fixed: total > 0 &&
                    selectedNotes.every((n) => n.fixed) &&
                    selectedFolders.every((f) => f.fixed),
                onFavorite: () => _batchFavorite(state),
                onPin: () => _batchPin(state),
                onFix: () => _batchFix(state),
                onMove: () => _batchMove(state),
                onTrash: () => _batchTrash(state),
                onCancel: _exitSelecting,
              );
            },
          )
        else if (!widget.embedded)
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.line)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 9, 16, 11),
            child: Row(
              children: [
                Text(
                  I18n.count(
                    state.notes.where((e) => !e.isTrashed).length,
                    '篇',
                    'note',
                  ),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(width: 8),
                Dot(color: c.lineStrong),
                const SizedBox(width: 8),
                Text(
                  I18n.count(state.totalWords, '字', 'word'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.inkMuted,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => state.setView('stats'),
                  child: Text(
                    _t('看看坚持'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10,
                      color: c.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    // 返回键先收搜索框/多选，再交给系统退出应用。
    final scoped = PopScope(
      canPop: !_searching && !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selecting) {
          _exitSelecting();
        } else if (_searching) {
          _toggleSearch();
        }
      },
      child: content,
    );

    if (widget.embedded) return _withDropTarget(scoped);
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: _withDropTarget(scoped),
    );
  }

  /// 整个侧栏都是投放区：拖到列表上方/下方（甚至标题、底栏）时，
  /// 都能按垂直位置落到首位或末位，而不是一松手弹回原处。
  Widget _withDropTarget(Widget child) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data.startsWith('note:') ||
          details.data.startsWith('folder:'),
      onMove: (details) => _previewAt(details.offset + _dragGrabOffset),
      onAcceptWithDetails: (_) => _commitDrop(),
      builder: (context, candidate, rejected) => child,
    );
  }

  Widget _selectionHeader(AppPalette c, AppState state) {
    return Row(
      children: [
        const SizedBox(width: 4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _t('已选 {n} 项', {
                  'n': _selectedIds.length + _selectedFolderIds.length,
                }),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _t('点按卡片继续选择'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        SoftIconButton(
          icon: LucideIcons.checkCheck,
          tooltip: _t('全选'),
          size: 30,
          onPressed: () => _selectAll(state),
        ),
        const SizedBox(width: 2),
        SoftIconButton(
          icon: LucideIcons.x,
          tooltip: _t('取消'),
          size: 30,
          onPressed: _exitSelecting,
        ),
      ],
    );
  }

  List<Object> _entries(AppState state) {
    if (state.view == 'all') return state.listEntries;
    return _grouped(state, state.visibleNotes);
  }

  /// 在文件夹里拖动时出现的「移出到上一层」投放条。
  Widget _dropOutStrip(AppState state) {
    final current = state.folderById(state.folderFilter);
    if (state.folderFilter == '__unfiled__' || current == null) {
      return const SizedBox.shrink();
    }
    final parentId = current.parentId;
    final parentName = parentId == null
        ? _t('全部')
        : (state.folderById(parentId)?.name ?? _t('上一层'));
    final c = AppPalette.of(context);
    return Padding(
      key: _dropOutKey,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DragTarget<String>(
        onWillAcceptWithDetails: (details) =>
            details.data.startsWith('note:') ||
            details.data.startsWith('folder:'),
        onAcceptWithDetails: (details) async {
          final data = details.data;
          if (data.startsWith('note:')) {
            await state.moveNoteToFolder(data.substring(5), parentId);
          } else if (data.startsWith('folder:')) {
            await state.moveFoldersToFolder(
              [data.substring(7)],
              parentId,
            );
          }
          if (mounted) {
            showToast(
              context,
              _t('已移到「{name}」', {'name': parentName}),
              icon: LucideIcons.folderUp,
            );
          }
        },
        builder: (context, candidate, rejected) {
          final hot = candidate.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hot ? c.accentSoft : c.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: hot
                    ? c.accent.withValues(alpha: 0.6)
                    : c.lineStrong.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  LucideIcons.folderUp,
                  size: 14,
                  color: hot ? c.accent : c.inkMuted,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    hot
                        ? _t('松手移出到「{name}」', {'name': parentName})
                        : _t('拖到这里移出当前文件夹'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10.5,
                      color: hot ? c.accent : c.inkMuted,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _folderRow(
    BuildContext context,
    AppState state,
    Folder folder,
    String generation,
    NoteMeta? dragNote,
    Folder? dragFolder,
  ) {
    final id = folder.id;
    final gapBefore = _preview?.beforeId == id;
    final gapAfter = _preview?.afterId == id;
    final inside = _preview?.insideFolderId == id;
    final row = FolderCard(
      key: _keyFor(generation, id, folder: true),
      folder: folder,
      count: state.folderCount(id),
      words: state.folderWords(id),
      dropInside: inside,
      selecting: _selecting,
      checked: _selectedFolderIds.contains(id),
      dragDisabled: _selecting || folder.fixed,
      onToggleCheck: () => _toggleSelectedFolder(id),
      onOpen: () => state.setFolderFilter(id),
      onMenu: (position) => _folderMenu(folder, position),
      onDragStart: (folderId, down) => _beginDrag(folderId, true, down),
      onDragEnd: _endDrag,
    );
    if (!gapBefore && !gapAfter) return row;
    final slot = dragNote != null
        ? _NoteSlot(meta: dragNote, key: const ValueKey('drag-mirror'))
        : dragFolder != null
            ? _FolderSlot(folder: dragFolder, key: const ValueKey('drag-mirror'))
            : const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gapBefore) slot,
        row,
        if (gapAfter) slot,
      ],
    );
  }

  Widget _noteRow(
    BuildContext context,
    AppState state,
    NoteMeta note,
    String generation,
    NoteMeta? dragNote,
    Folder? dragFolder,
  ) {
    final removing = _removingId == note.id;
    final gapBefore = _preview?.beforeId == note.id;
    final gapAfter = _preview?.afterId == note.id;
    final dropTarget = gapBefore || gapAfter;
    final row = TweenAnimationBuilder<double>(
      key: ValueKey('row-${note.id}'),
      tween: Tween<double>(begin: 1, end: removing ? 0 : 1),
      duration: const Duration(milliseconds: 190),
      curve: Curves.easeInCubic,
      onEnd: removing ? () => _finishTrash(note) : null,
      builder: (context, t, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: Opacity(opacity: t, child: child),
        ),
      ),
      child: NoteCard(
        key: _keyFor(generation, note.id),
        meta: note,
        selected: state.current?.id == note.id,
        view: state.view,
        dropTarget: dropTarget,
        selecting: _selecting,
        checked: _selectedIds.contains(note.id),
        dragDisabled: _selecting || note.fixed,
        onToggleCheck: () => _toggleSelected(note.id),
        onStartSelect: () => _startSelecting(noteId: note.id),
        onMoveRequest: () => _moveNoteToFolder(note),
        onDragStart: (id, down) => _beginDrag(id, false, down),
        onDragEnd: _endDrag,
        onRequestTrash: _requestTrash,
      ),
    );
    if (!dropTarget) return row;
    final slot = dragNote != null
        ? _NoteSlot(meta: dragNote, key: const ValueKey('drag-mirror'))
        : dragFolder != null
            ? _FolderSlot(folder: dragFolder, key: const ValueKey('drag-mirror'))
            : const SizedBox.shrink();
    // 目标位置让出一张卡的空隙，空隙里放半透明的「影子卡」。
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (gapBefore) slot,
        row,
        if (gapAfter) slot,
      ],
    );
  }

  /// 今日 / 全部 / 时间 / 标签 现在共用一个列表页，这条切换条就是页面的范围开关。
  Widget _scopeBar(BuildContext context, AppState state) {
    final items = <({String view, String label, IconData icon})>[
      (view: 'today', label: _t('今日'), icon: LucideIcons.sun),
      (view: 'all', label: _t('全部'), icon: LucideIcons.library),
      (view: 'time', label: _t('时间'), icon: LucideIcons.clock),
      (view: 'favorites', label: _t('收藏'), icon: LucideIcons.heart),
      (view: 'tags', label: _t('标签'), icon: LucideIcons.tag),
      if (widget.embedded)
        (view: 'trash', label: _t('回收站'), icon: LucideIcons.recycle),
    ];
    if (!widget.embedded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 9),
        child: Row(
          children: [
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: _ScopePill(
                  label: item.label,
                  selected: state.view == item.view,
                  onTap: () => state.setView(item.view),
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final item in items)
            _ScopeChip(
              icon: item.icon,
              label: item.label,
              selected: state.view == item.view,
              onTap: () => state.setView(item.view),
            ),
        ],
      ),
    );
  }

  Future<void> _showMobileMenu(BuildContext context, AppState state) async {
    final c = AppPalette.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.78,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 6),
              child: Text(
                '${I18n.count(state.activeNotes.length, '篇', 'note')} · '
                '${I18n.count(state.totalWords, '字', 'word')}',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
            ),
            _MobileMenuRow(
              icon: LucideIcons.library,
              label: _t('全部笔记'),
              onTap: () => Navigator.of(context).pop('all'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.clock,
              label: _t('时间'),
              onTap: () => Navigator.of(context).pop('time'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.heart,
              label: _t('收藏'),
              onTap: () => Navigator.of(context).pop('favorites'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.tag,
              label: _t('标签'),
              onTap: () => Navigator.of(context).pop('tags'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.folderPlus,
              label: _t('新建文件夹'),
              onTap: () => Navigator.of(context).pop('folder'),
            ),
            if (state.view != 'trash')
              _MobileMenuRow(
                icon: LucideIcons.listChecks,
                label: _t('多选'),
                onTap: () => Navigator.of(context).pop('multi'),
              ),
            _MobileMenuRow(
              icon: LucideIcons.recycle,
              label: _t('回收站'),
              hint: state.trashedNotes.isEmpty
                  ? null
                  : '${state.trashedNotes.length}',
              onTap: () => Navigator.of(context).pop('trash'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.command,
              label: _t('命令面板'),
              hint: 'Ctrl K',
              onTap: () => Navigator.of(context).pop('palette'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.search,
              label: _t('搜索'),
              onTap: () => Navigator.of(context).pop('search'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.chartNoAxesColumn,
              label: _t('写作统计'),
              onTap: () => Navigator.of(context).pop('stats'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.settings,
              label: _t('设置'),
              onTap: () => Navigator.of(context).pop('settings'),
            ),
            _MobileMenuRow(
              icon: LucideIcons.plus,
              label: _t('新建笔记'),
              onTap: () => Navigator.of(context).pop('new'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
              child: Text(
                _t('长按卡片可拖动排序，拖到上下边缘会自动滚动'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9.5,
                  color: c.inkMuted,
                ),
              ),
            ),
              ],
            ),
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case 'all':
        state.setView('all');
        break;
      case 'time':
        state.setView('time');
        break;
      case 'tags':
        state.setView('tags');
        break;
      case 'trash':
        state.setView('trash');
        break;
      case 'folder':
        await _createFolder(null);
        break;
      case 'multi':
        _startSelecting();
        break;
      case 'palette':
        showCommandPalette(context);
        break;
      case 'search':
        if (!_searching) _toggleSearch();
        break;
      case 'stats':
        state.setView('stats');
        break;
      case 'settings':
        state.setView('settings');
        break;
      case 'new':
        showNewNoteSheet(context);
        break;
    }
  }

  Widget _empty(BuildContext context, AppState state) {
    final c = AppPalette.of(context);
    final text = switch (state.view) {
      'trash' => _t('回收站是空的'),
      'search' => _t('没有找到相关的文字'),
      'today' => _t('今天还是一张白纸'),
      'favorites' => _t('还没有收藏的文字'),
      'tags' => state.tagFilter == null ? _t('还没有标签') : _t('这个标签下还没有文字'),
      _ => _t('还没有笔记'),
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkEmpty(size: 110),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 12,
                color: c.inkMuted,
                height: 1.7,
              ),
            ),
            if (state.view != 'trash' && state.view != 'search') ...[
              const SizedBox(height: 16),
              SoftButton(
                label: _t('写一页'),
                icon: LucideIcons.penLine,
                dense: true,
                onPressed: () => showNewNoteSheet(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Object> _grouped(AppState state, List<NoteMeta> notes) {
    if (state.view != 'time' && state.view != 'calendar') {
      return notes;
    }
    final result = <Object>[];
    final today = dayKey(DateTime.now());
    final yest = dayKey(DateTime.now().subtract(const Duration(days: 1)));
    String current = '';
    for (final n in notes) {
      final key = n.day;
      final label = key == today
          ? _t('今天')
          : key == yest
          ? _t('昨天')
          : (DateTime.now().difference(parseDay(key)).inDays < 7)
          ? _t('本周')
          : _t('{y} 年 {m} 月', {
              'y': parseDay(key).year,
              'm': parseDay(key).month,
            });
      if (label != current) {
        current = label;
        result.add(_GroupHeader(label));
      }
      result.add(n);
    }
    return result;
  }
}

class _NoteCardContent extends StatelessWidget {
  const _NoteCardContent({
    required this.meta,
    this.selected = false,
    this.showMore = false,
    this.onMore,
    this.snippet,
    this.selecting = false,
    this.checked = false,
  });

  final NoteMeta meta;
  final bool selected;
  final bool showMore;
  final ValueChanged<Offset>? onMore;
  final String? snippet;
  final bool selecting;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < 900;
    final mood = MoodX.fromScore(meta.mood);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selecting)
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 7),
                child: Icon(
                  checked ? LucideIcons.circleCheck : LucideIcons.circle,
                  size: mobile ? 16 : 15,
                  color: checked ? c.accent : c.inkMuted,
                ),
              ),
            if (meta.pinned)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 5),
                child: Icon(
                  LucideIcons.pin,
                  size: mobile ? 12 : 11,
                  color: c.accent,
                ),
              ),
            if (meta.fixed && !meta.pinned)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 5),
                child: Icon(
                  LucideIcons.lock,
                  size: mobile ? 11 : 10,
                  color: c.accent,
                ),
              ),
            Expanded(
              child: Text(
                meta.title.trim().isEmpty ? _t('无题') : meta.title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: mobile ? 14.5 : 13.5,
                  fontWeight:
                      selected || checked ? FontWeight.w600 : FontWeight.w500,
                  color: c.ink,
                  height: 1.35,
                ),
              ),
            ),
            if (showMore && onMore != null && !selecting)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => onMore!(d.globalPosition),
                  child: SizedBox(
                    width: mobile ? 36 : 20,
                    height: mobile ? 30 : 18,
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Icon(
                        LucideIcons.ellipsis,
                        size: mobile ? 17 : 15,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: mobile ? 5 : 4),
        Text(
          snippet ??
              (meta.excerpt.isEmpty ? _t('还没有写下正文') : meta.excerpt),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: mobile ? 12.5 : 11.5,
            height: 1.6,
            color: meta.excerpt.isEmpty && snippet == null
                ? c.inkMuted
                : c.inkSoft,
          ),
        ),
        SizedBox(height: mobile ? 8 : 7),
        Row(
          children: [
            Icon(
              meta.fixed ? LucideIcons.lock : kindIcon(meta.kind),
              size: mobile ? 11 : 10,
              color: meta.fixed ? c.accent : c.inkMuted,
            ),
            const SizedBox(width: 4),
            Text(
              shortDate(meta.createdAt),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: mobile ? 10.5 : 9.5,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(width: 7),
            Dot(size: 2, color: c.lineStrong),
            const SizedBox(width: 7),
            Text(
              I18n.count(meta.words, '字', 'word'),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: mobile ? 10.5 : 9.5,
                color: c.inkMuted,
              ),
            ),
            if (mood != null) ...[
              const SizedBox(width: 7),
              Text(
                mood.emoji,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: mobile ? 11 : 10,
                  color: mood.color,
                ),
              ),
            ],
            const Spacer(),
            if (meta.favorite)
              Icon(
                LucideIcons.heart,
                size: mobile ? 11 : 10,
                color: c.accent,
              ),
            if (meta.tags.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  meta.tags.take(2).map((e) => '#$e').join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: mobile ? 10 : 9,
                    color: c.inkMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 跟着指针走的整张卡片：和原卡同宽、略微放大并倾斜 1.5°，
/// 像从列表里被「拿起来」，而不是飘着一枚小纸片。
class _NoteGhost extends StatefulWidget {
  const _NoteGhost({required this.meta, required this.width});
  final NoteMeta meta;
  final double width;

  @override
  State<_NoteGhost> createState() => _NoteGhostState();
}

class _NoteGhostState extends State<_NoteGhost>
    with TickerProviderStateMixin {
  late final AnimationController _wobble = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 620),
  )..forward();

  /// 拿稳之后还留一点点慢速晃动，像被手轻轻拿着。
  late final AnimationController _sway = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1900),
  )..repeat(reverse: true);

  late final Listenable _anim = Listenable.merge([_wobble, _sway]);

  @override
  void dispose() {
    _wobble.dispose();
    _sway.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        final t = _wobble.value;
        // 拿起时晃两下，振幅迅速衰减；然后交给很轻的持续晃动。
        final damp = (1 - t) * (1 - t);
        final idle = math.sin(_sway.value * math.pi * 2);
        final angle =
            math.sin(t * math.pi * 3.8) * 0.024 * damp + idle * 0.006;
        final sway = math.sin(t * math.pi * 2.6) * 2.6 * damp +
            math.sin(_sway.value * math.pi * 2 + 1.1) * 1.4;
        final scale = 1 + 0.06 * Curves.easeOutCubic.transform(t);
        return Transform.translate(
          offset: Offset(sway, 0),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: SizedBox(
        width: widget.width,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.accent.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: 0.24),
                blurRadius: 26,
                offset: const Offset(0, 13),
              ),
            ],
          ),
          child: _NoteCardContent(meta: widget.meta),
        ),
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
      width: 250,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.accent.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.24),
            blurRadius: 26,
            offset: const Offset(0, 13),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(LucideIcons.folder, size: 16, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              folder.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: c.ink,
              ),
            ),
          ),
          Text(
            _t('{n} 篇', {'n': count}),
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9.5,
              color: c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 插入位置的「影子卡」：列表在这里让出一张卡的空隙，
/// 空隙里留一张 45% 透明的同一张卡 —— 松手后它就落在这。
class _NoteSlot extends StatelessWidget {
  const _NoteSlot({required this.meta, super.key});
  final NoteMeta meta;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.45,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.accent.withValues(alpha: 0.35)),
              boxShadow: [
                BoxShadow(
                  color: c.shadow.withValues(alpha: 0.16),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _NoteCardContent(meta: meta),
          ),
        ),
      ),
    );
  }
}

class _FolderSlot extends StatelessWidget {
  const _FolderSlot({required this.folder, super.key});
  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.45,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.accent.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.folder, size: 14, color: c.accent),
                const SizedBox(width: 8),
                Text(
                  folder.name,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 13,
                    color: c.ink,
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

class _GroupHeader {
  const _GroupHeader(this.label);
  final String label;
}

class _DragEntry {
  const _DragEntry({
    required this.id,
    required this.folder,
    required this.rect,
  });
  final String id;
  final bool folder;
  final Rect rect;
}

/// 拖拽预览：空位插在哪张卡的前面 / 后面，或者放进哪个文件夹。
class _DropPreview {
  const _DropPreview({
    this.beforeId,
    this.afterId,
    this.targetIsFolder = false,
    this.insideFolderId,
  });
  final String? beforeId;
  final String? afterId;
  final bool targetIsFolder;
  final String? insideFolderId;
}

/// 文件夹卡片：和其它笔记卡片长在一起，但用文件夹图标和篇数区分。
/// 整张卡可以拖动；卡片中间是放进文件夹，上下边缘是普通排序。
class FolderCard extends StatefulWidget {
  const FolderCard({
    required this.folder,
    required this.count,
    required this.words,
    required this.onOpen,
    required this.onMenu,
    this.dropInside = false,
    this.selecting = false,
    this.checked = false,
    this.dragDisabled = false,
    this.onToggleCheck,
    this.onDragStart,
    this.onDragEnd,
    super.key,
  });

  final Folder folder;
  final int count;
  final int words;
  final bool dropInside;
  final bool selecting;
  final bool checked;
  final bool dragDisabled;
  final VoidCallback? onToggleCheck;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onMenu;
  final void Function(String id, Offset downPosition)? onDragStart;
  final void Function(String id, bool accepted)? onDragEnd;

  @override
  State<FolderCard> createState() => _FolderCardState();
}

class _FolderCardState extends State<FolderCard> {
  Offset _downPosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final desktop = const {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);
    final card = Padding(
      padding: EdgeInsets.only(bottom: wide ? 4 : 6),
      child: HoverBuilder(
        cursor: SystemMouseCursors.click,
        builder: (context, hovered, t) {
          final inside = widget.dropInside;
          return GestureDetector(
            onTap: widget.selecting ? widget.onToggleCheck : widget.onOpen,
            onSecondaryTapUp: (details) =>
                widget.onMenu(details.globalPosition),
            child: AnimatedContainer(
              duration: Motion.fast,
              curve: Motion.enter,
              padding: EdgeInsets.fromLTRB(
                wide ? 12 : 14,
                wide ? 11 : 12,
                wide ? 10 : 12,
                wide ? 10 : 12,
              ),
              decoration: BoxDecoration(
                color: inside
                    ? c.accentSoft
                    : widget.checked
                        ? c.accentSoft
                        : hovered
                            ? c.paper
                            : Colors.transparent,
                borderRadius: BorderRadius.circular(wide ? 10 : 12),
                border: Border.all(
                  color: inside
                      ? c.accent.withValues(alpha: 0.75)
                      : widget.checked
                          ? c.accent.withValues(alpha: 0.55)
                          : hovered
                              ? c.line
                              : Colors.transparent,
                  width: inside ? 1.4 : 1,
                ),
                boxShadow: inside
                    ? [
                        BoxShadow(
                          color: c.accent.withValues(alpha: 0.18),
                          blurRadius: 16,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.selecting)
                        Padding(
                          padding: const EdgeInsets.only(right: 7),
                          child: Icon(
                            widget.checked
                                ? LucideIcons.circleCheck
                                : LucideIcons.circle,
                            size: wide ? 15 : 16,
                            color: widget.checked ? c.accent : c.inkMuted,
                          ),
                        ),
                      if (widget.folder.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(
                            LucideIcons.pin,
                            size: wide ? 11 : 12,
                            color: c.accent,
                          ),
                        ),
                      if (widget.folder.fixed && !widget.folder.pinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 5),
                          child: Icon(
                            LucideIcons.lock,
                            size: wide ? 10 : 11,
                            color: c.accent,
                          ),
                        ),
                      Icon(
                        inside ? LucideIcons.folderOpen : LucideIcons.folder,
                        size: wide ? 14 : 16,
                        color: c.accent,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          widget.folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: wide ? 13.5 : 14.5,
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (inside)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            _t('松手放入'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 9.5,
                              color: c.accent,
                            ),
                          ),
                        ),
                      if (!widget.selecting)
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => widget.onMenu(d.globalPosition),
                            child: SizedBox(
                              width: wide ? 22 : 34,
                              height: wide ? 20 : 28,
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Icon(
                                  LucideIcons.ellipsis,
                                  size: wide ? 15 : 17,
                                  color: c.inkMuted,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: wide ? 4 : 5),
                  Text(
                    widget.count == 0
                        ? _t('空文件夹')
                        : _t('{n} 篇笔记', {'n': widget.count}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: wide ? 11.5 : 12.5,
                      height: 1.6,
                      color: widget.count == 0 ? c.inkMuted : c.inkSoft,
                    ),
                  ),
                  SizedBox(height: wide ? 7 : 8),
                  Row(
                    children: [
                      Icon(
                        LucideIcons.folderTree,
                        size: wide ? 10 : 11,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _t('文件夹'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: wide ? 9.5 : 10.5,
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 7),
                      Dot(size: 2, color: c.lineStrong),
                      const SizedBox(width: 7),
                      Text(
                        I18n.count(widget.words, '字', 'word'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: wide ? 9.5 : 10.5,
                          color: c.inkMuted,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        LucideIcons.chevronRight,
                        size: wide ? 12 : 14,
                        color: c.inkMuted,
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

    if (widget.onDragStart == null || widget.dragDisabled) return card;
    final listened = Listener(
      onPointerDown: (event) => _downPosition = event.position,
      child: card,
    );
    final feedback = Material(
      color: Colors.transparent,
      child: _FolderGhost(folder: widget.folder, count: widget.count),
    );
    if (desktop) {
      return Draggable<String>(
        data: 'folder:${widget.folder.id}',
        feedback: feedback,
        childWhenDragging: const SizedBox.shrink(),
        onDragStarted: () =>
            widget.onDragStart!(widget.folder.id, _downPosition),
        onDragEnd: (details) =>
            widget.onDragEnd?.call(widget.folder.id, details.wasAccepted),
        child: listened,
      );
    }
    return LongPressDraggable<String>(
      data: 'folder:${widget.folder.id}',
      delay: const Duration(milliseconds: 300),
      hapticFeedbackOnStart: true,
      feedback: feedback,
      childWhenDragging: const SizedBox.shrink(),
      onDragStarted: () =>
          widget.onDragStart!(widget.folder.id, _downPosition),
      onDragEnd: (details) =>
          widget.onDragEnd?.call(widget.folder.id, details.wasAccepted),
      child: listened,
    );
  }
}

/// 整张卡片就是拖拽源；按下即拖（触屏仍是长按），
/// 放下的判断交给整个列表的 DragTarget，卡片本身不再各自抢指针。
class NoteCard extends StatefulWidget {
  const NoteCard({
    required this.meta,
    required this.selected,
    required this.view,
    this.dropTarget = false,
    this.selecting = false,
    this.checked = false,
    this.dragDisabled = false,
    this.onToggleCheck,
    this.onStartSelect,
    this.onMoveRequest,
    this.onDragStart,
    this.onDragEnd,
    this.onRequestTrash,
    super.key,
  });

  final NoteMeta meta;
  final bool selected;
  final String view;
  final bool dropTarget;
  final bool selecting;
  final bool checked;
  final bool dragDisabled;
  final VoidCallback? onToggleCheck;
  final VoidCallback? onStartSelect;
  final VoidCallback? onMoveRequest;
  final void Function(String id, Offset downPosition)? onDragStart;
  final void Function(String id, bool accepted)? onDragEnd;
  final ValueChanged<NoteMeta>? onRequestTrash;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  NoteMeta get meta => widget.meta;
  Offset _downPosition = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final state = context.read<AppState>();
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final query = state.query.trim();
        final snippet = widget.view == 'search' && query.isNotEmpty
            ? searchSnippet(state.noteText(meta.id), query)
            : null;
        final desktop = const {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(Theme.of(context).platform);
        void onTap() {
          if (widget.selecting) {
            widget.onToggleCheck?.call();
            return;
          }
          if (widget.view == 'trash') {
            _showTrashPreview(context, state, meta);
          } else {
            state.openNote(meta.id);
          }
        }

        final card = Padding(
          padding: EdgeInsets.only(bottom: wide ? 4 : 6),
          child: HoverBuilder(
            cursor: widget.selecting
                ? SystemMouseCursors.click
                : widget.view == 'trash'
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.grab,
            builder: (context, hovered, t) {
              final c = AppPalette.of(context);
              final bg = widget.checked
                  ? c.accentSoft
                  : widget.selected
                      ? c.accentSoft
                      : hovered
                          ? c.paper
                          : Colors.transparent;
              return GestureDetector(
                onTap: onTap,
                onSecondaryTapDown: (details) => _showContextMenu(
                  context,
                  state,
                  meta,
                  details.globalPosition,
                ),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.enter,
                  padding: EdgeInsets.fromLTRB(
                    wide ? 12 : 14,
                    wide ? 11 : 12,
                    wide ? 10 : 12,
                    wide ? 10 : 12,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(wide ? 10 : 12),
                    border: Border.all(
                      color: widget.dropTarget
                          ? c.accent.withValues(alpha: 0.6)
                          : widget.checked
                              ? c.accent.withValues(alpha: 0.55)
                              : widget.selected
                                  ? c.accent.withValues(alpha: 0.25)
                                  : hovered
                                      ? c.line
                                      : Colors.transparent,
                    ),
                    boxShadow: widget.dropTarget
                        ? [
                            BoxShadow(
                              color: c.accent.withValues(alpha: 0.12),
                              blurRadius: 14,
                            ),
                          ]
                        : null,
                  ),
                  child: _NoteCardContent(
                    meta: meta,
                    selected: widget.selected,
                    snippet: snippet,
                    selecting: widget.selecting,
                    checked: widget.checked,
                    showMore: hovered ||
                        widget.selected ||
                        !desktop ||
                        widget.selecting,
                    onMore: (position) =>
                        _showContextMenu(context, state, meta, position),
                  ),
                ),
              );
            },
          ),
        );

        final semanticCard = Semantics(
          button: true,
          label: '${meta.title.trim().isEmpty ? _t('无题') : meta.title.trim()}，'
              '${meta.words} ${_t('字')}',
          onTap: onTap,
          child: card,
        );
        if (widget.view == 'trash' || widget.dragDisabled) return semanticCard;

        final draggableChild = Listener(
          onPointerDown: (event) => _downPosition = event.position,
          child: semanticCard,
        );
        final feedback = Material(
          color: Colors.transparent,
          child: _NoteGhost(meta: meta, width: constraints.maxWidth),
        );

        void onDragStarted() {
          widget.onDragStart?.call(meta.id, _downPosition);
        }

        void onDragEnd(DraggableDetails details) =>
            widget.onDragEnd?.call(meta.id, details.wasAccepted);

        // 桌面上用鼠标拖东西，不应该先按住不动 300ms；
        // 300ms 长按只留给触屏，用来和列表滚动区分开。
        if (desktop) {
          return Draggable<String>(
            data: 'note:${meta.id}',
            feedback: feedback,
            childWhenDragging: const SizedBox.shrink(),
            onDragStarted: onDragStarted,
            onDragEnd: onDragEnd,
            child: draggableChild,
          );
        }
        final palette = AppPalette.of(context);
        return Dismissible(
          key: ValueKey('swipe-${meta.id}'),
          direction: DismissDirection.horizontal,
          confirmDismiss: (direction) async {
            if (direction == DismissDirection.startToEnd) {
              await state.toggleFavorite(meta);
              if (context.mounted) {
                showToast(
                  context,
                  meta.favorite ? _t('已取消收藏') : _t('已收藏'),
                  icon: LucideIcons.heart,
                );
              }
              return false;
            }
            await state.trashNote(meta.id);
            if (context.mounted) {
              showToast(
                context,
                _t('已移到回收站'),
                actionLabel: _t('撤销'),
                onAction: () => state.restoreNote(meta.id),
              );
            }
            // 列表已经把这篇文章移走；这里返回 false 让 Dismissible 收回去，
            // 避免它在已销毁的卡片上做移除断言。
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 22),
            color: palette.accentSoft,
            child: Icon(LucideIcons.heart, size: 18, color: palette.accent),
          ),
          secondaryBackground: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 22),
            color: palette.danger.withValues(alpha: 0.12),
            child: Icon(LucideIcons.trash2, size: 18, color: palette.danger),
          ),
          child: LongPressDraggable<String>(
            data: 'note:${meta.id}',
            delay: const Duration(milliseconds: 300),
            hapticFeedbackOnStart: true,
            feedback: feedback,
            childWhenDragging: const SizedBox.shrink(),
            onDragStarted: onDragStarted,
            onDragEnd: onDragEnd,
            child: draggableChild,
          ),
        );
      },
    );
  }

  void _showContextMenu(
    BuildContext context,
    AppState state,
    NoteMeta meta,
    Offset position,
  ) {
    final desktop = const {
      TargetPlatform.windows,
      TargetPlatform.linux,
      TargetPlatform.macOS,
    }.contains(Theme.of(context).platform);
    if (!desktop) {
      _showActionsSheet(context, state, meta);
      return;
    }
    final c = AppPalette.of(context);
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: c.surface,
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(_t(meta.pinned ? '取消置顶' : '置顶')),
        ),
        PopupMenuItem(
          value: 'fixed',
          child: Text(_t(meta.fixed ? '取消固定' : '固定')),
        ),
        PopupMenuItem(
          value: 'fav',
          child: Text(_t(meta.favorite ? '取消收藏' : '收藏')),
        ),
        if (widget.view != 'trash') ...[
          PopupMenuItem(value: 'duplicate', child: Text(_t('复制一份'))),
          PopupMenuItem(value: 'move', child: Text(_t('移动到文件夹…'))),
          PopupMenuItem(value: 'export', child: Text(_t('导出…'))),
          PopupMenuItem(value: 'multi', child: Text(_t('多选'))),
          PopupMenuItem(value: 'trash', child: Text(_t('移到回收站'))),
        ] else ...[
          PopupMenuItem(value: 'restore', child: Text(_t('恢复'))),
          PopupMenuItem(value: 'purge', child: Text(_t('永久删除'))),
        ],
      ],
    ).then((value) {
      if (!context.mounted) return;
      _applyNoteAction(context, state, meta, value);
    });
  }

  Future<void> _showActionsSheet(
    BuildContext context,
    AppState state,
    NoteMeta meta,
  ) async {
    final c = AppPalette.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: c.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text(
                meta.title.trim().isEmpty ? _t('无题') : meta.title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
            if (widget.view == 'trash') ...[
              _MobileMenuRow(
                icon: LucideIcons.eye,
                label: _t('查看全文'),
                onTap: () => Navigator.of(context).pop('preview'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.recycle,
                label: _t('恢复'),
                onTap: () => Navigator.of(context).pop('restore'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.trash2,
                label: _t('永久删除'),
                onTap: () => Navigator.of(context).pop('purge'),
              ),
            ] else ...[
              _MobileMenuRow(
                icon: meta.pinned ? LucideIcons.pinOff : LucideIcons.pin,
                label: _t(meta.pinned ? '取消置顶' : '置顶'),
                onTap: () => Navigator.of(context).pop('pin'),
              ),
              _MobileMenuRow(
                icon: meta.fixed ? LucideIcons.lockOpen : LucideIcons.lock,
                label: _t(meta.fixed ? '取消固定' : '固定'),
                onTap: () => Navigator.of(context).pop('fixed'),
              ),
              _MobileMenuRow(
                icon: meta.favorite ? LucideIcons.starOff : LucideIcons.star,
                label: _t(meta.favorite ? '取消收藏' : '收藏'),
                onTap: () => Navigator.of(context).pop('fav'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.copy,
                label: _t('复制一份'),
                onTap: () => Navigator.of(context).pop('duplicate'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.folderInput,
                label: _t('移动到文件夹…'),
                onTap: () => Navigator.of(context).pop('move'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.listChecks,
                label: _t('多选'),
                onTap: () => Navigator.of(context).pop('multi'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.download,
                label: _t('导出…'),
                onTap: () => Navigator.of(context).pop('export'),
              ),
              _MobileMenuRow(
                icon: LucideIcons.trash2,
                label: _t('移到回收站'),
                onTap: () => Navigator.of(context).pop('trash'),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    await _applyNoteAction(context, state, meta, action);
  }

  Future<void> _applyNoteAction(
    BuildContext context,
    AppState state,
    NoteMeta meta,
    String? value,
  ) async {
    if (value == null || !context.mounted) return;
    switch (value) {
      case 'pin':
        await state.togglePin(meta);
        break;
      case 'fixed':
        await state.toggleFixed(meta);
        break;
      case 'fav':
        await state.toggleFavorite(meta);
        break;
      case 'multi':
        widget.onStartSelect?.call();
        break;
      case 'move':
        widget.onMoveRequest?.call();
        break;
      case 'trash':
        widget.onRequestTrash?.call(meta);
        break;
      case 'preview':
        if (context.mounted) _showTrashPreview(context, state, meta);
        break;
      case 'restore':
        await state.restoreNote(meta.id);
        if (context.mounted) {
          showToast(
            context,
            _t('已恢复到原来的位置'),
            icon: LucideIcons.recycle,
          );
        }
        break;
      case 'purge':
        if (context.mounted &&
            await showConfirm(
              context,
              title: _t('永久删除？'),
              message: _t('这篇文字将无法恢复。'),
              danger: true,
              confirmLabel: _t('删除'),
            )) {
          await state.purgeNote(meta.id);
        }
        break;
      case 'duplicate':
        final copy = await state.duplicateNote(meta.id);
        if (copy != null && context.mounted) {
          showToast(context, _t('已复制一份'), icon: LucideIcons.copy);
        }
        break;
      case 'export':
        await state.openNote(meta.id);
        if (context.mounted) await showExportSheet(context);
        break;
    }
  }

  void _showTrashPreview(BuildContext context, AppState state, NoteMeta meta) {
    final c = AppPalette.of(context);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 24, 26, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  meta.title.isEmpty ? _t('无题') : meta.title,
                  style: TextStyle(
                    fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                    fontSize: 22,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shortDate(meta.createdAt)} · ${I18n.count(meta.words, '字', 'word')}',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      meta.excerpt.isEmpty ? _t('（空）') : meta.excerpt,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 14,
                        height: 1.9,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () async {
                        if (await showConfirm(
                          context,
                          title: _t('永久删除？'),
                          message: _t('这篇文字将无法恢复。'),
                          danger: true,
                          confirmLabel: _t('删除'),
                        )) {
                          await state.purgeNote(meta.id);
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                      child: Text(_t('永久删除'), style: TextStyle(color: c.danger)),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.ink,
                        foregroundColor: c.paper,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      onPressed: () async {
                        await state.restoreNote(meta.id);
                        if (context.mounted) {
                          showToast(
                            context,
                            _t('已恢复'),
                            icon: LucideIcons.recycle,
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(LucideIcons.recycle, size: 14),
                      label: Text(_t('恢复')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.count,
    required this.notesCount,
    required this.favorite,
    required this.pinned,
    required this.fixed,
    required this.onFavorite,
    required this.onPin,
    required this.onFix,
    required this.onMove,
    required this.onTrash,
    required this.onCancel,
  });

  final int count;
  final int notesCount;
  final bool favorite;
  final bool pinned;
  final bool fixed;
  final VoidCallback onFavorite;
  final VoidCallback onPin;
  final VoidCallback onFix;
  final VoidCallback onMove;
  final VoidCallback onTrash;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _BatchAction(
              icon: favorite ? LucideIcons.heartOff : LucideIcons.heart,
              label: favorite ? _t('取消收藏') : _t('收藏'),
              onTap: notesCount == 0 ? null : onFavorite,
            ),
            _BatchAction(
              icon: pinned ? LucideIcons.pinOff : LucideIcons.pin,
              label: pinned ? _t('取消置顶') : _t('置顶'),
              onTap: count == 0 ? null : onPin,
            ),
            _BatchAction(
              icon: fixed ? LucideIcons.lockOpen : LucideIcons.lock,
              label: fixed ? _t('取消固定') : _t('固定'),
              onTap: count == 0 ? null : onFix,
            ),
            _BatchAction(
              icon: LucideIcons.folderInput,
              label: _t('移动'),
              onTap: count == 0 ? null : onMove,
            ),
            _BatchAction(
              icon: LucideIcons.trash2,
              label: _t('删除'),
              danger: true,
              onTap: count == 0 ? null : onTrash,
            ),
            _BatchAction(
              icon: LucideIcons.x,
              label: _t('取消'),
              onTap: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final color = onTap == null
        ? c.inkMuted.withValues(alpha: 0.45)
        : danger
            ? c.danger
            : c.inkSoft;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.line),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 桌面上的范围胶囊：比手机的 chip 更紧凑，去掉图标只留文字，
/// 选中用低饱和的 accentSoft 底，和设置页的胶囊保持同一套语气。
class _ScopePill extends StatelessWidget {
  const _ScopePill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected
                  ? c.accent.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 11,
              color: selected ? c.accent : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? c.accent.withValues(alpha: 0.32) : c.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: selected ? c.accent : c.inkMuted),
            const SizedBox(width: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 11,
                color: selected ? c.accent : c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileMenuRow extends StatelessWidget {
  const _MobileMenuRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.hint,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 16, color: c.inkMuted),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 13,
                  color: c.ink,
                ),
              ),
            ),
            if (hint != null)
              Text(
                hint!,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
            const SizedBox(width: 6),
            Icon(LucideIcons.chevronRight, size: 14, color: c.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// 英文文案。键是界面里的中文原文，值是对应的英文。
const Map<String, String> _en = <String, String>{
  // 顶部标题与说明
  '今日': 'Today',
  '全部笔记': 'All notes',
  '时间': 'Timeline',
  '标签': 'Tags',
  '回收站': 'Trash',
  '搜索': 'Search',
  '日历': 'Calendar',
  '笔记': 'Notes',
  '未分类': 'Unfiled',
  '按日期翻看写过的字': 'Read your words by date',
  '按标签整理你的文字': 'Organize your words by tag',
  '与这个标签有关的文字': 'Words with this tag',
  '删除的文字会在这里保留': 'Deleted words stay here',
  '搜索标题、正文与标签': 'Search titles, text and tags',
  '所有写下的日子': 'Every day you wrote down',
  '文件夹里的文字': 'Words in this folder',
  // 工具栏
  '新建（Ctrl N）': 'New (Ctrl N)',
  '搜索所有文字…': 'Search all words…',
  '更多': 'More',
  '全部': 'All',
  '命令面板': 'Command palette',
  '写作统计': 'Writing stats',
  '设置': 'Settings',
  '新建笔记': 'New note',
  '新建文件夹': 'New folder',
  '新建子文件夹': 'New subfolder',
  '收起笔记列表': 'Collapse note list',
  '长按卡片可拖动排序，拖到上下边缘会自动滚动':
      'Long-press a card to reorder; drag near an edge to scroll',
  '返回上一层': 'Back',
  // 排序
  '最近': 'Recent',
  '创建': 'Created',
  '标题': 'Title',
  '字数': 'Words',
  '手动': 'Manual',
  // 底部统计
  '看看坚持': 'See streak',
  // 空列表
  '回收站是空的': 'Trash is empty',
  '没有找到相关的文字': 'No matching words found',
  '今天还是一张白纸': 'Today is still a blank page',
  '还没有标签': 'No tags yet',
  '这个标签下还没有文字': 'Nothing under this tag yet',
  '还没有笔记': 'No notes yet',
  '写一页': 'Write a page',
  // 日期分组
  '今天': 'Today',
  '昨天': 'Yesterday',
  '本周': 'This week',
  '{y} 年 {m} 月': '{m}/{y}',
  // 卡片
  '无题': 'Untitled',
  '还没有写下正文': 'No text yet',
  '置顶的笔记和普通笔记之间不能调换顺序':
      'Pinned notes cannot be reordered across the pinned boundary',
  '同一天、同样置顶状态的笔记才能调整顺序':
      'Only notes from the same day with the same pin state can be reordered',
  // 右键菜单
  '取消置顶': 'Unpin',
  '置顶': 'Pin',
  '固定': 'Fix in place',
  '取消固定': 'Unfix',
  '取消收藏': 'Unfavorite',
  '收藏': 'Favorite',
  '写过又舍不得删的文字': 'Words you kept on purpose',
  '还没有收藏的文字': 'No favorites yet',
  '收起': 'Collapse',
  '已收藏': 'Added to favorites',
  '已取消收藏': 'Removed from favorites',
  '已置顶': 'Pinned',
  '已取消置顶': 'Unpinned',
  '已固定': 'Fixed in place',
  '已取消固定': 'Unfixed',
  '复制一份': 'Duplicate',
  '导出…': 'Export…',
  '查看全文': 'Read',
  '移到回收站': 'Move to Trash',
  '移动到文件夹…': 'Move to folder…',
  '移到文件夹': 'Move to folder',
  '已移动到文件夹': 'Moved to folder',
  '多选': 'Select',
  '全选': 'Select all',
  '取消': 'Cancel',
  '已选 {n} 项': '{n} selected',
  '点按卡片继续选择': 'Tap cards to add them',
  '已处理选中的项目': 'Selected items handled',
  '删除选中的文件夹？': 'Delete selected folders?',
  '文件夹本身会被删除，里面的笔记会移到上一层；选中的笔记会移到回收站。':
      'The folders themselves are removed and their notes move up a level; selected notes go to Trash.',
  '松手移出到「{name}」': 'Drop to move out to “{name}”',
  '拖到这里移出当前文件夹': 'Drag here to move out of this folder',
  '已移到「{name}」': 'Moved to “{name}”',
  '上一层': 'Up one level',
  '恢复': 'Restore',
  '永久删除': 'Delete forever',
  '已恢复到原来的位置': 'Restored to its original place',
  '永久删除？': 'Delete forever?',
  '这篇文字将无法恢复。': 'This text cannot be recovered.',
  '删除': 'Delete',
  '已复制一份': 'Duplicated',
  '在编辑器右上角的菜单里可以导出这篇文字':
      'Export this note from the menu at the top right of the editor',
  // 文件夹
  '文件夹': 'Folder',
  '空文件夹': 'Empty folder',
  '{n} 篇笔记': '{n} notes',
  '{n} 篇': '{n}',
  '文件夹已建好': 'Folder created',
  '例如：日记 / 小说 / 读书': 'e.g. Diary / Novel / Reading',
  '建好': 'Create',
  '重命名': 'Rename',
  '删除文件夹': 'Delete folder',
  '删除这个文件夹？': 'Delete this folder?',
  '里面的笔记会移到上一层，不会被删除。':
      'The notes inside move up a level; nothing gets deleted.',
  '松手放入': 'Drop inside',
  '已放入「{name}」': 'Moved into “{name}”',
  '把笔记拖到另一张卡片的上方或下方才能调整顺序':
      'Drop a note above or below another card to reorder',
  '把文件夹拖到另一张卡片的上方或下方才能调整顺序':
      'Drop a folder above or below another card to reorder',
  // 回收站预览
  '（空）': '(empty)',
  '已恢复': 'Restored',
  '已移到回收站': 'Moved to Trash',
  '撤销': 'Undo',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);
