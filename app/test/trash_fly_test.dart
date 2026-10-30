import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/trash_fly.dart';

void main() {
  testWidgets('trash flight shows the note card while it travels', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  TrashFly.fly(
                    context: context,
                    from: const Rect.fromLTWH(120, 120, 220, 64),
                    title: '飞走的纸',
                    after: () async {},
                  );
                },
                child: const Text('删除'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('飞走的纸'), findsOneWidget);

    await tester.pumpAndSettle();
  });
}
