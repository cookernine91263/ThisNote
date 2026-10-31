import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/editor_page.dart';
import 'package:this_note/src/features/editor/find_bar.dart';
import 'package:this_note/src/features/editor/outline_panel.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness(AppState state) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.build(Brightness.light, 1.0, accent: 'vermilion'),
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: const Scaffold(
          body: SizedBox(width: 1000, height: 700, child: EditorPage()),
        ),
      ),
    );
  }

  testWidgets('查找条能显示命中数、按下一处前进', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late AppState state;
    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('thisnote_panel_');
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      for (final note in state.notes.toList()) {
        await state.purgeNote(note.id);
      }
      await state.createNote(title: '查找测试');
      state.session!.controller.replaceText(
        0,
        0,
        '春天来了。春天很好。\n',
        const TextSelection.collapsed(offset: 0),
      );
      await state.session!.flush();
    });

    await tester.pumpWidget(harness(state));
    await tester.pump();

    state.session!.openFind();
    await tester.pump();
    expect(find.byType(FindBar), findsOneWidget);

    final field = find
        .descendant(of: find.byType(FindBar), matching: find.byType(TextField))
        .first;
    // 打开查找后，键盘输入应该直接进查找框，而不是落在标题里。
    expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);

    await tester.enterText(field, '春天');
    await tester.pump();
    expect(find.text('2 处'), findsOneWidget);

    await tester.tap(find.byTooltip('下一处 · Enter'));
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);

    await tester.tap(find.byTooltip('下一处 · Enter'));
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('大纲列出标题，点一下跳到位置', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late AppState state;
    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('thisnote_panel_');
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      for (final note in state.notes.toList()) {
        await state.purgeNote(note.id);
      }
      await state.createNote(title: '大纲测试');
      final session = state.session!;
      session.controller.replaceText(
        0,
        0,
        '第一章\n正文内容\n第二章\n春天来了。\n',
        const TextSelection.collapsed(offset: 0),
      );
      session.controller.updateSelection(
        const TextSelection(baseOffset: 0, extentOffset: 3),
        ChangeSource.local,
      );
      session.controller.formatSelection(
        Attribute('header', AttributeScope.block, 1),
      );
      session.controller.updateSelection(
        const TextSelection(baseOffset: 9, extentOffset: 12),
        ChangeSource.local,
      );
      session.controller.formatSelection(
        Attribute('header', AttributeScope.block, 2),
      );
      await session.flush();
    });

    await tester.pumpWidget(harness(state));
    await tester.pump();

    state.session!.toggleOutline();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.byType(OutlinePanel), findsOneWidget);
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第二章'), findsOneWidget);

    // 先把光标移开，确保后面的跳转不是「本来就停在那里」。
    state.session!.jumpTo(0);
    await tester.pump();
    expect(state.session!.controller.selection.start, 0);

    await tester.tap(find.text('第二章'));
    await tester.pump();
    expect(state.session!.controller.selection.start, 9);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('替换条可以一次替换全部命中', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late AppState state;
    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('thisnote_panel_');
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      for (final note in state.notes.toList()) {
        await state.purgeNote(note.id);
      }
      await state.createNote(title: '替换测试');
      state.session!.controller.replaceText(
        0,
        0,
        '春天来了。春天很好。\n',
        const TextSelection.collapsed(offset: 0),
      );
      await state.session!.flush();
    });

    await tester.pumpWidget(harness(state));
    await tester.pump();

    state.session!.openFind(withReplace: true);
    await tester.pump();
    expect(find.text('替换为…'), findsOneWidget);

    final fields = find.descendant(
      of: find.byType(FindBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), '春天');
    await tester.enterText(fields.at(1), '夏日');
    await tester.pump();

    await tester.tap(find.text('全部'));
    await tester.pump();

    expect(state.session!.plainText.contains('夏日来了。夏日很好。'), isTrue);
    expect(state.session!.plainText.contains('春天'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('标签对话框能从用过的标签里补全并保存', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late AppState state;
    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('thisnote_panel_');
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      for (final note in state.notes.toList()) {
        await state.purgeNote(note.id);
      }
      // 先造一条带「读书」标签的旧笔记，作为补全来源。
      await state.createNote(title: '旧笔记');
      await state.session!.setTags(['读书']);
      await state.closeEditor();
      await state.createNote(title: '新笔记');
    });

    await tester.pumpWidget(harness(state));
    await tester.pump();

    await tester.tap(find.text('标签'));
    await tester.pump();
    expect(find.text('用过的标签'), findsOneWidget);

    await tester.tap(find.text('# 读书'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();

    expect(state.session!.note.tags, contains('读书'));
    // 头部标签也应立刻刷新，而不是等下一次正文保存。
    expect(find.text('# 读书'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
