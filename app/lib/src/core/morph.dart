import 'package:flutter/material.dart';

/// 页面切换的「平滑」。
///
/// 和 PPT 的「平滑」一个思路：新旧两块内容里标签相同的元素认作同一个，
/// 旧元素直接从原来的位置、尺寸飞向新位置，到站后再把内容换成新的一份；
/// 认不出对应关系的元素各自淡出、淡入。
class MorphSwitcher extends StatefulWidget {
  const MorphSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 460),
    this.curve = Curves.easeInOutCubic,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  State<MorphSwitcher> createState() => _MorphSwitcherState();
}

class _MorphSwitcherState extends State<MorphSwitcher>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late final _MorphSession _session = _MorphSession(_controller, widget.curve);

  Widget? _outgoing;

  @override
  void didUpdateWidget(covariant MorphSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.child.key == widget.child.key) return;

    if (_session.running || _session.pending) {
      // 上一段还没跑完就又切了：直接收尾，从眼下这页重新开始。
      _session.finish();
      _outgoing = null;
    }

    final leaving = _session.keys[_session.inSlot]!.keys.toSet();
    _session.begin(leaving);
    setState(() {
      _outgoing = oldWidget.child;
      _session.keys[_session.inSlot] = {};
    });

    // 等这一帧把新页面摆好、量到位置之后再起飞。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(_session.start);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outgoing = _outgoing;
    // 新页面放在上面：飞进来的元素是新的内容，得压住旧页面上正在淡出的东西。
    return IgnorePointer(
      ignoring: _session.running,
      child: Stack(
        key: _session.rootKey,
        fit: StackFit.expand,
        children: [
          if (outgoing != null)
            Positioned.fill(
              key: outgoing.key ?? ObjectKey(outgoing),
              child: _MorphScope(
                session: _session,
                slot: _session.outSlot,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: outgoing,
                  builder: (context, child) => Opacity(
                    opacity: _session.pageOpacity(outgoing: true),
                    child: child,
                  ),
                ),
              ),
            ),
          Positioned.fill(
            key: widget.child.key ?? ObjectKey(widget.child),
            child: _MorphScope(
              session: _session,
              slot: _session.inSlot,
              child: AnimatedBuilder(
                animation: _controller,
                child: widget.child,
                builder: (context, child) => Opacity(
                  opacity: _session.pageOpacity(outgoing: false),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Phase { idle, pending, morph, crossFade }

class _MorphSession {
  _MorphSession(this.controller, this.curve);

  final AnimationController controller;
  final Curve curve;
  final GlobalKey rootKey = GlobalKey();

  /// 每个槽位里注册的块：标签 -> 测量用的 key。
  final Map<String, Map<String, GlobalKey>> keys = {'a': {}, 'b': {}};
  String outSlot = 'a';
  String inSlot = 'b';

  Set<String> _leaving = {};
  Set<String> _paired = {};
  _Phase _phase = _Phase.idle;

  bool get running => _phase == _Phase.morph || _phase == _Phase.crossFade;
  bool get pending => _phase == _Phase.pending;

  void begin(Set<String> leaving) {
    _leaving = leaving;
    _paired = {};
    _phase = _Phase.pending;
    outSlot = inSlot;
    inSlot = inSlot == 'a' ? 'b' : 'a';
    controller.value = 0;
  }

  void start() {
    if (_phase != _Phase.pending) return;
    _paired = _leaving.where(keys[inSlot]!.containsKey).toSet();
    _phase = _paired.isEmpty ? _Phase.crossFade : _Phase.morph;
    controller
      ..value = 0
      ..forward();
  }

  void finish() {
    _phase = _Phase.idle;
    _paired = {};
    _leaving = {};
    controller
      ..stop()
      ..value = 0;
  }

  bool isOutgoing(String slot) => slot == outSlot;

  double get _t => curve.transform(controller.value.clamp(0.0, 1.0));

  double pageOpacity({required bool outgoing}) {
    switch (_phase) {
      case _Phase.idle:
        return 1;
      case _Phase.pending:
        // 新页面先别露头，这一帧看到的还是旧页面，不会闪。
        return outgoing ? 1 : 0;
      case _Phase.crossFade:
        final t = _t;
        return outgoing ? 1 - _ramp(t, 0, 0.5) : _ramp(t, 0.18, 0.72);
      case _Phase.morph:
        return 1;
    }
  }

  /// 这一对块值不值得飞过去：标签要对上，尺寸也不能差太多。
  bool _canFly(String tag) {
    if (!_paired.contains(tag)) return false;
    final a = _rectOf(keys[outSlot]![tag]);
    final b = _rectOf(keys[inSlot]![tag]);
    if (a == null || b == null) return false;
    if (a.width <= 0 || a.height <= 0 || b.width <= 0 || b.height <= 0) {
      return false;
    }
    return _similar(a, b);
  }

  /// 旧块：对接上的立刻让位——新块已经顶在同一个位置上了。
  Widget decorateOutgoing(String tag, Widget child) {
    if (_phase == _Phase.idle || _phase == _Phase.pending) return child;
    final t = _t;
    if (_canFly(tag)) {
      return Opacity(opacity: 1 - _ramp(t, 0, 0.1), child: child);
    }
    return Opacity(opacity: 1 - _ramp(t, 0, 0.42), child: child);
  }

  /// 新块：从旧块的位置、尺寸飞回自己的位置，途中一直显示新的内容。
  Widget decorateIncoming(String tag, Widget child) {
    if (_phase == _Phase.idle || _phase == _Phase.pending) return child;
    final t = _t;
    if (_phase == _Phase.crossFade) return child;
    final own = _rectOf(keys[inSlot]![tag]);
    final from = _canFly(tag) ? _rectOf(keys[outSlot]![tag]) : null;
    if (own == null || from == null) {
      return Opacity(opacity: _ramp(t, 0.32, 0.86), child: child);
    }
    final rect = Rect.lerp(from, own, t)!;
    final matrix = Matrix4.identity()
      ..translateByDouble(rect.left - own.left, rect.top - own.top, 0, 1)
      ..scaleByDouble(
        rect.width / own.width,
        rect.height / own.height,
        1,
        1,
      );
    return Transform(transform: matrix, child: child);
  }

  Rect? _rectOf(GlobalKey? key) {
    final ctx = key?.currentContext;
    final rootCtx = rootKey.currentContext;
    if (ctx == null || rootCtx == null) return null;
    final box = ctx.findRenderObject();
    final root = rootCtx.findRenderObject();
    if (box is! RenderBox || root is! RenderBox) return null;
    if (!box.hasSize || !root.hasSize) return null;
    final offset =
        box.localToGlobal(Offset.zero) - root.localToGlobal(Offset.zero);
    return offset & box.size;
  }
}

double _ramp(double t, double begin, double end) {
  if (t <= begin) return 0;
  if (t >= end) return 1;
  return (t - begin) / (end - begin);
}

/// 两块尺寸相差不超过约三倍，才值得让它飞过去。
bool _similar(Rect a, Rect b) {
  final sx = a.width > b.width ? a.width / b.width : b.width / a.width;
  final sy = a.height > b.height ? a.height / b.height : b.height / a.height;
  return sx <= 3 && sy <= 3;
}

class _MorphScope extends InheritedWidget {
  const _MorphScope({
    required this.session,
    required this.slot,
    required super.child,
  });

  final _MorphSession session;
  final String slot;

  static _MorphScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MorphScope>();

  @override
  bool updateShouldNotify(_MorphScope old) =>
      old.session != session || old.slot != slot;
}

/// 一块可以在页面切换时“变形”的内容。
class MorphBlock extends StatefulWidget {
  const MorphBlock({super.key, required this.tag, required this.child});

  /// 标签：新旧页面里标签相同，就会从旧位置飞到新位置。
  final String tag;
  final Widget child;

  @override
  State<MorphBlock> createState() => _MorphBlockState();
}

class _MorphBlockState extends State<MorphBlock> {
  final GlobalKey _key = GlobalKey();
  _MorphSession? _session;
  String? _slot;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = _MorphScope.maybeOf(context);
    if (scope == null) return;
    if (_session != scope.session || _slot != scope.slot) {
      _unregister();
      _session = scope.session;
      _slot = scope.slot;
      _session!.keys[_slot!]![widget.tag] = _key;
    }
  }

  @override
  void dispose() {
    _unregister();
    super.dispose();
  }

  void _unregister() {
    final session = _session;
    final slot = _slot;
    if (session == null || slot == null) return;
    final map = session.keys[slot];
    if (map != null && identical(map[widget.tag], _key)) map.remove(widget.tag);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) return widget.child;
    final outgoing = session.isOutgoing(_slot!);
    return AnimatedBuilder(
      animation: session.controller,
      child: RepaintBoundary(key: _key, child: widget.child),
      builder: (context, child) => outgoing
          ? session.decorateOutgoing(widget.tag, child!)
          : session.decorateIncoming(widget.tag, child!),
    );
  }
}

/// 把一列内容按标签登记成可变形块；[tags] 里名字相同的块会互相对接。
class MorphGroup extends StatelessWidget {
  const MorphGroup({
    super.key,
    required this.children,
    this.id = '',
    this.tags,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.mainAxisSize = MainAxisSize.max,
  });

  final List<Widget> children;

  /// 页面自己的名字，用来给没配对的块生成不会撞车的标签。
  final String id;
  final List<String?>? tags;
  final CrossAxisAlignment crossAxisAlignment;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) {
    var tagIndex = 0;
    return Column(
      crossAxisAlignment: crossAxisAlignment,
      mainAxisSize: mainAxisSize,
      children: [
        for (var i = 0; i < children.length; i++)
          if (children[i] is SizedBox)
            children[i]
          else
            MorphBlock(
              tag: tags != null &&
                      tagIndex < tags!.length &&
                      tags![tagIndex] != null
                  ? tags![tagIndex++]!
                  : '$id#${tagIndex++}',
              child: children[i],
            ),
      ],
    );
  }
}
