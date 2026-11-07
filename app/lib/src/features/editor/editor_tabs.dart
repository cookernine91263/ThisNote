import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

const Map<String, String> _en = <String, String>{
  '新建笔记': 'New note',
  '无题': 'Untitled',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class EditorTabs extends StatefulWidget {
  const EditorTabs({required this.state, super.key});

  final AppState state;

  @override
  State<EditorTabs> createState() => _EditorTabsState();
}

class _EditorTabsState extends State<EditorTabs> {
  final Map<String, GlobalKey> _tabKeys = {};
  String? _dragId;
  String? _pressedId;
  Offset? _downPosition;
  bool _dragging = false;

  GlobalKey _keyFor(String id) =>
      _tabKeys.putIfAbsent(id, () => GlobalKey());

  Rect? _rectOf(String id) {
    final box =
        _tabKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  String? _tabAt(Offset global) {
    for (final id in widget.state.openTabs) {
      final rect = _rectOf(id);
      if (rect != null && rect.contains(global)) return id;
    }
    return null;
  }

  void _pointerDown(PointerDownEvent event) {
    final id = _tabAt(event.position);
    if (id == null) return;
    final rect = _rectOf(id);
    // 右侧关闭按钮不参与拖动，避免点关闭时顺手把标签拖走。
    if (rect != null && event.position.dx > rect.right - 26) return;
    _pressedId = id;
    _downPosition = event.position;
    _dragging = false;
  }

  void _pointerMove(PointerMoveEvent event) {
    final pressed = _pressedId;
    final start = _downPosition;
    if (pressed == null || start == null) return;
    if (!_dragging) {
      if ((event.position - start).distance < 8) return;
      _dragging = true;
      setState(() => _dragId = pressed);
    }
    _liveReorder(event.position);
  }

  void _pointerUp() {
    _pressedId = null;
    _downPosition = null;
    _dragging = false;
    if (_dragId != null) setState(() => _dragId = null);
  }

  /// 直接按指针位置换位：拖动中标签会实时滑到新位置。
  void _liveReorder(Offset global) {
    final id = _dragId;
    if (id == null) return;
    final tabs = widget.state.openTabs;
    var index = tabs.length;
    for (var i = 0; i < tabs.length; i++) {
      final rect = _rectOf(tabs[i]);
      if (rect == null) continue;
      if (global.dx < rect.center.dx) {
        index = i;
        break;
      }
    }
    final from = tabs.indexOf(id);
    if (from < 0) return;
    // 插在自己当前位置或下一位都是「没动」。
    if (index == from || index == from + 1) return;
    widget.state.moveTabToIndex(id, index);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = widget.state;
    if (state.openTabs.length < 2) return const SizedBox.shrink();
    final active = state.current?.id;
    final titles = <String, NoteMeta>{
      for (final meta in state.notes) meta.id: meta,
    };
    // 标签数量少时等分整条栏宽；多到放不下时保持最小宽度并允许横向滚动。
    final tabs = state.openTabs;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final available = constraints.maxWidth - 16;
                final width = math.max(
                  140.0,
                  available / tabs.length - 4,
                );
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: (_) => _pointerUp(),
                  onPointerCancel: (_) => _pointerUp(),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: width * tabs.length,
                      height: 36,
                      child: Stack(
                        children: [
                          for (var i = 0; i < tabs.length; i++)
                            AnimatedPositioned(
                              key: ValueKey('slot-${tabs[i]}'),
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              left: i * width,
                              top: 0,
                              bottom: 0,
                              width: width,
                              child: _buildTab(
                                context,
                                tabs[i],
                                titles[tabs[i]],
                                activeId: active,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: _t('新建笔记'),
            icon: Icon(LucideIcons.plus, size: 15, color: c.inkMuted),
            onPressed: () => state.createNote(),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(
    BuildContext context,
    String id,
    NoteMeta? meta, {
    required String? activeId,
  }) {
    final title = (meta?.title.trim().isEmpty ?? true)
        ? _t('无题')
        : meta!.title.trim();
    final tab = _Tab(
      title: title,
      active: id == activeId,
      dragging: id == _dragId,
      onTap: () => widget.state.switchTab(id),
      onClose: () => widget.state.closeTab(id),
    );
    return KeyedSubtree(key: _keyFor(id), child: tab);
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.title,
    required this.active,
    required this.onTap,
    required this.onClose,
    this.dragging = false,
  });

  final String title;
  final bool active;
  final bool dragging;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: 5, right: 4),
      child: AnimatedScale(
        scale: dragging ? 1.02 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.only(left: 10, right: 3),
            decoration: BoxDecoration(
              color: active || dragging ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: dragging
                    ? c.accent.withValues(alpha: 0.55)
                    : active
                        ? c.line
                        : Colors.transparent,
              ),
              boxShadow: dragging
                  ? [
                      BoxShadow(
                        color: c.shadow.withValues(alpha: 0.24),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10.5,
                      color: active ? c.ink : c.inkMuted,
                    ),
                  ),
                ),
                InkWell(
                  onTap: onClose,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      LucideIcons.x,
                      size: 11,
                      color: active
                          ? c.inkMuted
                          : c.inkMuted.withValues(alpha: 0.5),
                    ),
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
