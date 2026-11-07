import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/features/editor/table_embed.dart';

void main() {
  testWidgets('表格编辑器：空白表格也显示格子，可增删行列并保存', (tester) async {
    TableData? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light, 1.0),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showTableEditor(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 空白表格默认 3×3，每个格子都是一个输入框。
    expect(find.byType(TextField), findsNWidgets(9));
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).first, '表头内容');
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('table-add-row')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(12));
    // 增行不会丢掉已经输入的内容。
    expect(find.text('表头内容'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('table-add-column')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(16));

    await tester.tap(find.byKey(const ValueKey('table-remove-row')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(12));

    await tester.tap(find.byKey(const ValueKey('table-remove-column')));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(9));

    // 表头开关仍然可用。
    await tester.tap(find.byKey(const ValueKey('table-header-toggle')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.rows.length, 3);
    expect(result!.rows.first.length, 3);
    expect(result!.rows.first.first, '表头内容');
    expect(result!.header, isFalse);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('已有表格补齐成矩形，窄窗口里也不溢出', (tester) async {
    tester.view.physicalSize = const Size(420, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(Brightness.light, 1.0),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showTableEditor(
                context,
                initial: TableData(
                  rows: [
                    ['名称'],
                    ['苹果', '3', '斤'],
                  ],
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 两行按最长的一行补成 3 列。
    expect(find.byType(TextField), findsNWidgets(6));
    expect(find.text('名称'), findsOneWidget);
    expect(find.text('斤'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
