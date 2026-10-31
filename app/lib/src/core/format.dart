import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'i18n.dart';

const _weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
const _weekdaysEn = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// 界面文案的英文表。这里只有零散的问候语与时间短语，其余日期用 intl 拼。
const _en = <String, String>{
  '夜深了': 'Late night',
  '早上好': 'Good morning',
  '上午好': 'Good morning',
  '午安': 'Good afternoon',
  '下午好': 'Good afternoon',
  '晚上好': 'Good evening',
  '刚刚': 'just now',
  '今天': 'Today',
  '昨天': 'Yesterday',
  '{n} 分钟前': '{n} min ago',
  '{n} 小时前': '{n} h ago',
  '{n} 天前': '{n} days ago',
  '不到 1 分钟': 'under a minute',
  '约 {n} 分钟': 'about {n} min',
};

String two(int n) => n.toString().padLeft(2, '0');

String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

DateTime parseDay(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String greeting(DateTime now) {
  final h = now.hour;
  if (h < 5) return tr('夜深了', null, _en);
  if (h < 9) return tr('早上好', null, _en);
  if (h < 12) return tr('上午好', null, _en);
  if (h < 14) return tr('午安', null, _en);
  if (h < 18) return tr('下午好', null, _en);
  if (h < 23) return tr('晚上好', null, _en);
  return tr('夜深了', null, _en);
}

String weekdayLabel(DateTime d) =>
    I18n.isEn ? _weekdaysEn[d.weekday - 1] : _weekdays[d.weekday - 1];

String dateLabel(DateTime d) {
  if (I18n.isEn) {
    // Oct 30, 2026 · Friday
    return '${DateFormat('MMM d, y').format(d)} · ${weekdayLabel(d)}';
  }
  return '${d.year}年${d.month}月${d.day}日 · ${weekdayLabel(d)}';
}

String shortDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return tr('今天', null, _en);
  if (diff == 1) return tr('昨天', null, _en);
  if (diff > 1 && diff < 7) return weekdayLabel(d);
  if (I18n.isEn) {
    if (d.year == now.year) return DateFormat('MMM d').format(d);
    return '${d.year}.${d.month}.${d.day}';
  }
  if (d.year == now.year) return '${d.month}月${d.day}日';
  return '${d.year}.${d.month}.${d.day}';
}

String timeLabel(DateTime d) => DateFormat('HH:mm').format(d);

String monthTitle(DateTime d) {
  if (I18n.isEn) return DateFormat('MMMM y').format(d);
  return '${d.year} 年 ${d.month} 月';
}

String relativeTime(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return tr('刚刚', null, _en);
  if (diff.inMinutes < 60) {
    return tr('{n} 分钟前', {'n': diff.inMinutes}, _en);
  }
  if (diff.inHours < 24) return tr('{n} 小时前', {'n': diff.inHours}, _en);
  if (diff.inDays == 1) return tr('昨天', null, _en);
  if (diff.inDays < 7) return tr('{n} 天前', {'n': diff.inDays}, _en);
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
  if (minutes <= 0) return tr('不到 1 分钟', null, _en);
  return tr('约 {n} 分钟', {'n': minutes}, _en);
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
