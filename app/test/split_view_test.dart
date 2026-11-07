import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/data/repository.dart';
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

  test('分屏第二会话可以独立编辑和保存', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-split-');
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(() {
      state.dispose();
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }

    final a = await state.createNote(title: '左');
    final b = await state.createNote(title: '右');
    await state.switchTab(a.id);
    await state.openSecondaryNote(b.id);
    expect(state.current?.id, a.id);
    expect(state.secondarySession?.note.id, b.id);

    state.secondarySession!.controller.replaceText(
      0,
      0,
      '右栏写下的字\n',
      const TextSelection.collapsed(offset: 0),
    );
    await state.secondarySession!.flush();

    final saved = await state.store.loadNote(b.id);
    expect(saved?.text, contains('右栏写下的字'));

    await state.openSecondaryNote(a.id);
    expect(state.secondarySession?.note.id, b.id, reason: '不能把左栏重复打开');
    await state.closeSecondary();
    expect(state.secondarySession, isNull);
    expect(state.secondaryNote, isNull);
  });

  testWidgets('窄窗口分屏不出现布局溢出', (tester) async {
    tester.view.physicalSize = const Size(1386, 893);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-split-layout-');
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
      final a = await state.createNote(title: '左');
      final b = await state.createNote(title: '右');
      await state.switchTab(a.id);
      await state.openSecondaryNote(b.id);
      state.setView('all');
    });
    addTearDown(state.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: state, child: const ThisNoteApp()),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);

    // 更窄的分屏也要收得下标题栏。
    tester.view.physicalSize = const Size(1024, 768);
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}