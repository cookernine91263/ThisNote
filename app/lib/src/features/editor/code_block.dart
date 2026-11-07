import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:highlight/highlight_core.dart' as hl;
import 'package:highlight/languages/bash.dart' as bash;
import 'package:highlight/languages/cpp.dart' as cpp;
import 'package:highlight/languages/cs.dart' as cs;
import 'package:highlight/languages/css.dart' as css;
import 'package:highlight/languages/dart.dart' as dart;
import 'package:highlight/languages/go.dart' as go;
import 'package:highlight/languages/java.dart' as java;
import 'package:highlight/languages/javascript.dart' as javascript;
import 'package:highlight/languages/json.dart' as json;
import 'package:highlight/languages/kotlin.dart' as kotlin;
import 'package:highlight/languages/markdown.dart' as markdown;
import 'package:highlight/languages/python.dart' as python;
import 'package:highlight/languages/rust.dart' as rust;
import 'package:highlight/languages/sql.dart' as sql;
import 'package:highlight/languages/swift.dart' as swift;
import 'package:highlight/languages/typescript.dart' as typescript;
import 'package:highlight/languages/xml.dart' as xml;
import 'package:highlight/languages/yaml.dart' as yaml;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import 'table_embed.dart';

const Map<String, String> _en = <String, String>{
  '代码块': 'Code block',
  '纯文本': 'Plain text',
  '语言': 'Language',
  '代码': 'Code',
  '在这里粘贴或输入代码…': 'Paste or type code here…',
  '保存': 'Save',
  '取消': 'Cancel',
  '删除代码块': 'Delete block',
  '已复制代码': 'Code copied',
  '复制代码': 'Copy code',
  '编辑代码': 'Edit code',
  '删除': 'Delete',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

const String codeBlockKey = 'code-block';

class CodeBlockData {
  const CodeBlockData({required this.code, this.language = ''});

  final String code;
  final String language;

  Map<String, dynamic> toJson() => {'code': code, 'lang': language};

  factory CodeBlockData.fromJson(Map<String, dynamic> json) => CodeBlockData(
        code: (json['code'] ?? json['text'] ?? '').toString(),
        language: (json['lang'] ?? json['language'] ?? '').toString(),
      );

  static CodeBlockData? fromRaw(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) {
      return CodeBlockData.fromJson(raw.cast<String, dynamic>());
    }
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is Map) {
        return CodeBlockData.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return null;
  }
}

CodeBlockData? codeBlockOf(Embeddable embed) {
  if (embed.type != codeBlockKey) return null;
  return CodeBlockData.fromRaw(embed.data);
}

BlockEmbed codeBlockEmbed(CodeBlockData data) =>
    BlockEmbed(codeBlockKey, jsonEncode(data.toJson()));

/// 把 Delta 转成可搜索/可统计的纯文本。代码块整段保留，图片与分隔线跳过。
String deltaPlainText(Delta delta) {
  final out = StringBuffer();
  for (final op in delta.toList()) {
    final data = op.data;
    if (data is String) {
      out.write(data);
      continue;
    }
    if (data is Embeddable) {
      final code = codeBlockOf(data);
      if (code != null) {
        out
          ..write(code.code)
          ..write('\n');
      } else {
        final table = tableOf(data);
        if (table != null) {
          out
            ..write(table.plainText)
            ..write('\n');
        } else {
          out.write(Embed.kObjectReplacementCharacter);
        }
      }
      continue;
    }
    if (data is Map) {
      final code = CodeBlockData.fromRaw(data[codeBlockKey]);
      if (code != null) {
        out
          ..write(code.code)
          ..write('\n');
      } else {
        final table = TableData.fromRaw(data[tableKey]);
        if (table != null) {
          out
            ..write(table.plainText)
            ..write('\n');
        } else {
          out.write(Embed.kObjectReplacementCharacter);
        }
      }
    }
  }
  return out.toString();
}

const Map<String, String> codeLanguages = {
  '': '纯文本',
  'dart': 'Dart',
  'python': 'Python',
  'cpp': 'C++',
  'c': 'C',
  'javascript': 'JavaScript',
  'typescript': 'TypeScript',
  'json': 'JSON',
  'html': 'HTML',
  'css': 'CSS',
  'sql': 'SQL',
  'bash': 'Bash',
  'java': 'Java',
  'kotlin': 'Kotlin',
  'swift': 'Swift',
  'go': 'Go',
  'rust': 'Rust',
  'csharp': 'C#',
  'yaml': 'YAML',
  'markdown': 'Markdown',
};

