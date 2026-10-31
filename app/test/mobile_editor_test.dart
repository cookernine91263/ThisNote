import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/editor_page.dart';
import 'package:this_note/src/state/app_state.dart';

/// 手机窄屏上的编辑器：不能再出现 release 里的灰色错误块。
/// 曾经 mobile 分支 decoration 为 null 却仍要求 clip，安卓上直接断言失败。
void main() {
  testWidgets('mobile editor renders at 360dp without a gray error box',
      (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-mobile-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.openNote('seed-welcome', autofocus: false);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 1.0),
          home: EditorPage(mobile: true, onBack: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'editor build');

    await tester.runAsync(() => state.trashNote('seed-welcome'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'after trash');

    state.dispose();
  });
}
