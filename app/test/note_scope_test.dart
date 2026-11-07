import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/note_list.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, (call) async {
      if (call.method == 'isMaximized') return false;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowChannel, null);
  });

  testWidgets('今日 / 全部 / 标签 共用一个笔记页并记住上次范围', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-scope-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.updateSettings((s) => s.onboardingDone = true);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const ThisNoteApp()),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 侧栏只剩一个「笔记」入口，不再各自占一格。
    expect(find.byTooltip('笔记'), findsOneWidget);
    expect(find.byTooltip('今日'), findsNothing);
    expect(find.byTooltip('全部'), findsNothing);
    expect(find.byTooltip('标签'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(NoteListPanel),
        matching: find.text('全部'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.view, 'all');
    expect(state.settings.lastListView, 'all');

    // 去设置再回来：仍停在「全部」，而不是跳回今日。
    await tester.tap(find.byTooltip('设置'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.view, 'settings');

    await tester.tap(find.byTooltip('笔记'));
    await tester.pump(const Duration(milliseconds: 350));
    expect(state.view, 'all');
    expect(tester.takeException(), isNull);

    state.dispose();
  });

  testWidgets('全部笔记侧栏可以收起和展开', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-collapse-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.updateSettings((s) => s.onboardingDone = true);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const ThisNoteApp()),
    );
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byTooltip('收起笔记列表'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开笔记列表').hitTestable(), findsOneWidget);

    await tester.tap(find.byTooltip('展开笔记列表').hitTestable());
    await tester.pumpAndSettle();
    expect(find.byTooltip('展开笔记列表').hitTestable(), findsNothing);
    expect(tester.takeException(), isNull);

    state.dispose();
  });
}
