import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/services/clipboard_image.dart';
import 'package:this_note/src/state/app_state.dart';

void _cleanup(Directory dir) {
  try {
    dir.deleteSync(recursive: true);
  } catch (_) {
    // Windows 上偶发文件占用，临时目录留给系统清理即可。
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('拖入图片会存成 asset 并插入当前笔记', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_drop_');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }

    final png = encodePng(1, 1, Uint8List.fromList([255, 0, 0]));
    final imageFile = File(p.join(temp.path, 'shot.png'))
      ..writeAsBytesSync(png);

    final result = await state.acceptDroppedFiles([imageFile.path]);
    expect(result.images, 1);
    expect(result.imported, 0);
    expect(state.session, isNotNull);
    expect(state.session!.plainText.contains('\uFFFC'), isTrue);

    final assets = Directory(p.join(state.store.dataPath, 'assets'));
    expect(assets.listSync().whereType<File>(), isNotEmpty);

    state.dispose();
    _cleanup(temp);
  });

  test('拖入 Markdown 会导入成一篇笔记', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote_drop_');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }

    final md = File(p.join(temp.path, '拖进来的稿子.md'))
      ..writeAsStringSync('# 拖进来的标题\n\n正文。\n');

    final result = await state.acceptDroppedFiles([md.path]);
    expect(result.imported, 1);
    expect(result.images, 0);
    expect(
      state.notes.any((note) => note.title == '拖进来的标题'),
      isTrue,
    );

    state.dispose();
    _cleanup(temp);
  });
}
