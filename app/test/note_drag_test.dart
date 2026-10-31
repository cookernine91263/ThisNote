import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/note_list.dart';
import 'package:this_note/src/state/app_state.dart';

/// 桌面上用鼠标拖笔记：按下就移动，不应该先等 300ms 长按。
/// 这里还特意打开了和 app.dart 一样的「鼠标也能拖动滚动」策略，
/// 确认卡片拖拽仍然抢在滚动前面。
class _MouseScrollBehavior extends MaterialScrollBehavior {
  const _MouseScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };
}

void main() {
  testWidgets('鼠标按下后直接拖动就可以调整同一天笔记的顺序', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-drag-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.createNote(title: 'A');
      await state.createNote(title: 'B');
      state.setView('all');
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: state,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light, 1.0),
            scrollBehavior: const _MouseScrollBehavior(),
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

      final a = find.ancestor(
        of: find.text('A'),
        matching: find.byType(NoteCard),
      );
      final b = find.ancestor(
        of: find.text('B'),
        matching: find.byType(NoteCard),
      );
      expect(a, findsOneWidget);
      expect(b, findsOneWidget);

      final aRect = tester.getRect(a);
      final bRect = tester.getRect(b);
      expect(aRect.top, greaterThan(bRect.top), reason: 'B 是较新的一篇，先出现在上面');
      final aId = state.notes.firstWhere((n) => n.title == 'A').id;

      // 不做任何长按等待：按下、立刻往上拖到 B 的上半部分。
      final gesture = await tester.startGesture(
        aRect.center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(Offset(aRect.center.dx, bRect.center.dy - 24));
      await tester.pump(const Duration(milliseconds: 120));
      // 位置快照在下一帧结束后才量好，再补一帧把预览画出来。
      await tester.pump();

      // 拖动过程中：原位置收起来，B 前面出现一张影子卡的空隙。
      final mirror = find.byKey(const ValueKey('drag-mirror'));
      expect(mirror, findsOneWidget);
      expect(tester.getRect(mirror).height, greaterThan(40));
      expect(
        tester.getRect(find.byKey(ValueKey('row-$aId'))).height,
        lessThan(2),
        reason: '被拖走的卡片应该把原来的位置让出来',
      );
      final bNow = tester.getRect(b);
      expect(tester.getRect(mirror).bottom, lessThanOrEqualTo(bNow.top + 1));

      await gesture.up();
      await tester.pumpAndSettle();

      expect(state.sort, 'manual', reason: '拖过之后应该切到手动顺序');
      final titles = state.visibleNotes.map((n) => n.title).toList();
      expect(titles.indexOf('A'), lessThan(titles.indexOf('B')));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      state.dispose();
    }
  });

  testWidgets('切视图时新旧两份列表交替，不会撞 GlobalKey', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-switch-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.createNote(title: 'A');
      await state.createNote(title: 'B');
      state.setView('all');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 1.0),
          home: Scaffold(
            body: SizedBox(width: 324, child: NoteListPanel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // AnimatedSwitcher 会在 250ms 里同时挂着旧列表和新列表。
    state.setView('today');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull);

    state.setView('all');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    state.dispose();
  });
}
