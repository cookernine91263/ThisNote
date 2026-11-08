import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/services/library_export.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> freshState(Directory temp) async {
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }
    return state;
  }

  test('整库导出 Markdown：重名加序号，assets 一起带走', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_export_');
    final out = Directory.systemTemp.createTempSync('thisnote_out_');
    final state = await freshState(temp);

    await state.createNote(title: '同名的一篇');
    await state.closeEditor();
    await state.createNote(title: '同名的一篇');
    await state.closeEditor();

    final assets = Directory(p.join(state.store.dataPath, 'assets'));
    await assets.create(recursive: true);
    await File(p.join(assets.path, 'pic.png')).writeAsBytes([1, 2, 3]);

    final count = await exportLibraryMarkdown(
      state.store,
      state.activeNotes,
      out.path,
    );
    expect(count, 2);
    expect(File(p.join(out.path, '同名的一篇.md')).existsSync(), isTrue);
    expect(File(p.join(out.path, '同名的一篇-2.md')).existsSync(), isTrue);
    expect(File(p.join(out.path, 'assets', 'pic.png')).existsSync(), isTrue);

    final first = File(p.join(out.path, '同名的一篇.md')).readAsStringSync();
    expect(first.contains('# 同名的一篇'), isTrue);

    state.dispose();
    temp.deleteSync(recursive: true);
    out.deleteSync(recursive: true);
  });

  test('文件夹导出 ZIP：保留子文件夹、重名加序号、图片路径随层级改写', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_folder_zip_');
    final state = await freshState(temp);

    final root = await state.createFolder('小说');
    final child = await state.createFolder('卷一', parentId: root.id);
    final first = await state.createNote(title: '同名');
    await state.closeEditor();
    await state.moveNoteToFolder(first.id, root.id);
    final second = await state.createNote(title: '同名');
    await state.closeEditor();
    await state.moveNoteToFolder(second.id, child.id);

    final assets = Directory(p.join(state.store.dataPath, 'assets'));
    await assets.create(recursive: true);
    await File(p.join(assets.path, 'pic.png')).writeAsBytes([1, 2, 3]);
    Future<void> attachImage(String id) async {
      final note = (await state.store.loadNote(id))!;
      note.delta = [
        {
          'insert': {'image': 'assets/pic.png'},
        },
        {'insert': '\n'},
        ...note.delta,
      ];
      await state.store.saveNote(note);
    }

    await attachImage(first.id);
    await attachImage(second.id);

    final result = await buildFolderZip(
      store: state.store,
      folder: root,
      folders: state.folders,
      notes: state.activeNotes,
    );
    expect(result.count, 2);

    final archive = ZipDecoder().decodeBytes(result.bytes);
    final files = {
      for (final file in archive.files)
        if (file.isFile) file.name: file,
    };
    expect(files.keys, containsAll([
      '小说/同名.md',
      '小说/卷一/同名.md',
      '小说/assets/pic.png',
    ]));
    final rootMd = utf8.decode(files['小说/同名.md']!.content as List<int>);
    final childMd =
        utf8.decode(files['小说/卷一/同名.md']!.content as List<int>);
    expect(rootMd.contains('](assets/pic.png)'), isTrue);
    expect(childMd.contains('](../assets/pic.png)'), isTrue);

    state.dispose();
    temp.deleteSync(recursive: true);
  });

  test('文件夹导出支持 TXT / EPUB / PNG', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_folder_fmt_');
    final state = await freshState(temp);

    final folder = await state.createFolder('杂记');
    final note = await state.createNote(title: '一篇');
    await state.closeEditor();
    await state.moveNoteToFolder(note.id, folder.id);

    Future<Archive> zip(FolderExportFormat format,
        {Map<String, List<Uint8List>> png = const {}}) async {
      final result = await buildFolderZip(
        store: state.store,
        folder: folder,
        folders: state.folders,
        notes: state.activeNotes,
        format: format,
        pngPages: png,
      );
      expect(result.count, 1);
      return ZipDecoder().decodeBytes(result.bytes);
    }

    final txt = await zip(FolderExportFormat.txt);
    final txtFile = txt.files.firstWhere((f) => f.isFile);
    expect(txtFile.name, '杂记/一篇.txt');

    final epub = await zip(FolderExportFormat.epub);
    final epubFile = epub.files.firstWhere((f) => f.isFile);
    expect(epubFile.name, '杂记/一篇.epub');
    expect((epubFile.content as List<int>).take(2), [0x50, 0x4B]);

    final png = await zip(
      FolderExportFormat.png,
      png: {
        note.id: [Uint8List.fromList([9, 8, 7])],
      },
    );
    expect(png.files.map((f) => f.name), contains('杂记/一篇.png'));

    state.dispose();
    temp.deleteSync(recursive: true);
  });

  test('导入 Markdown 生成笔记，并且真的写进磁盘', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_import_');
    final state = await freshState(temp);

    final note = await state.importMarkdown(
      content: '# 导入的标题\n\n**粗体**与正文。\n',
      filename: 'whatever.md',
    );
    expect(note.title, '导入的标题');
    expect(note.text.contains('粗体'), isTrue);
    expect(state.notes.any((n) => n.id == note.id), isTrue);

    final reloaded = await state.store.loadNote(note.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.title, '导入的标题');
    expect(reloaded.delta, isNotEmpty);
    expect(reloaded.words, greaterThan(0));

    state.dispose();
    temp.deleteSync(recursive: true);
  });
}
