import 'package:flutter/material.dart';

import '../core/motion.dart';
import '../core/theme.dart';

class Seal extends StatelessWidget {
  const Seal({super.key, this.size = 34, this.radius = 9});
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.accent,
            Color.lerp(c.accent, Colors.black, 0.18)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.24),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _SealPainter(accent: c.accent),
        size: Size.square(size),
      ),
    );
  }
}

/// 一枚纸页、一笔墨、一方小印。
/// 不依赖某个汉字字形，缩小到 21px 仍然能读出“写下”的动作。
class _SealPainter extends CustomPainter {
  _SealPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final r = s * 0.075;
    final page = Path()
      ..moveTo(s * 0.245, s * 0.175)
      ..lineTo(s * 0.635, s * 0.175)
      ..lineTo(s * 0.775, s * 0.315)
      ..lineTo(s * 0.775, s * 0.785)
      ..quadraticBezierTo(s * 0.775, s * 0.82, s * 0.74, s * 0.82)
      ..lineTo(s * 0.275, s * 0.82)
      ..quadraticBezierTo(s * 0.24, s * 0.82, s * 0.24, s * 0.785)
      ..lineTo(s * 0.24, s * 0.21)
      ..quadraticBezierTo(s * 0.24, s * 0.175, s * 0.275, s * 0.175)
      ..close();

    final paper = Paint()..color = const Color(0xFFFFF8EA);
    canvas.drawPath(page, paper);

    final fold = Path()
      ..moveTo(s * 0.635, s * 0.175)
      ..lineTo(s * 0.775, s * 0.315)
      ..lineTo(s * 0.635, s * 0.315)
      ..close();
    canvas.drawPath(fold, Paint()..color = const Color(0xFFE8D9C2));
    canvas.drawPath(
      fold,
      Paint()
        ..color = const Color(0xFF211E19).withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.008,
    );

    final ink = const Color(0xFF211E19);
    final brushPoints = <Offset>[
      ..._cubic(
        Offset(s * 0.30, s * 0.665),
        Offset(s * 0.40, s * 0.64),
        Offset(s * 0.47, s * 0.56),
        Offset(s * 0.55, s * 0.49),
      ),
      ..._cubic(
        Offset(s * 0.55, s * 0.49),
        Offset(s * 0.61, s * 0.44),
        Offset(s * 0.66, s * 0.38),
        Offset(s * 0.70, s * 0.31),
      ).skip(1),
    ];
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < brushPoints.length; i++) {
      final p = brushPoints[i];
      final prev = brushPoints[i == 0 ? 0 : i - 1];
      final next =
          brushPoints[i == brushPoints.length - 1 ? i : i + 1];
      final tangent = next - prev;
      final length = tangent.distance < 0.001 ? 1.0 : tangent.distance;
      final normal = Offset(-tangent.dy, tangent.dx) / length;
      final t = i / (brushPoints.length - 1);
      final half = s * (0.045 * (1 - t) + 0.007 * t);
      left.add(p + normal * half);
      right.add(p - normal * half);
    }
    final brushPolygon = Path()..addPolygon(left + right.reversed.toList(), true);
    canvas.drawPath(brushPolygon, Paint()..color = ink);
    canvas.drawCircle(
      brushPoints.first,
      s * 0.045,
      Paint()..color = ink,
    );
    canvas.drawCircle(
      brushPoints.last,
      s * 0.007,
      Paint()..color = ink,
    );
    canvas.drawCircle(
      Offset(s * 0.285, s * 0.675),
      s * 0.022,
      Paint()..color = ink,
    );

    final sealRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(s * 0.615, s * 0.615, s * 0.17, s * 0.17),
      Radius.circular(s * 0.018),
    );
    canvas.drawRRect(sealRect, Paint()..color = ink);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.637, s * 0.637, s * 0.126, s * 0.126),
        Radius.circular(s * 0.008),
      ),
      Paint()
        ..color = const Color(0xFFFFF8EA).withValues(alpha: 0.7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.009,
    );
    canvas.drawCircle(
      Offset(s * 0.700, s * 0.700),
      s * 0.022,
      Paint()..color = const Color(0xFFFFF8EA).withValues(alpha: 0.86),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.015, s * 0.015, s - s * 0.03, s - s * 0.03),
        Radius.circular(r),
      ),
      Paint()
        ..color = const Color(0xFFFFF8EA).withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012,
    );
  }

  List<Offset> _cubic(Offset p0, Offset p1, Offset p2, Offset p3) {
    const steps = 48;
    return [
      for (var i = 0; i <= steps; i++)
        () {
          final t = i / steps;
          final u = 1 - t;
          return p0 * (u * u * u) +
              p1 * (3 * u * u * t) +
              p2 * (3 * u * t * t) +
              p3 * (t * t * t);
        }(),
    ];
  }

  @override
  bool shouldRepaint(covariant _SealPainter oldDelegate) =>
      oldDelegate.accent != accent;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final curve = CurvedAnimation(parent: _c, curve: Motion.spring);
    return Scaffold(
      backgroundColor: c.paper,
      body: Center(
        child: FadeTransition(
          opacity: _c,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ScaleTransition(
                scale: Tween(begin: 0.82, end: 1.0).animate(curve),
                child: const Seal(size: 56, radius: 15),
              ),
              const SizedBox(height: 22),
              Text(
                '此记',
                style: TextStyle(
                  fontFamily: 'WenKai',
                  fontSize: 28,
                  letterSpacing: 6,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正在展开纸页',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 11.5,
                  letterSpacing: 2,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
