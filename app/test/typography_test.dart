import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/typography.dart';

void main() {
  test('中英文之间自动加空格', () {
    expect(normalizeChineseTypography('你好world世界'), '你好 world 世界');
    expect(normalizeChineseTypography('用 Flutter写笔记'), '用 Flutter 写笔记');
    expect(normalizeChineseTypography('看https://a.com/x'), '看 https://a.com/x');
  });

  test('紧挨中文的半角标点转全角', () {
    expect(normalizeChineseTypography('他说,今天很好!'), '他说，今天很好！');
    expect(normalizeChineseTypography('第一.第二'), '第一。第二');
    expect(normalizeChineseTypography('为什么?'), '为什么？');
    expect(normalizeChineseTypography('中文(括号)'), '中文（括号）');
  });

  test('省略号与破折号规范化', () {
    expect(normalizeChineseTypography('等等...'), '等等……');
    expect(normalizeChineseTypography('他说--算了'), '他说——算了');
  });

  test('数字和英文句点不被误转', () {
    expect(normalizeChineseTypography('3.14 和 2.0'), '3.14 和 2.0');
    expect(normalizeChineseTypography('version 1.2.3'), 'version 1.2.3');
  });

  test('多余空格与标点前后的空格会被收掉', () {
    expect(normalizeChineseTypography('已经好了 ， 真的'), '已经好了，真的');
    expect(normalizeChineseTypography('（  你好  ）'), '（你好）');
    expect(normalizeChineseTypography('太  多  空  格'), '太 多 空 格');
    expect(normalizeChineseTypography('行尾空格   \n下一行'), '行尾空格\n下一行');
  });

  test('换行结构保持不变', () {
    const input = '第一段\n\n第二段 English 混排\n第三段';
    final output = normalizeChineseTypography(input);
    expect(output.split('\n').length, input.split('\n').length);
    expect(output.contains('English 混排'), isTrue);
  });
}
