import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../core/theme.dart';
import '../../data/repository.dart';

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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: () => _preview(context, file),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  file,
                  width: constraints.maxWidth,
                  fit: BoxFit.fitWidth,
                  errorBuilder: (context, error, stack) => _missing(context),
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
        '图片已不在此设备上',
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 10,
          color: c.inkMuted,
        ),
      ),
    );
  }

  void _preview(BuildContext context, File file) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
      builder: (context) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          maxScale: 4,
          child: Center(child: Image.file(file)),
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
