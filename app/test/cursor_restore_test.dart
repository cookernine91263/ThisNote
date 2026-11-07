import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('重新打开笔记会回到上次的光标位置', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-cursor-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }

    final note = await state.createNote(title: '光标');
    state.session!.controller.replaceText(
      0,
      0,
      '前面 这里 后面\n',
      const TextSelection.collapsed(offset: 3),
    );
    await state.saveNow();
    await state.closeEditor();

    await state.openNote(note.id, autofocus: false);
    expect(state.session!.controller.selection.extentOffset, 3);
  });
}