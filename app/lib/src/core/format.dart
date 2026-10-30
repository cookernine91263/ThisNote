import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

final _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];

String two(int n) => n.toString().padLeft(2, '0');

String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return '夜深了';
  if (h < 9) return '早上好';
  if (h < 12) return '上午好';
  if (h < 14) return '午安';
  if (h < 18) return '下午好';
  if (h < 23) return '晚上好';
  return '夜深了';
}

String weekdayLabel(DateTime d) => _weekdays[d.weekday - 1];

String dateLabel(DateTime d) =>
    '${d.year}年${d.month}月${d.day}日 · ${weekdayLabel(d)}';

String shortDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '昨天';
  if (diff > 1 && diff < 7) return weekdayLabel(d);
  if (d.year == now.year) return '${d.month}月${d.day}日';
  return '${d.year}.${d.month}.${d.day}';
}

String timeLabel(DateTime d) => DateFormat('HH:mm').format(d);

String monthTitle(DateTime d) => '${d.year} 年 ${d.month} 月';

String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return '刚刚';
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  if (diff.inDays == 1) return '昨天';
  if (diff.inDays < 7) return '${diff.inDays} 天前';
  return shortDate(d);
}

/// 中日韩字符按字计，西文按词计。
int countWords(String text) {
  if (text.trim().isEmpty) return 0;
  final cjk = RegExp(r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]')
      .allMatches(text)
      .length;
  final latin = RegExp(r"[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*")
      .allMatches(text)
      .length;
  return cjk + latin;
}

String excerptOf(String text, {int max = 84}) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (clean.length <= max) return clean;
  return '${clean.substring(0, max)}…';
}

String readingTime(int words) {
  final minutes = (words / 300).ceil();
  return minutes <= 0 ? '不到 1 分钟' : '约 $minutes 分钟';
}

/// 把颜色转为 Quill 使用的 #RRGGBB
String hexOf(Color c) {
  final v = c.toARGB32() & 0xFFFFFF;
  return '#${v.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

Color? parseHex(String? value) {
  if (value == null) return null;
  var v = value.trim();
  if (v.startsWith('#')) v = v.substring(1);
  if (v.length == 3) {
    v = v.split('').map((e) => '$e$e').join();
  }
  if (v.length == 6) v = 'FF$v';
  final n = int.tryParse(v, radix: 16);
  return n == null ? null : Color(n);
}
