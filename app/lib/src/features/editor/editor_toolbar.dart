import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';
import '../ai_chat/ai_chat_panel.dart';
import 'code_block.dart';
import 'color_picker.dart';
import 'font_picker.dart';
import 'huazi.dart';
import 'note_fonts.dart';

/// 文案以中文为源，英文放在 [_en] 里。工具栏按钮窄，标签只取短的词，
/// 完整的说法放进 tooltip。
const Map<String, String> _en = <String, String>{
  '撤销 · Ctrl Z': 'Undo · Ctrl Z',
  '重做 · Ctrl Y': 'Redo · Ctrl Y',
  '正文': 'Body',
  '标题 1': 'Heading 1',
  '标题 2': 'Heading 2',
  '标题 3': 'Heading 3',
  '黑体': 'Sans',
  '宋体': 'Serif',
  '文楷': 'WenKai',
  '手写': 'Brush',
  '小薇': 'XiaoWei',
  '细黑': 'Light',
  '得意黑': 'Smiley',
  '等宽': 'Mono',
  '加粗 · Ctrl B': 'Bold · Ctrl B',
  '倾斜 · Ctrl I': 'Italic · Ctrl I',
  '变细': 'Light',
  '下划线 · Ctrl U': 'Underline · Ctrl U',
  '删除线': 'Strike',
  '文字颜色': 'Text color',
  '高亮': 'Highlight',
  '左对齐': 'Align left',
  '居中': 'Center',
  '右对齐': 'Align right',
  '两端对齐': 'Justify',
  '无序列表': 'Bulleted list',
  '有序列表': 'Numbered list',
  '待办清单': 'To-do list',
  '引用': 'Quote',
  '代码块': 'Code block',
  '链接': 'Link',
  '插入图片': 'Insert image',
  '粘贴图片（来自剪贴板）': 'Paste image (from clipboard)',
  '分隔线': 'Divider',
  'AI 助手 · 润色 / 续写 / 起标题': 'AI assistant · polish / continue / title',
  '花字': 'Flower',
  '清除格式': 'Clear formatting',
  '图片': 'Image',
  '剪贴板里没有可粘贴的图片': 'No image in the clipboard to paste',
  '添加链接': 'Add link',
  '移除': 'Remove',
  '应用': 'Apply',
  '段落样式': 'Paragraph style',
  '对齐方式': 'Alignment',
  '列表': 'List',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class EditorToolbar extends StatelessWidget {
  const EditorToolbar({
    required this.controller,
    required this.session,
    super.key,
    this.mobile = false,
  });

  final QuillController controller;
  final EditorSession session;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final style = controller.getSelectionStyle();
        final attrs = style.attributes;
        final customFonts = context.watch<AppState>().settings.customFonts;
        bool has(String key) => attrs.containsKey(key);
        final header = attrs[Attribute.header.key]?.value;
        final list = attrs[Attribute.list.key]?.value;
        final align = attrs[Attribute.align.key]?.value;
        final font = attrs[Attribute.font.key]?.value?.toString();
        final thin = font == 'style:thin' || font == 'NotoSansSCLight';
        final huazi = isHuaziStyle(attrs);

        void toggle(Attribute attr) {
          if (has(attr.key)) {
            controller.formatSelection(Attribute.clone(attr, null));
          } else {
            controller.formatSelection(attr);
          }
        }

        void applyHeader(int? level) {
          if (level == null) {
            controller.formatSelection(Attribute.clone(Attribute.h1, null));
          } else {
            controller.formatSelection(
              Attribute('header', AttributeScope.block, level),
            );
          }
        }

        void applyList(String value) {
          if (list == value) {
            controller.formatSelection(Attribute.clone(Attribute.ul, null));
          } else {
            controller.formatSelection(
              Attribute('list', AttributeScope.block, value),
            );
          }
        }

        void applyAlign(String value) {
          if (align == value) {
            controller.formatSelection(Attribute.clone(Attribute.align, null));
          } else {
            controller.formatSelection(
              Attribute('align', AttributeScope.block, value),
            );
          }
        }

        final children = <Widget>[
          _ToolButton(
            icon: LucideIcons.undo2,
            tooltip: _t('撤销 · Ctrl Z'),
            onPressed: controller.hasUndo ? controller.undo : null,
          ),
          _ToolButton(
            icon: LucideIcons.redo2,
            tooltip: _t('重做 · Ctrl Y'),
            onPressed: controller.hasRedo ? controller.redo : null,
          ),
          const _Sep(),
          _MenuChip(
            tooltip: _t('段落样式'),
            label: switch (header) {
              1 => _t('标题 1'),
              2 => _t('标题 2'),
              3 => _t('标题 3'),
              _ => _t('正文'),
            },
            active: header != null,
            // 「标题 1」比「正文」宽，72 会在换行字体下溢出几像素。
            width: 84,
            menu: [
              _MenuItem(_t('正文'), () => applyHeader(null)),
              _MenuItem(_t('标题 1'), () => applyHeader(1)),
              _MenuItem(_t('标题 2'), () => applyHeader(2)),
              _MenuItem(_t('标题 3'), () => applyHeader(3)),
            ],
          ),
          const SizedBox(width: 2),
          _FontChip(
            label: _t(fontLabel(font, customFonts)),
            active: font != null,
            onTap: () async {
              final selected = await showFontPicker(
                context,
                controller: controller,
              );
              if (selected == null) return;
              controller.formatSelection(
                selected == '__default__'
                    ? Attribute.clone(Attribute.font, null)
                    : Attribute('font', AttributeScope.inline, selected),
              );
              session.editorFocus.requestFocus();
            },
          ),
          const SizedBox(width: 2),
          _ToolButton(
            icon: LucideIcons.bold,
            tooltip: _t('加粗 · Ctrl B'),
            active: has('bold'),
            onPressed: () => toggle(Attribute.bold),
          ),
          _ToolButton(
            icon: LucideIcons.italic,
            tooltip: _t('倾斜 · Ctrl I'),
            active: has('italic'),
            onPressed: () => toggle(Attribute.italic),
          ),
          _ToolButton(
            icon: LucideIcons.type,
            tooltip: _t('变细'),
            active: thin,
            onPressed: () {
              if (thin) {
                session.clearFont();
              } else {
                session.applyThin();
              }
            },
          ),
          _ToolButton(
            icon: LucideIcons.underline,
            tooltip: _t('下划线 · Ctrl U'),
            active: has('underline'),
            onPressed: () => toggle(Attribute.underline),
          ),
          _ToolButton(
            icon: LucideIcons.strikethrough,
            tooltip: _t('删除线'),
            active: has('strike'),
            onPressed: () => toggle(Attribute.strikeThrough),
          ),
          const _Sep(),
          _ToolButton(
            icon: LucideIcons.palette,
            tooltip: _t('文字颜色'),
            active: has('color'),
            onPressed: () async {
              final hex = await showNoteColorPicker(
                context,
                background: false,
              );
              if (hex == null) return;
              controller.formatSelection(
                hex == 'clear'
                    ? Attribute.clone(Attribute.color, null)
                    : Attribute('color', AttributeScope.inline, hex),
              );
            },
          ),
          _ToolButton(
            icon: LucideIcons.highlighter,
            tooltip: _t('高亮'),
            active: has('background'),
            onPressed: () async {
              final hex = await showNoteColorPicker(
                context,
                background: true,
              );
              if (hex == null) return;
              controller.formatSelection(
                hex == 'clear'
                    ? Attribute.clone(Attribute.background, null)
                    : Attribute('background', AttributeScope.inline, hex),
              );
            },
          ),
          _MenuChip(
            tooltip: _t('对齐方式'),
            icon: switch (align) {
              'center' => LucideIcons.alignCenter,
              'right' => LucideIcons.alignRight,
              'justify' => LucideIcons.alignJustify,
              _ => LucideIcons.alignLeft,
            },
            active: align != null,
            width: 38,
            menu: [
              _MenuItem(_t('左对齐'), () => applyAlign('left'), icon: LucideIcons.alignLeft),
              _MenuItem(_t('居中'), () => applyAlign('center'), icon: LucideIcons.alignCenter),
              _MenuItem(_t('右对齐'), () => applyAlign('right'), icon: LucideIcons.alignRight),
              _MenuItem(_t('两端对齐'), () => applyAlign('justify'), icon: LucideIcons.alignJustify),
            ],
          ),
          _MenuChip(
            tooltip: _t('列表'),
            icon: switch (list) {
              'ordered' => LucideIcons.listOrdered,
              'checked' || 'unchecked' => LucideIcons.listChecks,
              _ => LucideIcons.list,
            },
            active: list != null,
            width: 38,
            menu: [
              _MenuItem(_t('无序列表'), () => applyList('bullet'), icon: LucideIcons.list),
              _MenuItem(_t('有序列表'), () => applyList('ordered'), icon: LucideIcons.listOrdered),
              _MenuItem(_t('待办清单'), () => applyList('unchecked'), icon: LucideIcons.listChecks),
            ],
          ),
          _ToolButton(
            icon: LucideIcons.textQuote,
            tooltip: _t('引用'),
            active: has('blockquote'),
            onPressed: () => toggle(Attribute.blockQuote),
          ),
          _ToolButton(
            icon: LucideIcons.code,
            tooltip: _t('代码块'),
            active: has('code-block') || selectionIsCodeBlock(controller),
            onPressed: () {
              final legacy = legacyCodeBlockAt(controller);
              if (legacy != null) {
                showCodeBlockDialog(
                  context,
                  controller,
                  initial: CodeBlockData(code: legacy.code),
                  legacyStart: legacy.start,
                  legacyEnd: legacy.end,
                );
              } else {
                showCodeBlockDialog(context, controller);
              }
            },
          ),
          _ToolButton(
            icon: LucideIcons.link,
            tooltip: _t('链接'),
            active: has('link'),
            onPressed: () async {
              final url = await _linkDialog(context, controller);
              if (url == null) return;
              controller.formatSelection(
                url.isEmpty
                    ? Attribute.clone(Attribute.link, null)
                    : Attribute('link', AttributeScope.inline, url),
              );
            },
          ),
          _ToolButton(
            icon: LucideIcons.image,
            tooltip: _t('插入图片'),
            onPressed: () => _insertImage(context),
          ),
          _ToolButton(
            icon: LucideIcons.clipboardPaste,
            tooltip: _t('粘贴图片（来自剪贴板）'),
            onPressed: () => _pasteImage(context),
          ),
          _ToolButton(
            icon: LucideIcons.separatorHorizontal,
            tooltip: _t('分隔线'),
            onPressed: session.insertDivider,
          ),
          const _Sep(),
          _ToolButton(
            icon: LucideIcons.sparkles,
            tooltip: _t('AI 助手 · 润色 / 续写 / 起标题'),
            active: session.aiOpen,
            onPressed: () => openAiChat(context, session),
          ),
          _HuaziButton(
            active: huazi,
            onPressed: () => showHuaziGallery(context, session),
          ),
          _ToolButton(
            icon: LucideIcons.removeFormatting,
            tooltip: _t('清除格式'),
            onPressed: session.clearFormatting,
          ),
        ];

        final bar = Container(
          height: mobile ? 46 : 40,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius:
                mobile ? BorderRadius.zero : BorderRadius.circular(12),
            border: mobile
                ? Border(top: BorderSide(color: c.line))
                : Border.all(color: c.line),
            boxShadow: mobile
                ? null
                : [
                    BoxShadow(
                      color:
                          c.shadow.withValues(alpha: c.isDark ? 0.24 : 0.045),
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              scrollbars: false,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 14),
              child: Row(children: children),
            ),
          ),
        );
        if (mobile) return bar;
        // 桌面上把工具栏收成一张圆角的小卡片，别再横着切满一条。
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
          child: bar,
        );
      },
    );
  }

  Future<void> _insertImage(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: _t('图片'),
          extensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
        ),
      ],
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    final ext = p.extension(file.name).replaceAll('.', '');
    final state = context.read<AppState>();
    final rel = await state.store.saveAsset(
      bytes,
      ext.isEmpty ? 'png' : ext,
    );
    session.insertImage(rel);
    session.editorFocus.requestFocus();
  }

  Future<void> _pasteImage(BuildContext context) async {
    final ok = await session.pasteImageFromClipboard();
    if (!context.mounted) return;
    if (!ok) {
      showToast(context, _t('剪贴板里没有可粘贴的图片'), icon: LucideIcons.alertCircle);
    } else {
      session.editorFocus.requestFocus();
    }
  }

  Future<String?> _linkDialog(
      BuildContext context, QuillController controller) async {
    final c = AppPalette.of(context);
    final existing =
        controller.getSelectionStyle().attributes[Attribute.link.key]?.value;
    final text = TextEditingController(text: existing?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          _t('添加链接'),
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        content: SizedBox(
          width: (MediaQuery.sizeOf(context).width - 96).clamp(220.0, 380.0),
          child: TextField(
            controller: text,
            autofocus: true,
            style: TextStyle(fontFamily: 'NotoSansSC', fontSize: 13, color: c.ink),
            decoration: InputDecoration(
              hintText: 'https://',
              hintStyle: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 13,
                color: c.inkMuted,
              ),
              filled: true,
              fillColor: c.paper,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: c.accent),
              ),
            ),
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: Text(_t('移除'), style: TextStyle(color: c.inkMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.ink,
              foregroundColor: c.paper,
            ),
            onPressed: () => Navigator.of(context).pop(text.text.trim()),
            child: Text(_t('应用')),
          ),
        ],
      ),
    );
    text.dispose();
    return result;
  }

}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    this.active = false,
    this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: SoftIconButton(
        icon: icon,
        tooltip: tooltip,
        active: active,
        size: 32,
        iconSize: 16,
        onPressed: onPressed,
      ),
    );
  }
}

