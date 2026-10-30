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
        color: c.accent,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: c.accent.withValues(alpha: 0.22),
            blurRadius: size * 0.35,
            offset: Offset(0, size * 0.12),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '记',
        style: TextStyle(
          fontFamily: 'WenKai',
          fontSize: size * 0.6,
          height: 1,
          color: c.onAccent,
        ),
      ),
    );
  }
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