String codeLanguageLabel(String id) {
  final label = codeLanguages[id] ?? id;
  return id.isEmpty ? _t('纯文本') : label;
}

bool _languagesReady = false;

void _ensureLanguages() {
  if (_languagesReady) return;
  _languagesReady = true;
  hl.highlight.registerLanguages({
    'dart': dart.dart,
    'python': python.python,
    'cpp': cpp.cpp,
    'c': cpp.cpp,
    'javascript': javascript.javascript,
    'typescript': typescript.typescript,
    'json': json.json,
    'xml': xml.xml,
    'css': css.css,
    'sql': sql.sql,
    'bash': bash.bash,
    'java': java.java,
    'kotlin': kotlin.kotlin,
    'swift': swift.swift,
    'go': go.go,
    'rust': rust.rust,
    'csharp': cs.cs,
    'yaml': yaml.yaml,
    'markdown': markdown.markdown,
  });
}

class CodeBlockEmbedBuilder extends EmbedBuilder {
  const CodeBlockEmbedBuilder();

  @override
  String get key => codeBlockKey;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) => codeBlockOf(node.value)?.code ?? '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = codeBlockOf(embedContext.node.value);
    if (data == null) return const SizedBox.shrink();
    return _CodeBlockCard(
      data: data,
      controller: embedContext.controller,
      offset: embedContext.node.documentOffset,
    );
  }
}

bool selectionIsCodeBlock(QuillController controller) {
  final selection = controller.selection;
  if (!selection.isValid) return false;
  final node = controller.queryNode(selection.start);
  return node is Embed && node.value.type == codeBlockKey;
}

class LegacyCodeBlock {
  const LegacyCodeBlock({
    required this.start,
    required this.end,
    required this.code,
  });

  final int start;
  final int end;
  final String code;
}

/// 找出光标所在的旧版「行属性代码块」，用于按需升级成代码卡片。
LegacyCodeBlock? legacyCodeBlockAt(QuillController controller) {
  final selection = controller.selection;
  if (!selection.isValid) return null;
  final target = selection.start;
  final lines = <({int start, int end, bool code, String text})>[];
  var pos = 0;
  for (final op in controller.document.toDelta().toList()) {
    final data = op.data;
    if (data is! String) {
      pos += 1;
      continue;
    }
    final isCode = op.attributes?['code-block'] == true;
    var search = 0;
    while (true) {
      final nl = data.indexOf('\n', search);
      if (nl < 0) break;
      lines.add((
        start: pos + search,
        end: pos + nl + 1,
        code: isCode,
        text: data.substring(search, nl),
      ));
      search = nl + 1;
    }
    pos += data.length;
  }
  var index = -1;
  for (var i = 0; i < lines.length; i++) {
    if (target >= lines[i].start && target <= lines[i].end) {
      index = i;
      break;
    }
  }
  if (index < 0 || !lines[index].code) return null;
  var first = index;
  var last = index;
  while (first > 0 && lines[first - 1].code) {
    first--;
  }
  while (last + 1 < lines.length && lines[last + 1].code) {
    last++;
  }
  return LegacyCodeBlock(
    start: lines[first].start,
    end: lines[last].end,
    code: [
      for (var i = first; i <= last; i++) lines[i].text,
    ].join('\n'),
  );
}

class _CodeBlockCard extends StatelessWidget {
  const _CodeBlockCard({
    required this.data,
    required this.controller,
    required this.offset,
  });

