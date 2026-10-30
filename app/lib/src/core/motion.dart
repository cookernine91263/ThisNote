import 'package:flutter/material.dart';

/// 全站动效语言：短、克制、有回弹，但不喧宾夺主。
class Motion {
  static const fast = Duration(milliseconds: 160);
  static const base = Duration(milliseconds: 260);
  static const slow = Duration(milliseconds: 440);
  static const page = Duration(milliseconds: 520);
  static const breathe = Duration(milliseconds: 2400);

  static const enter = Curves.easeOutCubic;
  static const exit = Curves.easeInCubic;
  static const spring = Cubic(0.16, 1.0, 0.3, 1.0);
  static const softSpring = Cubic(0.22, 0.9, 0.24, 1.0);
}

/// 页面级淡入 + 上浮
class Reveal extends StatelessWidget {
  const Reveal({
    required this.child,
    super.key,
    this.delay = Duration.zero,
    this.duration = Motion.page,
    this.offset = 14,
  });

  final Widget child;
  final Duration delay;
  final Duration duration;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration + delay,
      curve: Interval(
        delay.inMilliseconds / (duration.inMilliseconds + delay.inMilliseconds),
        1,
        curve: Motion.enter,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, (1 - t) * offset),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 数字滚动（用于字数、统计）
class RollingNumber extends StatelessWidget {
  const RollingNumber(
    this.value, {
    super.key,
    this.style,
    this.duration = const Duration(milliseconds: 700),
    this.suffix = '',
  });

  final int value;
  final TextStyle? style;
  final Duration duration;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Motion.enter,
      builder: (context, v, _) => Text(
        '${v.round()}$suffix',
        style: style,
      ),
    );
  }
}

/// 极轻的呼吸动画，用于状态点
class BreathingDot extends StatefulWidget {
  const BreathingDot({
    required this.color,
    super.key,
    this.size = 6,
    this.active = true,
  });

  final Color color;
  final double size;
  final bool active;

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.breathe,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant BreathingDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _c.repeat(reverse: true);
      } else {
        _c.stop();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: widget.active
          ? Tween(begin: 0.35, end: 0.95).animate(
              CurvedAnimation(parent: _c, curve: Curves.easeInOut),
            )
          : const AlwaysStoppedAnimation(1),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