class _HuaziButton extends StatelessWidget {
  const _HuaziButton({required this.active, required this.onPressed});
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: HoverBuilder(
        builder: (context, hovered, t) {
          return GestureDetector(
            onTap: onPressed,
            child: AnimatedContainer(
              duration: Motion.fast,
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: active
                    ? c.accent
                    : hovered
                        ? c.accentSoft
                        : c.accentSoft.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: active ? c.accent : c.accent.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.sparkles,
                    size: 14,
                    color: active ? c.onAccent : c.accent,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _t('花字'),
                    style: TextStyle(
                      fontFamily: 'WenKai',
                      fontSize: 13,
                      letterSpacing: 1,
                      color: active ? c.onAccent : c.accent,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _FontChip extends StatelessWidget {
  const _FontChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: HoverBuilder(
        builder: (context, hovered, t) {
          return GestureDetector(
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              // 英文名（WenKai / XiaoWei）比中文名宽，允许最少 64 宽、按需变宽。
              constraints: const BoxConstraints(minWidth: 64),
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              decoration: BoxDecoration(
                color: active
                    ? c.accentSoft
                    : hovered
                        ? c.paper
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10.5,
                      color: active ? c.accent : c.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    LucideIcons.chevronDown,
                    size: 11,
                    color: active ? c.accent : c.inkMuted,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.menu,
    required this.active,
    required this.width,
    this.label,
    this.icon,
    this.tooltip = '',
  });

  final String? label;
  final IconData? icon;
  final List<_MenuItem> menu;
  final bool active;
  final double width;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopupMenuButton<int>(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      position: PopupMenuPosition.under,
      color: c.surface,
      onSelected: (i) => menu[i].onTap(),
      itemBuilder: (context) => [
        for (final item in menu)
          PopupMenuItem<int>(
            value: menu.indexOf(item),
            height: 38,
            child: Row(
              children: [
                if (item.icon != null) ...[
                  Icon(item.icon, size: 14, color: c.inkMuted),
                  const SizedBox(width: 9),
                ],
                Text(
                  item.label,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 12,
                    color: c.ink,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: BoxConstraints(minWidth: width),
        height: 30,
        padding: EdgeInsets.symmetric(horizontal: icon != null ? 0 : 9),
        decoration: BoxDecoration(
          color: active ? c.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null)
              Icon(icon, size: 16, color: active ? c.accent : c.inkSoft)
            else ...[
              Text(
                label ?? '',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10.5,
                  color: active ? c.accent : c.inkSoft,
                ),
              ),
              const SizedBox(width: 3),
              Icon(
                LucideIcons.chevronDown,
                size: 12,
                color: active ? c.accent : c.inkMuted,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuItem {
  const _MenuItem(this.label, this.onTap, {this.icon});
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
}

class _Sep extends StatelessWidget {
  const _Sep();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: 1,
      height: 17,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: c.line,
    );
  }
}
