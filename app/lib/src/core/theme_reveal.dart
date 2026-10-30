import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 主题切换时从触点向外扩散的“圆孔”揭示。
/// 先截下旧主题，再切主题，让旧截图只在圆外可见；文字不缩放，只改变可见区域。
class ThemeReveal {
  static final GlobalKey rootKey = GlobalKey();
  static bool _busy = false;

  static Future<void> reveal({
    required BuildContext context,
    required Offset globalOrigin,
    required Future<void> Function() apply,
  }) async {
    if (_busy) {
      await apply();
      return;
    }
    _busy = true;
    try {
      final object = rootKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) {
        await apply();
        return;
      }
      final localOrigin = object.globalToLocal(globalOrigin);
      final size = object.size;
      ui.Image? image;
      try {
        image = await object.toImage(pixelRatio: 1);
      } catch (_) {
        image = null;
      }
      if (image == null) {
        await apply();
        return;
      }
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) {
        await apply();
        return;
      }
      await apply();
      // 等新主题真正画出一帧，再让旧截图下面透出新主题。
      await Future<void>.delayed(const Duration(milliseconds: 24));
      if (!context.mounted) return;
      await showGeneralDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        barrierLabel: 'theme',
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        pageBuilder: (context, _, __) => _RevealLayer(
          bytes: data.buffer.asUint8List(),
          origin: localOrigin,
          size: size,
        ),
      );
    } finally {
      _busy = false;
    }
  }
}

class _RevealLayer extends StatefulWidget {
  const _RevealLayer({
    required this.bytes,
    required this.origin,
    required this.size,
  });
  final Uint8List bytes;
  final Offset origin;
  final Size size;

  @override
  State<_RevealLayer> createState() => _RevealLayerState();
}

class _RevealLayerState extends State<_RevealLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 680),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  late final double _maxDistanceSquared = _distanceSquaredToCover();

  double _distanceSquaredToCover() {
    final w = widget.size.width;
    final h = widget.size.height;
    final o = widget.origin;
    final dx = o.dx < w - o.dx ? w - o.dx : o.dx;
    final dy = o.dy < h - o.dy ? h - o.dy : o.dy;
    return dx * dx + dy * dy;
  }

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curve,
      builder: (context, _) {
        final radius = 4 + math.sqrt(_maxDistanceSquared) * _curve.value;
        return ClipPath(
          clipper: _HoleClipper(center: widget.origin, radius: radius),
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.fill,
            width: widget.size.width,
            height: widget.size.height,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        );
      },
    );
  }
}

class _HoleClipper extends CustomClipper<Path> {
  _HoleClipper({required this.center, required this.radius});
  final Offset center;
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(Rect.fromCircle(center: center, radius: radius))
      ..fillType = PathFillType.evenOdd;
    return path;
  }

  @override
  bool shouldReclip(covariant _HoleClipper oldClipper) =>
      oldClipper.radius != radius || oldClipper.center != center;
}


