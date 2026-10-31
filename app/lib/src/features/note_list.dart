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
import 'folder_tree.dart';
import 'new_note_sheet.dart';

class NoteListPanel extends StatefulWidget {
  const NoteListPanel({super.key, this.width = 324, this.embedded = false});

  final double width;
  final bool embedded;

  @override
  State<NoteListPanel> createState() => _NoteListPanelState();
}

class _NoteListPanelState extends State<NoteListPanel> {
  bool _searching = false;
  String? _removingId;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  /// 拖拽时的实时预览：被拖的卡片先让位，目标位置留出一张卡的空隙。
  /// 灵感来自看板 drag 的「卡片跟着指针走、列表实时重排」。
  String? _dragId;
  List<({String id, Rect rect})>? _dragRects;
  Offset? _lastDragPoint;
  _DropPreview? _preview;
  String? _lastGeneration;
  final Map<String, GlobalKey> _cardKeys = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 列表切视图时 AnimatedSwitcher 会让新旧两份列表同时存在一会儿，
  /// 卡片的 GlobalKey 必须按这一份列表的 key 分组，否则同一个笔记
  /// 会在新旧两棵树里各挂一个同名 GlobalKey。
  String _generation(AppState state) =>
      '${state.view}-${state.folderFilter}-${state.tagFilter}';

  GlobalKey _keyFor(String generation, String id) =>
      _cardKeys.putIfAbsent('$generation::$id', () => GlobalKey());

