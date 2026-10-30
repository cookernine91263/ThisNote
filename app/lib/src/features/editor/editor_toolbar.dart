import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../../core/format.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';
import '../ai_sheet.dart';
import 'huazi.dart';

const _textColors = <String>[
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

const _highlightColors = <String>[
  '#F3E2BE',
  '#EED4CA',
  '#DCE6D6',
  '#D6E2EA',
  '#E8DCE8',
  '#EDE3D0',
  '#DDD8CE',
  '#F5E9D7',
];

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
        bool has(String key) => attrs.containsKey(key);
        final header = attrs[Attribute.header.key]?.value;
        final list = attrs[Attribute.list.key]?.value;
        final align = attrs[Attribute.align.key]?.value;
        final font = attrs[Attribute.font.key]?.value;
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
            tooltip: '撤销 · Ctrl Z',
            onPressed: controller.hasUndo ? controller.undo : null,
          ),
          _ToolButton(
            icon: LucideIcons.redo2,
            tooltip: '重做 · Ctrl Y',
            onPressed: controller.hasRedo ? controller.redo : null,
          ),
          const _Sep(),
          _MenuChip(
            label: switch (header) {
              1 => '标题 1',
              2 => '标题 2',
              3 => '标题 3',
              _ => '正文',
            },
            active: header != null,
            width: 72,
            menu: [
              _MenuItem('正文', () => applyHeader(null)),
              _MenuItem('标题 1', () => applyHeader(1)),
              _MenuItem('标题 2', () => applyHeader(2)),
              _MenuItem('标题 3', () => applyHeader(3)),
            ],
          ),
          const SizedBox(width: 2),
          _ToolButton(
            icon: LucideIcons.bold,
            tooltip: '加粗 · Ctrl B',
            active: has('bold'),
            onPressed: () => toggle(Attribute.bold),
          ),
          _ToolButton(
            icon: LucideIcons.italic,
            tooltip: '倾斜 · Ctrl I',
            active: has('italic'),
            onPressed: () => toggle(Attribute.italic),
          ),
          _ToolButton(
            icon: LucideIcons.type,
            tooltip: '变细',
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
            tooltip: '下划线 · Ctrl U',
            active: has('underline'),
            onPressed: () => toggle(Attribute.underline),
          ),
          _ToolButton(
            icon: LucideIcons.strikethrough,
            tooltip: '删除线',
            active: has('strike'),
            onPressed: () => toggle(Attribute.strikeThrough),
          ),
          const _Sep(),
          _ToolButton(
            icon: LucideIcons.palette,
            tooltip: '文字颜色',
            active: has('color'),
            onPressed: () async {
              final hex = await _pickColor(context, background: false);
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
            tooltip: '高亮',
            active: has('background'),
            onPressed: () async {
              final hex = await _pickColor(context, background: true);
              if (hex == null) return;
              controller.formatSelection(
                hex == 'clear'
                    ? Attribute.clone(Attribute.background, null)
                    : Attribute('background', AttributeScope.inline, hex),
              );
            },
          ),
          _MenuChip(
            icon: switch (align) {
              'center' => LucideIcons.alignCenter,
              'right' => LucideIcons.alignRight,
              'justify' => LucideIcons.alignJustify,
              _ => LucideIcons.alignLeft,
            },
            active: align != null,
            width: 38,
            menu: [
              _MenuItem('左对齐', () => applyAlign('left'), icon: LucideIcons.alignLeft),
              _MenuItem('居中', () => applyAlign('center'), icon: LucideIcons.alignCenter),
              _MenuItem('右对齐', () => applyAlign('right'), icon: LucideIcons.alignRight),
              _MenuItem('两端对齐', () => applyAlign('justify'), icon: LucideIcons.alignJustify),
            ],
          ),
          _MenuChip(
            icon: switch (list) {
              'ordered' => LucideIcons.listOrdered,
              'checked' || 'unchecked' => LucideIcons.listChecks,
              _ => LucideIcons.list,
            },
            active: list != null,
            width: 38,
            menu: [
              _MenuItem('无序列表', () => applyList('bullet'), icon: LucideIcons.list),
              _MenuItem('有序列表', () => applyList('ordered'), icon: LucideIcons.listOrdered),
              _MenuItem('待办清单', () => applyList('unchecked'), icon: LucideIcons.listChecks),
            ],
          ),
          _ToolButton(
            icon: LucideIcons.textQuote,
            tooltip: '引用',
            active: has('blockquote'),
            onPressed: () => toggle(Attribute.blockQuote),
          ),
          _ToolButton(
            icon: LucideIcons.code,
            tooltip: '代码块',
            active: has('code-block'),
            onPressed: () => toggle(Attribute.codeBlock),
          ),
          _ToolButton(
            icon: LucideIcons.link,
            tooltip: '链接',
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
            tooltip: '插入图片',
            onPressed: () => _insertImage(context),
          ),
          _ToolButton(
            icon: LucideIcons.separatorHorizontal,
            tooltip: '分隔线',
            onPressed: session.insertDivider,
          ),
          const _Sep(),
          _ToolButton(
            icon: LucideIcons.sparkles,
            tooltip: 'AI 助手 · 润色 / 续写 / 起标题',
            onPressed: () => showAiSheet(context, session),
          ),
          _HuaziButton(
            active: huazi,
            onPressed: () => showHuaziGallery(context, session),
          ),
          _ToolButton(
            icon: LucideIcons.removeFormatting,
            tooltip: '清除格式',
            onPressed: session.clearFormatting,
          ),
        ];

        return Container(
          height: mobile ? 46 : 44,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(
              top: mobile ? BorderSide(color: c.line) : BorderSide.none,
              bottom: mobile ? BorderSide.none : BorderSide(color: c.line),
            ),
          ),
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
      },
    );
  }

  Future<void> _insertImage(BuildContext context) async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '图片',
          extensions: ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
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
          '添加链接',
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        content: SizedBox(
          width: 380,
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
            child: Text('移除', style: TextStyle(color: c.inkMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.ink,
              foregroundColor: c.paper,
            ),
            onPressed: () => Navigator.of(context).pop(text.text.trim()),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    text.dispose();
    return result;
  }

  Future<String?> _pickColor(
    BuildContext context, {
    required bool background,
  }) async {
    final c = AppPalette.of(context);
    final colors = background ? _highlightColors : _textColors;
    return showDialog<String>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.line),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                background ? '高亮颜色' : '文字颜色',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hex in colors)
                    InkWell(
                      onTap: () => Navigator.of(context).pop(hex),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: parseHex(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.lineStrong.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop('clear'),
                  child: Text(
                    '清除颜色',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 11,
                      color: c.inkMuted,
                    ),
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
                    '花字',
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

class _MenuChip extends StatelessWidget {
  const _MenuChip({
    required this.menu,
    required this.active,
    required this.width,
    this.label,
    this.icon,
  });

  final String? label;
  final IconData? icon;
  final List<_MenuItem> menu;
  final bool active;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopupMenuButton<int>(
      tooltip: '',
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
        width: width,
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
