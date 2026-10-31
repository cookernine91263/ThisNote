import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/format.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppState state;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('thisnote_state_');
    state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    // 清掉示例笔记，让统计从零开始，断言才不会被种子内容干扰。
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }
  });

  tearDown(() {
    state.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('续写旧笔记也计入今天，且当天进度不会被多次保存重复累加', () async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final note = await state.createNote(day: yesterday, title: '昨天的稿子');
    final today = dayKey(DateTime.now());

    // 今天在这篇旧稿上写了 120 字。
    state.recordActivity(note.id, 120);
    expect(state.wordsByDay[today], 120);

    // 继续写到 200 字：只按峰值算，不会 120 + 200。
    state.recordActivity(note.id, 200);
    expect(state.wordsByDay[today], 200);

    // 删回 80 字也不倒扣。
    state.recordActivity(note.id, 80);
    expect(state.wordsByDay[today], 200);

    // 总字数仍按正文算，不受活跃度影响。
    expect(state.totalWords, note.words);
    expect(state.streak, greaterThanOrEqualTo(1));
  });

  test('活跃度会写盘并在下次启动时恢复', () async {
    final note = await state.createNote(title: '今天');
    state.recordActivity(note.id, 260);
    await state.persistActivity();

    final reopened = AppState(store: NoteStore(rootOverride: temp.path));
    await reopened.init();
    expect(reopened.wordsByDay[dayKey(DateTime.now())], 260);
    reopened.dispose();
  });

  test('拖拽排序只在同一天生效，并保持日期分组连续', () async {
    final today = DateTime.now();
    final a = await state.createNote(day: today, title: 'A');
    final b = await state.createNote(day: today, title: 'B');
    final old = await state.createNote(
      day: today.subtract(const Duration(days: 2)),
      title: 'C',
    );

    // 把 A 放到 B 的后面。
    expect(await state.reorderNote(a.id, b.id, after: true), isTrue);
    expect(state.sort, 'manual');
    final sameDay = state.visibleNotes
        .where((n) => n.day == dayKey(today))
        .map((n) => n.title)
        .toList();
    expect(sameDay.indexOf('B'), lessThan(sameDay.indexOf('A')));

    // 跨日期不允许。
    expect(await state.reorderNote(a.id, old.id), isFalse);

    // 手动排序下，同一个日期必须连成一块，不能被打散后重复出现。
    final seen = <String>{};
    String? previous;
    for (final note in state.visibleNotes) {
      if (note.day == previous) continue;
      expect(
        seen.add(note.day),
        isTrue,
        reason: '日期分组被打断：${note.day}',
      );
      previous = note.day;
    }
  });

  test('从「最近」切到手动排序时，看到的顺序不变', () async {
    final before = state.visibleNotes.map((n) => n.id).toList();
    await state.beginManualOrder();
    expect(state.sort, 'manual');
    expect(state.visibleNotes.map((n) => n.id).toList(), before);
  });

  test('恢复历史版本前会先留一份快照，恢复本身可回溯', () async {
    final note = await state.createNote(title: '版本测试');
    final session = state.session!;
    session.controller.replaceText(
      0,
      0,
      '第一版\n',
      const TextSelection.collapsed(offset: 4),
    );
    await session.flush(snapshot: true);
    final before = await state.historyFor(note.id);
    expect(before, isNotEmpty);

    session.controller.replaceText(
      0,
      0,
      '第二版\n',
      const TextSelection.collapsed(offset: 4),
    );
    await session.flush();
    expect(session.plainText.contains('第二版'), isTrue);

    await state.restoreSnapshot(before.first);
    expect(state.session!.plainText.contains('第一版'), isTrue);
    expect(state.session!.plainText.contains('第二版'), isFalse);

    final after = await state.historyFor(note.id);
    expect(
      after.any((snap) => snap.text.contains('第二版')),
      isTrue,
      reason: '恢复会覆盖当前内容，所以恢复前的正文必须先留成一个版本',
    );
  });

  test('正文文件损坏时能从 .bak 读回上一版', () async {
    final note = await state.createNote(title: '备份测试');
    final session = state.session!;
    session.controller.replaceText(
      0,
      0,
      '第一版\n',
      const TextSelection.collapsed(offset: 4),
    );
    await session.flush();
    session.controller.replaceText(
      0,
      0,
      '第二版\n',
      const TextSelection.collapsed(offset: 4),
    );
    await session.flush();
    await state.closeEditor();

    // 模拟写到一半断电：主文件成了半截 JSON。
    final main = File('${temp.path}/notes/${note.id}.json');
    expect(main.existsSync(), isTrue);
    main.writeAsStringSync('{"title": "坏掉的');

    final loaded = await state.store.loadNote(note.id);
    expect(loaded, isNotNull, reason: '损坏时应回退到 .bak，而不是直接丢笔记');
    expect(loaded!.text.contains('第一版'), isTrue);
  });

  test('改标签、心情会立刻落盘，不用等下一次敲字', () async {
    final note = await state.createNote(title: '元数据');
    final session = state.session!;
    await session.flush();

    await session.setTags(['读书', '日常']);
    await session.setMood(4);
    await session.setWeather('sunny');
    await session.setKind(NoteKind.essay);

    final saved = await state.store.loadNote(note.id);
    expect(saved, isNotNull);
    expect(saved!.tags, containsAll(['读书', '日常']));
    expect(saved.mood, 4);
    expect(saved.weather, 'sunny');
    expect(saved.kind, NoteKind.essay);
  });
}
