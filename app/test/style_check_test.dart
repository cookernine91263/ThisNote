import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/services/style_check.dart';

/// 生成一段连续且互不相同的汉字，方便精确控制长度。
String hanRun(int count) =>
    String.fromCharCodes(List.generate(count, (i) => 0x4E00 + i));

List<StyleIssue> only(List<StyleIssue> issues, StyleIssueKind kind) =>
    issues.where((issue) => issue.kind == kind).toList();

void main() {
  test('空文本与干净文本没有问题', () {
    expect(checkChineseStyle(''), isEmpty);
    expect(checkChineseStyle('今天的天气很好，我们一起去公园散步。'), isEmpty);
    expect(checkChineseStyle('Hello world. This is fine.'), isEmpty);
  });

  test('口水词逐个报出，位置与长度准确', () {
    final issues = checkChineseStyle('其实这个真的不错');
    expect(issues.map((issue) => issue.kind).toSet(), {StyleIssueKind.filler});
    expect(issues.map((issue) => issue.offset), [0, 4]);
    expect(issues.first.length, 2);
    expect(issues.first.message, '口水词，能删就删');
  });

  test('多字口水短语整体标记', () {
    const text = '值得一提的是我觉得这段还行';
    final issues = only(checkChineseStyle(text), StyleIssueKind.filler);
    expect(issues.map((issue) => text.substring(
          issue.offset,
          issue.offset + issue.length,
        )), ['值得一提的是', '我觉得']);
  });

  test('紧邻重复的两字词报 repetition', () {
    const text = '这首歌非常非常好听';
    final repeats = only(checkChineseStyle(text), StyleIssueKind.repetition);
    expect(repeats.length, 1);
    expect(repeats.single.offset, 3);
    expect(repeats.single.length, 4);
    expect(text.substring(3, 7), '非常非常');
    expect(repeats.single.message, '重复用词，删掉一个');
  });

  test('三字短语重复（慢慢地慢慢地）也报', () {
    const text = '他慢慢地慢慢地走过来';
    final repeats = only(checkChineseStyle(text), StyleIssueKind.repetition);
    expect(repeats.length, 1);
    expect(repeats.single.offset, 1);
    expect(repeats.single.length, 6);
  });

  test('四字短语重复也能被整段覆盖', () {
    const text = '他总是磨磨蹭蹭磨磨蹭蹭，才出门。';
    final repeats = only(checkChineseStyle(text), StyleIssueKind.repetition);
    expect(repeats.length, 1);
    expect(repeats.single.offset, 3);
    expect(repeats.single.length, 8);
    expect(text.substring(3, 11), '磨磨蹭蹭磨磨蹭蹭');
  });

  test('连续三次重复只报一条并覆盖整段', () {
    const text = '非常非常非常';
    final repeats = only(checkChineseStyle(text), StyleIssueKind.repetition);
    expect(repeats.length, 1);
    expect(repeats.single.offset, 0);
    expect(repeats.single.length, 6);

    const long = '慢慢地慢慢地慢慢地走';
    final merged = only(checkChineseStyle(long), StyleIssueKind.repetition);
    expect(merged.length, 1);
    expect(merged.single.length, 9);
  });

  test('看看 / 慢慢 / 刚刚 这类叠词不报', () {
    expect(checkChineseStyle('看看这个，慢慢走，刚刚好。'), isEmpty);
    expect(checkChineseStyle('他笑了笑，读了读，走了走。'), isEmpty);
    expect(checkChineseStyle('哈哈哈哈。'), isEmpty);
  });

  test('超过 60 字的长句在句首报出', () {
    final body = hanRun(61);
    final issues = only(checkChineseStyle(body), StyleIssueKind.longSentence);
    expect(issues.length, 1);
    expect(issues.single.offset, 0);
    expect(issues.single.length, 61);
    expect(issues.single.message, '句子偏长，考虑拆成两句');

    const prefix = '今天很好。';
    final after = only(
      checkChineseStyle('$prefix$body'),
      StyleIssueKind.longSentence,
    );
    expect(after.length, 1);
    expect(after.single.offset, prefix.length);
    expect(after.single.length, 61);
  });

  test('恰好 60 字不算长句，标点与空格不计数', () {
    expect(only(checkChineseStyle(hanRun(60)), StyleIssueKind.longSentence),
        isEmpty);
    final withSpaces = hanRun(60).split('').join('  ');
    expect(only(checkChineseStyle(withSpaces), StyleIssueKind.longSentence),
        isEmpty);
    final twoSentences = '${hanRun(40)}。${hanRun(40)}';
    expect(only(checkChineseStyle(twoSentences), StyleIssueKind.longSentence),
        isEmpty);
  });

  test('换行也会切分句子', () {
    final text = '${hanRun(40)}\n${hanRun(40)}';
    expect(only(checkChineseStyle(text), StyleIssueKind.longSentence), isEmpty);
  });

  test('连续标点（重复与混用）各报一条', () {
    const text = '好的，，我知道了。。';
    final issues = only(checkChineseStyle(text), StyleIssueKind.punctuation);
    expect(issues.length, 2);
    expect(issues[0].offset, 2);
    expect(issues[0].length, 2);
    expect(issues[1].offset, 8);
    expect(issues[1].length, 2);
    expect(issues[0].message, '连续标点，保留一个');

    const mixed = '第一段、。第二段';
    final mixedIssues =
        only(checkChineseStyle(mixed), StyleIssueKind.punctuation);
    expect(mixedIssues.length, 1);
    expect(mixedIssues.single.offset, 3);
    expect(mixedIssues.single.length, 2);
  });

  test('？！并用不算连续标点', () {
    expect(only(checkChineseStyle('真的吗？！'), StyleIssueKind.punctuation),
        isEmpty);
    expect(only(checkChineseStyle('真的吗！？好吧'), StyleIssueKind.punctuation),
        isEmpty);
  });

  test('中文之间用半角逗号句号报 punctuation', () {
    const comma = '中文,中文';
    final commaIssues = only(checkChineseStyle(comma), StyleIssueKind.punctuation);
    expect(commaIssues.length, 1);
    expect(commaIssues.single.offset, 2);
    expect(commaIssues.single.length, 1);
    expect(commaIssues.single.message, '中文之间用全角标点');

    const dot = '中文.中文';
    expect(only(checkChineseStyle(dot), StyleIssueKind.punctuation).single.offset,
        2);
    // 句末的半角句号不在中文之间，不报。
    expect(only(checkChineseStyle('中文. Hello'), StyleIssueKind.punctuation),
        isEmpty);
  });

  test('半角 ... 当作省略号报出', () {
    const text = '等等...';
    final issues = only(checkChineseStyle(text), StyleIssueKind.punctuation);
    expect(issues.length, 1);
    expect(issues.single.offset, 2);
    expect(issues.single.length, 3);
    expect(only(checkChineseStyle('等等……'), StyleIssueKind.punctuation),
        isEmpty);
  });

  test('中文之间的多个空格报 spacing', () {
    const text = '这是  测试。';
    final issues = only(checkChineseStyle(text), StyleIssueKind.spacing);
    expect(issues.length, 1);
    expect(issues.single.offset, 2);
    expect(issues.single.length, 2);
    expect(issues.single.message, '多余空格，只留一个');

    expect(only(checkChineseStyle('请看  文档'), StyleIssueKind.spacing).length,
        1);
    // 单个空格、行首缩进、英文之间都不算。
    expect(only(checkChineseStyle('英文  text'), StyleIssueKind.spacing),
        isEmpty);
    expect(only(checkChineseStyle('中文\n  中文'), StyleIssueKind.spacing),
        isEmpty);
  });

  test('的的 / 了了 / 是是 这类单字重复报 typo', () {
    const text = '我的的书';
    final issues = only(checkChineseStyle(text), StyleIssueKind.typo);
    expect(issues.length, 1);
    expect(issues.single.offset, 1);
    expect(issues.single.length, 2);
    expect(issues.single.message, '疑似笔误，删掉多余的字');

    expect(only(checkChineseStyle('他走了了。'), StyleIssueKind.typo).single.offset,
        2);
    expect(only(checkChineseStyle('这是是错的'), StyleIssueKind.typo).single.offset,
        1);
    // 不做「在再」「做作」这类有歧义的判断。
    expect(checkChineseStyle('他在再试一次，做作业。'), isEmpty);
  });

  test('emoji 前后 offset 仍是 UTF-16 下标', () {
    const text = '😀其实';
    expect(text.length, 4);
    final issues = checkChineseStyle(text);
    expect(issues.length, 1);
    expect(issues.single.offset, 2);
    expect(issues.single.length, 2);
    expect(text.substring(2, 4), '其实');

    const mixed = '😀😀慢慢😀非常非常';
    final repeats = only(checkChineseStyle(mixed), StyleIssueKind.repetition);
    expect(repeats.length, 1);
    expect(repeats.single.offset, 8);
    expect(repeats.single.length, 4);
    expect(mixed.substring(8, 12), '非常非常');
  });

  test('结果按 offset 升序，跨类型混排', () {
    const text = '其实😀这个非常非常好，，真的...我的的书';
    final issues = checkChineseStyle(text);
    expect(issues.length, greaterThan(3));
    for (var i = 1; i < issues.length; i++) {
      expect(issues[i].offset, greaterThanOrEqualTo(issues[i - 1].offset));
    }
    final kinds = issues.map((issue) => issue.kind).toSet();
    expect(kinds.contains(StyleIssueKind.filler), isTrue);
    expect(kinds.contains(StyleIssueKind.repetition), isTrue);
    expect(kinds.contains(StyleIssueKind.punctuation), isTrue);
    expect(kinds.contains(StyleIssueKind.typo), isTrue);
  });

  test('所有 offset / length 都能直接切开原文', () {
    const text = '其实，这个非常非常好，，我我慢慢走...我的的书';
    for (final issue in checkChineseStyle(text)) {
      expect(issue.offset >= 0, isTrue);
      expect(issue.offset + issue.length, lessThanOrEqualTo(text.length));
      expect(text.substring(issue.offset, issue.offset + issue.length).isEmpty,
          isFalse);
    }
  });
}