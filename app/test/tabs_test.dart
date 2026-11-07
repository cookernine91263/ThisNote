import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/editor_tabs.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('多标签切换、关闭与内容保存', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-tabs-');
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

    final a = await state.createNote(title: 'A');
    state.session!.controller.replaceText(
      0,
      0,
      '第一页\n',
      const TextSelection.collapsed(offset: 0),
    );
    await state.saveNow();
    final b = await state.createNote(title: 'B');
    state.session!.controller.replaceText(
      0,
      0,
      '第二页\n',
      const TextSelection.collapsed(offset: 0),
    );
    await state.saveNow();

    expect(state.openTabs, [a.id, b.id]);
    expect(state.current?.id, b.id);

    await state.switchTab(a.id);
    expect(state.current?.id, a.id);
    expect(state.session?.note.text, contains('第一页'));
    expect(state.openTabs.length, 2);

    await state.closeTab(a.id);
    expect(state.current?.id, b.id);
    expect(state.openTabs, [b.id]);

    await state.closeTab(b.id);
    expect(state.current, isNull);
    expect(state.openTabs, isEmpty);
  });

  test('标签可以拖动调整顺序', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-tab-order-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await state.init();
    final a = await state.createNote(title: 'A');
    final b = await state.createNote(title: 'B');
    final c = await state.createNote(title: 'C');
    expect(state.openTabs, [a.id, b.id, c.id]);

    // 把 C 拖到最前。
    state.moveTabToIndex(c.id, 0);
    expect(state.openTabs, [c.id, a.id, b.id]);

    // 把 A 拖到最后。
    state.moveTabToIndex(a.id, 3);
    expect(state.openTabs, [c.id, b.id, a.id]);
  });

  testWidgets('标签栏按数量铺开宽度且不溢出', (tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-tab-layout-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      await state.init();
      await state.createNote(title: '一');
      await state.createNote(title: '二');
      await state.createNote(title: '三');
    });

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light, 1.0),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 900, child: EditorTabs(state: state)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('一'), findsOneWidget);
    expect(find.text('二'), findsOneWidget);
    expect(find.text('三'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('直接拖动标签卡片就能换位', (tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-tab-drag-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await tester.runAsync(() async {
      await state.init();
      await state.createNote(title: '一');
      await state.createNote(title: '二');
      await state.createNote(title: '三');
    });
    final first = state.openTabs.first;

    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(Brightness.light, 1.0),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 900, child: EditorTabs(state: state)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final y = tester.getCenter(find.text('一')).dy;
      final secondRight = tester.getRect(find.text('二')).right + 6;
      final thirdRight = tester.getRect(find.text('三')).right + 6;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('一')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(Offset(secondRight, y));
      await tester.pump(const Duration(milliseconds: 80));
      await gesture.moveTo(Offset(thirdRight, y));
      await tester.pump(const Duration(milliseconds: 260));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(state.openTabs.last, first);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}