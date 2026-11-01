import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/ai_chat/ai_chat_panel.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  testWidgets('AI chat panel renders on a phone width', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-ai-panel-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.updateSettings((s) {
        s.aiSettings.enabled = true;
        s.aiSettings.baseUrl = 'http://127.0.0.1:1/v1';
        s.aiSettings.apiKey = 'test-key';
        s.aiSettings.model = 'test-model';
      });
      await state.openNote('seed-welcome', autofocus: false);
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light, 1),
        home: Scaffold(
          body: AiChatPanel(
            session: state.session!,
            docked: true,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('有什么想一起写的？'), findsOneWidget);

    state.dispose();
  });
}
