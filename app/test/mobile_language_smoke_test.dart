import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

/// 手机窄屏 + 英文 + 1.3 倍字号：所有主视图都不能溢出。
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

  testWidgets('English mobile UI renders every view at 1.3x text',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(
      tester.platformDispatcher.clearTextScaleFactorTestValue,
    );

    final temp = Directory.systemTemp.createTempSync('thisnote-en-mobile-');
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
      await state.setLanguage('en');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const ThisNoteApp()),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull, reason: 'boot');

    for (final view in const [
      'today',
      'all',
      'tags',
      'trash',
      'search',
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
    expect(tester.takeException(), isNull, reason: 'editor');

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    state.dispose();
  });
}
