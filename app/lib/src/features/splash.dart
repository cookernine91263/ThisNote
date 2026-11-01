import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/motion.dart';
import '../core/theme.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '此记': 'ThisNote',
  '正在展开纸页': 'Unfolding the page',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class Seal extends StatelessWidget {
  const Seal({
    super.key,
    this.size = 34,
    this.radius = 9,
    this.ringColor,
  });
  final double size;
  final double radius;

  /// 印章内圈的描边色。默认取当前纸色，深浅色与自定义背景都能融进去。
  final Color? ringColor;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: Colors.transparent,
      ),
      child: CustomPaint(
        painter: _InkMarkPainter(
          ink: c.ink,
          accent: c.accent,
          ring: ringColor ?? c.paper,
        ),
        size: Size.square(size),
      ),
    );
  }
}

/// 一笔墨、一枚圆印。颜色跟随当前主题：浅色墨黑朱砂，深色米白暖红。
class _InkMarkPainter extends CustomPainter {
  _InkMarkPainter({
    required this.ink,
    required this.accent,
    required this.ring,
  });
  final Color ink;
  final Color accent;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final points = <Offset>[
      ..._cubic(
        Offset(s * 0.22, s * 0.72),
        Offset(s * 0.40, s * 0.68),
        Offset(s * 0.55, s * 0.50),
        Offset(s * 0.78, s * 0.27),
      ),
    ];
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final prev = points[i == 0 ? 0 : i - 1];
      final next = points[i == points.length - 1 ? i : i + 1];
      final tangent = next - prev;
      final length = tangent.distance < 0.001 ? 1.0 : tangent.distance;
      final normal = Offset(-tangent.dy, tangent.dx) / length;
      final t = i / (points.length - 1);
      final half = s * (0.052 * (1 - t) + 0.006 * t);
      left.add(p + normal * half);
      right.add(p - normal * half);
    }
    final brush = Path()..addPolygon(left + right.reversed.toList(), true);
    canvas.drawPath(brush, Paint()..color = ink);
    canvas.drawCircle(points.first, s * 0.052, Paint()..color = ink);
    canvas.drawCircle(
      Offset(s * 0.76, s * 0.66),
      s * 0.095,
      Paint()..color = accent,
    );
    canvas.drawCircle(
      Offset(s * 0.76, s * 0.66),
      s * 0.065,
      Paint()
        ..color = ring.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.012,
    );
  }

  List<Offset> _cubic(Offset p0, Offset p1, Offset p2, Offset p3) {
    const steps = 56;
    final result = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final u = 1 - t;
      result.add(
        p0 * (u * u * u) +
            p1 * (3 * u * u * t) +
            p2 * (3 * u * t * t) +
            p3 * (t * t * t),
      );
    }
    return result;
  }

  @override
  bool shouldRepaint(covariant _InkMarkPainter oldDelegate) =>
      oldDelegate.ink != ink ||
      oldDelegate.accent != accent ||
      oldDelegate.ring != ring;
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
                _t('此记'),
                style: TextStyle(
                  fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                  fontSize: 28,
                  fontWeight: I18n.isEn ? FontWeight.w600 : null,
                  letterSpacing: I18n.isEn ? 1.2 : 6,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _t('正在展开纸页'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 11.5,
                  letterSpacing: I18n.isEn ? 0.6 : 2,
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
