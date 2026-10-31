import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/command_palette.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget harness(AppState state) {
    return ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        theme: AppTheme.build(Brightness.light, 1, accent: 'vermilion'),
        home: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showCommandPalette(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('命令面板能搜到笔记；空搜索只露出最近六篇', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('thisnote_palette_');
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      for (final note in state.notes.toList()) {
        await state.purgeNote(note.id);
      }
      for (var i = 1; i <= 8; i++) {
        await state.createNote(title: '第 $i 篇');
        await state.closeEditor();
      }
    });

    await tester.pumpWidget(harness(state));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('打开：').evaluate().length, 6);

    await tester.enterText(find.byType(TextField), '第 8 篇');
    await tester.pump();
    expect(find.text('打开：第 8 篇'), findsOneWidget);

    // 普通命令仍然可用：搜「设置」并执行。
    await tester.enterText(find.byType(TextField), '设置');
    await tester.pump();
    // 输入框里也是「设置」，取最后一个（命令行）。
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    expect(state.view, 'settings');

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('打开笔记后，命令面板里才出现格式命令', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      final temp = Directory.systemTemp.createTempSync('thisnote_palette_');
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      for (final note in state.notes.toList()) {
        await state.purgeNote(note.id);
      }
      await state.createNote(title: '格式测试');
    });

    await tester.pumpWidget(harness(state));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 列表是懒加载的，直接搜命令名，确认它们在有会话时存在。
    for (final label in ['加粗', '查找', '整理排版']) {
      await tester.enterText(find.byType(TextField), label);
      await tester.pump();
      expect(
        find.text(label),
        findsNWidgets(2),
        reason: '$label 应该出现在命令面板里（输入框 + 命令）',
      );
    }

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
