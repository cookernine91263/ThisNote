/// 把 Markdown / 纯文本导入成 Quill Delta。
///
/// 只覆盖常见的写作语法：标题、粗斜体、行内代码、链接、列表、引用、
/// 代码块、分隔线与空行。图片暂不落地（保留为文字，避免导入后出现坏链接）。
library;

class ParsedMarkdown {
  const ParsedMarkdown({
    required this.title,
    required this.delta,
    required this.text,
  });

  final String title;
  final List<dynamic> delta;
  final String text;
}

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*)$');
final RegExp _divider = RegExp(r'^\s*(---+|\*\*\*+|___+)\s*$');
final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');
final RegExp _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final RegExp _ordered = RegExp(r'^\s*\d+[.)]\s+(.*)$');
final RegExp _inline = RegExp(
  r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)|\*([^*]+)\*',
);

ParsedMarkdown parseMarkdown(String source, {String fallbackTitle = '导入的笔记'}) {
  final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final ops = <Map<String, dynamic>>[];
  final codeLines = <String>[];
  String? title;
  var inCode = false;

  void flushCode() {
    for (final line in codeLines) {
      if (line.isNotEmpty) {
        ops.add({'insert': line});
      }
      ops.add({
        'insert': '\n',
        'attributes': {'code-block': true},
      });
    }
    codeLines.clear();
  }

  void blankLine() {
    if (ops.isEmpty) return;
    final last = ops.last;
    if (last['insert'] == '\n' && last['attributes'] == null) return;
    ops.add({'insert': '\n'});
  }

  for (final raw in lines) {
    final line = raw.trimRight();
    if (line.trimLeft().startsWith('```')) {
      if (inCode) {
        flushCode();
        inCode = false;
      } else {
        inCode = true;
      }
      continue;
    }
    if (inCode) {
      codeLines.add(raw);
      continue;
    }

    if (line.trim().isEmpty) {
      blankLine();
      continue;
    }

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      final hashes = heading.group(1)!.length;
      final text = heading.group(2)!.trim();
      if (title == null && hashes == 1) {
        // 第一个 H1 当作笔记标题，不再重复出现在正文里。
        title = _plainInline(text);
        continue;
      }
      ops.addAll(_inlineOps(text));
      ops.add({
        'insert': '\n',
        'attributes': {'header': hashes.clamp(1, 3)},
      });
      continue;
    }

    if (_divider.hasMatch(line)) {
      ops.add({
        'insert': {'divider': 'hr'},
      });
      ops.add({'insert': '\n'});
      continue;
    }

    final quote = _quote.firstMatch(line);
    if (quote != null) {
      ops.addAll(_inlineOps(quote.group(1)!.trim()));
      ops.add({
        'insert': '\n',
        'attributes': {'blockquote': true},
      });
      continue;
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      ops.addAll(_inlineOps(bullet.group(1)!.trim()));
      ops.add({
        'insert': '\n',
        'attributes': {'list': 'bullet'},
      });
      continue;
    }

    final ordered = _ordered.firstMatch(line);
    if (ordered != null) {
      ops.addAll(_inlineOps(ordered.group(1)!.trim()));
      ops.add({
        'insert': '\n',
        'attributes': {'list': 'ordered'},
      });
      continue;
    }

    ops.addAll(_inlineOps(line.trim()));
    ops.add({'insert': '\n'});
  }
  if (inCode) flushCode();

  if (ops.isEmpty) ops.add({'insert': '\n'});
  final last = ops.last['insert'];
  if (last is! String || !last.endsWith('\n')) {
    ops.add({'insert': '\n'});
  }

  final text = ops
      .where((op) => op['insert'] is String)
      .map((op) => op['insert'] as String)
      .join()
      .replaceAll('\n', ' ')
      .trim();

  return ParsedMarkdown(
    title: (title == null || title.isEmpty) ? fallbackTitle : title,
    delta: ops,
    text: text,
  );
}

List<Map<String, dynamic>> _inlineOps(String text) {
  if (text.isEmpty) return const [];
  final ops = <Map<String, dynamic>>[];
  var index = 0;
  for (final match in _inline.allMatches(text)) {
    if (match.start > index) {
      ops.add({'insert': text.substring(index, match.start)});
    }
    if (match.group(1) != null) {
      ops.add({
        'insert': match.group(1),
        'attributes': {'bold': true},
      });
    } else if (match.group(2) != null) {
      ops.add({
        'insert': match.group(2),
        'attributes': {'code': true},
      });
    } else if (match.group(3) != null) {
      ops.add({
        'insert': match.group(3),
        'attributes': {'link': match.group(4)},
      });
    } else if (match.group(5) != null) {
      ops.add({
        'insert': match.group(5),
        'attributes': {'italic': true},
      });
    }
    index = match.end;
  }
  if (index < text.length) {
    ops.add({'insert': text.substring(index)});
  }
  return ops;
}

String _plainInline(String text) {
  var value = text;
  value = value.replaceAllMapped(
    RegExp(r'\*\*(.+?)\*\*'),
    (match) => match.group(1)!,
  );
  value = value.replaceAllMapped(
    RegExp(r'\[([^\]]+)\]\(([^)]+)\)'),
    (match) => match.group(1)!,
  );
  return value.replaceAll(RegExp(r'[*`]'), '').trim();
}
