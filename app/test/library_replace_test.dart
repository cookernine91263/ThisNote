import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('跨笔记替换会留历史快照并重开当前笔记', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-replace-');
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

    final first = await state.createNote(title: '第一篇');
    state.session!.controller.replaceText(
      0,
      0,
      '今天写了一句。今天很好。\n',
      const TextSelection.collapsed(offset: 0),
    );
    await state.saveNow();

    final second = await state.createNote(title: '第二篇');
    state.session!.controller.replaceText(
      0,
      0,
      '今天也要继续写。\n',
      const TextSelection.collapsed(offset: 0),
    );
    await state.saveNow();

    expect(state.countMatchesInLibrary('今天'), 3);
    final replaced = await state.replaceAllInLibrary('今天', '昨日');
    expect(replaced, 3);

    final firstAfter = await state.store.loadNote(first.id);
    final secondAfter = await state.store.loadNote(second.id);
    expect(firstAfter!.text, contains('昨日写了一句。昨日很好。'));
    expect(secondAfter!.text, contains('昨日也要继续写。'));
    expect(await state.store.loadSnapshots(first.id), isNotEmpty);
    expect(state.current?.id, second.id);
    expect(state.session?.note.text, contains('昨日'));
  });
}