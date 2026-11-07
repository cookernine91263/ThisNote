/// 离线中文写作风格检查。
///
/// 纯 Dart 实现（不依赖 Flutter），供编辑器侧边栏列出可点击的问题。
/// 返回的 offset / length 都是 UTF-16 码元下标，与 Dart 字符串下标一致，
/// 可以直接交给 TextSelection 使用。
library;

/// 问题类型，侧边栏按此分组展示。
enum StyleIssueKind { filler, repetition, longSentence, punctuation, spacing, typo }

/// 一条风格问题。[offset] 与 [length] 为 UTF-16 码元下标。
class StyleIssue {
  const StyleIssue({
    required this.offset,
    required this.length,
    required this.message,
    required this.kind,
  });

  final int offset;
  final int length;
  final String message;
  final StyleIssueKind kind;

  @override
  String toString() => 'StyleIssue(${kind.name}, $offset+$length, $message)';
}

/// 检查一段中文文本，返回按 offset 升序排列的问题列表。
///
/// 只做低误报的规则；同一类型里相互重叠的问题会合并，保留最早、最长的一条。
List<StyleIssue> checkChineseStyle(String text) {
  if (text.isEmpty) return const [];
  final units = _splitUnits(text);
  return _normalize([
    ..._fillerIssues(units),
    ..._repetitionIssues(units),
    ..._longSentenceIssues(units),
    ..._punctuationIssues(units),
    ..._spacingIssues(units),
    ..._typoIssues(units),
  ]);
}

/// 口水词与口头短语。
const _fillerWords = <String>[
  '其实',
  '真的',
  '非常',
  '然后',
  '就是',
  '比较',
  '基本上',
  '说实话',
  '我觉得',
  '的时候',
  '进行',
  '通过',
  '由于',
  '可以说',
  '总的来说',
  '值得一提的是',
];

const _fillerMessage = '口水词，能删就删';
const _repetitionMessage = '重复用词，删掉一个';
const _longSentenceMessage = '句子偏长，考虑拆成两句';
const _runPunctMessage = '连续标点，保留一个';
const _halfWidthMessage = '中文之间用全角标点';
const _ellipsisMessage = '省略号用「……」，不要用 ...';
const _spacingMessage = '多余空格，只留一个';
const _typoMessage = '疑似笔误，删掉多余的字';

/// 一个“字符”：代理对记作一个单元，长度 2。
class _Unit {
  const _Unit(this.start, this.length, this.code);

  final int start;
  final int length;
  final int code;

  int get end => start + length;
}

List<_Unit> _splitUnits(String text) {
  final units = <_Unit>[];
  var i = 0;
  while (i < text.length) {
    final cu = text.codeUnitAt(i);
    final paired = cu >= 0xD800 &&
        cu <= 0xDBFF &&
        i + 1 < text.length &&
        text.codeUnitAt(i + 1) >= 0xDC00 &&
        text.codeUnitAt(i + 1) <= 0xDFFF;
    if (paired) {
      final low = text.codeUnitAt(i + 1);
      units.add(_Unit(i, 2, 0x10000 + ((cu - 0xD800) << 10) + (low - 0xDC00)));
      i += 2;
    } else {
      units.add(_Unit(i, 1, cu));
      i += 1;
    }
  }
  return units;
}

bool _isHan(int code) =>
    (code >= 0x4E00 && code <= 0x9FFF) ||
    (code >= 0x3400 && code <= 0x4DBF) ||
    (code >= 0xF900 && code <= 0xFAFF);

/// 字母（半角与全角），用于长句计数。
bool _isLetter(int code) =>
    (code >= 0x41 && code <= 0x5A) ||
    (code >= 0x61 && code <= 0x7A) ||
    (code >= 0xFF21 && code <= 0xFF3A) ||
    (code >= 0xFF41 && code <= 0xFF5A);

bool _isBlank(int code) => code == 0x20 || code == 0x09 || code == 0x3000;

/// 句子分隔符：。！？!?；; 以及换行。
const _sentenceEnds = <int>{
  0x3002, 0xFF01, 0xFF1F, 0x21, 0x3F, 0xFF1B, 0x3B, 0x0A, 0x0D, //
};

