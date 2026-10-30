import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme.dart';

/// 纸张颗粒：非常轻的噪点，让纯色背景有纸的触感。
class PaperGrain extends StatelessWidget {
  const PaperGrain({required this.color, this.opacity = 0.05, super.key});

  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GrainPainter(color.withValues(alpha: opacity)),
        size: Size.infinite,
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(20261030);
    final paint = Paint()..color = color;
    final count = (size.width * size.height / 2200).clamp(250, 2400).toInt();
    for (var i = 0; i < count; i++) {
      final x = rnd.nextDouble() * size.width;
      final y = rnd.nextDouble() * size.height;
      final r = rnd.nextDouble() < 0.82 ? 0.55 : 1.05;
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) => old.color != color;
}

/// 纸面卡片：发丝边 + 极浅阴影 + 可选颗粒
class PaperSurface extends StatelessWidget {
  const PaperSurface({
    required this.child,
    super.key,
    this.padding,
    this.margin,
    this.radius = Radii.lg,
    this.color,
    this.borderColor,
    this.shadow = true,
    this.grain = true,
    this.clip = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final Color? color;
  final Color? borderColor;
  final bool shadow;
  final bool grain;
  final bool clip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final bg = color ?? c.surface;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? c.line, width: 1),
        boxShadow: shadow
            ? [
                BoxShadow(
                  color: c.shadow.withValues(alpha: c.isDark ? 0.22 : 0.055),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: c.shadow.withValues(alpha: c.isDark ? 0.12 : 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (grain) Positioned.fill(child: PaperGrain(color: c.ink, opacity: c.grain)),
          child,
        ],
      ),
    );
    final wrapped = onTap == null
        ? content
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: content),
          );
    return margin == null ? wrapped : Padding(padding: margin!, child: wrapped);
  }
}

/// 监听 hover，并把进度交给 builder。
class HoverBuilder extends StatefulWidget {
  const HoverBuilder({
    required this.builder,
    super.key,
    this.cursor = SystemMouseCursors.click,
  });

  final Widget Function(BuildContext context, bool hovered, double t) builder;
  final MouseCursor cursor;

  @override
  State<HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<HoverBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.fast,
    value: 0,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _c.forward(),
      onExit: (_) => _c.reverse(),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => widget.builder(context, _c.value > 0.5, _c.value),
      ),
    );
  }
}

class SoftIconButton extends StatelessWidget {
  const SoftIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.tooltip,
    this.active = false,
    this.size = 32,
    this.iconSize = 18,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final bool active;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final button = HoverBuilder(
      builder: (context, hovered, t) {
        final bg = active
            ? c.accentSoft
            : hovered
                ? c.surfaceAlt
                : Colors.transparent;
        final fg = color ??
            (active ? c.accent : (hovered ? c.ink : c.inkSoft));
        return AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.enter,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(size * 0.3),
          ),
          child: Icon(icon, size: iconSize, color: fg),
        );
      },
    );
    return Tooltip(
      message: tooltip ?? '',
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          onTap: onPressed,
          behavior: HitTestBehavior.opaque,
          child: MouseRegion(
            cursor: onPressed == null
                ? SystemMouseCursors.basic
                : SystemMouseCursors.click,
            child: Opacity(opacity: onPressed == null ? 0.38 : 1, child: button),
          ),
        ),
      ),
    );
  }
}

