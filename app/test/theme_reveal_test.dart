import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/theme_reveal.dart';

/// 最小复刻 app.dart 的接线，用来盯住揭示的顺序：
/// 旧截图必须先盖住整屏，主题才允许切换。
void main() {
  testWidgets('reveal covers the old theme before applying the new one',
      (tester) async {
    final mode = ValueNotifier<ThemeMode>(ThemeMode.dark);

    Future<void> apply() async {
      mode.value =
          mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    }

    await tester.pumpWidget(
      ValueListenableBuilder<bool>(
        valueListenable: ThemeReveal.revealing,
        builder: (context, revealing, _) => ValueListenableBuilder<ThemeMode>(
          valueListenable: mode,
          builder: (context, current, _) => RepaintBoundary(
            key: ThemeReveal.rootKey,
            child: MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: current,
              themeAnimationDuration:
                  revealing ? Duration.zero : kThemeAnimationDuration,
              builder: (context, child) => Stack(
                fit: StackFit.expand,
                children: [child!, ThemeReveal.overlay()],
              ),
              home: Scaffold(
                body: Center(
                  child: GestureDetector(
                    key: const ValueKey('switch'),
                    onTapUp: (details) => ThemeReveal.reveal(
                      context: context,
                      globalOrigin: details.globalPosition,
                      apply: apply,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: const SizedBox(width: 120, height: 120),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    ThemeMode appMode() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;
    expect(appMode(), ThemeMode.dark);

    await tester.tap(find.byKey(const ValueKey('switch')));
    for (var i = 0; i < 30 && findByType().evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 旧截图已经在铺满整屏了，此时主题必须还没有换。
    expect(findByType().evaluate(), isNotEmpty);
    expect(appMode(), ThemeMode.dark);

    await tester.pump(const Duration(milliseconds: 16));
    expect(appMode(), ThemeMode.light);
    // 换完主题后旧截图还在，圆孔才开始扩散。
    expect(findByType().evaluate(), isNotEmpty);

    for (var i = 0; i < 80 && findByType().evaluate().isNotEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 32));
    }
    expect(findByType().evaluate(), isEmpty);
    expect(appMode(), ThemeMode.light);
    expect(ThemeReveal.revealing.value, isFalse);
  });
}

Finder findByType() => find.byType(RawImage);
