import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
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

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
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
      '已移到回收站',
      actionLabel: '撤销',
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
        ? '未分类'
        : state.folderById(state.folderFilter)?.name;
    final title = switch (state.view) {
      'today' => '今日',
      'all' => folderName ?? '全部笔记',
      'tags' => state.tagFilter == null ? '标签' : '# ${state.tagFilter}',
      'trash' => '回收站',
      'search' => '搜索',
      'calendar' => '日历',
      _ => '笔记',
    };
    final subtitle = switch (state.view) {
      'today' => dateLabel(DateTime.now()),
      'tags' => state.tagFilter == null ? '按标签整理你的文字' : '与这个标签有关的文字',
      'trash' => '删除的文字会在这里保留',
      'search' => '搜索标题、正文与标签',
      'all' => state.folderFilter == null ? '所有写下的日子' : '文件夹里的文字',
      _ => '',
    };
    final notes = state.visibleNotes;
    final list = _grouped(state, notes);

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
                                  fontFamily: state.view == 'today'
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
                      tooltip: '全部笔记',
                      size: 30,
                      onPressed: () => state.setView('all'),
                    ),
                  SoftIconButton(
                    icon: _searching ? LucideIcons.x : LucideIcons.search,
                    tooltip: '搜索',
                    size: 30,
                    active: _searching,
                    onPressed: _toggleSearch,
                  ),
                  const SizedBox(width: 2),
                  SoftIconButton(
                    icon: LucideIcons.plus,
                    tooltip: '新建（Ctrl N）',
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
                                    hintText: '搜索所有文字…',
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
                  label: '全部',
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
                for (final s in const [
                  ('updated', '最近'),
                  ('created', '创建'),
                  ('title', '标题'),
                  ('words', '字数'),
                  ('manual', '手动'),
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
                  : Scrollbar(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(10, 2, 10, 20),
                        itemCount: list.length,
                        itemBuilder: (context, i) {
                          final item = list[i];
                          if (item is _GroupHeader) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(10, 14, 10, 7),
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
                          return TweenAnimationBuilder<double>(
                            key: ValueKey('row-${note.id}'),
                            tween: Tween<double>(
                              begin: 1,
                              end: removing ? 0 : 1,
                            ),
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
                              meta: note,
                              selected: state.current?.id == note.id,
                              view: state.view,
                              onRequestTrash: _requestTrash,
                            ),
                          );
                        },
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
                '${state.notes.where((e) => !e.isTrashed).length} 篇',
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
                '${state.totalWords} 字',
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
                  '看看坚持',
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
      'trash' => '回收站是空的',
      'search' => '没有找到相关的文字',
      'today' => '今天还是一张白纸',
      'tags' => state.tagFilter == null ? '还没有标签' : '这个标签下还没有文字',
      _ => '还没有笔记',
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
                label: '写一页',
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
          ? '今天'
          : key == yest
          ? '昨天'
          : (DateTime.now().difference(parseDay(key)).inDays < 7)
          ? '本周'
          : '${parseDay(key).year} 年 ${parseDay(key).month} 月';
      if (label != current) {
        current = label;
        result.add(_GroupHeader(label));
      }
      result.add(n);
    }
    return result;
  }
}