/// 带文字的轻按钮
class SoftButton extends StatelessWidget {
  const SoftButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.active = false,
    this.primary = false,
    this.dense = false,
    this.tooltip,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool active;
  final bool primary;
  final bool dense;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final child = HoverBuilder(
      builder: (context, hovered, t) {
        final bg = primary
            ? (hovered ? c.accent : c.ink)
            : active
                ? c.accentSoft
                : hovered
                    ? c.surfaceAlt
                    : Colors.transparent;
        final fg = primary
            ? c.onAccent
            : active
                ? c.accent
                : c.inkSoft;
        final borderColor = primary
            ? Colors.transparent
            : active
                ? c.accent.withValues(alpha: 0.28)
                : hovered
                    ? c.line
                    : Colors.transparent;
        return AnimatedContainer(
          duration: Motion.fast,
          height: dense ? 30 : 36,
          padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 13),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(dense ? 8 : 10),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: dense ? 14 : 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: dense ? 12 : 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ],
          ),
        );
      },
    );
    final t = Tooltip(message: tooltip ?? '', child: child);
    if (onPressed == null) return Opacity(opacity: 0.4, child: t);
    return GestureDetector(onTap: onPressed, child: t);
  }
}

class Kbd extends StatelessWidget {
  const Kbd(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: c.line),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 10,
          height: 1.2,
          color: c.inkMuted,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing, this.padding});

  final String text;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: padding ?? const EdgeInsets.only(left: 4, right: 4, bottom: 10),
      child: Row(
        children: [
          Text(
            text,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 11,
              letterSpacing: 1.6,
              color: c.inkMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({
    required this.label,
    super.key,
    this.selected = false,
    this.onTap,
    this.onDelete,
    this.count,
    this.dense = true,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final int? count;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      cursor: onTap == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 9 : 12,
              vertical: dense ? 5 : 7,
            ),
            decoration: BoxDecoration(
              color: selected
                  ? c.accentSoft
                  : hovered
                      ? c.surfaceAlt
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: selected ? c.accent.withValues(alpha: 0.3) : c.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '# $label',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: dense ? 11.5 : 12.5,
                    color: selected ? c.accent : c.inkSoft,
                    height: 1.2,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 5),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10,
                      color: selected ? c.accent : c.inkMuted,
                    ),
                  ),
                ],
                if (onDelete != null) ...[
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onDelete,
                    child: Icon(Icons.close_rounded, size: 11, color: c.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class StatusDot extends StatelessWidget {
  const StatusDot({required this.color, this.active = false, super.key});
  final Color color;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return BreathingDot(color: color, active: active, size: 5.5);
  }
}

class Dot extends StatelessWidget {
  const Dot({this.size = 3, this.color, super.key});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color ?? AppPalette.of(context).inkMuted,
          shape: BoxShape.circle,
        ),
      );
}

/// 空状态的小插画：一圈淡墨 + 一支停顿的笔
class InkEmpty extends StatelessWidget {
  const InkEmpty({this.size = 132, super.key});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return SizedBox(
      width: size,
      height: size * 0.78,
      child: CustomPaint(painter: _InkPainter(c.inkMuted, c.accent)),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter(this.ink, this.accent);
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = ink.withValues(alpha: 0.35);
    canvas.drawCircle(center.translate(-8, 0), size.height * 0.33, paint);
    final wash = Paint()
      ..color = ink.withValues(alpha: 0.045)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center.translate(-8, 0), size.height * 0.3, wash);
    final pen = Paint()
      ..color = accent.withValues(alpha: 0.75)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final start = center.translate(size.width * 0.22, -size.height * 0.22);
    canvas.drawLine(start, start.translate(size.width * 0.12, size.height * 0.16), pen);
    canvas.drawCircle(start, 2.1, pen..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(covariant _InkPainter old) =>
      old.ink != ink || old.accent != accent;
}

Future<void> showToast(BuildContext context, String message, {IconData? icon}) async {
  final c = AppPalette.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 2),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.paper),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              message,
              style: TextStyle(fontFamily: 'NotoSansSC', color: c.paper, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool danger = false,
}) async {
  final c = AppPalette.of(context);
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: c.surface,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 6),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      title: Text(
        title,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 17,
          fontWeight: FontWeight.w600,
          color: c.ink,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 13.5,
          height: 1.6,
          color: c.inkSoft,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel, style: TextStyle(color: c.inkMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? c.danger : c.ink,
            foregroundColor: c.paper,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
