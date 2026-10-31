import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/app.dart';
import 'package:this_note/src/core/i18n.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/onboarding.dart';
import 'package:this_note/src/state/app_state.dart';

const _en = <String, String>{
  '共 {n} 篇': '{n} notes',
  '保存': 'Save',
};

void main() {
  setUp(() => I18n.lang = AppLang.zh);
  tearDown(() => I18n.lang = AppLang.zh);

  test('translates with placeholders and falls back to Chinese', () {
    expect(tr('保存', null, _en), '保存');
    I18n.lang = AppLang.en;
    expect(tr('保存', null, _en), 'Save');
    expect(tr('共 {n} 篇', {'n': 3}, _en), '3 notes');
    // 没有英文条目时保留中文，不会出现空字符串。
    expect(tr('未收录的词'), '未收录的词');
  });

  test('language is persisted in settings', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-i18n-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    expect(state.settings.language, 'zh');
    expect(I18n.lang, AppLang.zh);

    await state.setLanguage('en');
    expect(state.settings.language, 'en');
    expect(I18n.lang, AppLang.en);

    final reopened = AppState(store: NoteStore(rootOverride: temp.path));
    await reopened.init();
    expect(reopened.settings.language, 'en');
    expect(I18n.lang, AppLang.en);
    reopened.dispose();
    state.dispose();
  });

  test('unknown languages fall back to Chinese', () {
    expect(AppLang.fromCode('fr'), AppLang.zh);
    expect(AppLang.fromCode(null), AppLang.zh);
    expect(AppLang.fromCode('en'), AppLang.en);
    expect(AppLang.en.locale.languageCode, 'en');
  });

  testWidgets('language toggle reports the picked language', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LanguageToggle(
            value: 'zh',
            onChanged: (code) => picked = code,
          ),
        ),
      ),
    );
    await tester.tap(find.text('English'));
    expect(picked, 'en');
  });

  testWidgets('onboarding renders in the saved English locale', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-onboard-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {
        // Windows 上文件句柄偶尔还没释放，清理失败不该让测试失败。
      }
    });
    late AppState state;
    // testWidgets 用假时钟，真实文件读写必须放进 runAsync。
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.setLanguage('en');
      await state.updateSettings((s) => s.onboardingDone = false);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: const ThisNoteApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Write your days down'), findsOneWidget);
    expect(find.text('把日子写下来'), findsNothing);
    expect(find.text('English'), findsOneWidget);
    expect(state.settings.language, 'en');

    state.dispose();
  });
}