class _NoteGhost extends StatelessWidget {
  const _NoteGhost({required this.meta});
  final NoteMeta meta;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(LucideIcons.feather, size: 14, color: c.accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              meta.title.trim().isEmpty ? '无题' : meta.title.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 11,
                color: c.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader {
  const _GroupHeader(this.label);
  final String label;
}

/// 长按整张卡片即可拖动排序；拖到另一张卡片的上半/下半，
/// 会出现一条插入线。跨日期不参与排序，拖进文件夹仍走原来的通道。
class NoteCard extends StatefulWidget {
  const NoteCard({
    required this.meta,
    required this.selected,
    required this.view,
    this.onRequestTrash,
    super.key,
  });

  final NoteMeta meta;
  final bool selected;
  final String view;
  final ValueChanged<NoteMeta>? onRequestTrash;

  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  final GlobalKey _cardKey = GlobalKey();
  bool _hoverBefore = false;
  bool _hoverAfter = false;

  NoteMeta get meta => widget.meta;

  /// 只接受同一天的另一张卡片：列表是按日期分组的，
  /// 跨组插入会让日期分组失去意义。
  bool _accepts(String data) {
    if (!data.startsWith('note:')) return false;
    final id = data.substring(5);
    if (id == meta.id) return false;
    final state = context.read<AppState>();
    final index = state.notes.indexWhere((n) => n.id == id);
    if (index < 0) return false;
    final source = state.notes[index];
    return !source.isTrashed && source.day == meta.day;
  }

  void _updateHover(Offset globalPosition) {
    final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final after = box.globalToLocal(globalPosition).dy > box.size.height / 2;
    if (after == _hoverAfter && !after == _hoverBefore) return;
    setState(() {
      _hoverAfter = after;
      _hoverBefore = !after;
    });
  }

  void _clearHover() {
    if (!_hoverBefore && !_hoverAfter) return;
    setState(() {
      _hoverBefore = false;
      _hoverAfter = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.read<AppState>();
    final mood = MoodX.fromScore(meta.mood);
    final hot = _hoverBefore || _hoverAfter;

    final card = Padding(
      key: _cardKey,
      padding: const EdgeInsets.only(bottom: 4),
      child: HoverBuilder(
        builder: (context, hovered, t) {
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
                  color: hot
                      ? c.accent.withValues(alpha: 0.55)
                      : widget.selected
                          ? c.accent.withValues(alpha: 0.25)
                          : hovered
                              ? c.line
                              : Colors.transparent,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (meta.pinned)
                        Padding(
                          padding: const EdgeInsets.only(top: 3, right: 5),
                          child: Icon(
                            LucideIcons.pin,
                            size: 11,
                            color: c.accent,
                          ),
                        ),
                      Expanded(
                        child: Text(
                          meta.title.trim().isEmpty
                              ? '无题'
                              : meta.title.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 13.5,
                            fontWeight: widget.selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: c.ink,
                            height: 1.35,
                          ),
                        ),
                      ),
                      if (hovered || widget.selected)
                        GestureDetector(
                          onTapDown: (d) => _showContextMenu(
                            context,
                            state,
                            meta,
                            d.globalPosition,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4, top: 1),
                            child: Icon(
                              LucideIcons.ellipsis,
                              size: 15,
                              color: c.inkMuted,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    meta.excerpt.isEmpty ? '还没有写下正文' : meta.excerpt,
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
                      Icon(
                        kindIcon(meta.kind),
                        size: 10,
                        color: c.inkMuted,
                      ),
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
                        '${meta.words} 字',
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
              ),
            ),
          );
        },
      ),
    );

    final layered = Stack(
      clipBehavior: Clip.none,
      children: [
        card,
        if (_hoverBefore)
          const Positioned(top: -2, left: 12, right: 12, child: _DropLine()),
        if (_hoverAfter)
          const Positioned(bottom: 2, left: 12, right: 12, child: _DropLine()),
      ],
    );

    if (widget.view == 'trash') return layered;

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _accepts(details.data),
      onMove: (details) => _updateHover(details.offset),
      onLeave: (_) => _clearHover(),
      onAcceptWithDetails: (details) async {
        final after = _hoverAfter;
        _clearHover();
        final id = details.data.substring(5);
        final ok = await state.reorderNote(id, meta.id, after: after);
        if (!ok && context.mounted) {
          showToast(context, '只能在同一天里调整顺序', icon: LucideIcons.alertCircle);
        }
      },
      builder: (context, candidate, rejected) => LongPressDraggable<String>(
        data: 'note:${meta.id}',
        delay: const Duration(milliseconds: 300),
        hapticFeedbackOnStart: true,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedbackOffset: const Offset(-20, -18),
        feedback: Material(
          color: Colors.transparent,
          child: _NoteGhost(meta: meta),
        ),
        childWhenDragging: Opacity(opacity: 0.28, child: layered),
        onDragStarted: () {
          // 只冻结顺序，不切换排序模式：切换会重建列表、打断拖动。
          state.prepareManualOrder();
        },
        onDragEnd: (_) => _clearHover(),
        child: layered,
      ),
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
        PopupMenuItem(value: 'pin', child: Text(meta.pinned ? '取消置顶' : '置顶')),
        PopupMenuItem(value: 'fav', child: Text(meta.favorite ? '取消收藏' : '收藏')),
        if (widget.view != 'trash') ...[
          const PopupMenuItem(value: 'duplicate', child: Text('复制一份')),
          const PopupMenuItem(value: 'export', child: Text('导出…')),
          const PopupMenuItem(value: 'trash', child: Text('移到回收站')),
        ] else ...[
          const PopupMenuItem(value: 'restore', child: Text('恢复')),
          const PopupMenuItem(value: 'purge', child: Text('永久删除')),
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
            showToast(context, '已恢复到原来的位置', icon: LucideIcons.recycle);
          }
          break;
        case 'purge':
          if (await showConfirm(
            context,
            title: '永久删除？',
            message: '这篇文字将无法恢复。',
            danger: true,
            confirmLabel: '删除',
          )) {
            await state.purgeNote(meta.id);
          }
          break;
        case 'duplicate':
          final copy = await state.duplicateNote(meta.id);
          if (copy != null && context.mounted) {
            showToast(context, '已复制一份', icon: LucideIcons.copy);
          }
          break;
        case 'export':
          showToast(context, '在编辑器右上角的菜单里可以导出这篇文字');
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
                  meta.title.isEmpty ? '无题' : meta.title,
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 22,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${shortDate(meta.createdAt)} · ${meta.words} 字',
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
                      meta.text.isEmpty ? '（空）' : meta.text,
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
                          title: '永久删除？',
                          message: '这篇文字将无法恢复。',
                          danger: true,
                          confirmLabel: '删除',
                        )) {
                          await state.purgeNote(meta.id);
                          if (context.mounted) Navigator.of(context).pop();
                        }
                      },
                      child: Text('永久删除', style: TextStyle(color: c.danger)),
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
                            '已恢复',
                            icon: LucideIcons.recycle,
                          );
                          Navigator.of(context).pop();
                        }
                      },
                      icon: const Icon(LucideIcons.recycle, size: 14),
                      label: const Text('恢复'),
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

class _DropLine extends StatelessWidget {
  const _DropLine();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Row(
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Container(
            height: 2,
            decoration: BoxDecoration(
              color: c.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ],
    );
  }
}
