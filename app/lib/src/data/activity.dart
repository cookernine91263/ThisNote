/// 每日写作活跃度模型：只依赖 dart:convert，可在无 Flutter 绑定的测试中直接使用。
///
/// 现有统计按「笔记创建日期」归集字数，用户续写旧笔记时不会计入当天。
/// 这里把「当天首次打开笔记时的字数」记为基线，之后只累计新增的峰值字数，
/// 于是续写旧笔记也能正确计入当天。
library;

import 'dart:convert';

/// 单篇笔记在一天内的写作记录。
class NoteActivity {
  NoteActivity({required this.startWords, this.gain = 0});

  /// 当天首次打开该笔记时的字数（基线）。
  final int startWords;

  /// 当天观察到的最大增量：max(0, peakWords - startWords)。
  int gain;

  Map<String, dynamic> toJson() => {'s': startWords, 'g': gain};

  factory NoteActivity.fromJson(Map<String, dynamic>? json) {
    if (json == null) return NoteActivity(startWords: 0);
    return NoteActivity(startWords: _count(json['s']), gain: _count(json['g']));
  }
}

/// 一天内所有笔记的写作记录，`notes` 以笔记 id 为键。
class DayActivity {
  DayActivity();

  final Map<String, NoteActivity> notes = {};

  /// 当天累计新增字数。
  int get words {
    var total = 0;
    for (final note in notes.values) {
      total += note.gain;
    }
    return total;
  }

  Map<String, dynamic> toJson() =>
      {for (final e in notes.entries) e.key: e.value.toJson()};

  factory DayActivity.fromJson(Map<String, dynamic>? json) {
    final day = DayActivity();
    _stringMap(json).forEach((noteId, value) {
      day.notes[noteId] = NoteActivity.fromJson(_stringMap(value));
    });
    return day;
  }
}

/// 按 'YYYY-MM-DD' 归集的写作活跃度日志。
class ActivityLog {
  ActivityLog();

  final Map<String, DayActivity> days = {};

  /// 当天的首次调用记录并返回基线字数；之后返回已存的基线，不再改变。
  int startSession(String day, String noteId, int words) {
    final dayLog = _day(day);
    final note = dayLog.notes[noteId];
    if (note != null) return note.startWords;
    final start = _count(words);
    dayLog.notes[noteId] = NoteActivity(startWords: start);
    return start;
  }

  /// 记录一次新的字数，只增不减，返回最终的 gain。
  /// 条目不存在时以当前字数为基线新建，gain 为 0。
  int touch(String day, String noteId, int words) {
    final dayLog = _day(day);
    final note = dayLog.notes[noteId];
    if (note == null) {
      dayLog.notes[noteId] = NoteActivity(startWords: _count(words));
      return 0;
    }
    final delta = _count(words) - note.startWords;
    final gain = delta < 0 ? 0 : delta;
    if (gain > note.gain) note.gain = gain;
    return note.gain;
  }

  /// 某天记录的总字数，缺失时返回 0。
  int wordsOn(String day) => days[day]?.words ?? 0;

  /// 有实际新增字数的日期集合。
  Set<String> activeDays() =>
      {for (final e in days.entries) if (e.value.words > 0) e.key};

  Map<String, dynamic> toJson() =>
      {'days': {for (final e in days.entries) e.key: e.value.toJson()}};

  factory ActivityLog.fromJson(Map<String, dynamic>? json) {
    final log = ActivityLog();
    _stringMap(json?['days']).forEach((day, value) {
      log.days[day] = DayActivity.fromJson(_stringMap(value));
    });
    return log;
  }

  /// 解析持久化字符串；null 或任何脏数据都返回空日志，绝不抛异常。
  static ActivityLog decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return ActivityLog();
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return ActivityLog();
      return ActivityLog.fromJson(_stringMap(data));
    } catch (_) {
      return ActivityLog();
    }
  }

  String encode() => jsonEncode(toJson());

  /// 丢弃严格早于 cutoff 的日期（按 'YYYY-MM-DD' 字符串比较）。
  void pruneBefore(String cutoff) {
    days.removeWhere((day, _) => day.compareTo(cutoff) < 0);
  }

  DayActivity _day(String day) => days.putIfAbsent(day, DayActivity.new);
}

/// 单个字数的绝对值上限，避免异常数据把统计撑爆。
const int _maxCount = 1000000000;

/// 把任意值收敛成 [0, _maxCount] 的整数。
int _count(dynamic value) {
  int parsed;
  if (value is int) {
    parsed = value;
  } else if (value is num) {
    parsed = value.isFinite ? value.toInt() : 0;
  } else if (value is String) {
    parsed = int.tryParse(value.trim()) ?? 0;
  } else {
    parsed = 0;
  }
  if (parsed < 0) return 0;
  return parsed > _maxCount ? _maxCount : parsed;
}

/// 只保留字符串键，把任意值安全地读成 `Map<String, dynamic>`。
Map<String, dynamic> _stringMap(dynamic value) {
  final out = <String, dynamic>{};
  if (value is Map) {
    value.forEach((key, v) {
      if (key is String) out[key] = v;
    });
  }
  return out;
}
