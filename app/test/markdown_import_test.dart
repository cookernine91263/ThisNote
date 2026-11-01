import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/features/editor/code_block.dart';
import 'package:this_note/src/services/markdown_import.dart';

void main() {
  test('第一个 H1 作为标题，H2 留在正文里', () {
    final parsed = parseMarkdown(
      '# 我的标题\n\n正文第一段。\n\n## 小标题\n\n正文第二段。\n',
      fallbackTitle: '文件名',
    );
    expect(parsed.title, '我的标题');
    expect(parsed.text.contains('正文第一段'), isTrue);
    expect(
      parsed.delta.any((op) => op['attributes']?['header'] == 2),
      isTrue,
    );
  });

  test('没有 H1 时用文件名兜底', () {
    final parsed = parseMarkdown('一段普通文字。\n', fallbackTitle: '导入的文件');
    expect(parsed.title, '导入的文件');
    expect(parsed.text, '一段普通文字。');
  });

  test('行内粗体、斜体、代码与链接带上属性', () {
    final parsed = parseMarkdown(
      '这是**粗体**和*斜体*，还有`代码`与[链接](https://a.com)。\n',
    );
    final delta = parsed.delta;
    expect(
      delta.any((op) => op['insert'] == '粗体' && op['attributes']?['bold'] == true),
      isTrue,
    );
    expect(
      delta.any((op) => op['insert'] == '斜体' && op['attributes']?['italic'] == true),
      isTrue,
    );
    expect(
      delta.any((op) => op['insert'] == '代码' && op['attributes']?['code'] == true),
      isTrue,
    );
    expect(
      delta.any(
        (op) =>
            op['insert'] == '链接' && op['attributes']?['link'] == 'https://a.com',
      ),
      isTrue,
    );
  });

  test('列表、引用与代码块保留块级属性', () {
    final parsed = parseMarkdown(
      '> 引用一句\n\n- 项目一\n- 项目二\n\n1. 第一\n2. 第二\n\n```\ncode line\n```\n',
    );
    final delta = parsed.delta;
    expect(
      delta.any((op) => op['attributes']?['list'] == 'bullet'),
      isTrue,
    );
    expect(
      delta.any((op) => op['attributes']?['list'] == 'ordered'),
      isTrue,
    );
    expect(
      delta.any((op) => op['attributes']?['blockquote'] == true),
      isTrue,
    );
    expect(
      delta.any(
        (op) =>
            op['insert'] is Map && op['insert'][codeBlockKey] != null,
      ),
      isTrue,
    );
    expect(parsed.text.contains('code line'), isTrue);
  });

  test('分隔线变成 divider embed', () {
    final parsed = parseMarkdown('上面\n\n---\n\n下面\n');
    expect(
      parsed.delta.any((op) => op['insert'] is Map && op['insert']['divider'] != null),
      isTrue,
    );
  });

  test('空行分成段落，文本字段不带换行', () {
    final parsed = parseMarkdown('第一段。\n\n第二段。\n');
    expect(parsed.text.contains('\n'), isFalse);
    expect(parsed.text.contains('第一段。'), isTrue);
    expect(parsed.text.contains('第二段。'), isTrue);
    final paragraphs =
        parsed.delta.where((op) => op['insert'] == '\n').length;
    expect(paragraphs, greaterThanOrEqualTo(2));
  });

  test('CRLF 与空文档都能处理', () {
    final crlf = parseMarkdown('# 标题\r\n\r\n正文\r\n');
    expect(crlf.title, '标题');
    expect(crlf.text.contains('正文'), isTrue);

    final empty = parseMarkdown('', fallbackTitle: '空文件');
    expect(empty.title, '空文件');
    expect(empty.delta, isNotEmpty);
  });
}
