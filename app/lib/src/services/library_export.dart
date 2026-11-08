import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../core/i18n.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'exporter.dart';

/// 没有标题的笔记导出时用的占位名。
const _en = <String, String>{
  '无题': 'Untitled',
  '未命名': 'Untitled',
  'Markdown': 'Markdown',
  '纯文本': 'Plain text',
  'EPUB 电子书': 'EPUB ebook',
  'PNG 图片': 'PNG image',
};

/// 文件夹导出的文件格式。每篇笔记在 ZIP 里单独成文件。
enum FolderExportFormat { markdown, txt, epub, png }

extension FolderExportFormatX on FolderExportFormat {
  String get label => switch (this) {
        FolderExportFormat.markdown => tr('Markdown', null, _en),
        FolderExportFormat.txt => tr('纯文本', null, _en),
        FolderExportFormat.epub => tr('EPUB 电子书', null, _en),
        FolderExportFormat.png => tr('PNG 图片', null, _en),
      };

  String get description => switch (this) {
        FolderExportFormat.markdown =>
          tr('每篇一个 Markdown，图片一并带走', null, _en),
        FolderExportFormat.txt => tr('每篇一个纯文本，只要文字', null, _en),
        FolderExportFormat.epub =>
          tr('每篇一本 EPUB，可在阅读器里打开', null, _en),
        FolderExportFormat.png =>
          tr('每篇一张长图，篇数多时会慢一些', null, _en),
      };

  String get extension => switch (this) {
        FolderExportFormat.markdown => 'md',
        FolderExportFormat.txt => 'txt',
        FolderExportFormat.epub => 'epub',
        FolderExportFormat.png => 'png',
      };
}

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

/// 把一个文件夹连同子文件夹打包成 zip。
///
/// 解压后是 `<文件夹名>/`，内部保留原来的层级；每篇笔记按 [format]
/// 单独成文件。Markdown 里引用到的图片放在根目录的 `assets/` 下，并按
/// 笔记所在层级改写成正确的相对路径。PNG 需要先由界面渲染好传进
/// [pngPages]（笔记 id → 每页图片字节）。返回打包出的篇数。
Future<({Uint8List bytes, int count})> buildFolderZip({
  required NoteStore store,
  required Folder folder,
  required List<Folder> folders,
  required List<NoteMeta> notes,
  FolderExportFormat format = FolderExportFormat.markdown,
  Map<String, List<Uint8List>> pngPages = const {},
}) async {
  final exporter = NoteExporter(store);
  final archive = Archive();
  final root = _safeName(folder.name);
  final folderIds = _folderTreeIds(folder.id, folders);
  final byFolder = <String, List<NoteMeta>>{};
  for (final meta in notes) {
    final id = meta.folderId;
    if (id == null || !folderIds.contains(id)) continue;
    byFolder.putIfAbsent(id, () => []).add(meta);
  }

  final referencedAssets = <String>{};
  var count = 0;
  final pending = <({Folder folder, String dir})>[
    (folder: folder, dir: root),
  ];
  while (pending.isNotEmpty) {
    final current = pending.removeAt(0);
    final used = <String>{};
    final localNotes = byFolder[current.folder.id] ?? const <NoteMeta>[];
    for (final meta in localNotes) {
      final note = await store.loadNote(meta.id);
      if (note == null) continue;
      final title = note.title.trim().isEmpty
          ? tr('无题', null, _en)
          : note.title.trim();
      final base = _safeName(title);
      final payloads = <Uint8List>[];
      switch (format) {
        case FolderExportFormat.markdown:
          final assetsFromHere = p.posix.relative(
            '$root/assets',
            from: current.dir,
          );
          final markdown = exporter.markdown(note).replaceAllMapped(
            RegExp(r'\]\((assets/[^)]+)\)'),
            (match) {
              final ref = match[1]!;
              referencedAssets.add(ref);
              return '](${p.posix.join(
                assetsFromHere,
                ref.substring('assets/'.length),
              )})';
            },
          );
          payloads.add(utf8.encode(markdown));
          break;
        case FolderExportFormat.txt:
          payloads.add(utf8.encode(exporter.txt(note)));
          break;
        case FolderExportFormat.epub:
          payloads.add(await exporter.epub(note));
          break;
        case FolderExportFormat.png:
          payloads.addAll(pngPages[note.id] ?? const <Uint8List>[]);
          break;
      }
      if (payloads.isEmpty) continue;

      // 同一目录里重名的笔记加序号；多页 PNG 先把整组文件名都占住，
      // 避免第二篇用掉 `-2` 和第一篇的第二页撞名。
      final ext = format.extension;
      final pages = payloads.length;
      List<String> namesFor(String stem) => [
            for (var i = 0; i < pages; i++)
              pages == 1
                  ? '$stem.$ext'
                  : '$stem-${pages >= 10 ? '${i + 1}'.padLeft(2, '0') : i + 1}.$ext',
          ];
      var stem = base;
      var suffix = 2;
      while (namesFor(stem).any(used.contains)) {
        stem = '$base-$suffix';
        suffix++;
      }
      final names = namesFor(stem);
      used.addAll(names);
      for (var i = 0; i < payloads.length; i++) {
        final bytes = payloads[i];
        archive.addFile(
          ArchiveFile(
            p.posix.join(current.dir, names[i]),
            bytes.length,
            bytes,
          ),
        );
      }
      count++;
    }

    final usedDirs = format == FolderExportFormat.markdown && current.dir == root
        ? <String>{'assets'}
        : <String>{};
    for (final child in folders.where(
      (item) => item.parentId == current.folder.id,
    )) {
      final base = _safeName(child.name);
      var name = base;
      var suffix = 2;
      while (!usedDirs.add(name)) {
        name = '$base-$suffix';
        suffix++;
      }
      pending.add((
        folder: child,
        dir: p.posix.join(current.dir, name),
      ));
    }
  }

  for (final ref in referencedAssets) {
    final bytes = await store.readAsset(ref);
    if (bytes == null) continue;
    archive.addFile(
      ArchiveFile(p.posix.join(root, ref), bytes.length, bytes),
    );
  }

  return (
    bytes: Uint8List.fromList(ZipEncoder().encode(archive)),
    count: count,
  );
}

Set<String> _folderTreeIds(String rootId, List<Folder> folders) {
  final ids = <String>{rootId};
  var grew = true;
  while (grew) {
    grew = false;
    for (final folder in folders) {
      final parent = folder.parentId;
      if (parent != null && ids.contains(parent) && ids.add(folder.id)) {
        grew = true;
      }
    }
  }
  return ids;
}

final _reserved = <String>{
  'con',
  'prn',
  'aux',
  'nul',
  for (var i = 1; i <= 9; i++) 'com$i',
  for (var i = 1; i <= 9; i++) 'lpt$i',
};

String _safeName(String title) {
  var cleaned = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (cleaned.length > 60) cleaned = cleaned.substring(0, 60);
  // Windows 上以点或空格结尾的文件名解压时会失败。
  cleaned = cleaned.replaceAll(RegExp(r'[. ]+$'), '').trim();
  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    return tr('未命名', null, _en);
  }
  if (_reserved.contains(cleaned.toLowerCase())) {
    return '_$cleaned';
  }
  return cleaned;
}
