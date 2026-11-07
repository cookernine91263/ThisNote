import 'dart:io';
import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/mobile_nav.dart';
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

  test('booting from trash returns to the last list view', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-last-view-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    final first = AppState(store: NoteStore(rootOverride: temp.path));
    await first.init();
    await first.updateSettings((s) {
      s.lastView = 'trash';
      s.lastListView = 'all';
    });
    first.dispose();

    final second = AppState(store: NoteStore(rootOverride: temp.path));
    await second.init();
    expect(second.view, 'all');
    second.dispose();
  });

  testWidgets('liquid nav switches tabs at 360dp without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    final temp = Directory.systemTemp.createTempSync('thisnote-mobile-nav-');
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

    final nav = find.byType(LiquidNavBar);
    expect(nav, findsOneWidget);

    Future<void> tapTab(String label) async {
      await tester.tap(find.descendant(of: nav, matching: find.text(label)));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: 'tap $label');
    }

    expect(state.view, 'today');
    await tapTab('日历');
    expect(state.view, 'calendar');
    await tapTab('统计');
    expect(state.view, 'stats');
    await tapTab('我的');
    expect(state.view, 'settings');

    // 切到别处再回「笔记」，应回到上次的列表视图。
    await tapTab('笔记');
    expect(state.view, 'today');

    // 手机列表里的 scope chip 可以直接进「全部」。
    await tester.tap(find.text('全部').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.view, 'all');
    expect(tester.takeException(), isNull);

    await tapTab('统计');
    expect(state.view, 'stats');
    await tapTab('笔记');
    expect(state.view, 'all');

    // 回收站也是可以到达的（scope chip）。
    await tester.tap(find.text('回收站').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.view, 'trash');
    expect(tester.takeException(), isNull);

    // 连续快速点击：动画从当前形状接续，最终只认最后一次选择。
    await tester.tap(find.descendant(of: nav, matching: find.text('日历')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.descendant(of: nav, matching: find.text('我的')));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.descendant(of: nav, matching: find.text('统计')));
    await tester.pump(const Duration(milliseconds: 600));
    expect(state.view, 'stats');
    expect(tester.takeException(), isNull);

    final statSemantics = tester.getSemantics(
      find.descendant(
        of: nav,
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == '统计',
        ),
      ),
    );
    expect(statSemantics.flagsCollection.isSelected, Tristate.isTrue);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    state.dispose();
  });
}
