import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/i18n.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'exporter.dart';

/// 没有标题的笔记导出时用的占位名。
const _en = <String, String>{
  '无题': 'Untitled',
};

/// 把整库笔记导出成一个 Markdown 文件夹（附 assets 图片）。
/// 返回导出的篇数。
Future<int> exportLibraryMarkdown(
  NoteStore store,
  List<NoteMeta> notes,
  String targetDir,
) async {
  final exporter = NoteExporter(store);
  final used = <String>{};
  var count = 0;

  for (final meta in notes) {
    final note = await store.loadNote(meta.id);
    if (note == null) continue;
    final markdown = exporter.markdown(note);
    final base = _safeName(
      note.title.trim().isEmpty ? tr('无题', null, _en) : note.title.trim(),
    );
    var name = '$base.md';
    var suffix = 2;
    while (!used.add(name)) {
      name = '$base-$suffix.md';
      suffix++;
    }
    await File(p.join(targetDir, name)).writeAsString(markdown, flush: true);
    count++;
  }

  // 图片按相对路径写在 Markdown 里，把 assets 一起带走才不会裂。
  final assets = Directory(p.join(store.dataPath, 'assets'));
  if (await assets.exists()) {
    final target = Directory(p.join(targetDir, 'assets'));
    if (!await target.exists()) await target.create(recursive: true);
    await for (final entity in assets.list()) {
      if (entity is File) {
        await entity.copy(p.join(target.path, p.basename(entity.path)));
      }
    }
  }

  return count;
}

String _safeName(String title) {
  final cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final cut = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  return cut.isEmpty ? tr('无题', null, _en) : cut;
}