  final CodeBlockData data;
  final QuillController controller;
  final int offset;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      codeLanguageLabel(data.language),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9.5,
                        color: c.accent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  SoftIconButton(
                    icon: LucideIcons.copy,
                    tooltip: _t('复制代码'),
                    size: 26,
                    iconSize: 14,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: data.code));
                      if (context.mounted) {
                        showToast(
                          context,
                          _t('已复制代码'),
                          icon: LucideIcons.check,
                        );
                      }
                    },
                  ),
                  SoftIconButton(
                    icon: LucideIcons.pencil,
                    tooltip: _t('编辑代码'),
                    size: 26,
                    iconSize: 14,
                    onPressed: () => showCodeBlockDialog(
                      context,
                      controller,
                      initial: data,
                      replaceOffset: offset,
                    ),
                  ),
                  SoftIconButton(
                    icon: LucideIcons.trash2,
                    tooltip: _t('删除代码块'),
                    size: 26,
                    iconSize: 14,
                    onPressed: () {
                      controller.replaceText(
                        offset,
                        1,
                        '',
                        TextSelection.collapsed(offset: offset),
                      );
                    },
                  ),
                ],
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => showCodeBlockDialog(
                context,
                controller,
                initial: data,
                replaceOffset: offset,
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Text.rich(
                  TextSpan(
                    children: _highlightSpans(data.code, data.language, c),
                    style: _baseCodeStyle(c),
                  ),
                  softWrap: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _baseCodeStyle(AppPalette c) => TextStyle(
      fontFamily: 'SourceHanMono',
      fontFamilyFallback: const ['NotoSansSC', 'monospace'],
      fontSize: 13,
      height: 1.7,
      color: c.inkSoft,
    );

Map<String, TextStyle> _highlightTheme(AppPalette c) => {
      'keyword': TextStyle(color: c.accent, fontWeight: FontWeight.w600),
      'built_in': TextStyle(color: c.blue),
      'type': TextStyle(color: c.blue),
      'literal': TextStyle(color: c.gold),
      'number': TextStyle(color: c.gold),
      'string': TextStyle(color: c.sage),
      'comment': TextStyle(color: c.inkMuted, fontStyle: FontStyle.italic),
      'title': TextStyle(color: c.ink, fontWeight: FontWeight.w600),
      'attr': TextStyle(color: c.accent),
      'attribute': TextStyle(color: c.blue),
      'variable': TextStyle(color: c.inkSoft),
      'meta': TextStyle(color: c.inkMuted),
      'symbol': TextStyle(color: c.gold),
      'tag': TextStyle(color: c.accent),
      'name': TextStyle(color: c.accent),
      'selector-tag': TextStyle(color: c.accent),
      'selector-class': TextStyle(color: c.blue),
      'selector-id': TextStyle(color: c.blue),
    };

List<TextSpan> _highlightSpans(String code, String language, AppPalette c) =>
    codeHighlightSpans(
      code,
      language,
      base: _baseCodeStyle(c),
      theme: _highlightTheme(c),
    );

/// 语法高亮成 TextSpan。PNG 导出也用它，主题色由调用方给。
List<TextSpan> codeHighlightSpans(
  String code,
  String language, {
  required TextStyle base,
  required Map<String, TextStyle> theme,
}) {
  if (language.isEmpty || code.length > 20000) {
    return [TextSpan(text: code, style: base)];
  }
  _ensureLanguages();
  final key = language == 'html' ? 'xml' : language;
  try {
    final result = hl.highlight.parse(code, language: key);
    final spans = <TextSpan>[];
    void walk(hl.Node node, TextStyle inherited) {
      final style = node.className == null
          ? inherited
          : (theme[node.className] ?? inherited);
      final value = node.value;
      if (value != null && value.isNotEmpty) {
        spans.add(TextSpan(text: value, style: style));
      }
      final children = node.children;
      if (children != null) {
        for (final child in children) {
          walk(child, style);
        }
      }
    }

    for (final node in result.nodes ?? const <hl.Node>[]) {
      walk(node, base);
    }
    if (spans.isEmpty) return [TextSpan(text: code, style: base)];
    return spans;
  } catch (_) {
    return [TextSpan(text: code, style: base)];
  }
}

Future<void> showCodeBlockDialog(
  BuildContext context,
  QuillController controller, {
  CodeBlockData? initial,
  int? replaceOffset,
  int? legacyStart,
  int? legacyEnd,
}) async {
  final mobile = MediaQuery.sizeOf(context).width < 760;
  final editor = _CodeBlockEditor(
    initial: initial ?? const CodeBlockData(code: ''),
    canDelete: replaceOffset != null,
  );
  final result = await (mobile
      ? showModalBottomSheet<CodeBlockResult>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: AppPalette.of(context).surface,
          builder: (context) => SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.9,
            child: editor,
          ),
        )
      : showDialog<CodeBlockResult>(
          context: context,
          barrierColor: Colors.black.withValues(alpha: 0.2),
          builder: (context) => Dialog(
            backgroundColor: AppPalette.of(context).surface,
            insetPadding: const EdgeInsets.all(22),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: AppPalette.of(context).line),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 560),
              child: editor,
            ),
          ),
        ));
  if (result == null || !context.mounted) return;

  if (result.delete) {
    if (replaceOffset != null) {
      controller.replaceText(
        replaceOffset,
        1,
        '',
        TextSelection.collapsed(offset: replaceOffset),
      );
    }
    return;
  }
  final data = result.data;
  if (data == null) return;
  final embed = codeBlockEmbed(data);

  if (replaceOffset != null) {
    controller.replaceText(
      replaceOffset,
      1,
      embed,
      TextSelection.collapsed(offset: replaceOffset + 1),
    );
    return;
  }
  if (legacyStart != null && legacyEnd != null && legacyEnd > legacyStart) {
    controller.replaceText(
      legacyStart,
      legacyEnd - legacyStart,
      embed,
      TextSelection.collapsed(offset: legacyStart + 1),
    );
    return;
  }

  final selection = controller.selection;
  final docText = controller.document.toPlainText();
  final start = selection.isValid ? selection.start : docText.length - 1;
  final end = selection.isValid ? selection.end : start;
  final lineStart = start <= 0 ? 0 : docText.lastIndexOf('\n', start - 1) + 1;
  final lineEnd = docText.indexOf('\n', start);
  final before = docText.substring(lineStart, start).trim();
  final after = lineEnd < 0
      ? ''
      : docText.substring(end, lineEnd).trim();
  if (before.isEmpty && after.isEmpty) {
    final lineContentLength =
        lineEnd < 0 ? docText.length - lineStart : lineEnd - lineStart;
    controller.replaceText(
      lineStart,
      lineContentLength,
      embed,
      TextSelection.collapsed(offset: lineStart + 1),
    );
    return;
  }
  controller.replaceText(
    selection.start,
    0,
    embed,
    TextSelection.collapsed(offset: selection.start + 1),
  );
  controller.replaceText(
    selection.start + 1,
    0,
    '\n',
    TextSelection.collapsed(offset: selection.start + 2),
  );
}

