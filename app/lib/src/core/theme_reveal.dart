import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

/// 主题切换时从触点向外扩散的“圆孔”揭示。
///
/// 顺序是这套动效的全部关键：
/// 1. 先截下旧主题；
/// 2. 旧截图立刻整屏盖住（此时画面和点击前完全一样）；
/// 3. 在旧截图下面换主题；
/// 4. 等新主题在下面画好，圆孔才开始从触点扩散。
///
/// 一旦顺序反过来（先换主题、再盖截图），用户就会看到主题已经切过去了，
/// 紧接着整屏又跳回旧主题，把同一段动画重放一遍。
class ThemeReveal {
  ThemeReveal._();

  static final GlobalKey rootKey = GlobalKey();

  /// 揭示进行中：这段时间关掉 MaterialApp 自带的主题过渡，
  /// 让圆孔里透出来的是已经就位的新主题，而不是还在渐变的颜色。
  static final ValueNotifier<bool> revealing = ValueNotifier<bool>(false);

  static final ValueNotifier<_Shot?> _shot = ValueNotifier<_Shot?>(null);
  static bool _busy = false;

  /// 盖在 Navigator 之上的一层，放在 MaterialApp.builder 的 Stack 里。
  static Widget overlay() => const _RevealOverlay();

  static Future<void> reveal({
    required BuildContext context,
    required Offset globalOrigin,
    required Future<void> Function() apply,
  }) async {
    if (_busy) {
      // 上一次揭示还在扩散：直接换主题，不再叠一层截图。
      await apply();
      return;
    }
    _busy = true;
    _Shot? shot;
    try {
      final object = rootKey.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) {
        await apply();
        return;
      }
      final size = object.size;
      final origin = object.globalToLocal(globalOrigin);
      final ratio =
          (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0).clamp(1.0, 2.0);
      ui.Image? image;
      try {
        image = await object.toImage(pixelRatio: ratio);
      } catch (_) {
        image = null;
      }
      if (image == null) {
        await apply();
        return;
      }
      shot = _Shot(image: image, origin: origin, size: size);

      // 旧截图先铺满整屏，这一帧之后用户看到的还是切换前的画面。
      _shot.value = shot;
      revealing.value = true;
      final covered = await _nextFrame();

      // 旧截图已经挡住整屏，这时候换主题不会被看见。
      await apply();
      final ready = covered && await _nextFrame();

      if (!ready || !identical(_shot.value, shot)) return;
      shot.start();
      await shot.done;
    } finally {
      if (shot != null) {
        if (identical(_shot.value, shot)) _shot.value = null;
        shot.finish();
        revealing.value = false;
        shot.dispose();
      }
      _busy = false;
    }
  }

  /// 等一帧画完。窗口不渲染（最小化、被系统节流）时宁可放弃动效，
  /// 也不能让旧截图永久压在上面。
  static Future<bool> _nextFrame() async {
    try {
      await SchedulerBinding.instance.endOfFrame
          .timeout(const Duration(seconds: 1));
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

/// 一次揭示所需的数据：旧主题截图 + 触点在截图坐标系里的位置。
class _Shot {
  _Shot({required this.image, required this.origin, required this.size})
      : reachSquared = _reachSquared(origin, size);

  final ui.Image image;
  final Offset origin;
  final Size size;

  /// 圆心到最远一角的距离平方，用来算扩散终点。
  final double reachSquared;

  final Completer<void> _gate = Completer<void>();
  final Completer<void> _done = Completer<void>();

  /// 旧截图已经铺满，可以开始扩散。
  Future<void> get started => _gate.future;

  /// 扩散结束，旧截图可以撤掉了。
  Future<void> get done => _done.future;

  void start() {
    if (!_gate.isCompleted) _gate.complete();
  }

  void finish() {
    if (!_done.isCompleted) _done.complete();
  }

  void dispose() => image.dispose();

  static double _reachSquared(Offset origin, Size size) {
    final dx = math.max(origin.dx, size.width - origin.dx);
    final dy = math.max(origin.dy, size.height - origin.dy);
    return dx * dx + dy * dy;
  }
}

class _RevealOverlay extends StatefulWidget {
  const _RevealOverlay();

  @override
  State<_RevealOverlay> createState() => _RevealOverlayState();
}

class _RevealOverlayState extends State<_RevealOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 680);

  _Shot? _current;
  double _reachSquared = 1;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
  );
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );

  @override
  void initState() {
    super.initState();
    ThemeReveal._shot.addListener(_onShotChanged);
    _attach(ThemeReveal._shot.value);
  }

  @override
  void dispose() {
    ThemeReveal._shot.removeListener(_onShotChanged);
    // 图层被提前拆掉时也要让等待的一方继续，免得 reveal 永远挂着。
    _current?.finish();
    _curve.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onShotChanged() {
    final next = ThemeReveal._shot.value;
    if (identical(next, _current)) return;
    setState(() => _attach(next));
  }

  void _attach(_Shot? next) {
    _current = next;
    if (next == null) {
      _controller.stop();
      return;
    }
    _reachSquared = next.reachSquared;
    _controller.value = 0;
    next.started.then((_) {
      if (!mounted || !identical(_current, next)) return;
      _controller.forward(from: 0).whenComplete(() {
        if (!mounted || !identical(_current, next)) return;
        // 先撤旧截图（同帧内不再绘制它），再放开等待 reveal 的一方。
        ThemeReveal._shot.value = null;
        next.finish();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final shot = _current;
    if (shot == null) return const SizedBox.shrink();
    return Positioned.fill(
      child: AbsorbPointer(
        child: AnimatedBuilder(
          animation: _curve,
          builder: (context, child) => ClipPath(
            clipper: _HoleClipper(
              center: shot.origin,
              radius: math.sqrt(_reachSquared) * _curve.value,
            ),
            child: child,
          ),
          child: RawImage(
            image: shot.image,
            width: shot.size.width,
            height: shot.size.height,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.low,
          ),
        ),
      ),
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
