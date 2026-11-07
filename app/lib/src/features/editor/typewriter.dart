import 'package:flutter/material.dart';

import '../../state/app_state.dart';

/// 打字机模式：光标始终停在视口中间，文字像从打字机里推出来。
///
/// 只移动滚动位置，不改文档；用户自己滚动后短暂让出控制权，
/// 避免和惯性滚动打架。
class TypewriterScroll extends StatefulWidget {
  const TypewriterScroll({
    required this.session,
    required this.enabled,
    required this.child,
    super.key,
  });

  final EditorSession session;
  final bool enabled;
  final Widget child;

  @override
  State<TypewriterScroll> createState() => _TypewriterScrollState();
}

class _TypewriterScrollState extends State<TypewriterScroll> {
  DateTime _manualScrollAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _programmatic = false;

  @override
  void initState() {
    super.initState();
    widget.session.addListener(_scheduleCenter);
    widget.session.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant TypewriterScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session.removeListener(_scheduleCenter);
      oldWidget.session.scrollController.removeListener(_onScroll);
      widget.session.addListener(_scheduleCenter);
      widget.session.scrollController.addListener(_onScroll);
    }
    if (widget.enabled && !oldWidget.enabled) _scheduleCenter();
  }

  @override
  void dispose() {
    widget.session.removeListener(_scheduleCenter);
    widget.session.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!_programmatic) _manualScrollAt = DateTime.now();
  }

  void _scheduleCenter() {
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _center());
  }

  void _center() {
    if (!mounted || !widget.enabled) return;
    if (!widget.session.editorFocus.hasFocus) return;
    if (DateTime.now().difference(_manualScrollAt) <
        const Duration(milliseconds: 380)) {
      return;
    }
    final render = widget.session.editorKey.currentState?.renderEditor;
    final scroll = widget.session.scrollController;
    if (render == null || !scroll.hasClients) return;
    final selection = widget.session.controller.selection;
    if (!selection.isValid) return;
    final offset = selection.extentOffset
        .clamp(0, widget.session.controller.document.length);
    final caret = render.getLocalRectForCaret(TextPosition(offset: offset));
    final viewport = scroll.position.viewportDimension;
    final target = (caret.center.dy - viewport / 2)
        .clamp(0.0, scroll.position.maxScrollExtent);
    if ((target - scroll.offset).abs() < 2) return;
    _programmatic = true;
    scroll.jumpTo(target);
    _programmatic = false;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}