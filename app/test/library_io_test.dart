import 'dart:io';

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
