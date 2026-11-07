import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/table_embed.dart';
import 'package:this_note/src/services/exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('EPUB 包含 mimetype、container、opf、导航与正文', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-epub-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();
    final table = TableData(
      header: true,
      rows: [
        ['章节', '页数'],
        ['一', '3'],
      ],
    );
    final note = Note(
      id: 'epub-note',
      title: ' EPUB 测试 ',
      kind: NoteKind.note,
      createdAt: DateTime(2026, 11, 6),
      updatedAt: DateTime(2026, 11, 6),
      day: '2026-11-06',
      text: 'EPUB 测试\n正文\n',
      delta: [
        {'insert': '正文\n'},
        {
          'insert': {'table': jsonEncode(table.toJson())},
        },
        {'insert': '\n'},
      ],
    );

    final bytes = await NoteExporter(store).epub(note);
    final archive = ZipDecoder().decodeBytes(bytes);
    final names = archive.files.map((f) => f.name).toList();
    expect(names, contains('mimetype'));
    expect(names, contains('META-INF/container.xml'));
    expect(names, contains('OEBPS/content.opf'));
    expect(names, contains('OEBPS/nav.xhtml'));
    expect(names, contains('OEBPS/chapter.xhtml'));
    expect(names, contains('OEBPS/style.css'));

    String content(String name) {
      final file = archive.files.firstWhere((f) => f.name == name);
      return utf8.decode(file.content as List<int>);
    }

    expect(content('mimetype'), 'application/epub+zip');
    expect(content('META-INF/container.xml'), contains('content.opf'));
    expect(content('OEBPS/chapter.xhtml'), contains('<h1'));
    expect(content('OEBPS/chapter.xhtml'), contains('<table class="tn-table">'));
    expect(content('OEBPS/chapter.xhtml'), contains('正文'));
  });
}