  Rect? _rectOf(String generation, String id) {
    final box = _cardKeys['$generation::$id']
        ?.currentContext
        ?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _beginDrag(String id) {
    final state = context.read<AppState>();
    final dragIndex = state.notes.indexWhere((n) => n.id == id);
    final candidates = <String>[];
    if (dragIndex >= 0) {
      final dragNote = state.notes[dragIndex];
      // 置顶笔记在排序里永远排在最前，跨过置顶/非置顶的界线调序是无效的，
      // 所以只在同一置顶状态的那一段里找插入点。
      for (final note in state.visibleNotes) {
        if (note.id == id ||
            note.day != dragNote.day ||
            note.isTrashed ||
            note.pinned != dragNote.pinned) {
          continue;
        }
        candidates.add(note.id);
      }
    }
    setState(() {
      _dragId = id;
      _dragRects = null;
      _lastDragPoint = null;
      _preview = null;
    });
    // 位置只量一次：等这一帧把被拖走的卡片收起来之后再量。
    // 之后整个拖动都用这份快照判断插入点，空位让位就不会反过来
    // 改变判断、再让空位跳走 —— 那正是拖动时「抽搐」的来源。
    final generation = _generation(state);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dragId != id) return;
      final rects = <({String id, Rect rect})>[];
      for (final candidate in candidates) {
        final rect = _rectOf(generation, candidate);
        if (rect != null) rects.add((id: candidate, rect: rect));
      }
      setState(() => _dragRects = rects);
      // 快照晚一帧才就绪；如果这期间指针已经动过，补算一次预览，
      // 免得用户停在原地时看不到空位。
      final point = _lastDragPoint;
      if (point != null) _previewAt(point);
    });
  }

  void _endDrag(String id, bool accepted) {
    if (_dragId != id) return;
    setState(() {
      _dragId = null;
      _dragRects = null;
      _lastDragPoint = null;
      _preview = null;
    });
  }

  void _setPreview(_DropPreview? next) {
    if (identical(next, _preview)) return;
    if (next?.beforeId == _preview?.beforeId &&
        next?.afterId == _preview?.afterId) {
      return;
    }
    setState(() => _preview = next);
  }

  /// 指针在列表里移动时，按「第一张中心点在指针下方的卡片」决定空位插在哪。
  /// 判断用的是拖动开始时量好的位置，不是当前布局：空位一开、卡片一让位，
  /// 再拿新位置去算就会在两张卡之间来回跳。
  /// 跨日期不参与排序：指针离开当天那一组就收起空位，松手也不改顺序。
  void _previewAt(Offset global) {
    _lastDragPoint = global;
    if (_dragId == null) return;
    final rects = _dragRects;
    if (rects == null) return;
    if (rects.isEmpty) {
      _setPreview(null);
      return;
    }
    final first = rects.first.rect;
    final last = rects.last.rect;
    // 允许在组标题附近留一点余量，但离开这一组就取消预览。
    if (global.dy < first.top - 36 || global.dy > last.bottom + 36) {
      _setPreview(null);
      return;
    }
    String? beforeId;
    for (final entry in rects) {
      if (global.dy < entry.rect.center.dy) {
        beforeId = entry.id;
        break;
      }
    }
    _setPreview(
      _DropPreview(
        beforeId: beforeId,
        afterId: beforeId == null ? rects.last.id : null,
      ),
    );
  }

  Future<void> _commitDrop() async {
    final dragId = _dragId;
    final preview = _preview;
    if (dragId == null) return;
    setState(() {
      _dragId = null;
      _dragRects = null;
      _lastDragPoint = null;
      _preview = null;
    });
    if (preview == null) {
      showToast(
        context,
        _t('同一天、同样置顶状态的笔记才能调整顺序'),
        icon: LucideIcons.alertCircle,
      );
      return;
    }
    final target = preview.beforeId ?? preview.afterId;
    if (target == null) return;
    await context.read<AppState>().reorderNote(
      dragId,
      target,
      after: preview.beforeId == null,
    );
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
    setState(() => _searching = !_searching);
    if (_searching) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchFocus.requestFocus(),
      );
    } else {
      _searchCtrl.clear();
      context.read<AppState>().setQuery('');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final c = AppPalette.of(context);
    final folderName = state.folderFilter == '__unfiled__'
        ? _t('未分类')
        : state.folderById(state.folderFilter)?.name;
    final title = switch (state.view) {
      'today' => _t('今日'),
      'all' => folderName ?? _t('全部笔记'),
      'tags' => state.tagFilter == null ? _t('标签') : '# ${state.tagFilter}',
      'trash' => _t('回收站'),
      'search' => _t('搜索'),
      'calendar' => _t('日历'),
      _ => _t('笔记'),
    };
    final subtitle = switch (state.view) {
      'today' => dateLabel(DateTime.now()),
      'tags' => state.tagFilter == null
          ? _t('按标签整理你的文字')
          : _t('与这个标签有关的文字'),
      'trash' => _t('删除的文字会在这里保留'),
      'search' => _t('搜索标题、正文与标签'),
      'all' => state.folderFilter == null
          ? _t('所有写下的日子')
          : _t('文件夹里的文字'),
      _ => '',
    };
    final notes = state.visibleNotes;
    final list = _grouped(state, notes);
    final generation = _generation(state);
    if (_lastGeneration != generation) {
      _lastGeneration = generation;
      // 旧列表还在做退场动画时仍然握着旧的 GlobalKey，这里只是不再跟踪它们。
      _cardKeys.removeWhere((key, _) => !key.startsWith('$generation::'));
    }
    final dragIndex =
        _dragId == null ? -1 : state.notes.indexWhere((n) => n.id == _dragId);
    final dragMeta = dragIndex < 0 ? null : state.notes[dragIndex];

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, widget.embedded ? 8 : 18, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
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
                                  fontFamily:
                                      state.view == 'today' && !I18n.isEn
                                          ? 'WenKai'
                                          : 'NotoSansSC',
                                  fontSize: state.view == 'today' ? 24 : 20,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: state.view == 'today'
                                      ? 1
                                      : -0.2,
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
                                fontSize: 10.5,
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
                  const SizedBox(width: 2),
                  SoftIconButton(
                    icon: LucideIcons.plus,
                    tooltip: _t('新建（Ctrl N）'),
                    size: 30,
                    onPressed: () => showNewNoteSheet(context),
                  ),
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
                                  onChanged: state.setQuery,
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
        if (state.view == 'all') FolderTree(state: state),
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
                for (final entry in state.tagCounts.entries.take(14))
                  TagChip(
                    label: entry.key,
                    count: entry.value,
                    selected: state.tagFilter == entry.key,
                    onTap: () => state.selectTag(entry.key),
                  ),
              ],
            ),
          ),
        if (state.view == 'all')
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 12, 8),
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
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 10.5,
                            color: state.sort == s.$1 ? c.paper : c.inkMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
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
              child: list.isEmpty
                  ? _empty(context, state)
                  : DragTarget<String>(
                      onWillAcceptWithDetails: (details) =>
                          details.data.startsWith('note:'),
                      onMove: (details) => _previewAt(details.offset),
                      onAcceptWithDetails: (_) => _commitDrop(),
                      builder: (context, candidate, rejected) => Scrollbar(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 20),
                          itemCount: list.length,
                          itemBuilder: (context, i) {
                            final item = list[i];
                            if (item is _GroupHeader) {
                              return Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(10, 14, 10, 7),
                                child: Text(
                                  item.label,
                                  style: TextStyle(
                                    fontFamily: 'NotoSansSC',
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    color: c.inkMuted,
                                  ),
                                ),
                              );
                            }
                            final note = item as NoteMeta;
                            final removing = _removingId == note.id;
                            final gapBefore = _preview?.beforeId == note.id;
                            final gapAfter = _preview?.afterId == note.id;
                            final dropTarget = gapBefore || gapAfter;
                            final row = TweenAnimationBuilder<double>(
                              key: ValueKey('row-${note.id}'),
                              tween: Tween<double>(
                                begin: 1,
                                end: removing ? 0 : 1,
                              ),
                              duration: const Duration(milliseconds: 190),
                              curve: Curves.easeInCubic,
                              onEnd:
                                  removing ? () => _finishTrash(note) : null,
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
                                onDragStart: _beginDrag,
                                onDragEnd: _endDrag,
                                onRequestTrash: _requestTrash,
                              ),
                            );
                            if (!dropTarget || dragMeta == null) return row;
                            // 目标位置让出一张卡的空隙，空隙里放半透明的「影子卡」。
                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (gapBefore)
                                  _DragSlot(
                                    key: const ValueKey('drag-mirror'),
                                    meta: dragMeta,
                                  ),
                                row,
                                if (gapAfter)
                                  _DragSlot(
                                    key: const ValueKey('drag-mirror'),
                                    meta: dragMeta,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ),
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

    if (widget.embedded) return content;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: content,
    );
  }

  Widget _empty(BuildContext context, AppState state) {
    final c = AppPalette.of(context);
    final text = switch (state.view) {
      'trash' => _t('回收站是空的'),
      'search' => _t('没有找到相关的文字'),
      'today' => _t('今天还是一张白纸'),
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
    if (state.view == 'today' ||
        state.view == 'calendar' ||
        state.view == 'trash') {
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
  });

  final NoteMeta meta;
  final bool selected;
  final bool showMore;
  final ValueChanged<Offset>? onMore;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final mood = MoodX.fromScore(meta.mood);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (meta.pinned)
              Padding(
                padding: const EdgeInsets.only(top: 3, right: 5),
                child: Icon(LucideIcons.pin, size: 11, color: c.accent),
              ),
            Expanded(
              child: Text(
                meta.title.trim().isEmpty ? _t('无题') : meta.title.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: c.ink,
                  height: 1.35,
                ),
              ),
            ),
            if (showMore && onMore != null)
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTapDown: (d) => onMore!(d.globalPosition),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4, top: 1),
                    child: Icon(
                      LucideIcons.ellipsis,
                      size: 15,
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          meta.excerpt.isEmpty ? _t('还没有写下正文') : meta.excerpt,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 11.5,
            height: 1.6,
            color: meta.excerpt.isEmpty ? c.inkMuted : c.inkSoft,
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Icon(kindIcon(meta.kind), size: 10, color: c.inkMuted),
            const SizedBox(width: 4),
            Text(
              shortDate(meta.createdAt),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
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
                fontSize: 9.5,
                color: c.inkMuted,
              ),
            ),
            if (mood != null) ...[
              const SizedBox(width: 7),
              Text(
                mood.emoji,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: mood.color,
                ),
              ),
            ],
            const Spacer(),
            if (meta.favorite)
              Icon(LucideIcons.heart, size: 10, color: c.accent),
            if (meta.tags.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  meta.tags.take(2).map((e) => '#$e').join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9,
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
/// 跟着指针走的整张卡片：拿起来时轻轻晃一下（阻尼衰减），
/// 同时放大到 105%，最后停在正常角度。
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
          padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(10),
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

/// 插入位置的「影子卡」：列表在这里让出一张卡的空隙，
/// 空隙里留一张 45% 透明的同一张卡 —— 松手后它就落在这。
class _DragSlot extends StatelessWidget {
  const _DragSlot({required this.meta, super.key});
  final NoteMeta meta;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.45,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
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

class _GroupHeader {
  const _GroupHeader(this.label);
  final String label;
}

/// 拖拽预览：空位插在哪张卡的前面 / 后面。
class _DropPreview {
  const _DropPreview({this.beforeId, this.afterId});
  final String? beforeId;
  final String? afterId;
}

/// 整张卡片就是拖拽源；按下即拖（触屏仍是长按），
/// 放下的判断交给整个列表的 DragTarget，卡片本身不再各自抢指针。
class NoteCard extends StatefulWidget {
  const NoteCard({
    required this.meta,
    required this.selected,
    required this.view,
    this.dropTarget = false,
    this.onDragStart,
    this.onDragEnd,
    this.onRequestTrash,
    super.key,
  });

  final NoteMeta meta;
  final bool selected;
  final String view;
  final bool dropTarget;
  final ValueChanged<String>? onDragStart;
  final void Function(String id, bool accepted)? onDragEnd;
  final ValueChanged<NoteMeta>? onRequestTrash;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  NoteMeta get meta => widget.meta;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final state = context.read<AppState>();
        final card = Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: HoverBuilder(
            cursor: widget.view == 'trash'
                ? SystemMouseCursors.click
                : SystemMouseCursors.grab,
            builder: (context, hovered, t) {
              final c = AppPalette.of(context);
              final bg = widget.selected
                  ? c.accentSoft
                  : hovered
                      ? c.paper
                      : Colors.transparent;
              return GestureDetector(
                onTap: () {
                  if (widget.view == 'trash') {
                    _showTrashPreview(context, state, meta);
                  } else {
                    state.openNote(meta.id);
                  }
                },
                onSecondaryTapDown: (details) => _showContextMenu(
                  context,
                  state,
                  meta,
                  details.globalPosition,
                ),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  curve: Motion.enter,
                  padding: const EdgeInsets.fromLTRB(12, 11, 10, 10),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.dropTarget
                          ? c.accent.withValues(alpha: 0.6)
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
                    showMore: hovered || widget.selected,
                    onMore: (position) =>
                        _showContextMenu(context, state, meta, position),
                  ),
                ),
              );
            },
          ),
        );

        if (widget.view == 'trash') return card;

        final feedback = Material(
          color: Colors.transparent,
          child: _NoteGhost(meta: meta, width: constraints.maxWidth),
        );

        void onDragStarted() {
          // 只冻结顺序，不切换排序模式：切换会重建列表、打断拖动。
          state.prepareManualOrder();
          widget.onDragStart?.call(meta.id);
        }

        void onDragEnd(DraggableDetails details) =>
            widget.onDragEnd?.call(meta.id, details.wasAccepted);

        // 桌面上用鼠标拖东西，不应该先按住不动 300ms；
        // 300ms 长按只留给触屏，用来和列表滚动区分开。
        final desktop = const {
          TargetPlatform.windows,
          TargetPlatform.linux,
          TargetPlatform.macOS,
        }.contains(Theme.of(context).platform);

        if (desktop) {
          return Draggable<String>(
            data: 'note:${meta.id}',
            feedback: feedback,
            childWhenDragging: const SizedBox.shrink(),
            onDragStarted: onDragStarted,
            onDragEnd: onDragEnd,
            child: card,
          );
        }
        return LongPressDraggable<String>(
          data: 'note:${meta.id}',
          delay: const Duration(milliseconds: 300),
          hapticFeedbackOnStart: true,
          feedback: feedback,
          childWhenDragging: const SizedBox.shrink(),
          onDragStarted: onDragStarted,
          onDragEnd: onDragEnd,
          child: card,
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
          value: 'fav',
          child: Text(_t(meta.favorite ? '取消收藏' : '收藏')),
        ),
        if (widget.view != 'trash') ...[
          PopupMenuItem(value: 'duplicate', child: Text(_t('复制一份'))),
          PopupMenuItem(value: 'export', child: Text(_t('导出…'))),
          PopupMenuItem(value: 'trash', child: Text(_t('移到回收站'))),
        ] else ...[
          PopupMenuItem(value: 'restore', child: Text(_t('恢复'))),
          PopupMenuItem(value: 'purge', child: Text(_t('永久删除'))),
        ],
      ],
    ).then((value) async {
      if (!context.mounted || value == null) return;
      switch (value) {
        case 'pin':
          await state.togglePin(meta);
          break;
        case 'fav':
          await state.toggleFavorite(meta);
          break;
        case 'trash':
          widget.onRequestTrash?.call(meta);
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
          if (await showConfirm(
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
          showToast(context, _t('在编辑器右上角的菜单里可以导出这篇文字'));
          break;
      }
    });
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
                      meta.text.isEmpty ? _t('（空）') : meta.text,
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

/// 英文文案。键是界面里的中文原文，值是对应的英文。
const Map<String, String> _en = <String, String>{
  // 顶部标题与说明
  '今日': 'Today',
  '全部笔记': 'All notes',
  '标签': 'Tags',
  '回收站': 'Trash',
  '搜索': 'Search',
  '日历': 'Calendar',
  '笔记': 'Notes',
  '未分类': 'Unfiled',
  '按标签整理你的文字': 'Organize your words by tag',
  '与这个标签有关的文字': 'Words with this tag',
  '删除的文字会在这里保留': 'Deleted words stay here',
  '搜索标题、正文与标签': 'Search titles, text and tags',
  '所有写下的日子': 'Every day you wrote down',
  '文件夹里的文字': 'Words in this folder',
  // 工具栏
  '新建（Ctrl N）': 'New (Ctrl N)',
  '搜索所有文字…': 'Search all words…',
  '全部': 'All',
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
  '同一天、同样置顶状态的笔记才能调整顺序':
      'Only notes from the same day with the same pin state can be reordered',
  // 右键菜单
  '取消置顶': 'Unpin',
  '置顶': 'Pin',
  '取消收藏': 'Unfavorite',
  '收藏': 'Favorite',
  '复制一份': 'Duplicate',
  '导出…': 'Export…',
  '移到回收站': 'Move to Trash',
  '恢复': 'Restore',
  '永久删除': 'Delete forever',
  '已恢复到原来的位置': 'Restored to its original place',
  '永久删除？': 'Delete forever?',
  '这篇文字将无法恢复。': 'This text cannot be recovered.',
  '删除': 'Delete',
  '已复制一份': 'Duplicated',
  '在编辑器右上角的菜单里可以导出这篇文字':
      'Export this note from the menu at the top right of the editor',
  // 回收站预览
  '（空）': '(empty)',
  '已恢复': 'Restored',
  '已移到回收站': 'Moved to Trash',
  '撤销': 'Undo',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);
