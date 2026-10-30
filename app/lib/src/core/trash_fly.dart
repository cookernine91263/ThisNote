import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// 把一张小卡片沿一条柔和的二次曲线送进左下角回收站。
class TrashFly {
  static final GlobalKey targetKey = GlobalKey();

  static Future<void> fly({
    required BuildContext context,
    required Rect from,
    required String title,
    required Future<void> Function() after,
  }) async {
    final targetBox =
        targetKey.currentContext?.findRenderObject() as RenderBox?;
    final screen = MediaQuery.sizeOf(context);
    final end = targetBox != null
        ? targetBox.localToGlobal(targetBox.size.center(Offset.zero))
        : Offset(60, screen.height - 110);
    await showGeneralDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: 'trash',
      barrierColor: Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, _, __) => _TrashFlight(
        from: from,
        to: end,
        title: title,
        onDone: () async {
          await after();
        },
        onClose: () {
          Navigator.of(dialogContext, rootNavigator: true).pop();
        },
      ),
    );
  }
}

class _TrashFlight extends StatefulWidget {
  const _TrashFlight({
    required this.from,
    required this.to,
    required this.title,
    required this.onDone,
    required this.onClose,
  });

  final Rect from;
  final Offset to;
  final String title;
  final Future<void> Function() onDone;
  final VoidCallback onClose;

  @override
  State<_TrashFlight> createState() => _TrashFlightState();
}

class _TrashFlightState extends State<_TrashFlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 640),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  late final Rect _from = widget.from;
  late final Offset _start = widget.from.center;
  late final Offset _end = widget.to;
  late final Offset _control = Offset(
    (_start.dx + _end.dx) / 2 + 26,
    math.min(_start.dy, _end.dy) - 96,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() async {
      await widget.onDone();
      if (mounted) widget.onClose();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Offset _point(double t) {
    final u = 1 - t;
    return _start * (u * u) + _control * (2 * u * t) + _end * (t * t);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return SizedBox.expand(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, _) {
            final t = _curve.value;
            final point = _point(t);
            final scale = 1 - 0.76 * Curves.easeIn.transform(t);
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: point.dx - _from.width / 2,
                  top: point.dy - _from.height / 2,
                  child: Opacity(
                    opacity: (1 - t * 0.72).clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: -0.035 + 0.07 * t,
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: _from.width.clamp(160.0, 230.0),
                          padding: const EdgeInsets.fromLTRB(13, 10, 11, 10),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: c.accent.withValues(alpha: 0.3),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: c.shadow.withValues(alpha: 0.16),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: c.accentSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Icon(
                                  LucideIcons.feather,
                                  size: 12,
                                  color: c.accent,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  widget.title.trim().isEmpty
                                      ? '无题'
                                      : widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'NotoSansSC',
                                    fontSize: 10.5,
                                    color: c.ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
