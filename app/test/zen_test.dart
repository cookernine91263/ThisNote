import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/shell.dart';
import 'package:this_note/src/state/app_state.dart';

/// 回归：设置页里点「专注」曾把侧栏藏起来，却仍停在设置页，退不出去。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  setUp(() {
    // 标题栏在测试环境里没有原生实现；退出专注后它会重新出现。
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

  testWidgets('focus mode from settings returns to the note and can be exited',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-zen-');
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
      await state.updateSettings((s) => s.onboardingDone = true);
      state.setView('settings');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const ThisNoteApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(state.view, 'settings');

    // 设置页点专注：应回到笔记并进入专注，而不是停在设置页。
    await tester.tap(find.byKey(const Key('rail-focus')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.view, 'all');
    expect(find.byTooltip('退出专注模式'), findsOneWidget);

    // 专注页面上的退出按钮必须能把侧栏带回来。
    await tester.tap(find.byIcon(LucideIcons.minimize2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('退出专注模式'), findsNothing);
    // 标题栏只在 Windows 上渲染；Linux CI 里专注退出仍然有效。
    if (Platform.isWindows) {
      expect(find.byType(WindowTitleBar), findsOneWidget);
    }

    await tester.tap(find.byKey(const Key('rail-settings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.view, 'settings');

    // 等 settings.json 的异步写入结束，避免临时目录清理时撞上写句柄。
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    state.dispose();
  });

  testWidgets('Escape and Ctrl+, both leave focus mode', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-zen-keys-');
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
      await state.updateSettings((s) => s.onboardingDone = true);
      state.setView('all');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const ThisNoteApp(),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byKey(const Key('rail-focus')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('退出专注模式'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('退出专注模式'), findsNothing);

    await tester.tap(find.byKey(const Key('rail-focus')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('退出专注模式'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.comma);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.view, 'settings');
    expect(find.byTooltip('退出专注模式'), findsNothing);

    // 等 settings.json 的异步写入结束，避免临时目录清理时撞上写句柄。
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    state.dispose();
  });
}





