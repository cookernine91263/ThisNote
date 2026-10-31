import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

import '../../core/theme.dart';

DefaultStyles buildQuillStyles(
  AppPalette c, {
  required double scale,
  required double lineHeight,
  double paragraphGap = 0,
  double letterSpacing = 0.15,
}) {
  final bodySize = 17.0 * scale;
  final gap = paragraphGap.clamp(0.0, 40.0);
  final paragraphSpacing = VerticalSpacing(2 + gap / 2, 2 + gap / 2);
  final body = TextStyle(
    fontFamily: 'NotoSansSC',
    fontSize: bodySize,
    height: lineHeight,
    color: c.ink,
    letterSpacing: letterSpacing,
  );

  DefaultTextBlockStyle block(
    TextStyle style, {
    VerticalSpacing? vertical,
    HorizontalSpacing? horizontal,
    BoxDecoration? decoration,
  }) =>
      DefaultTextBlockStyle(
        style,
        horizontal ?? const HorizontalSpacing(0, 0),
        vertical ?? paragraphSpacing,
        VerticalSpacing.zero,
        decoration,
      );

  return DefaultStyles(
    paragraph: block(body),
    h1: block(
      TextStyle(
        fontFamily: 'WenKai',
        fontSize: 30 * scale,
        height: 1.45,
        color: c.ink,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      vertical: const VerticalSpacing(24, 10),
    ),
    h2: block(
      TextStyle(
        fontFamily: 'WenKai',
        fontSize: 24 * scale,
        height: 1.45,
        color: c.ink,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
      vertical: const VerticalSpacing(20, 8),
    ),
    h3: block(
      TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 20 * scale,
        height: 1.5,
        color: c.ink,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      vertical: const VerticalSpacing(16, 6),
    ),
    h4: block(body.copyWith(fontSize: 18 * scale, fontWeight: FontWeight.w600)),
    h5: block(body.copyWith(fontSize: 17 * scale, fontWeight: FontWeight.w600)),
    h6: block(body.copyWith(fontSize: 16 * scale, fontWeight: FontWeight.w600)),
    lineHeightNormal: block(body.copyWith(height: 1.45)),
    lineHeightTight: block(body.copyWith(height: 1.7)),
    lineHeightOneAndHalf: block(body.copyWith(height: 1.9)),
    lineHeightDouble: block(body.copyWith(height: 2.2)),
    quote: block(
      body.copyWith(color: c.inkSoft),
      horizontal: const HorizontalSpacing(16, 12),
      vertical: VerticalSpacing(8 + gap / 2, 8 + gap / 2),
      decoration: BoxDecoration(
        color: c.accentSoft.withValues(alpha: c.isDark ? 0.35 : 0.32),
        border: Border(
          left: BorderSide(color: c.accent.withValues(alpha: 0.55), width: 2),
        ),
        borderRadius: BorderRadius.circular(3),
      ),
    ),
    code: block(
      TextStyle(
        fontFamily: 'monospace',
        fontSize: 14 * scale,
        height: 1.65,
        color: c.inkSoft,
      ),
      horizontal: const HorizontalSpacing(14, 12),
      vertical: VerticalSpacing(10 + gap / 2, 10 + gap / 2),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
    ),
    lists: DefaultListBlockStyle(
      body,
      const HorizontalSpacing(0, 0),
      paragraphSpacing,
      VerticalSpacing.zero,
      null,
      null,
    ),
    bold: const TextStyle(fontWeight: FontWeight.w700),
    italic: const TextStyle(fontStyle: FontStyle.italic),
    underline: TextStyle(
      decoration: TextDecoration.underline,
      decorationColor: c.inkMuted,
    ),
    strikeThrough: TextStyle(
      decoration: TextDecoration.lineThrough,
      decorationColor: c.inkMuted,
    ),
    link: TextStyle(
      color: c.blue,
      decoration: TextDecoration.underline,
      decorationColor: c.blue,
    ),
    inlineCode: InlineCodeStyle(
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13.5 * scale,
        color: c.accent,
      ),
      backgroundColor: c.surfaceAlt,
      radius: const Radius.circular(4),
    ),
    placeHolder: block(body.copyWith(color: c.inkMuted)),
    color: c.ink,
    sizeSmall: body.copyWith(fontSize: 13 * scale),
    sizeLarge: body.copyWith(fontSize: 22 * scale),
    sizeHuge: body.copyWith(fontSize: 30 * scale),
    small: TextStyle(fontSize: 12 * scale),
    subscript: TextStyle(fontSize: 11 * scale),
    superscript: TextStyle(fontSize: 11 * scale),
    indent: block(body),
    align: block(body),
    leading: block(body),
  );
}
