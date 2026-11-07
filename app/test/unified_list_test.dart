import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/note_list.dart';
import 'package:this_note/src/state/app_state.dart';

Future<AppState> _boot(WidgetTester tester, String prefix) async {
  final temp = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    try {
      temp.deleteSync(recursive: true);
    } catch (_) {}
  });
  final state = AppState(store: NoteStore(rootOverride: temp.path));
  await tester.runAsync(state.init);
  addTearDown(state.dispose);
  return state;
}

Future<void> _pumpList(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.build(Brightness.light, 1.0),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 324, child: NoteListPanel()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('在文件夹里新建的笔记会直接落进这个文件夹', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-folder-new-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    addTearDown(state.dispose);

    final folder = await state.createFolder('小说');
    state.setFolderFilter(folder.id);
    final note = await state.createNote(title: '第一章');

    expect(note.folderId, folder.id);
    expect(state.visibleNotes.map((n) => n.id), contains(note.id));

    state.setFolderFilter(null);
    expect(
      state.visibleNotes.map((n) => n.id),
      isNot(contains(note.id)),
      reason: '文件夹里的笔记不应该同时出现在上一层',
    );
    expect(
      state.listEntries.whereType<Folder>().map((f) => f.id),
      contains(folder.id),
    );
  });

  test('固定后的笔记不会因为再次修改而离开原来的位置', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-fixed-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    addTearDown(state.dispose);
    state.setView('all');

    final a = await state.createNote(title: 'A');
    final b = await state.createNote(title: 'B');
    final c = await state.createNote(title: 'C');
    final ids = {a.id, b.id, c.id};
    List<String> ours() => state.visibleNotes
        .where((n) => ids.contains(n.id))
        .map((n) => n.title)
        .toList();
    // 最近更新：C / B / A。
    expect(ours(), ['C', 'B', 'A']);

    await state.toggleFixed(state.metaById(b.id)!);
    final anchor = state.visibleNotes.indexWhere((n) => n.id == b.id);
    expect(anchor, greaterThan(0));

    // 修改 B 自己：B 应该停在原来的位置上。
    final fixed = state.metaById(b.id)!..updatedAt = DateTime.now();
    await state.updateMeta(fixed);
    final cMeta = state.metaById(c.id)!..updatedAt = DateTime.now();
    await state.updateMeta(cMeta);

    expect(state.visibleNotes.indexWhere((n) => n.id == b.id), anchor);
    expect(
      state.visibleNotes.indexWhere((n) => n.id == c.id),
      lessThan(anchor),
    );
  });

  test('「全部」里可以把笔记拖到文件夹卡片上方，并冻结成手动顺序', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-unified-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    addTearDown(state.dispose);
    state.setView('all');

    final folder = await state.createFolder('小说');
    final one = await state.createNote(title: '一');
    final two = await state.createNote(title: '二');

    final ok = await state.reorderListEntry(
      one.id,
      folder.id,
      after: false,
      targetIsFolder: true,
    );
    expect(ok, isTrue);
    expect(state.sort, 'manual');
    final entries = state.listEntries;
    final oneIndex = entries.indexWhere(
      (e) => e is NoteMeta && e.id == one.id,
    );
    final folderIndex = entries.indexWhere(
      (e) => e is Folder && e.id == folder.id,
    );
    expect(oneIndex, greaterThanOrEqualTo(0));
    expect(folderIndex, greaterThan(oneIndex));
    expect(
      entries.whereType<NoteMeta>().map((n) => n.id),
      containsAll([one.id, two.id]),
    );

    await state.moveNoteToFolder(two.id, folder.id);
    state.setFolderFilter(folder.id);
    expect(state.visibleNotes.map((n) => n.id), [two.id]);
  });

  test('批量收藏、固定、移动和删除只落一次盘', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-batch-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    addTearDown(state.dispose);
    state.setView('all');

    final a = await state.createNote(title: 'A');
    final b = await state.createNote(title: 'B');
    final folder = await state.createFolder('归档');

    await state.setFavoriteMany([a.id, b.id], true);
    await state.setPinnedMany([a.id, b.id], true);
    await state.setFixedMany([a.id, b.id], true);
    expect(state.metaById(a.id)!.favorite, isTrue);
    expect(state.metaById(b.id)!.pinned, isTrue);
    expect(state.metaById(b.id)!.fixed, isTrue);

    await state.moveNotesToFolder([a.id, b.id], folder.id);
    expect(state.metaById(a.id)!.folderId, folder.id);
    expect(state.metaById(b.id)!.folderId, folder.id);

    await state.trashMany([a.id, b.id]);
    expect(state.metaById(a.id)!.isTrashed, isTrue);
    expect(state.metaById(b.id)!.isTrashed, isTrue);
  });

  testWidgets('文件夹以卡片出现在同一列表里，笔记可以拖进文件夹', (tester) async {
    final state = await _boot(tester, 'thisnote-folder-list-');
    late Folder folder;
    late Note note;
    await tester.runAsync(() async {
      state.setView('all');
      folder = await state.createFolder('小说');
      note = await state.createNote(title: '第一章');
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpList(tester, state);

      expect(find.byType(FolderCard), findsOneWidget);
      expect(find.text('小说'), findsOneWidget);
      expect(find.text('第一章'), findsOneWidget);
      expect(find.text('时间'), findsOneWidget);
      expect(
        find.text('本周'),
        findsNothing,
        reason: '「全部」是平铺列表，不插日期分组标题',
      );

      final noteFinder = find.ancestor(
        of: find.text('第一章'),
        matching: find.byType(NoteCard),
      );
      final folderFinder = find.byType(FolderCard);
      final gesture = await tester.startGesture(
        tester.getCenter(noteFinder),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(tester.getCenter(folderFinder));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(find.text('松手放入'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    expect(state.metaById(note.id)!.folderId, folder.id);
    expect(find.text('第一章'), findsNothing);
    expect(find.byType(FolderCard), findsOneWidget);
  });

  testWidgets('把卡片拖到列表下边缘时会自动滚动', (tester) async {
    final state = await _boot(tester, 'thisnote-autoscroll-');
    await tester.runAsync(() async {
      state.setView('all');
      for (var i = 0; i < 30; i++) {
        await state.createNote(title: '长列表 $i');
      }
      await state.closeEditor();
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpList(tester, state);
      final listFinder = find.byWidgetPredicate(
        (widget) => widget is ListView && widget.scrollDirection == Axis.vertical,
      );
      final listView = tester.widget<ListView>(listFinder);
      final before = listView.controller!.offset;

      final firstCard = find.byType(NoteCard).first;
      final listRect = tester.getRect(listFinder);
      final gesture = await tester.startGesture(
        tester.getCenter(firstCard),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(
        Offset(listRect.center.dx, listRect.bottom - 20),
      );
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        listView.controller!.offset,
        greaterThan(before),
        reason: '拖到列表下边缘应该自动向下滚动',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('固定卡片只锁住自己，其它卡片可以自由跨过它排序', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-fixed-slot-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    addTearDown(state.dispose);
    state.setView('all');

    final a = await state.createNote(title: 'A');
    final b = await state.createNote(title: 'B');
    final c = await state.createNote(title: 'C');
    await state.toggleFixed(state.metaById(b.id)!);

    // 固定的 B 自己不能被拖走。
    expect(await state.reorderListEntry(b.id, c.id), isFalse);
    // C 可以跨过固定的 B，B 的位置保持不变。
    expect(await state.reorderListEntry(c.id, a.id), isTrue);
    expect(state.metaById(b.id)!.fixed, isTrue);
    var titles = state.visibleNotes
        .where((n) => [a.id, b.id, c.id].contains(n.id))
        .map((n) => n.title)
        .toList();
    expect(titles[1], 'B');

    // A 也可以从下面跨回固定卡片上方。
    expect(await state.reorderListEntry(a.id, b.id), isTrue);
    titles = state.visibleNotes
        .where((n) => [a.id, b.id, c.id].contains(n.id))
        .map((n) => n.title)
        .toList();
    expect(titles[1], 'B');
  });

  testWidgets('文件夹也能参与多选并批量固定', (tester) async {
    final state = await _boot(tester, 'thisnote-folder-select-');
    late Folder folder;
    await tester.runAsync(() async {
      state.setView('all');
      folder = await state.createFolder('小说');
      await state.createNote(title: '正文');
    });
    await _pumpList(tester, state);

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小说'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 项'), findsOneWidget);

    await tester.tap(find.text('固定'));
    await tester.pumpAndSettle();
    expect(state.folderById(folder.id)!.fixed, isTrue);
  });

  testWidgets('文件夹里的笔记可以拖到「移出」条回到上一层', (tester) async {
    final state = await _boot(tester, 'thisnote-folder-out-');
    late Folder folder;
    late Note note;
    await tester.runAsync(() async {
      state.setView('all');
      folder = await state.createFolder('小说');
      note = await state.createNote(title: '章一');
      await state.moveNoteToFolder(note.id, folder.id);
      state.setFolderFilter(folder.id);
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpList(tester, state);
      final card = find.ancestor(
        of: find.text('章一'),
        matching: find.byType(NoteCard),
      );
      final start = tester.getCenter(card);
      final gesture = await tester.startGesture(
        start,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      // 先动一下让 Draggable 真正开始，移出条才会出现。
      await gesture.moveTo(Offset(start.dx, start.dy - 50));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(find.text('拖到这里移出当前文件夹'), findsOneWidget);
      await gesture.moveTo(
        tester.getCenter(find.text('拖到这里移出当前文件夹')),
      );
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    expect(state.metaById(note.id)!.folderId, isNull);
    expect(
      state.visibleNotes.map((n) => n.id),
      isNot(contains(note.id)),
    );
  });

  testWidgets('拖到侧栏最上方会落到第一位，而不是弹回原处', (tester) async {
    final state = await _boot(tester, 'thisnote-drag-top-');
    late Note a;
    await tester.runAsync(() async {
      state.setView('all');
      await state.createNote(title: '前一篇');
      a = await state.createNote(title: '最后这篇');
      await state.closeEditor();
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await _pumpList(tester, state);
      final card = find.ancestor(
        of: find.text('最后这篇'),
        matching: find.byType(NoteCard),
      );
      final panel = tester.getRect(find.byType(NoteListPanel));
      final gesture = await tester.startGesture(
        tester.getCenter(card),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(Offset(panel.center.dx, panel.top + 6));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }

    expect(
      state.visibleNotes.where((n) => !n.pinned).first.id,
      a.id,
    );
  });

  testWidgets('多选时可以按住滑过卡片连续选中', (tester) async {
    final state = await _boot(tester, 'thisnote-sweep-');
    await tester.runAsync(() async {
      state.setView('all');
      await state.createNote(title: '滑一');
      await state.createNote(title: '滑二');
      await state.createNote(title: '滑三');
      await state.closeEditor();
    });
    await _pumpList(tester, state);

    await tester.tap(find.byTooltip('多选'));
    await tester.pumpAndSettle();
    final cards = find.byType(NoteCard);
    final start = tester.getCenter(cards.at(0));
    final end = tester.getCenter(cards.at(2));
    final gesture = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveTo(Offset(end.dx, end.dy - 10));
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.moveTo(end);
    await tester.pump(const Duration(milliseconds: 60));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('已选 3 项'), findsOneWidget);
  });
}
