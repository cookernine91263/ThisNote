/// 版本历史预览用的文本差异计算（纯 Dart，不依赖 Flutter）。
///
/// 把旧快照与当前笔记比较成有序的 [DiffRun] 列表，保证：
/// `equal` + `delete` 依次拼接可还原旧文本，`equal` + `insert` 依次拼接
/// 可还原新文本。因此 [DiffRun.oldOffset] / [DiffRun.newOffset] 始终是
/// 两侧原文中的 UTF-16 偏移，可直接用于渲染高亮。
library;

import 'dart:typed_data';

enum DiffKind { equal, insert, delete }

class DiffRun {
  const DiffRun({
    required this.kind,
    required this.text,
    required this.oldOffset,
    required this.newOffset,
  });

  final DiffKind kind;
  final String text;

  /// 该 run 在旧文本中的起始偏移（UTF-16）。
  final int oldOffset;

  /// 该 run 在新文本中的起始偏移（UTF-16）。
  final int newOffset;

  @override
  String toString() {
    return 'DiffRun(${kind.name}, ${text.length} chars, '
        'old: $oldOffset, new: $newOffset)';
  }
}

/// 行数 / 字符数上限：超过时退化成一整段删除加一整段新增，
/// 避免 O(n*m) 的 LCS 计算卡住 UI。
const int _maxLines = 2000;
const int _maxChars = 20000;

/// 单行笔记或任一边不超过该字符数时，走字符级 LCS，改动更精确。
const int _shortText = 200;

/// LCS 表格的单元格上限，控制耗时与内存。
const int _maxCells = 8000000;

/// 计算 [oldText] 与 [newText] 的差异，返回已合并的连续片段。
List<DiffRun> diffText(String oldText, String newText) {
  if (oldText.isEmpty && newText.isEmpty) return const <DiffRun>[];
  if (oldText.isEmpty) {
    return <DiffRun>[
      DiffRun(kind: DiffKind.insert, text: newText, oldOffset: 0, newOffset: 0),
    ];
  }
  if (newText.isEmpty) {
    return <DiffRun>[
      DiffRun(kind: DiffKind.delete, text: oldText, oldOffset: 0, newOffset: 0),
    ];
  }
  if (oldText == newText) {
    return <DiffRun>[
      DiffRun(kind: DiffKind.equal, text: oldText, oldOffset: 0, newOffset: 0),
    ];
  }
  if (oldText.length > _maxChars || newText.length > _maxChars) {
    return _wholeReplacement(oldText, newText);
  }

  final oldLines = oldText.split('\n');
  final newLines = newText.split('\n');
  if (oldLines.length > _maxLines || newLines.length > _maxLines) {
    return _wholeReplacement(oldText, newText);
  }

  final charLevel = (oldLines.length <= 1 && newLines.length <= 1) ||
      oldText.length <= _shortText ||
      newText.length <= _shortText;
  if (charLevel) {
    final oldAtoms = _charAtoms(oldText);
    final newAtoms = _charAtoms(newText);
    if ((oldAtoms.length + 1) * (newAtoms.length + 1) > _maxCells) {
      return _wholeReplacement(oldText, newText);
    }
    return _diffAtoms(oldAtoms, newAtoms);
  }
  return _diffAtoms(_lineAtoms(oldLines), _lineAtoms(newLines));
}

/// 计算量过大时的兜底结果：先整段删除，再整段新增。
List<DiffRun> _wholeReplacement(String oldText, String newText) {
  return <DiffRun>[
    DiffRun(kind: DiffKind.delete, text: oldText, oldOffset: 0, newOffset: 0),
    DiffRun(
      kind: DiffKind.insert,
      text: newText,
      oldOffset: oldText.length,
      newOffset: 0,
    ),
  ];
}

/// 行级原子：每行带上自己的换行符（最后一行除外），
/// 保证所有原子依次拼接后与原文本完全一致，偏移才可加。
List<String> _lineAtoms(List<String> lines) {
  final atoms = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final atom = i == lines.length - 1 ? lines[i] : '${lines[i]}\n';
    if (atom.isNotEmpty) atoms.add(atom);
  }
  return atoms;
}

