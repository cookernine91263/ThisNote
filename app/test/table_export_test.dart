import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/table_embed.dart';
import 'package:this_note/src/services/exporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('表格可以导出为 HTML / Markdown / DOCX / PDF', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-table-');
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
        ['名称', '数量'],
        ['苹果', '3'],
        ['梨', '5'],
      ],
    );
    final note = Note(
      id: 'table-note',
      title: '表格测试',
      kind: NoteKind.note,
      createdAt: DateTime(2026, 11, 6),
      updatedAt: DateTime(2026, 11, 6),
      day: '2026-11-06',
      text: '表格测试\n名称\t数量\n苹果\t3\n梨\t5\n',
      delta: [
        {
          'insert': {tableKey: jsonEncode(table.toJson())},
        },
        {'insert': '\n'},
      ],
    );

    final exporter = NoteExporter(store);
    final html = await exporter.html(note);
    final wechat = await exporter.wechatHtml(note);
    final md = exporter.markdown(note);
    final docx = await exporter.docx(note);
    final pdf = await exporter.pdf(note);

    expect(html, contains('<table class="tn-table">'));
    expect(html, contains('<th>名称</th>'));
    expect(wechat, contains('<table style='));
    expect(wechat, contains('名称'));
    expect(md, contains('| 名称 | 数量 |'));
    expect(md, contains('| 苹果 | 3 |'));
    expect(docx.length, greaterThan(2000));
    expect(pdf.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });
}