import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/services/search_replace.dart';

List<dynamic> _plain(String text) => [
      {'insert': text},
    ];

void main() {
  test('普通文本替换并计数', () {
    final result = replaceInDelta(_plain('今天写了一句。今天很好。\n'), '今天', '昨日');
    expect(result.count, 2);
    expect(result.text, '昨日写了一句。昨日很好。\n');
  });

  test('大小写不敏感', () {
    final result = replaceInDelta(
      _plain('Hello hello HELLO\n'),
      'hello',
      'hi',
      caseSensitive: false,
    );
    expect(result.count, 3);
    expect(result.text, 'hi hi hi\n');
  });

  test('替换保留匹配起点所在文本段的粗体', () {
    final result = replaceInDelta(
      [
        {'insert': '普通 '},
        {
          'insert': '粗体文字',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ],
      '粗体',
      '加粗',
    );
    expect(result.count, 1);
    final bold = result.delta.firstWhere(
      (op) => op is Map && op['insert'] == '加粗文字',
    );
    expect((bold as Map)['attributes'], containsPair('bold', true));
  });

  test('跨格式边界的匹配只替换、不崩溃', () {
    final result = replaceInDelta(
      [
        {'insert': '前'},
        {
          'insert': '后',
          'attributes': {'italic': true},
        },
        {'insert': '\n'},
      ],
      '前后',
      '替换',
    );
    expect(result.count, 1);
    expect(result.text, '替换\n');
  });

  test('空替换等于删除', () {
    final result = replaceInDelta(_plain('保留删除保留\n'), '删除', '');
    expect(result.count, 1);
    expect(result.text, '保留保留\n');
  });

  test('空查询不做任何事', () {
    final delta = _plain('原文\n');
    final result = replaceInDelta(delta, '', 'x');
    expect(result.count, 0);
    expect(result.delta, same(delta));
  });

  test('整词匹配', () {
    final result = replaceInDelta(
      _plain('cat category cat\n'),
      'cat',
      'dog',
      wholeWord: true,
    );
    expect(result.count, 2);
    expect(result.text, 'dog category dog\n');
  });

  test('countOccurrences 与替换次数一致', () {
    const text = '一，二，一，三，一';
    expect(countOccurrences(text, '一'), 3);
    expect(countOccurrences(text, '四'), 0);
  });
}