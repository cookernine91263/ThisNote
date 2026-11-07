import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

/// 一次跨笔记替换的结果。delta 可以直接写回 Note。
class ReplaceResult {
  const ReplaceResult({
    required this.delta,
    required this.text,
    required this.count,
  });

  final List<dynamic> delta;
  final String text;
  final int count;
}

/// 在 Quill Delta 中做替换，保留匹配起点所在文本段的格式。
///
/// 从后往前改，前面的 offset 不会因为替换长度变化而失效。
ReplaceResult replaceInDelta(
  List<dynamic> deltaJson,
  String query,
  String replacement, {
  bool caseSensitive = false,
  bool wholeWord = false,
  int? limit,
}) {
  if (query.isEmpty) {
    return ReplaceResult(delta: deltaJson, text: '', count: 0);
  }
  final doc = Document.fromJson(deltaJson);
  final matches = doc.search(
    query,
    caseSensitive: caseSensitive,
    wholeWord: wholeWord,
  );
  var count = 0;
  for (final offset in matches.reversed) {
    if (limit != null && count >= limit) break;
    final attrs = _attributesAt(doc, offset);
    final change = Delta()
      ..retain(offset)
      ..delete(query.length);
    if (replacement.isNotEmpty) change.insert(replacement, attrs);
    doc.compose(change, ChangeSource.local);
    count++;
  }
  return ReplaceResult(
    delta: doc.toDelta().toJson(),
    text: doc.toPlainText(),
    count: count,
  );
}

/// 统计一段纯文本里 query 出现次数，供替换前的预览。
int countOccurrences(
  String text,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty || text.isEmpty) return 0;
  final haystack = caseSensitive ? text : text.toLowerCase();
  final needle = caseSensitive ? query : query.toLowerCase();
  var count = 0;
  var from = 0;
  while (true) {
    final at = haystack.indexOf(needle, from);
    if (at < 0) break;
    count++;
    from = at + needle.length;
  }
  return count;
}

Map<String, dynamic>? _attributesAt(Document doc, int offset) {
  var position = 0;
  for (final op in doc.toDelta().toList()) {
    final length = op.length ?? 0;
    if (op.isInsert && offset >= position && offset < position + length) {
      final data = op.data;
      if (data is! String) return null;
      final attrs = op.attributes;
      return attrs == null ? null : Map<String, dynamic>.from(attrs);
    }
    position += length;
  }
  return null;
}