class CodeBlockResult {
  const CodeBlockResult.save(this.data) : delete = false;
  const CodeBlockResult.delete()
      : data = null,
        delete = true;

  final CodeBlockData? data;
  final bool delete;
}

class _CodeBlockEditor extends StatefulWidget {
  const _CodeBlockEditor({required this.initial, required this.canDelete});

  final CodeBlockData initial;
  final bool canDelete;

  @override
  State<_CodeBlockEditor> createState() => _CodeBlockEditorState();
}

class _CodeBlockEditorState extends State<_CodeBlockEditor> {
  late final TextEditingController _code =
      TextEditingController(text: widget.initial.code);
  late String _language = codeLanguages.containsKey(widget.initial.language)
      ? widget.initial.language
      : '';

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      CodeBlockResult.save(
        CodeBlockData(code: _code.text, language: _language),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 10, 8),
            child: Row(
              children: [
                Icon(LucideIcons.code, size: 16, color: c.accent),
                const SizedBox(width: 8),
                Text(
                  _t('代码块'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                SoftIconButton(
                  icon: LucideIcons.x,
                  size: 28,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              children: [
                Text(
                  _t('语言'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 11,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _language,
                      isExpanded: true,
                      dropdownColor: c.surface,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 12,
                        color: c.ink,
                      ),
                      items: [
                        for (final entry in codeLanguages.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(
                              entry.key.isEmpty
                                  ? _t('纯文本')
                                  : entry.value,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _language = value);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.line),
                ),
                padding: const EdgeInsets.all(10),
                child: TextField(
                  key: const Key('code-block-input'),
                  controller: _code,
                  autofocus: true,
                  expands: true,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  style: _baseCodeStyle(c),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: _t('在这里粘贴或输入代码…'),
                    hintStyle: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12,
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 14),
            child: Row(
              children: [
                if (widget.canDelete)
                  TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(const CodeBlockResult.delete()),
                    child: Text(
                      _t('删除代码块'),
                      style: TextStyle(color: c.danger),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    _t('取消'),
                    style: TextStyle(color: c.inkMuted),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  key: const Key('code-block-save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.ink,
                    foregroundColor: c.paper,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _save,
                  child: Text(
                    _t('保存'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
