import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。预设的 id 与颜色不动，只翻名字与描述。
const Map<String, String> _en = <String, String>{
  '花字': 'Flower Text',
  '文楷 · 大字号': 'WenKai · Large',
  '小': 'Small',
  '中': 'Medium',
  '大': 'Large',
  '落笔即心安': 'Settle.',
  '选中文字后，选一种语气。字体为霞鹜文楷（OFL），中英日通用。':
      'Select some text, then pick a tone. Set in LXGW WenKai (OFL) — Chinese, English and Japanese alike.',
  '提示：花字是字符样式，可随时清除，不会改变原文。':
      'Tip: flower text is a character style. Clear it any time — the words stay the same.',
  '还原正文': 'Back to Body',
  '已还原为正文样式': 'Back to Body style',
  '先选中一段文字，再点花字': 'Select some text first, then tap Flower Text',
  '已应用花字「{name}」': 'Flower Text “{name}” applied',
  '朱砂': 'Cinnabar',
  '青黛': 'Indigo',
  '鎏金': 'Gilt',
  '墨韵': 'Ink',
  '落霞': 'Sunset',
  '雪松': 'Cedar',
  '夜航': 'Night Flight',
  '糖果': 'Candy',
  '一点郑重': 'With care',
  '远山与雾': 'Mist and hills',
  '旧书页的光': 'Old page light',
  '浓淡之间': 'Light and dark',
  '傍晚的橘': 'Evening orange',
  '安静的绿': 'Quiet green',
  '深蓝的星': 'Blue starlight',
  '轻一点': 'Lighter touch',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class HuaziPreset {
  const HuaziPreset({
    required this.id,
    required this.name,
    required this.colors,
    required this.glow,
    this.description = '',
  });

  final String id;
  final String name;
  final List<Color> colors;
  final Color glow;
  final String description;

  List<Color> resolvedColors(bool dark) {
    if (!dark) return colors;
    return colors
        .map((c) => Color.lerp(c, Colors.white, 0.18)!)
        .toList(growable: false);
  }
}

const huaziPresets = <HuaziPreset>[
  HuaziPreset(
    id: 'zhu',
    name: '朱砂',
    description: '一点郑重',
    colors: [Color(0xFF9E3F32), Color(0xFFD08A66), Color(0xFF8E3227)],
    glow: Color(0xFFB0473A),
  ),
  HuaziPreset(
    id: 'qing',
    name: '青黛',
    description: '远山与雾',
    colors: [Color(0xFF3E626B), Color(0xFF8FB0AC), Color(0xFF33545C)],
    glow: Color(0xFF3E626B),
  ),
  HuaziPreset(
    id: 'jin',
    name: '鎏金',
    description: '旧书页的光',
    colors: [Color(0xFF9A7438), Color(0xFFE0C08A), Color(0xFF8A622D)],
    glow: Color(0xFFA8824B),
  ),
  HuaziPreset(
    id: 'mo',
    name: '墨韵',
    description: '浓淡之间',
    colors: [Color(0xFF26231E), Color(0xFF6D6558), Color(0xFF26231E)],
    glow: Color(0xFF3B352C),
  ),
  HuaziPreset(
    id: 'xia',
    name: '落霞',
    description: '傍晚的橘',
    colors: [Color(0xFFB45E48), Color(0xFFD9A06D), Color(0xFF8E4A5B)],
    glow: Color(0xFFB45E48),
  ),
  HuaziPreset(
    id: 'xue',
    name: '雪松',
    description: '安静的绿',
    colors: [Color(0xFF546B55), Color(0xFF9AAF94), Color(0xFF425846)],
    glow: Color(0xFF546B55),
  ),
  HuaziPreset(
    id: 'ye',
    name: '夜航',
    description: '深蓝的星',
    colors: [Color(0xFF4E607C), Color(0xFF9A8FB8), Color(0xFF41516B)],
    glow: Color(0xFF4E607C),
  ),
  HuaziPreset(
    id: 'tang',
    name: '糖果',
    description: '轻一点',
    colors: [Color(0xFFC07A6A), Color(0xFFD7B077), Color(0xFF8FA47F)],
    glow: Color(0xFFC07A6A),
  ),
];

const _sizeTokens = <String, double>{'s': 24, 'm': 30, 'l': 38};

HuaziPreset? huaziPresetById(String id) {
  for (final p in huaziPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 花字使用「标准 Quill 属性」实现：文楷 + 大字号 + 加粗 + 颜色。
/// 这样在运行时应用、重新加载和导出时都稳定，不依赖行样式缓存。
Map<String, dynamic> huaziInlineAttributes(
  HuaziPreset preset,
  String size,
) =>
    {
      'font': 'WenKai',
      'size': switch (size) {
        's' => 'large',
        'l' => '40',
        _ => 'huge',
      },
      'bold': true,
      'color': hexOf(preset.colors.first),
    };

bool isHuaziStyle(Map<String, Attribute> attrs) {
  final font = attrs[Attribute.font.key]?.value;
  if (font is String && font.startsWith('huazi:')) return true;
  if (font != 'WenKai') return false;
  final size = attrs[Attribute.size.key]?.value;
  return size == 'huge' || size == 'large' || (size is num && size >= 24) || size == '40';
}

TextStyle huaziTextStyle(String value, {required bool dark}) {
  final parts = value.split(':');
  final id = parts.length > 1 ? parts[1] : 'zhu';
  final sizeToken = parts.length > 2 ? parts[2] : 'm';
  final preset = huaziPresetById(id) ?? huaziPresets.first;
  final colors = preset.resolvedColors(dark);
  final paint = Paint()
    ..shader = ui.Gradient.linear(
      const Offset(0, 0),
      const Offset(460, 30),
      colors,
      colors.length == 3 ? const [0.0, 0.52, 1.0] : null,
    );
  return TextStyle(
    fontFamily: 'WenKai',
    fontSize: _sizeTokens[sizeToken] ?? 30,
    height: 1.4,
    letterSpacing: 1.6,
    fontWeight: FontWeight.w500,
    foreground: paint,
    shadows: [
      Shadow(
        color: preset.glow.withValues(alpha: dark ? 0.4 : 0.2),
        blurRadius: dark ? 15 : 9,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

/// 供 Quill 的 customStyleBuilder 使用：字体切换、细体、倾斜与花字。
TextStyle quillCustomStyle(
  Attribute attribute, {
  required bool dark,
  Color? muted,
}) {
  if (attribute.key == Attribute.list.key && attribute.value == 'checked') {
    // 勾选后的待办只做展示层删除线：不改 Delta，取消勾选自动恢复。
    return TextStyle(
      decoration: TextDecoration.lineThrough,
      decorationColor: muted,
      decorationThickness: 1.3,
    );
  }
  if (attribute.key == Attribute.font.key) {
    final value = attribute.value;
    if (value is! String) return const TextStyle();
    if (value.startsWith('huazi:')) return huaziTextStyle(value, dark: dark);
    if (value == 'style:thin') {
      return const TextStyle(
        fontFamily: 'NotoSansSC',
        fontWeight: FontWeight.w300,
      );
    }
    if (value == 'Serif') {
      return const TextStyle(fontFamily: 'WenKai');
    }
  }
  return const TextStyle();
}

Future<void> showHuaziGallery(
  BuildContext context,
  EditorSession session,
) async {
  if (session.controller.selection.isCollapsed) {
    showToast(context, _t('先选中一段文字，再点花字'), icon: LucideIcons.textCursor);
    return;
  }
  final mobile = MediaQuery.sizeOf(context).width < 760;
  final Future<void> future;
  if (mobile) {
    future = showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HuaziShell(session: session, mobile: true),
    );
  } else {
    future = showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: _HuaziShell(session: session, mobile: false),
      ),
    );
  }
  await future;
}

class _HuaziShell extends StatelessWidget {
  const _HuaziShell({required this.session, required this.mobile});
  final EditorSession session;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: mobile ? double.infinity : 700,
      constraints: BoxConstraints(maxHeight: mobile ? 620 : 610),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(mobile ? 22 : 20),
          bottom: Radius.circular(mobile ? 0 : 20),
        ),
        border: Border.all(color: c.line),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.2),
            blurRadius: 50,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: _HuaziGallery(session: session, mobile: mobile),
    );
  }
}

