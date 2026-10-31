import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/editor_page.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppState> freshState() async {
    final temp = Directory.systemTemp.createTempSync('thisnote_focus_');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }
    return state;
  }

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

  testWidgets('新建空白笔记后，光标直接落在标题里', (tester) async {
    late AppState state;
    // 真实文件读写要在 runAsync 里做，testWidgets 的假时钟不会推进它们。
    await tester.runAsync(() async {
      state = await freshState();
      await state.createNote();
    });
    await tester.pumpWidget(harness(state));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final session = state.session;
    expect(session, isNotNull);
    expect(
      session!.titleFocus.hasFocus,
      isTrue,
      reason: '标题为空时，新建后应该可以直接打字，不用先点纸面',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });

  testWidgets('打开已有标题的笔记后，光标落在正文', (tester) async {
    late AppState state;
    await tester.runAsync(() async {
      state = await freshState();
      final note = await state.createNote(title: '已经有标题了');
      // 让正文也不为空，避免空文档的边界情况掩盖焦点问题。
      state.session!.controller.document.insert(0, '正文第一句\n');
      await state.session!.flush();
      await state.openNote(note.id);
    });
    await tester.pumpWidget(harness(state));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(state.session!.editorFocus.hasFocus, isTrue);
    expect(state.session!.titleFocus.hasFocus, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    state.dispose();
  });
}
