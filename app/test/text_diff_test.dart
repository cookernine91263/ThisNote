import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/services/text_diff.dart';

/// 校验 run 序列自洽：偏移连续、相邻同类已合并、且能还原两侧原文。
void checkRuns(List<DiffRun> runs, String oldText, String newText) {
  var oldPos = 0;
  var newPos = 0;
  final rebuiltOld = StringBuffer();
  final rebuiltNew = StringBuffer();
  for (var i = 0; i < runs.length; i++) {
    final run = runs[i];
    expect(run.text, isNotEmpty, reason: '第 $i 个 run 不应为空文本');
    expect(run.oldOffset, oldPos, reason: '第 $i 个 run 的 oldOffset');
    expect(run.newOffset, newPos, reason: '第 $i 个 run 的 newOffset');
    if (i > 0) {
      expect(
        run.kind,
        isNot(runs[i - 1].kind),
        reason: '第 $i 个 run 与上一个同类，应已合并',
      );
    }
    if (run.kind == DiffKind.equal) {
      rebuiltOld.write(run.text);
      rebuiltNew.write(run.text);
      oldPos += run.text.length;
      newPos += run.text.length;
    } else if (run.kind == DiffKind.delete) {
      rebuiltOld.write(run.text);
      oldPos += run.text.length;
    } else {
      rebuiltNew.write(run.text);
      newPos += run.text.length;
    }
  }
  expect(oldPos, oldText.length);
  expect(newPos, newText.length);
  expect(rebuiltOld.toString(), oldText);
  expect(rebuiltNew.toString(), newText);
}

List<DiffKind> kindsOf(List<DiffRun> runs) {
  return runs.map((run) => run.kind).toList();
}

List<String> textsOf(List<DiffRun> runs) {
  return runs.map((run) => run.text).toList();
}

/// 按类型拼接 run 文本，用于不依赖 LCS 具体对齐方式的断言。
String joined(List<DiffRun> runs, DiffKind kind) {
  return runs
      .where((run) => run.kind == kind)
      .map((run) => run.text)
      .join();
}