class _HuaziGallery extends StatefulWidget {
  const _HuaziGallery({required this.session, required this.mobile});
  final EditorSession session;
  final bool mobile;

  @override
  State<_HuaziGallery> createState() => _HuaziGalleryState();
}

class _HuaziGalleryState extends State<_HuaziGallery> {
  String _size = 'm';

  /// 小 / 中 / 大 的尺寸选择。桌面上贴着标题，手机上单独一行。
  List<Widget> _sizeChips(AppPalette c) => [
        for (final s in const [('s', '小'), ('m', '中'), ('l', '大')])
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: GestureDetector(
              onTap: () => setState(() => _size = s.$1),
              child: AnimatedContainer(
                duration: Motion.fast,
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _size == s.$1 ? c.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _t(s.$2),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10.5,
                    color: _size == s.$1 ? c.paper : c.inkMuted,
                  ),
                ),
              ),
            ),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('花字'),
                style: TextStyle(
                  fontFamily: 'WenKai',
                  fontSize: 25,
                  letterSpacing: 2,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _t('文楷 · 大字号'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9,
                    color: c.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const Spacer(),
              // 英文尺寸词比中文宽，手机上另起一行，免得把关闭按钮挤出面板。
              if (!widget.mobile) ..._sizeChips(c),
              const SizedBox(width: 8),
              SoftIconButton(
                icon: LucideIcons.x,
                size: 28,
                tooltip: _t('关闭'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          if (widget.mobile) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: _sizeChips(c),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            _t('选中文字后，选一种语气。字体为霞鹜文楷（OFL），中英日通用。'),
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 10.5,
              color: c.inkMuted,
            ),
          ),
          const SizedBox(height: 14),
          Flexible(
            child: SingleChildScrollView(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: huaziPresets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: widget.mobile ? 2 : 4,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: widget.mobile ? 1.55 : 1.15,
                ),
                itemBuilder: (context, i) {
                  final preset = huaziPresets[i];
                  return _HuaziCard(
                    preset: preset,
                    size: _size,
                    onTap: () {
                      final ok = widget.session.applyHuazi(
                        preset.id,
                        size: _size,
                      );
                      if (ok) {
                        Navigator.of(context).pop();
                        showToast(
                          context,
                          _t('已应用花字「{name}」', {
                            'name': _t(preset.name),
                          }),
                          icon: LucideIcons.sparkles,
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(LucideIcons.type, size: 12, color: c.inkMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _t('提示：花字是字符样式，可随时清除，不会改变原文。'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.session.clearFont();
                  Navigator.of(context).pop();
                  showToast(context, _t('已还原为正文样式'));
                },
                child: Text(
                  _t('还原正文'),
                  style: TextStyle(fontFamily: 'NotoSansSC', fontSize: 11, color: c.inkMuted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HuaziCard extends StatefulWidget {
  const _HuaziCard({
    required this.preset,
    required this.size,
    required this.onTap,
  });
  final HuaziPreset preset;
  final String size;
  final VoidCallback onTap;

  @override
  State<_HuaziCard> createState() => _HuaziCardState();
}

class _HuaziCardState extends State<_HuaziCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final style = TextStyle(
      fontFamily: 'WenKai',
      fontSize: styleSize(widget.size) * 0.82,
      height: 1.35,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w600,
      color: widget.preset.resolvedColors(c.isDark).first,
    );
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          curve: Motion.spring,
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          padding: const EdgeInsets.fromLTRB(13, 12, 12, 10),
          decoration: BoxDecoration(
            color: _hover ? c.paper : c.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _hover ? c.lineStrong : c.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    _t('落笔即心安'),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    style: style,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _t(widget.preset.name),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10.5,
                      color: c.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _t(widget.preset.description),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 8.5,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

double styleSize(String token) => switch (token) {
      's' => 24,
      'l' => 38,
      _ => 30,
    };
