import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/repository.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '图片已不在此设备上': 'Image is no longer on this device',
  '图片': 'Image',
  '看大图': 'View larger',
  '宽度': 'Width',
  '对齐': 'Align',
  '左': 'Left',
  '居中': 'Center',
  '右': 'Right',
  '替换…': 'Replace…',
  '删除': 'Delete',
  '完成': 'Done',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

/// 图片的宽度与对齐保存在 embed 自身的属性上，不改动正文，
/// 也不影响旧版只有路径的图片。
const String imageWidthKey = 'imageWidth';
const String imageAlignKey = 'imageAlign';

double imageWidthOf(Embed node) {
  final raw = node.style.attributes[imageWidthKey]?.value?.toString();
  final value = double.tryParse(raw ?? '');
  if (value == null) return 1;
  return value.clamp(0.2, 1.0);
}

String imageAlignOf(Embed node) {
  final raw = node.style.attributes[imageAlignKey]?.value?.toString();
  return raw == 'center' || raw == 'right' ? raw! : 'left';
}

Alignment alignmentFor(String value) {
  return switch (value) {
    'center' => Alignment.center,
    'right' => Alignment.centerRight,
    _ => Alignment.centerLeft,
  };
}

/// 给某一张图片写入宽度/对齐。offset 是该 embed 在文档里的位置。
void applyImageLayout(
  QuillController controller,
  int offset, {
  String? width,
  String? align,
}) {
  final attrs = <String, dynamic>{
    imageWidthKey: ?width,
    imageAlignKey: ?align,
  };
  if (attrs.isEmpty) return;
  controller.compose(
    Delta()
      ..retain(offset)
      ..retain(1, attrs),
    controller.selection,
    ChangeSource.local,
  );
}

class NoteImageEmbedBuilder extends EmbedBuilder {
  NoteImageEmbedBuilder(this.store);
  final NoteStore store;

  @override
  String get key => BlockEmbed.imageType;

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = embedContext.node.value.data?.toString() ?? '';
    if (data.isEmpty) return const SizedBox.shrink();
    final file = File(store.resolveAsset(data));
    final width = imageWidthOf(embedContext.node);
    final alignment = alignmentFor(imageAlignOf(embedContext.node));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: alignment,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: () => _edit(context, embedContext, file),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    file,
                    width: constraints.maxWidth * width,
                    cacheWidth: (constraints.maxWidth *
                            width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(64, 4096),
                    fit: BoxFit.fitWidth,
                    errorBuilder: (context, error, stack) => _missing(context),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _missing(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      width: 240,
      height: 90,
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      alignment: Alignment.center,
      child: Text(
        _t('图片已不在此设备上'),
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 10,
          color: c.inkMuted,
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context,
    EmbedContext embedContext,
    File file,
  ) async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.25),
      builder: (_) => _ImageControls(
        controller: embedContext.controller,
        // node.offset 是行内偏移，必须换成整篇文档里的偏移，
        // 否则属性会写到这一行的第一个字上。
        offset: embedContext.node.documentOffset,
        file: file,
        store: store,
      ),
    );
  }
}

class _ImageControls extends StatefulWidget {
  const _ImageControls({
    required this.controller,
    required this.offset,
    required this.file,
    required this.store,
  });

  final QuillController controller;
  final int offset;
  final File file;
  final NoteStore store;

  @override
  State<_ImageControls> createState() => _ImageControlsState();
}

class _ImageControlsState extends State<_ImageControls> {
  late double _width;
  late String _align;
  late File _file;

  @override
  void initState() {
    super.initState();
    final line = widget.controller.document.root.children;
    // 从当前文档里取回这张图的属性，作为面板初值。
    _width = 1;
    _align = 'left';
    for (final node in line) {
      if (node is! Line) continue;
      for (final leaf in node.children) {
        if (leaf is Embed && leaf.documentOffset == widget.offset) {
          _width = imageWidthOf(leaf);
          _align = imageAlignOf(leaf);
        }
      }
    }
    _file = widget.file;
  }

  void _setWidth(double value) {
    applyImageLayout(
      widget.controller,
      widget.offset,
      width: value.toStringAsFixed(2),
    );
    setState(() => _width = value);
  }

  void _setAlign(String value) {
    applyImageLayout(widget.controller, widget.offset, align: value);
    setState(() => _align = value);
  }

  Future<void> _replace() async {
    final picked = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: _t('图片'),
          extensions: const ['jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'],
        ),
      ],
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final ext = p.extension(picked.name).replaceAll('.', '');
    final rel = await widget.store.saveAsset(
      bytes,
      ext.isEmpty ? 'png' : ext,
    );
    if (!mounted) return;
    widget.controller.replaceText(
      widget.offset,
      1,
      BlockEmbed.image(rel),
      TextSelection.collapsed(offset: widget.offset + 1),
    );
    // replaceText 会重建这个 embed，宽度/对齐要重新写回去。
    applyImageLayout(
      widget.controller,
      widget.offset,
      width: _width.toStringAsFixed(2),
      align: _align,
    );
    setState(() {
      _file = File(widget.store.resolveAsset(rel));
    });
  }

  void _delete() {
    widget.controller.replaceText(
      widget.offset,
      1,
      '',
      TextSelection.collapsed(offset: widget.offset),
    );
    Navigator.of(context).pop();
  }

  void _preview() {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(child: Image.file(_file, cacheWidth: 2400)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _t('图片'),
                    style: TextStyle(
                      fontFamily: 'WenKai',
                      fontSize: 20,
                      letterSpacing: 1,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _preview,
                    child: Text(
                      _t('看大图'),
                      style: const TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  SoftIconButton(
                    icon: LucideIcons.x,
                    size: 28,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    _file,
                    height: 200,
                    cacheWidth: 1200,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stack) => Text(
                      _t('图片已不在此设备上'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _Label(_t('宽度')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final option in const [0.25, 0.5, 0.75, 1.0])
                    _Choice(
                      label: '${(option * 100).round()}%',
                      selected: (_width - option).abs() < 0.01,
                      onTap: () => _setWidth(option),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _Label(_t('对齐')),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: [
                  for (final option in const [
                    ('left', '左', LucideIcons.alignLeft),
                    ('center', '居中', LucideIcons.alignCenter),
                    ('right', '右', LucideIcons.alignRight),
                  ])
                    _Choice(
                      label: _t(option.$2),
                      icon: option.$3,
                      selected: _align == option.$1,
                      onTap: () => _setAlign(option.$1),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _replace,
                    icon: const Icon(LucideIcons.imagePlus, size: 14),
                    label: Text(
                      _t('替换…'),
                      style: const TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _delete,
                    icon: Icon(LucideIcons.trash2, size: 14, color: c.danger),
                    label: Text(
                      _t('删除'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11,
                        color: c.danger,
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.ink,
                      foregroundColor: c.paper,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_t('完成')),
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

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 9.5,
        letterSpacing: 0.8,
        color: c.inkMuted,
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.paper,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected ? c.accent.withValues(alpha: 0.45) : c.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 12,
                color: selected ? c.accent : c.inkMuted,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: selected ? c.accent : c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DividerEmbedBuilder extends EmbedBuilder {
  const DividerEmbedBuilder();

  @override
  String get key => 'divider';

  @override
  bool get expanded => true;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: c.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            ),
          ),
          Expanded(child: Container(height: 1, color: c.line)),
        ],
      ),
    );
  }
}
