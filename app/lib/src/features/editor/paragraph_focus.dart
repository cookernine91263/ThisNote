import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/app_state.dart';

/// 段落聚焦：只把当前段落留在纸上，其余文字用纸色轻轻盖住。
///
/// 遮罩是纯几何绘制，不修改文档；图片、代码块也能落在同一套坐标里。
class ParagraphFocusOverlay extends StatelessWidget {
  const ParagraphFocusOverlay({
    required this.session,
    required this.paper,
    super.key,
  });

  final EditorSession session;
  final Color paper;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: Listenable.merge([
          session,
          session.scrollController,
        ]),
        builder: (context, _) {
          final scroll = session.scrollController.hasClients
              ? session.scrollController.offset
              : 0.0;
          return CustomPaint(
            painter: _ParagraphFocusPainter(
              session: session,
              paper: paper,
              revision: session.revision,
              selectionOffset: session.controller.selection.extentOffset,
              scrollOffset: scroll,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ParagraphFocusPainter extends CustomPainter {
  _ParagraphFocusPainter({
    required this.session,
    required this.paper,
    required this.revision,
    required this.selectionOffset,
    required this.scrollOffset,
  });

  final EditorSession session;
  final Color paper;
  final int revision;
  final int selectionOffset;
  final double scrollOffset;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final render = session.editorKey.currentState?.renderEditor;
    if (render == null) return;
    final text = session.plainText;
    final length = text.length;
    final offset = selectionOffset.clamp(0, length);
    final start = offset <= 0 ? 0 : _lastNewline(text, offset - 1) + 1;
    var end = text.indexOf('\n', offset);
    if (end < 0) end = length;
    final caretEnd = math.max(start, math.min(end, length) - 1);
    final startRect = render.getLocalRectForCaret(TextPosition(offset: start));
    final endRect = render.getLocalRectForCaret(TextPosition(offset: caretEnd));
    final top = math.min(startRect.top, endRect.top) - scrollOffset;
    final bottom = math.max(startRect.bottom, endRect.bottom) - scrollOffset;
    if (bottom <= 0 || top >= size.height) return;

    final paint = Paint()..color = paper.withValues(alpha: 0.82);
    final upper = Rect.fromLTRB(0, 0, size.width, top.clamp(0.0, size.height));
    final lower = Rect.fromLTRB(
      0,
      bottom.clamp(0.0, size.height),
      size.width,
      size.height,
    );
    if (upper.height > 0) canvas.drawRect(upper, paint);
    if (lower.height > 0) canvas.drawRect(lower, paint);
  }

  int _lastNewline(String text, int from) {
    for (var i = from; i >= 0; i--) {
      if (text.codeUnitAt(i) == 10) return i;
    }
    return -1;
  }

  @override
  bool shouldRepaint(covariant _ParagraphFocusPainter old) =>
      old.revision != revision ||
      old.selectionOffset != selectionOffset ||
      old.scrollOffset != scrollOffset ||
      old.paper != paper;
}