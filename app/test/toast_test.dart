import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/core/ui.dart';

/// 提示条曾经是 SnackBar：横贯整个窗口、颜色反着主题、还会排队。
/// 现在只留一条，新的直接顶掉旧的，并且到点自己收起。
void main() {
  testWidgets('提示条只留一条，并会自己收起', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.dark, 1.0),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () =>
                      showToast(context, '第一条提示', icon: Icons.check),
                  child: const Text('one'),
                ),
                TextButton(
                  onPressed: () => showToast(context, '第二条提示'),
                  child: const Text('two'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('one'));
    await tester.pump();
    expect(find.text('第一条提示'), findsOneWidget);

    await tester.tap(find.text('two'));
    await tester.pump();
    expect(find.text('第二条提示'), findsOneWidget);
    expect(find.text('第一条提示'), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第二条提示'), findsNothing);
  });
}
