import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/note_fonts.dart';
import 'package:this_note/src/state/app_state.dart';

/// 导入字体：注册进字体引擎、落到数据目录、写进设置，并能在字体列表里找到。
void main() {
  testWidgets('导入的字体可以被保存、列出和移除', (tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-font-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await tester.runAsync(() => state.init());
    addTearDown(state.dispose);

    final data = await tester.runAsync(
      () => rootBundle.load('assets/fonts/MaShanZheng-Regular.ttf'),
    );
    final font = await tester.runAsync(
      () => state.importCustomFont(
        fileName: '我的行书.ttf',
        bytes: data!.buffer.asUint8List(),
      ),
    );

    expect(font, isNotNull);
    expect(font!.name, '我的行书');
    expect(state.settings.customFonts.length, 1);
    expect(
      File(state.store.resolveFont(font.file)).existsSync(),
      isTrue,
      reason: '字体文件应落在数据目录的 fonts/ 下',
    );

    final fonts = allNoteFonts(state.settings.customFonts);
    expect(fonts.any((e) => e.value == font.id), isTrue);
    expect(fontLabel(font.id, state.settings.customFonts), '我的行书');

    // 设置落盘后重开也能读回来。
    final reopened = AppState(store: NoteStore(rootOverride: temp.path));
    await tester.runAsync(() => reopened.init());
    expect(reopened.settings.customFonts.single.name, '我的行书');
    reopened.dispose();

    await tester.runAsync(() => state.removeCustomFont(font));
    expect(state.settings.customFonts, isEmpty);
    expect(File(state.store.resolveFont(font.file)).existsSync(), isFalse);
  });

  testWidgets('不是字体格式的文件会被拒绝', (tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-font2-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await tester.runAsync(() => state.init());
    addTearDown(state.dispose);

    final font = await tester.runAsync(
      () => state.importCustomFont(
        fileName: 'readme.png',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
    );
    expect(font, isNull);
    expect(state.settings.customFonts, isEmpty);
  });
}
