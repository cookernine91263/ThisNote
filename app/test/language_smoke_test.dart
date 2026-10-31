import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

/// 英文文案普遍比中文长，这里在收窄的桌面宽度下把所有主视图过一遍，
/// 让布局溢出以测试异常的形式暴露出来。
void main() {
  testWidgets('English UI renders every main view without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-en-smoke-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.setLanguage('en');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const ThisNoteApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    for (final view in const [
      'today',
      'all',
      'tags',
      'calendar',
      'stats',
      'settings',
    ]) {
      await tester.runAsync(() async => state.setView(view));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: 'view: $view');
    }

    await tester.runAsync(() async {
      await state.openNote('seed-welcome', autofocus: false);
    });
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);

    state.dispose();
  });
}
