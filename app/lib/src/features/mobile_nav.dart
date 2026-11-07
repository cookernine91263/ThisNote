import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../core/motion.dart';
import '../core/theme.dart';

class LiquidNavItem {
  const LiquidNavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// 手机底部导航：文字和图标钉在原位，一枚独立的强调色指示片在
/// 标签之间流动。
///
/// 指示片的左右边缘各用一条弹簧追自己的终点，前缘快、后缘慢，
/// 于是先被拉长、再收拢，收尾留一点回弹。终点取自每个标签的
/// 实际布局宽度，换语言、改字号、转屏都会重新测量；连续点击时
/// 从当前的形状和速度接着走，最后一次选择说了算。
///
/// 只用 CustomPainter 画，不叠 BackdropFilter / ImageFilter，
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
    with TickerProviderStateMixin {
  /// 指示片左右边缘的当前像素位置。
  late final AnimationController _left =
      AnimationController.unbounded(vsync: this);
  late final AnimationController _right =
      AnimationController.unbounded(vsync: this);

  // 前缘跑得快、后缘跟得慢；两者都略欠阻尼，收尾会轻轻回弹。
  static const _frontSpring = SpringDescription(
    mass: 1,
    stiffness: 380,
    damping: 28,
  );
  static const _backSpring = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 20,
  );

  final GlobalKey _stageKey = GlobalKey();
  List<GlobalKey> _itemKeys = const [];
  List<Rect> _targets = const [];

  int _targetIndex = 0;
  bool _ready = false;
  bool _measureScheduled = false;
  double? _stageWidth;
  double _stageHeight = 0;

