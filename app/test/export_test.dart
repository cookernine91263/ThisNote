import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/services/exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports docx, pdf, html, markdown and text', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_export_');
    final store = NoteStore(rootOverride: temp.path);
    await store.init();
    final note = Note(
      id: 'test-note',
      title: '此记导出测试',
      kind: NoteKind.note,
      tags: const ['测试'],
      createdAt: DateTime(2026, 10, 30, 19, 30),
      updatedAt: DateTime(2026, 10, 30, 19, 30),
      day: '2026-10-30',
      text: '此记导出测试\n这是一段正文。加粗与花字。\n第二段 Hello world.\n',
      delta: [
        {'insert': '这是一段正文。'},
        {
          'insert': '加粗',
          'attributes': {'bold': true},
        },
        {'insert': '与'},
        {
          'insert': '花字',
          'attributes': {'font': 'huazi:zhu:m'},
        },
        {'insert': '。\n'},
        {'insert': '第二段 Hello world.\n'},
        {
          'insert': '引用的一句话',
          'attributes': {'italic': true},
        },
        {'insert': '\n', 'attributes': {'blockquote': true}},
      ],
    );

    final exporter = NoteExporter(store);
    final docx = await exporter.docx(note);
    final pdf = await exporter.pdf(note);
    final html = await exporter.html(note);
    final md = exporter.markdown(note);
    final txt = exporter.txt(note);

    final out = Directory('test_out');
    if (!out.existsSync()) out.createSync();
    File(p.join(out.path, 'thisnote.docx')).writeAsBytesSync(docx);
    File(p.join(out.path, 'thisnote.pdf')).writeAsBytesSync(pdf);
    File(p.join(out.path, 'thisnote.html')).writeAsStringSync(html);
    File(p.join(out.path, 'thisnote.md')).writeAsStringSync(md);
    File(p.join(out.path, 'thisnote.txt')).writeAsStringSync(txt);

    expect(docx.length, greaterThan(2000));
    expect(pdf.length, greaterThan(4000));
    expect(pdf.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
    expect(html.contains('花字'), isTrue);
    expect(md.contains('# 此记导出测试'), isTrue);
    expect(txt.contains('第二段 Hello world.'), isTrue);
  });
}
