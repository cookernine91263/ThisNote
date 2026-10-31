import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/folder_tree.dart';
import 'package:this_note/src/state/app_state.dart';

/// 文件夹行的两个入口：行尾的「更多」按钮，和贴着这一行展开的菜单。
/// 以前行尾是一枚拖拽手柄图标，菜单位置又写死在窗口右缘，
/// 这两个用例把这两件事钉住。
void main() {
  Future<AppState> boot(WidgetTester tester) async {
    final temp = Directory.systemTemp.createTempSync('thisnote-folders-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
    });
    return state;
  }

  Future<void> pumpTree(WidgetTester tester, AppState state) async {
    tester.view.physicalSize = const Size(1386, 893);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark, 1.0),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: 324, child: FolderTree(state: state)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('文件夹行用「更多」按钮，而不是拖拽手柄', (tester) async {
    final state = await boot(tester);
    await tester.runAsync(() => state.createFolder('1'));
    await tester.runAsync(() async => state.setView('all'));
    await pumpTree(tester, state);

    expect(find.text('1'), findsWidgets);
    expect(find.byIcon(LucideIcons.gripVertical), findsNothing);
    expect(find.byTooltip('文件夹选项'), findsOneWidget);
    expect(find.byIcon(LucideIcons.ellipsis), findsOneWidget);

    state.dispose();
  });

  testWidgets('菜单贴着文件夹行展开，不会被钉在窗口右缘', (tester) async {
    final state = await boot(tester);
    await tester.runAsync(() => state.createFolder('1'));
    await tester.runAsync(() async => state.setView('all'));
    await pumpTree(tester, state);

    final id = state.rootFolders().first.id;
    final row = find.byKey(ValueKey('folder-$id'));
    final rowRect = tester.getRect(row);

    await tester.tap(find.byTooltip('文件夹选项'));
    await tester.pumpAndSettle();

    expect(find.text('新建子文件夹'), findsOneWidget);
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除文件夹'), findsOneWidget);

    final renameRect = tester.getRect(find.text('重命名'));
    // 菜单在行的下方。
    expect(renameRect.top, greaterThan(rowRect.bottom));
    // 而且横向留在列表栏里：右边缘不超过文件夹行，不会跑到窗口最右边。
    expect(renameRect.right, lessThanOrEqualTo(rowRect.right));
    expect(renameRect.right, greaterThan(rowRect.right - 200));
    expect(renameRect.left, greaterThan(rowRect.left));

    // 点空白处收起菜单，避免影响 tester 收尾。
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsNothing);

    state.dispose();
  });

  testWidgets('鼠标拖住文件夹拖到另一行中间，就成为它的子文件夹', (tester) async {
    final state = await boot(tester);
    late String aId;
    late String bId;
    await tester.runAsync(() async {
      aId = (await state.createFolder('A')).id;
      bId = (await state.createFolder('B')).id;
    });

    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await pumpTree(tester, state);

      final aRect = tester.getRect(find.byKey(ValueKey('folder-$aId')));
      final bRect = tester.getRect(find.byKey(ValueKey('folder-$bId')));

      // 按下就拖，不需要长按等待。
      final gesture = await tester.startGesture(
        aRect.center,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveTo(bRect.center);
      await tester.pump(const Duration(milliseconds: 120));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(state.folderById(aId)!.parentId, bId);
      expect(state.childFolders(bId).map((f) => f.id), contains(aId));
    } finally {
      debugDefaultTargetPlatformOverride = null;
      state.dispose();
    }
  });
}
