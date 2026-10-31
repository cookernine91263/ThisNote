import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'note_fonts.dart';

/// 文案以中文为源，英文放在 [_en] 里。字体名与描述来自 [noteFonts]，
/// 这里按中文原文查表，查不到就保留中文。
const Map<String, String> _en = <String, String>{
  '选一种字体': 'Choose a font',
  '中英日都在这张纸上': 'Chinese, English, Japanese — all on this sheet',
  '黑体': 'Sans',
  '宋体': 'Serif',
  '文楷': 'WenKai',
  '手写': 'Brush',
  '小薇': 'XiaoWei',
  '细黑': 'Light',
  '思源黑体 · 默认，安静清楚': 'Noto Sans · default, quiet and clear',
  '思源宋体 · 长文与书信': 'Noto Serif · for long reads and letters',
  '霞鹜文楷 · 手写的温度': 'LXGW WenKai · a handwritten warmth',
  '马善政毛笔 · 一句题目': 'Ma Shan Zheng brush · for one title',
  '站酷小薇 · 雅致的标题': 'ZCOOL XiaoWei · elegant headings',
  '思源细体 · 轻盈的呼吸': 'Noto Sans Light · a light breath',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<String?> showFontPicker(
  BuildContext context, {
  required QuillController controller,
}) async {
  final current =
      controller.getSelectionStyle().attributes[Attribute.font.key]?.value;
  return showDialog<String>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.24),
    builder: (context) => _FontDialog(current: current?.toString()),
  );
}

class _FontDialog extends StatelessWidget {
  const _FontDialog({this.current});
  final String? current;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(22),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 390,
          maxHeight: size.height - 80,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: c.isDark ? 0.45 : 0.16),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 10, 8),
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('选一种字体'),
                          style: TextStyle(
                            fontFamily: 'WenKai',
                            fontSize: 23,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _t('中英日都在这张纸上'),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 10,
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
              ),
              Flexible(
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(context).copyWith(
                    scrollbars: false,
                  ),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                    itemCount: noteFonts.length,
                    itemBuilder: (context, index) {
                      final font = noteFonts[index];
                      final active = font.value == current ||
                          (font.value == null &&
                              (current == null ||
                                  current!.isEmpty ||
                                  current == 'NotoSansSC'));
                      return _FontRow(
                        font: font,
                        active: active,
                        onTap: () => Navigator.of(context).pop(
                          font.value ?? '__default__',
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.font,
    required this.active,
    required this.onTap,
  });

  final NoteFont font;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.fromLTRB(13, 9, 10, 9),
            decoration: BoxDecoration(
              color: active
                  ? c.accentSoft
                  : hovered
                      ? c.paper
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: active ? c.accent.withValues(alpha: 0.4) : c.line,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            _t(font.label),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: active ? c.accent : c.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _t(font.description),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 9,
                                color: c.inkMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '此记 ThisNote あ',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontFamily: font.family,
                          fontSize: 20,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedOpacity(
                  opacity: active ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    LucideIcons.check,
                    size: 15,
                    color: c.accent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