/// 字符级原子：按 UTF-16 码元切分，代理对整体保留，避免把 emoji 拆开。
List<String> _charAtoms(String text) {
  final atoms = <String>[];
  var i = 0;
  while (i < text.length) {
    var size = 1;
    final unit = text.codeUnitAt(i);
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) size = 2;
    }
    atoms.add(text.substring(i, i + size));
    i += size;
  }
  return atoms;
}

/// 对两组原子做 LCS 动态规划，回溯出编辑步骤再合并成 run。
List<DiffRun> _diffAtoms(List<String> oldAtoms, List<String> newAtoms) {
  final n = oldAtoms.length;
  final m = newAtoms.length;
  final width = m + 1;
  final dp = Int32List((n + 1) * width);
  for (var i = 1; i <= n; i++) {
    final atom = oldAtoms[i - 1];
    final row = i * width;
    final prev = row - width;
    for (var j = 1; j <= m; j++) {
      if (atom == newAtoms[j - 1]) {
        dp[row + j] = dp[prev + j - 1] + 1;
      } else {
        final up = dp[prev + j];
        final left = dp[row + j - 1];
        dp[row + j] = up >= left ? up : left;
      }
    }
  }

  // 从右下角回溯，得到逆序步骤。
  final steps = <_Step>[];
  var i = n;
  var j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && oldAtoms[i - 1] == newAtoms[j - 1]) {
      steps.add(_Step(DiffKind.equal, oldAtoms[i - 1]));
      i--;
      j--;
    } else if (i > 0 &&
        (j == 0 || dp[(i - 1) * width + j] >= dp[i * width + j - 1])) {
      steps.add(_Step(DiffKind.delete, oldAtoms[i - 1]));
      i--;
    } else {
      steps.add(_Step(DiffKind.insert, newAtoms[j - 1]));
      j--;
    }
  }

  final runs = <DiffRun>[];
  var oldPos = 0;
  var newPos = 0;
  var index = steps.length - 1;
  while (index >= 0) {
    final step = steps[index];
    if (step.kind == DiffKind.equal) {
      _appendEqual(runs, step.text, oldPos, newPos);
      oldPos += step.text.length;
      newPos += step.text.length;
      index--;
      continue;
    }
    // 一个改动块内的删除与新增统一成「先删后增」，预览排版更稳定。
    final oldStart = oldPos;
    final newStart = newPos;
    final deleted = StringBuffer();
    final inserted = StringBuffer();
    while (index >= 0 && steps[index].kind != DiffKind.equal) {
      final change = steps[index];
      if (change.kind == DiffKind.delete) {
        deleted.write(change.text);
        oldPos += change.text.length;
      } else {
        inserted.write(change.text);
        newPos += change.text.length;
      }
      index--;
    }
    if (deleted.length > 0) {
      runs.add(DiffRun(
        kind: DiffKind.delete,
        text: deleted.toString(),
        oldOffset: oldStart,
        newOffset: newStart,
      ));
    }
    if (inserted.length > 0) {
      runs.add(DiffRun(
        kind: DiffKind.insert,
        text: inserted.toString(),
        oldOffset: oldPos,
        newOffset: newStart,
      ));
    }
  }
  return runs;
}

void _appendEqual(List<DiffRun> runs, String text, int oldPos, int newPos) {
  if (runs.isNotEmpty && runs.last.kind == DiffKind.equal) {
    final last = runs.removeLast();
    runs.add(DiffRun(
      kind: DiffKind.equal,
      text: last.text + text,
      oldOffset: last.oldOffset,
      newOffset: last.newOffset,
    ));
    return;
  }
  runs.add(DiffRun(
    kind: DiffKind.equal,
    text: text,
    oldOffset: oldPos,
    newOffset: newPos,
  ));
}

class _Step {
  const _Step(this.kind, this.text);

  final DiffKind kind;
  final String text;
}