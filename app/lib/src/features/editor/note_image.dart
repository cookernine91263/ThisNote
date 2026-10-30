import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

enum NoteImageTheme { paper, ink, rose, sage }

class _Paper {
  const _Paper({
    required this.bg,
    required this.surface,
    required this.ink,
    required this.soft,
    required this.accent,
    required this.line,
  });

  final Color bg;
  final Color surface;
  final Color ink;
  final Color soft;
  final Color accent;
  final Color line;

  static _Paper of(NoteImageTheme theme) => switch (theme) {
        NoteImageTheme.paper => const _Paper(
            bg: Color(0xFFF4EDDF),
            surface: Color(0xFFFFFBF3),
            ink: Color(0xFF211E19),
            soft: Color(0xFF6F675B),
            accent: Color(0xFFA84637),
            line: Color(0xFFDFD2BC),
          ),
        NoteImageTheme.ink => const _Paper(
            bg: Color(0xFF171411),
            surface: Color(0xFF1E1A16),
            ink: Color(0xFFEDE5D6),
            soft: Color(0xFFA59C8C),
            accent: Color(0xFFD38172),
            line: Color(0xFF3A342B),
          ),
        NoteImageTheme.rose => const _Paper(
            bg: Color(0xFFF1E3DD),
            surface: Color(0xFFFBF2ED),
            ink: Color(0xFF392326),
            soft: Color(0xFF7F6363),
            accent: Color(0xFF9A4F50),
            line: Color(0xFFE1CBC4),
          ),
        NoteImageTheme.sage => const _Paper(
            bg: Color(0xFFE8EDE3),
            surface: Color(0xFFF5F8F1),
            ink: Color(0xFF263229),
            soft: Color(0xFF667263),
            accent: Color(0xFF5F7464),
            line: Color(0xFFCED9C8),
          ),
      };
}

Future<void> showPngExport(BuildContext context) async {
  final state = context.read<AppState>();
  final note = state.current;
  if (note == null) return;
  await state.saveNow();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    builder: (_) => _PngDialog(note: note),
  );
}

class _PngDialog extends StatefulWidget {
  const _PngDialog({required this.note});
  final Note note;

  @override
  State<_PngDialog> createState() => _PngDialogState();
}