void main() {
  test('两侧都为空时没有差异', () {
    final runs = diffText('', '');
    expect(runs, isEmpty);
    checkRuns(runs, '', '');
  });

  test('旧文本为空时只产生一条新增', () {
    final runs = diffText('', '第一行');
    expect(runs.length, 1);
    expect(runs.single.kind, DiffKind.insert);
    expect(runs.single.text, '第一行');
    expect(runs.single.oldOffset, 0);
    expect(runs.single.newOffset, 0);
    checkRuns(runs, '', '第一行');
  });

  test('新文本为空时只产生一条删除', () {
    final runs = diffText('第一行', '');
    expect(runs.length, 1);
    expect(runs.single.kind, DiffKind.delete);
    expect(runs.single.text, '第一行');
    checkRuns(runs, '第一行', '');
  });

  test('完全相同时只有一条 equal', () {
    const text = '安静的写作空间\n第二行';
    final runs = diffText(text, text);
    expect(runs.length, 1);
    expect(runs.single.kind, DiffKind.equal);
    expect(runs.single.text, text);
    expect(runs.single.oldOffset, 0);
    expect(runs.single.newOffset, 0);
    checkRuns(runs, text, text);
  });

  test('单行内插入文字', () {
    final runs = diffText('安静地写', '安静地写字');
    expect(kindsOf(runs), [DiffKind.equal, DiffKind.insert]);
    expect(textsOf(runs), ['安静地写', '字']);
    expect(runs.last.oldOffset, 4);
    expect(runs.last.newOffset, 4);
    checkRuns(runs, '安静地写', '安静地写字');
  });

  test('单行内删除文字', () {
    final runs = diffText('安静地写字', '安静地写');
    expect(kindsOf(runs), [DiffKind.equal, DiffKind.delete]);
    expect(textsOf(runs), ['安静地写', '字']);
    expect(runs.last.oldOffset, 4);
    expect(runs.last.newOffset, 4);
    checkRuns(runs, '安静地写字', '安静地写');
  });

  test('单行内替换文字，先删后增', () {
    final runs = diffText('今天下雨', '今天刮风');
    expect(kindsOf(runs), [
      DiffKind.equal,
      DiffKind.delete,
      DiffKind.insert,
    ]);
    expect(textsOf(runs), ['今天', '下雨', '刮风']);
    expect(runs[1].oldOffset, 2);
    expect(runs[1].newOffset, 2);
    expect(runs[2].oldOffset, 4);
    expect(runs[2].newOffset, 2);
    checkRuns(runs, '今天下雨', '今天刮风');
  });

  test('连续改动合并成一条删除加一条新增', () {
    final runs = diffText('foo bar baz', 'foo qux baz');
    expect(kindsOf(runs), [
      DiffKind.equal,
      DiffKind.delete,
      DiffKind.insert,
      DiffKind.equal,
    ]);
    expect(runs[1].text, 'bar');
    expect(runs[2].text, 'qux');
    checkRuns(runs, 'foo bar baz', 'foo qux baz');
  });

  test('多行长文本按行比较', () {
    String line(int i) => '第$i行：${'内容' * 20}';
    final oldLines = List.generate(8, line);
    final newLines = List<String>.of(oldLines)..[3] = '第3行：${'改动' * 20}';
    final oldText = oldLines.join('\n');
    final newText = newLines.join('\n');
    expect(oldText.length, greaterThan(200));

    final runs = diffText(oldText, newText);
    expect(kindsOf(runs), [
      DiffKind.equal,
      DiffKind.delete,
      DiffKind.insert,
      DiffKind.equal,
    ]);
    expect(runs[0].text, '${oldLines[0]}\n${oldLines[1]}\n${oldLines[2]}\n');
    expect(runs[1].text, '${oldLines[3]}\n');
    expect(runs[2].text, '${newLines[3]}\n');
    expect(runs[2].oldOffset, runs[1].oldOffset + runs[1].text.length);
    expect(runs[2].newOffset, runs[1].newOffset);
    checkRuns(runs, oldText, newText);
  });

  test('新增整行时只标记该行', () {
    String line(int i) => '第$i行：${'内容' * 20}';
    final oldLines = List.generate(6, line);
    final newLines = List<String>.of(oldLines)..insert(2, '第2.5行：${'新增' * 20}');
    final oldText = oldLines.join('\n');
    final newText = newLines.join('\n');

    final runs = diffText(oldText, newText);
    expect(kindsOf(runs), [DiffKind.equal, DiffKind.insert, DiffKind.equal]);
    expect(runs[1].text, '${newLines[2]}\n');
    checkRuns(runs, oldText, newText);
  });

  test('单行超长文本做字符级比较', () {
    final oldText = '${'a' * 150}c${'a' * 149}';
    final newText = '${'a' * 150}d${'a' * 149}';
    final runs = diffText(oldText, newText);
    expect(kindsOf(runs), [
      DiffKind.equal,
      DiffKind.delete,
      DiffKind.insert,
      DiffKind.equal,
    ]);
    expect(runs[0].text, 'a' * 150);
    expect(runs[1].text, 'c');
    expect(runs[2].text, 'd');
    expect(runs[2].oldOffset, 151);
    expect(runs[2].newOffset, 150);
    expect(runs[3].text, 'a' * 149);
    checkRuns(runs, oldText, newText);
  });

  test('代理对不被拆开，偏移按 UTF-16 计', () {
    final oldText = '写😀';
    final newText = '写😀😀';
    final runs = diffText(oldText, newText);
    // 重复字符的对齐方式不唯一，只校验结论：多出一个完整的 emoji。
    expect(joined(runs, DiffKind.insert), '😀');
    expect(joined(runs, DiffKind.delete), '');
    for (final run in runs) {
      expect(String.fromCharCodes(run.text.runes), run.text);
    }
    checkRuns(runs, oldText, newText);
  });

  test('行数超过上限时退化为整段替换', () {
    final oldText = List.generate(2001, (i) => 'line $i').join('\n');
    final newText = List.generate(2001, (i) => 'LINE $i').join('\n');
    final runs = diffText(oldText, newText);
    expect(kindsOf(runs), [DiffKind.delete, DiffKind.insert]);
    expect(runs[0].text, oldText);
    expect(runs[1].text, newText);
    expect(runs[1].oldOffset, oldText.length);
    expect(runs[1].newOffset, 0);
    checkRuns(runs, oldText, newText);
  });

  test('字符数超过上限时退化为整段替换', () {
    final oldText = 'a' * 20001;
    final newText = 'a' * 20000;
    final runs = diffText(oldText, newText);
    expect(kindsOf(runs), [DiffKind.delete, DiffKind.insert]);
    checkRuns(runs, oldText, newText);
  });

  test('纯空白与空行也能还原', () {
    final cases = <List<String>>[
      ['\n', ''],
      ['\n\n', '\n'],
      ['a\n', 'a'],
      ['a', 'a\n'],
    ];
    for (final pair in cases) {
      final runs = diffText(pair[0], pair[1]);
      checkRuns(runs, pair[0], pair[1]);
    }
  });
}