/// 可能连用的中文标点（不含引号、括号，避免误伤「！」这类正常写法）。
const _runPunct = <int>{
  0xFF0C, 0x3002, 0xFF1B, 0xFF1A, 0x3001, 0xFF01, 0xFF1F, //
};

/// 只有混进这些分隔类标点时，混合连用（如 ，。）才算错。
const _runPunctSeparators = <int>{0xFF0C, 0x3002, 0xFF1B, 0xFF1A, 0x3001};

/// 高频手误的单字重复；不做「在再」「做作」这类有歧义的语法判断。
const _typoChars = <int>{0x7684 /* 的 */, 0x4E86 /* 了 */, 0x662F /* 是 */};

StyleIssue _issue(_Unit from, _Unit to, String message, StyleIssueKind kind) =>
    StyleIssue(
      offset: from.start,
      length: to.end - from.start,
      message: message,
      kind: kind,
    );

Iterable<StyleIssue> _fillerIssues(List<_Unit> units) sync* {
  for (var i = 0; i < units.length; i++) {
    for (final word in _fillerWords) {
      if (i + word.length > units.length) continue;
      var hit = true;
      for (var k = 0; k < word.length; k++) {
        if (units[i + k].code != word.codeUnitAt(k)) {
          hit = false;
          break;
        }
      }
      if (!hit) continue;
      yield _issue(
        units[i],
        units[i + word.length - 1],
        _fillerMessage,
        StyleIssueKind.filler,
      );
    }
  }
}

Iterable<StyleIssue> _repetitionIssues(List<_Unit> units) sync* {
  var i = 0;
  while (i < units.length) {
    final repeat = _repeatAt(units, i);
    if (repeat == null) {
      i += 1;
      continue;
    }
    final (period, times) = repeat;
    yield _issue(
      units[i],
      units[i + period * times - 1],
      _repetitionMessage,
      StyleIssueKind.repetition,
    );
    i += period * times;
  }
}

/// 在 [start] 处找 2-4 字的紧邻重复，返回（重复单元长度，重复次数）。
///
/// 单元本身是同一个字时（看看、慢慢、刚刚、哈哈哈）不算，这是汉语常见叠用。
(int, int)? _repeatAt(List<_Unit> units, int start) {
  for (var period = 4; period >= 2; period--) {
    if (start + period * 2 > units.length) continue;
    var uniform = true;
    for (var k = 1; k < period; k++) {
      if (units[start + k].code != units[start].code) {
        uniform = false;
        break;
      }
    }
    if (uniform) continue;
    var ok = true;
    for (var k = 0; k < period; k++) {
      final head = units[start + k];
      if (!_isHan(head.code) || head.code != units[start + period + k].code) {
        ok = false;
        break;
      }
    }
    if (!ok) continue;
    var times = 2;
    while (start + (times + 1) * period <= units.length) {
      var same = true;
      for (var k = 0; k < period; k++) {
        if (units[start + times * period + k].code != units[start + k].code) {
          same = false;
          break;
        }
      }
      if (!same) break;
      times += 1;
    }
    return (period, times);
  }
  return null;
}

Iterable<StyleIssue> _longSentenceIssues(List<_Unit> units) sync* {
  var i = 0;
  while (i < units.length) {
    var end = i;
    while (end < units.length && !_sentenceEnds.contains(units[end].code)) {
      end += 1;
    }
    final issue = _longSentence(units, i, end);
    if (issue != null) yield issue;
    i = end + 1;
  }
}

StyleIssue? _longSentence(List<_Unit> units, int from, int to) {
  while (from < to && _isBlank(units[from].code)) {
    from += 1;
  }
  while (to > from && _isBlank(units[to - 1].code)) {
    to -= 1;
  }
  if (to <= from) return null;
  var count = 0;
  for (var i = from; i < to; i++) {
    final code = units[i].code;
    if (_isHan(code) || _isLetter(code)) count += 1;
  }
  if (count <= 60) return null;
  return _issue(
    units[from],
    units[to - 1],
    _longSentenceMessage,
    StyleIssueKind.longSentence,
  );
}

