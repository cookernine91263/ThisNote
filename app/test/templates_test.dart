import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/data/templates.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('可以把当前笔记存成模板并再次使用', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-template-');
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

    await state.createNote(title: '模板标题');
    state.session!.controller.replaceText(
      0,
      0,
      '模板正文\n',
      const TextSelection.collapsed(offset: 0),
    );
    final template = await state.saveCurrentAsTemplate('我的模板');
    expect(template, isNotNull);
    expect(state.userTemplates.length, 1);
    expect(await state.store.loadTemplates(), hasLength(1));

    final note = await state.createNote(
      template: state.userTemplates.first.toNoteTemplate(),
    );
    expect(note.title, '模板标题');
    expect(note.text, contains('模板正文'));

    await state.deleteUserTemplate(template!.id);
    expect(state.userTemplates, isEmpty);
  });

  test('模板里会展开日期变量', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-template2-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await state.init();
    const template = NoteTemplate(
      id: 'vars',
      name: '变量',
      description: '',
      kind: NoteKind.note,
      delta: [
        {'insert': '写于 {{date}} {{weekday}}\n'},
      ],
    );
    final note = await state.createNote(template: template);
    final year = DateTime.now().year.toString();
    expect(note.text, contains(year));
    expect(note.text, isNot(contains('{{date}}')));
    expect(note.text, isNot(contains('{{weekday}}')));
  });

  test('系统分享的文字会落成一篇新笔记', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-share-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await state.init();
    await state.importSharedText('从浏览器分享的一句话\nhttps://example.com');
    expect(state.current, isNotNull);
    expect(state.current!.text, contains('从浏览器分享的一句话'));
    expect(state.notes.first.title, contains('从浏览器分享的一句话'));
  });

  test('今天写日记会打开同一篇', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-diary-');
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

    await state.openTodayDiary();
    final first = state.current!.id;
    await state.openNote(state.notes.first.id);
    await state.openTodayDiary();
    expect(state.current!.id, first);
    expect(state.activeNotes.where((n) => n.kind == NoteKind.diary).length, 1);
  });
}