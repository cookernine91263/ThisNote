import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/format.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  test('写作时长按分钟、小时展示', () {
    expect(writingTimeLabel(0, 300), contains('阅读'));
    expect(writingTimeLabel(30, 1200), contains('不到 1 分钟'));
    expect(writingTimeLabel(600, 1200), contains('10 分钟'));
    expect(writingTimeLabel(3600, 1200), contains('1 小时'));
    expect(writingTimeLabel(3660, 1200), contains('1 小时 1 分'));
    expect(writingTimeLabel(7200, 1200), contains('2 小时'));
  });

  test('写作时长会写进笔记 JSON，也能读回来', () {
    final note = Note(
      id: 'n1',
      title: '长信',
      delta: [
        {'insert': '正文\n'}
      ],
      text: '正文',
      kind: NoteKind.essay,
      createdAt: DateTime(2026, 10, 31, 16),
      updatedAt: DateTime(2026, 10, 31, 17),
      words: 2,
      writingSeconds: 3720,
      day: '2026-10-31',
    );
    final restored = Note.fromJson(
      jsonDecode(jsonEncode(note.toJson())) as Map<String, dynamic>,
    );
    expect(restored.writingSeconds, 3720);
    expect(restored.toMeta().writingSeconds, 3720);
  });

  test('导入的字体跟着设置一起保存', () {
    final settings = AppSettings(
      customFonts: [
        CustomFont(id: 'user_1', name: '我的字体', file: '1.ttf'),
      ],
    );
    final restored = AppSettings.fromJsonString(jsonEncode(settings.toJson()));
    expect(restored.customFonts.length, 1);
    expect(restored.customFonts.first.id, 'user_1');
    expect(restored.customFonts.first.name, '我的字体');
  });

  test('损坏的字体条目会被忽略，不影响设置读取', () {
    final restored = AppSettings.fromJson(<String, dynamic>{
      'customFonts': [
        {'id': '', 'file': ''},
        {'id': 'user_2', 'name': '可用', 'file': '2.otf'},
        'not-a-map',
      ],
    });
    expect(restored.customFonts.length, 1);
    expect(restored.customFonts.first.id, 'user_2');
  });

  testWidgets('冲刺计时可以开始与停止', (tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-sprint-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(state.dispose);
    await tester.runAsync(() async {
      await state.init();
      await state.openNote('seed-welcome', autofocus: false);
    });
    final session = state.session!;
    session.startSprint(25);
    expect(session.sprintActive, isTrue);
    expect(session.sprintRemainingSeconds, greaterThan(0));
    session.stopSprint();
    expect(session.sprintActive, isFalse);
  });

  testWidgets('动笔后写作时长会跟着累加', (tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-time-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await tester.runAsync(() async {
      await state.init();
      await state.openNote('seed-welcome', autofocus: false);
    });
    addTearDown(state.dispose);

    final session = state.session!;
    final before = session.writingSeconds;
    expect(before, 0, reason: '刚建好的笔记还没有动笔记录');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    session.controller.replaceText(
      0,
      0,
      '新写的一句',
      const TextSelection.collapsed(offset: 5),
    );

    expect(session.writingSeconds, greaterThanOrEqualTo(1));
    // 落盘会顺手取消 900ms 的自动保存定时器，测试收尾才不会有挂起的 Timer。
    await tester.runAsync(() => session.flush());
  });
}