Iterable<StyleIssue> _punctuationIssues(List<_Unit> units) sync* {
  yield* _runPunctIssues(units);
  yield* _ellipsisIssues(units);
  yield* _halfWidthIssues(units);
}

Iterable<StyleIssue> _runPunctIssues(List<_Unit> units) sync* {
  var i = 0;
  while (i < units.length) {
    if (!_runPunct.contains(units[i].code)) {
      i += 1;
      continue;
    }
    var end = i;
    var same = true;
    var separator = false;
    while (end < units.length && _runPunct.contains(units[end].code)) {
      if (units[end].code != units[i].code) same = false;
      if (_runPunctSeparators.contains(units[end].code)) separator = true;
      end += 1;
    }
    if (end - i >= 2 && (same || separator)) {
      yield _issue(units[i], units[end - 1], _runPunctMessage,
          StyleIssueKind.punctuation);
    }
    i = end;
  }
}

/// 「中文...中文」这种半角省略号，按错处理。
Iterable<StyleIssue> _ellipsisIssues(List<_Unit> units) sync* {
  var i = 0;
  while (i < units.length) {
    if (units[i].code != 0x2E) {
      i += 1;
      continue;
    }
    var end = i;
    while (end < units.length && units[end].code == 0x2E) {
      end += 1;
    }
    if (end - i >= 3) {
      yield _issue(units[i], units[end - 1], _ellipsisMessage,
          StyleIssueKind.punctuation);
    }
    i = end;
  }
}

Iterable<StyleIssue> _halfWidthIssues(List<_Unit> units) sync* {
  for (var i = 1; i + 1 < units.length; i++) {
    final code = units[i].code;
    if (code != 0x2C && code != 0x2E) continue;
    if (!_isHan(units[i - 1].code) || !_isHan(units[i + 1].code)) continue;
    yield _issue(
      units[i],
      units[i],
      _halfWidthMessage,
      StyleIssueKind.punctuation,
    );
  }
}

Iterable<StyleIssue> _spacingIssues(List<_Unit> units) sync* {
  var i = 0;
  while (i < units.length) {
    if (units[i].code != 0x20) {
      i += 1;
      continue;
    }
    var end = i;
    while (end < units.length && units[end].code == 0x20) {
      end += 1;
    }
    final insideChinese = i > 0 &&
        end < units.length &&
        _isHan(units[i - 1].code) &&
        _isHan(units[end].code);
    if (end - i >= 2 && insideChinese) {
      yield _issue(
        units[i],
        units[end - 1],
        _spacingMessage,
        StyleIssueKind.spacing,
      );
    }
    i = end;
  }
}

Iterable<StyleIssue> _typoIssues(List<_Unit> units) sync* {
  for (var i = 0; i + 1 < units.length; i++) {
    final code = units[i].code;
    if (code != units[i + 1].code || !_typoChars.contains(code)) continue;
    yield _issue(units[i], units[i + 1], _typoMessage, StyleIssueKind.typo);
  }
}

/// 同类型去重：保留最早的起点，起点相同时保留更长的一条。
List<StyleIssue> _normalize(List<StyleIssue> issues) {
  if (issues.isEmpty) return const [];
  final kept = <StyleIssue>[];
  for (final kind in StyleIssueKind.values) {
    final group = issues.where((issue) => issue.kind == kind).toList()
      ..sort((a, b) {
        final byOffset = a.offset.compareTo(b.offset);
        return byOffset != 0 ? byOffset : b.length.compareTo(a.length);
      });
    var lastEnd = -1;
    for (final issue in group) {
      if (issue.offset < lastEnd) continue;
      kept.add(issue);
      lastEnd = issue.offset + issue.length;
    }
  }
  kept.sort((a, b) {
    final byOffset = a.offset.compareTo(b.offset);
    if (byOffset != 0) return byOffset;
    final byLength = b.length.compareTo(a.length);
    return byLength != 0 ? byLength : a.kind.index.compareTo(b.kind.index);
  });
  return kept;
}