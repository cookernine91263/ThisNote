import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';

class LiquidNavItem {
  const LiquidNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 手机底部导航：一枚会「流动」的强调色胶囊在 tab 之间弹过去。
///
/// 只用 CustomPainter 画并集形状，不叠 BackdropFilter / ImageFilter，
/// 低端机上也不会因为每帧 saveLayer 掉帧。
class LiquidNavBar extends StatefulWidget {
  const LiquidNavBar({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });

  final List<LiquidNavItem> items;
  final int index;
  final ValueChanged<int> onTap;

  @override
  State<LiquidNavBar> createState() => _LiquidNavBarState();
}

class _LiquidNavBarState extends State<LiquidNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _move = AnimationController.unbounded(
    vsync: this,
    value: widget.index.toDouble(),
  );

  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 26,
  );

  @override
  void didUpdateWidget(covariant LiquidNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      final target = widget.index.toDouble();
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _move.value = target;
      } else {
        _move.animateWith(
          SpringSimulation(_spring, _move.value, target, _move.velocity),
        );
      }
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  void _tap(int index) {
    if (index == widget.index) return;
    HapticFeedback.selectionClick();
    widget.onTap(index);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.line)),
      ),
      padding: EdgeInsets.only(top: 6, bottom: bottom + 6),
      child: SizedBox(
        height: 50,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                Positioned.fill(
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: _LiquidPainter(
                        move: _move,
                        count: widget.items.length,
                        soft: c.accentSoft,
                        accent: c.accent.withValues(alpha: 0.22),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < widget.items.length; i++)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: widget.index == i,
                          label: widget.items[i].label,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _tap(i),
                            child: ExcludeSemantics(
                              child: _NavItem(
                                item: widget.items[i],
                                selected: widget.index == i,
                                move: _move,
                                index: i,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.item,
    required this.selected,
    required this.move,
    required this.index,
  });

  final LiquidNavItem item;
  final bool selected;
  final Animation<double> move;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return AnimatedBuilder(
      animation: move,
      builder: (context, _) {
        final distance = (move.value - index).abs().clamp(0.0, 1.0);
        final color = Color.lerp(c.accent, c.inkMuted, distance)!;
        final scale = 1.0 + 0.08 * (1 - distance);
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: Icon(item.icon, size: 18, color: color),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiquidPainter extends CustomPainter {
  _LiquidPainter({
    required this.move,
    required this.count,
    required this.soft,
    required this.accent,
  }) : super(repaint: move);

  final Animation<double> move;
  final int count;
  final Color soft;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    if (count <= 0) return;
    final segment = size.width / count;
    final y = size.height / 2;
    final t = move.value.clamp(0.0, (count - 1).toDouble());
    final x = (t + 0.5) * segment;

    // 速度越大，拖尾越远、胶囊越扁，看起来像被「拉」过去。
    final speed = move is AnimationController
        ? (move as AnimationController).velocity.abs()
        : 0.0;
    final pull = math.min(18.0, speed * 2.4);
    final stretch = math.min(7.0, speed * 1.4);
    final sign = (move is AnimationController &&
            (move as AnimationController).velocity < 0)
        ? -1.0
        : 1.0;
    final trailX = (x - sign * pull).clamp(segment * 0.3, size.width - segment * 0.3);
    final halfW = 22.0 + stretch;
    const halfH = 14.0;

    final fill = Paint()..color = soft;
    if ((trailX - x).abs() > 2) {
      canvas.drawLine(
        Offset(x, y),
        Offset(trailX, y),
        Paint()
          ..color = soft
          ..strokeWidth = 18
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(Offset(trailX, y), 12, fill);
    }
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(x, y), width: halfW * 2, height: halfH * 2),
      const Radius.circular(14),
    );
    canvas.drawRRect(rect, fill);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) =>
      oldDelegate.count != count ||
      oldDelegate.soft != soft ||
      oldDelegate.accent != accent;
}
