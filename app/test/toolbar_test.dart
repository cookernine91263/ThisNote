import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/editor_toolbar.dart';
import 'package:this_note/src/state/app_state.dart';

/// 工具栏里只有图标的几个下拉，鼠标停上去必须有文字说明。
void main() {
  testWidgets('对齐、列表等图标按钮都有悬停提示', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-toolbar-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await tester.runAsync(() => state.init());
    await tester.runAsync(() => state.openNote('seed-welcome', autofocus: false));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 1.0),
          home: Scaffold(
            body: EditorToolbar(
              controller: state.session!.controller,
              session: state.session!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final menus = tester
        .widgetList<PopupMenuButton<int>>(find.byType(PopupMenuButton<int>))
        .toList();
    final tooltips = menus.map((e) => e.tooltip).toList();
    expect(tooltips, contains('段落样式'));
    expect(tooltips, contains('对齐方式'));
    expect(tooltips, contains('列表'));
    // 不能有空的 tooltip：那就等于没有提示。
    expect(tooltips.every((e) => (e ?? '').isNotEmpty), isTrue);

    state.dispose();
  });
}