  @override
  void initState() {
    super.initState();
    _targetIndex = widget.index;
    _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 字号、语言和主题都在这里的依赖范围内；标签宽度可能变了。
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(covariant LiquidNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _itemKeys = List.generate(widget.items.length, (_) => GlobalKey());
      _targets = const [];
      _ready = false;
      _stageWidth = null;
      _scheduleMeasure();
    }
    if (oldWidget.index != widget.index) {
      _targetIndex = widget.index;
      _animateToIndex();
    } else {
      _scheduleMeasure();
    }
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      if (mounted) _measure();
    });
  }

  /// 从真实布局读出每个标签内容的大小，再把它们换算成指示片的终点。
  void _measure() {
    final stage = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    if (stage == null || !stage.hasSize) return;
    final width = stage.size.width;
    final height = stage.size.height;
    if (width <= 0 || height <= 0 || _itemKeys.isEmpty) return;

    final origin = stage.localToGlobal(Offset.zero);
    final slot = width / widget.items.length;
    final contents = <Rect>[];
    for (final key in _itemKeys) {
      final box = key.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      contents.add((box.localToGlobal(Offset.zero) - origin) & box.size);
    }
    if (contents.isEmpty) return;

    var contentHeight = 0.0;
    for (final rect in contents) {
      contentHeight = math.max(contentHeight, rect.height);
    }
    final indicatorHeight =
        math.min(height - 10, math.max(32.0, contentHeight + 4));

    final targets = <Rect>[];
    for (final content in contents) {
      final maxWidth = math.max(24.0, slot - 8);
      final w = math.min(maxWidth, math.max(58.0, content.width + 28));
      final left = (content.center.dx - w / 2)
          .clamp(4.0, math.max(4.0, width - w - 4))
          .toDouble();
      targets.add(
        Rect.fromLTWH(
          left,
          (height - indicatorHeight) / 2,
          w,
          indicatorHeight,
        ),
      );
    }

    final changed = !_sameGeometry(_targets, targets);
    final resized = width != _stageWidth || height != _stageHeight;
    _stageWidth = width;
    _stageHeight = height;
    if (changed) {
      setState(() => _targets = targets);
    }
    if (!_ready) {
      _ready = true;
      _snapTo(targets[_targetIndex.clamp(0, targets.length - 1)]);
    } else if (changed || resized) {
      _animateToIndex();
    }
  }

  void _animateToIndex() {
    if (!_ready || _targets.isEmpty) return;
    _animateTo(_targets[_targetIndex.clamp(0, _targets.length - 1)]);
  }

  void _animateTo(Rect target) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _snapTo(target);
      return;
    }
    final dx = target.center.dx - (_left.value + _right.value) / 2;
    if (dx.abs() < 0.5) {
      _springTo(_left, target.left, _frontSpring);
      _springTo(_right, target.right, _frontSpring);
      return;
    }
    // 往哪边走，哪边的边缘就是前缘；另一边滞后一拍再跟上。
    final movingRight = dx > 0;
    _springTo(
      movingRight ? _right : _left,
      movingRight ? target.right : target.left,
      _frontSpring,
    );
    _springTo(
      movingRight ? _left : _right,
      movingRight ? target.left : target.right,
      _backSpring,
    );
  }

  void _springTo(
    AnimationController controller,
    double target,
    SpringDescription spring,
  ) {
    final value = controller.value;
    if (!value.isFinite) {
      controller.value = target;
      return;
    }
    controller.animateWith(
      SpringSimulation(spring, value, target, controller.velocity),
    );
  }

  void _snapTo(Rect target) {
    _left.value = target.left;
    _right.value = target.right;
  }

  static bool _sameGeometry(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i].left - b[i].left).abs() > 0.5 ||
          (a[i].top - b[i].top).abs() > 0.5 ||
          (a[i].width - b[i].width).abs() > 0.5 ||
          (a[i].height - b[i].height).abs() > 0.5) {
        return false;
      }
    }
    return true;
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
            if (constraints.maxWidth != _stageWidth) _scheduleMeasure();
            return Stack(
              key: _stageKey,
              children: [
                if (_ready && _targets.isNotEmpty)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _LiquidIndicatorPainter(
                          left: _left,
                          right: _right,
                          height: _targets.first.height,
                          slotWidth: constraints.maxWidth / widget.items.length,
                          widest: _targets
                              .map((r) => r.width)
                              .reduce(math.max),
                          fill: c.accentSoft,
                          stroke: c.accent.withValues(alpha: 0.2),
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
                              child: Center(
                                child: _NavItem(
                                  key: _itemKeys[i],
                                  item: widget.items[i],
                                  selected: widget.index == i,
                                ),
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
    super.key,
    required this.item,
    required this.selected,
  });

  final LiquidNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: selected ? 1 : 0),
      duration: Motion.fast,
      curve: Motion.enter,
      builder: (context, t, _) {
        final color = Color.lerp(c.inkMuted, c.accent, t)!;
        return Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 18, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: color,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LiquidIndicatorPainter extends CustomPainter {
  _LiquidIndicatorPainter({
    required this.left,
    required this.right,
    required this.height,
    required this.slotWidth,
    required this.widest,
    required this.fill,
    required this.stroke,
  }) : super(repaint: Listenable.merge([left, right]));

  final Animation<double> left;
  final Animation<double> right;
  final double height;
  final double slotWidth;
  final double widest;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (height <= 0 || size.width <= 0) return;
    const inset = 3.0;
    var l = left.value;
    var r = right.value;
    if (!l.isFinite || !r.isFinite) return;
    l = l.clamp(inset, size.width - inset);
    r = r.clamp(inset, size.width - inset);
    if (r < l) {
      final swap = l;
      l = r;
      r = swap;
    }

    // 跨多个标签时也把拉长收在约一格出头，别扫过邻格的文字。
    final limit = math.min(
      size.width - inset * 2,
      math.max(slotWidth * 1.15, widest * 2.2),
    );
    if (r - l > limit) {
      final mid = (l + r) / 2;
      l = mid - limit / 2;
      r = mid + limit / 2;
    }

    final top = (size.height - height) / 2;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTRB(l, top, r, top + height),
      Radius.circular(height / 2),
    );
    canvas.drawRRect(capsule, Paint()..color = fill);
    canvas.drawRRect(
      capsule,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidIndicatorPainter oldDelegate) =>
      oldDelegate.height != height ||
      oldDelegate.slotWidth != slotWidth ||
      oldDelegate.widest != widest ||
      oldDelegate.fill != fill ||
      oldDelegate.stroke != stroke;
}