class _PngDialogState extends State<_PngDialog> {
  final _boundary = GlobalKey();
  NoteImageTheme _theme = NoteImageTheme.paper;
  bool _showMeta = true;
  bool _showTags = true;
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final object = _boundary.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;
      final image = await object.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      final base = _safeName(widget.note.title);
      if (Platform.isAndroid) {
        final dir = await getTemporaryDirectory();
        final file = File(p.join(dir.path, '$base.png'));
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            subject: widget.note.title.isEmpty ? '此记 · 图片' : widget.note.title,
          ),
        );
      } else {
        final location = await getSaveLocation(
          suggestedName: '$base.png',
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PNG 图片', extensions: ['png']),
          ],
        );
        if (location != null) {
          await File(location.path).writeAsBytes(bytes, flush: true);
          if (mounted) showToast(context, '图片已保存');
        }
      }
    } catch (e) {
      if (mounted) showToast(context, '导出图片失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 760,
          maxHeight: size.height - 46,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 50,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 12, 10),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '把这一页变成图片',
                            style: TextStyle(
                              fontFamily: 'WenKai',
                              fontSize: 23,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '不截屏，重新排一张可以收藏的纸',
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
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width =
                          (constraints.maxWidth - 76).clamp(300.0, 520.0);
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                        child: Center(
                          child: RepaintBoundary(
                            key: _boundary,
                            child: NoteImageCard(
                              note: widget.note,
                              theme: _theme,
                              width: width,
                              showMeta: _showMeta,
                              showTags: _showTags,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '纸色',
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10,
                              color: c.inkMuted,
                            ),
                          ),
                          for (final theme in NoteImageTheme.values)
                            _ThemeDot(
                              theme: theme,
                              active: theme == _theme,
                              onTap: () => setState(() => _theme = theme),
                            ),
                          _ToggleText(
                            label: '日期',
                            value: _showMeta,
                            onTap: () =>
                                setState(() => _showMeta = !_showMeta),
                          ),
                          _ToggleText(
                            label: '标签',
                            value: _showTags,
                            onTap: () =>
                                setState(() => _showTags = !_showTags),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            '长图会按内容自动延展',
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 9.5,
                              color: c.inkMuted,
                            ),
                          ),
                          const Spacer(),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.ink,
                              foregroundColor: c.paper,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 11,
                              ),
                            ),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.download, size: 15),
                            label: Text(_saving ? '正在生成…' : '保存 PNG'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({
    required this.theme,
    required this.active,
    required this.onTap,
  });
  final NoteImageTheme theme;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = _Paper.of(theme);
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: paper.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? c.ink : c.lineStrong.withValues(alpha: 0.55),
            width: active ? 2 : 1,
          ),
        ),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: paper.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleText extends StatelessWidget {
  const _ToggleText({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? LucideIcons.eye : LucideIcons.eyeOff,
            size: 12,
            color: value ? c.accent : c.inkMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9.5,
              color: value ? c.inkSoft : c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class NoteImageCard extends StatelessWidget {
  const NoteImageCard({
    required this.note,
    required this.theme,
    required this.width,
    this.showMeta = true,
    this.showTags = true,
    super.key,
  });

  final Note note;
  final NoteImageTheme theme;
  final double width;
  final bool showMeta;
  final bool showTags;

  @override
  Widget build(BuildContext context) {
    final paper = _Paper.of(theme);
    final scale = (width / 520).clamp(0.6, 1.0);
    final title = note.title.trim().isEmpty ? '无题' : note.title.trim();
    final lines = _Lines(note.delta, paper, scale).parse();
    final date = dateLabel(note.createdAt);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: paper.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: paper.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -width * 0.12,
            top: -width * 0.16,
            child: Container(
              width: width * 0.55,
              height: width * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    paper.accent.withValues(alpha: 0.08),
                    paper.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(42 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3 * scale,
                      height: 18 * scale,
                      color: paper.accent,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '此记',
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 13 * scale,
                        letterSpacing: 2,
                        color: paper.accent,
                      ),
                    ),
                    const Spacer(),
                    if (showMeta)
                      Text(
                        date,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9 * scale,
                          color: paper.soft,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 30 * scale),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 37 * scale,
                    height: 1.28,
                    letterSpacing: 1,
                    color: paper.ink,
                  ),
                ),
                if (showMeta) ...[
                  SizedBox(height: 10 * scale),
                  Text(
                    _subtitle(),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5 * scale,
                      height: 1.6,
                      color: paper.soft,
                    ),
                  ),
                ],
                if (showTags && note.tags.isNotEmpty) ...[
                  SizedBox(height: 16 * scale),
                  Wrap(
                    spacing: 7 * scale,
                    runSpacing: 6 * scale,
                    children: [
                      for (final tag in note.tags)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * scale,
                            vertical: 3 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: paper.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: paper.line),
                          ),
                          child: Text(
                            '# $tag',
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 8.5 * scale,
                              color: paper.soft,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                SizedBox(height: 22 * scale),
                Container(height: 0.8, color: paper.line),
                SizedBox(height: 18 * scale),
                if (lines.isEmpty)
                  Text(
                    '这一页还没有字。',
                    style: TextStyle(
                      fontFamily: 'NotoSerifSC',
                      fontSize: 14 * scale,
                      color: paper.soft,
                    ),
                  )
                else
                  for (final line in lines) _lineView(line, paper, scale),
                SizedBox(height: 28 * scale),
                Row(
                  children: [
                    Text(
                      '${note.words} 字',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9 * scale,
                        color: paper.soft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '此记 · ThisNote',
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 10 * scale,
                        letterSpacing: 1,
                        color: paper.soft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      note.kind.label,
      if (note.weather != null)
        WeatherX.fromKey(note.weather)?.label ?? '',
      if (note.mood != null) MoodX.fromScore(note.mood)?.label ?? '',
    ].where((e) => e.isNotEmpty).toList();
    return parts.join(' · ');
  }

  Widget _lineView(_Line line, _Paper paper, double scale) {
    final header = int.tryParse(line.header ?? '');
    final base = TextStyle(
      fontFamily: 'NotoSerifSC',
      fontSize: 14.5 * scale,
      height: 1.9,
      color: paper.ink,
    );
    final style = header == null
        ? base
        : base.copyWith(
            fontFamily: 'WenKai',
            fontSize:
                (header == 1 ? 26 : header == 2 ? 21 : 17) * scale,
            height: 1.45,
            fontWeight: FontWeight.w600,
          );
    final spans = <InlineSpan>[
      if (line.list != null)
        TextSpan(
          text: '·  ',
          style: style.copyWith(color: paper.accent),
        ),
      ...line.spans,
    ];
    final text = Text.rich(
      TextSpan(children: spans),
      style: style,
      textAlign: switch (line.align) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      },
    );
    return Padding(
      padding: EdgeInsets.only(
        left: line.quote ? 13 * scale : 0,
        bottom: (header == null ? 10 : 14) * scale,
      ),
      child: line.quote
          ? Container(
              padding: EdgeInsets.only(left: 12 * scale),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(
                    color: paper.accent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
              ),
              child: text,
            )
          : text,
    );
  }
}

class _Line {
  _Line({
    required this.spans,
    this.header,
    this.quote = false,
    this.list,
    this.align = 'left',
  });
  final List<InlineSpan> spans;
  final String? header;
  final bool quote;
  final String? list;
  final String align;
}

class _Lines {
  _Lines(this.delta, this.paper, this.scale);
  final List<dynamic> delta;
  final _Paper paper;
  final double scale;

  List<_Line> parse() {
    final lines = <_Line>[];
    var spans = <InlineSpan>[];
    String? header;
    var quote = false;
    String? list;
    var align = 'left';

    void flush() {
      if (spans.isNotEmpty || header != null || quote || list != null) {
        lines.add(_Line(
          spans: List.of(spans),
          header: header,
          quote: quote,
          list: list,
          align: align,
        ));
      }
      spans = <InlineSpan>[];
      header = null;
      quote = false;
      list = null;
      align = 'left';
    }

    for (final op in delta) {
      if (op is! Map) continue;
      final insert = op['insert'];
      final attrs = (op['attributes'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (insert is String) {
        final parts = insert.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            spans.add(TextSpan(
              text: parts[i],
              style: _inline(attrs),
            ));
          }
          if (i < parts.length - 1) {
            header = attrs['header']?.toString();
            quote = attrs['blockquote'] == true;
            list = attrs['list']?.toString();
            align = attrs['align']?.toString() ?? 'left';
            flush();
          }
        }
      } else if (insert is Map && insert['image'] is String) {
        spans.add(TextSpan(
          text: '［图片］',
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 10 * scale,
            color: paper.accent,
          ),
        ));
      }
    }
    flush();
    return lines;
  }

  TextStyle? _inline(Map<String, dynamic> attrs) {
    if (attrs.isEmpty) return null;
    var style = TextStyle(
      fontFamily: 'NotoSerifSC',
      fontSize: 14.5 * scale,
      height: 1.9,
      color: paper.ink,
    );
    final font = attrs['font']?.toString();
    if (font != null && font.isNotEmpty) {
      style = style.copyWith(fontFamily: font);
    }
    final size = attrs['size']?.toString();
    if (size != null) {
      style = style.copyWith(
        fontSize: (size == 'huge' || size == '40'
                ? 24
                : size == 'large'
                    ? 19
                    : 16) *
            scale,
        height: 1.35,
      );
    }
    if (attrs['bold'] == true) {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (attrs['italic'] == true) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    if (attrs['underline'] == true) {
      style = style.copyWith(decoration: TextDecoration.underline);
    }
    if (attrs['strike'] == true) {
      style = style.copyWith(
        decoration: TextDecoration.combine([
          if (style.decoration != null) style.decoration!,
          TextDecoration.lineThrough,
        ]),
      );
    }
    final color = attrs['color']?.toString();
    if (color != null) {
      final parsed = parseHex(color);
      if (parsed != null) style = style.copyWith(color: parsed);
    }
    final background = attrs['background']?.toString();
    if (background != null) {
      final parsed = parseHex(background);
      if (parsed != null) style = style.copyWith(backgroundColor: parsed);
    }
    if (attrs['link'] != null) {
      style = style.copyWith(
        color: paper.accent,
        decoration: TextDecoration.underline,
      );
    }
    return style;
  }
}

String _safeName(String title) {
  final base = title.trim().isEmpty
      ? '此记-${DateTime.now().millisecondsSinceEpoch}'
      : title.trim();
  final clean = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return clean.substring(0, clean.length > 50 ? 50 : clean.length);
}
