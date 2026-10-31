import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '高亮颜色': 'Highlight color',
  '文字颜色': 'Text color',
  '转一圈，挑一个今天心情的颜色': 'Spin the wheel, pick a color for today',
  '高亮底色': 'Highlight background',
  '保存到常用': 'Save to favorites',
  '已保存 {hex}': 'Saved {hex}',
  '明度': 'Brightness',
  '常用': 'Saved',
  '内置': 'Built-in',
  '清除颜色': 'Clear color',
  '用这个颜色': 'Use this color',
  '{hex} · 长按删除': '{hex} · long-press to delete',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

const _textPalette = <String>[
  '#211E19',
  '#575149',
  '#8D8576',
  '#A84637',
  '#A8824B',
  '#6F806C',
  '#56697D',
  '#7A5A6B',
  '#2E5B56',
  '#8C6534',
];

const _highlightPalette = <String>[
  '#F3E2BE',
  '#EED4CA',
  '#DCE6D6',
  '#D6E2EA',
  '#E8DCE8',
  '#EDE3D0',
  '#DDD8CE',
  '#F5E9D7',
];

Future<String?> showNoteColorPicker(
  BuildContext context, {
  required bool background,
}) {
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.26),
    builder: (_) => _ColorDialog(background: background),
  );
}

class _ColorDialog extends StatefulWidget {
  const _ColorDialog({required this.background});
  final bool background;

  @override
  State<_ColorDialog> createState() => _ColorDialogState();
}

class _ColorDialogState extends State<_ColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(
    widget.background ? const Color(0xFFF3E2BE) : const Color(0xFFA84637),
  );

  Color get _color => _hsv.toColor();

  String get _hex {
    final value = _color.toARGB32().toRadixString(16).padLeft(8, '0');
    return '#${value.substring(2).toUpperCase()}';
  }

  void _setColor(Color color) {
    setState(() => _hsv = HSVColor.fromColor(color));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final saved = state.settings.savedColors;
    final builtins = widget.background ? _highlightPalette : _textPalette;
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 370,
          maxHeight: size.height - 48,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: c.isDark ? 0.45 : 0.18),
                blurRadius: 42,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t(widget.background ? '高亮颜色' : '文字颜色'),
                          style: TextStyle(
                            fontFamily: 'WenKai',
                            fontSize: 22,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t('转一圈，挑一个今天心情的颜色'),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 9.5,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    SoftIconButton(
                      icon: LucideIcons.x,
                      size: 30,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _color,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.lineStrong),
                        boxShadow: [
                          BoxShadow(
                            color: _color.withValues(alpha: 0.28),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _hex,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              letterSpacing: 0.6,
                              color: c.ink,
                            ),
                          ),
                          Text(
                            _t(widget.background ? '高亮底色' : '文字颜色'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 9.5,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Tooltip(
                      message: _t('保存到常用'),
                      child: GestureDetector(
                        onTap: () async {
                          await state.saveColor(_hex);
                          if (context.mounted) {
                            showToast(
                              context,
                              _t('已保存 {hex}', {'hex': _hex}),
                            );
                          }
                        },
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            saved.any(
                                  (e) => e.toUpperCase() == _hex,
                                )
                                ? LucideIcons.star
                                : LucideIcons.starPlus,
                            size: 15,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Center(
                  child: _ColorWheel(
                    hsv: _hsv,
                    size: 196,
                    onChanged: (v) => setState(() => _hsv = v),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      LucideIcons.sunMedium,
                      size: 13,
                      color: c.inkMuted,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _t('明度'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        color: c.inkMuted,
                      ),
                    ),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 13,
                          ),
                          activeTrackColor: c.accent,
                          inactiveTrackColor: c.surfaceAlt,
                          thumbColor: c.accent,
                          overlayColor: c.accent.withValues(alpha: 0.12),
                        ),
                        child: Slider(
                          value: _hsv.value.clamp(0.08, 1),
                          onChanged: (v) => setState(
                            () => _hsv = _hsv.withValue(v),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '${(_hsv.value * 100).round()}%',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: c.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (saved.isNotEmpty) ...[
                  Text(
                    _t('常用'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final hex in saved)
                        _Swatch(
                          hex: hex,
                          selected: hex.toUpperCase() == _hex,
                          onTap: () => _setColor(_colorFromHex(hex)),
                          onLongPress: () => state.removeSavedColor(hex),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  _t('内置'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final hex in builtins)
                      _Swatch(
                        hex: hex,
                        selected: hex.toUpperCase() == _hex,
                        onTap: () => _setColor(_colorFromHex(hex)),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop('clear'),
                      child: Text(
                        _t('清除颜色'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 10.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ),
                    const Spacer(),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.ink,
                        foregroundColor: c.paper,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 9,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(_hex),
                      child: Text(_t('用这个颜色')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.hex,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final color = _colorFromHex(hex);
    return Tooltip(
      message: onLongPress == null
          ? hex
          : _t('{hex} · 长按删除', {'hex': hex}),
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? c.ink : c.lineStrong.withValues(alpha: 0.55),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: selected
              ? Icon(
                  LucideIcons.check,
                  size: 12,
                  color: color.computeLuminance() > 0.55
                      ? const Color(0xFF211E19)
                      : Colors.white,
                )
              : null,
        ),
      ),
    );
  }
}

class _ColorWheel extends StatelessWidget {
  const _ColorWheel({
    required this.hsv,
    required this.size,
    required this.onChanged,
  });

  final HSVColor hsv;
  final double size;
  final ValueChanged<HSVColor> onChanged;

  void _handle(Offset position, double radius) {
    final center = Offset(size / 2, size / 2);
    final delta = position - center;
    final distance = delta.distance;
    final hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360;
    final saturation = (distance / radius).clamp(0.0, 1.0);
    onChanged(hsv.withHue(hue).withSaturation(saturation));
  }

  @override
  Widget build(BuildContext context) {
    final radius = size / 2 - 2;
    return SizedBox(
      width: size,
      height: size,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _handle(
              Offset(d.localPosition.dx, d.localPosition.dy),
              radius,
            ),
            onPanStart: (d) => _handle(
              Offset(d.localPosition.dx, d.localPosition.dy),
              radius,
            ),
            onPanUpdate: (d) => _handle(
              Offset(d.localPosition.dx, d.localPosition.dy),
              radius,
            ),
            child: CustomPaint(
              painter: _WheelPainter(hsv: hsv),
            ),
          );
        },
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  _WheelPainter({required this.hsv});
  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final hueColors = <Color>[
      for (var i = 0; i <= 12; i++)
        HSVColor.fromAHSV(1, (i * 30) % 360, 1, hsv.value).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(colors: hueColors).createShader(rect),
    );

    // 圆心白、边缘透明的径向渐变，把色相盘变成饱和度盘。
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white,
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    if (hsv.value < 1) {
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
      );
    }

    final angle = hsv.hue * math.pi / 180;
    final position = center +
        Offset(
          math.cos(angle),
          math.sin(angle),
        ) *
            (hsv.saturation * radius);
    canvas.drawCircle(
      position,
      7,
      Paint()..color = Colors.white,
    );
    canvas.drawCircle(
      position,
      7,
      Paint()
        ..color = const Color(0xFF211E19)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.hsv != hsv;
}

Color _colorFromHex(String hex) {
  final value = hex.replaceAll('#', '');
  final parsed = int.tryParse(value, radix: 16);
  if (parsed == null) return const Color(0xFF211E19);
  if (value.length == 6) return Color(0xFF000000 | parsed);
  if (value.length == 8) return Color(parsed);
  return const Color(0xFF211E19);
}
