import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/features/editor/note_image.dart';

void main() {
  testWidgets('note image card renders to a real PNG', (tester) async {
    final note = Note(
      id: 'test',
      title: '这一天，风很轻',
      delta: [
        {'insert': '下午读到一句话：把日子写下来，就是把它留住。'},
        {'insert': '\n'},
        {
          'insert': '落笔即心安',
          'attributes': {'font': 'WenKai', 'size': 'large', 'color': '#A84637'},
        },
        {'insert': '\n'},
      ],
      text: '下午读到一句话：把日子写下来，就是把它留住。\n落笔即心安\n',
      kind: NoteKind.diary,
      tags: const ['日常', '阅读'],
      mood: Mood.calm.score,
      weather: 'sunny',
      createdAt: DateTime(2026, 10, 30),
      updatedAt: DateTime(2026, 10, 30),
      words: 28,
      day: '2026-10-30',
    );

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: NoteImageCard(
                note: note,
                theme: NoteImageTheme.paper,
                width: 520,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final result = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final size = (image.width, image.height);
      image.dispose();
      return (data, size);
    });
    final data = result!.$1;
    expect(result.$2.$1, greaterThan(1000));
    expect(result.$2.$2, greaterThan(800));
    expect(data, isNotNull);
    expect(data!.lengthInBytes, greaterThan(10000));
    Directory('test_out').createSync(recursive: true);
    File('test_out/note_card.png').writeAsBytesSync(data.buffer.asUint8List());
  });

  testWidgets('每一段都能量到位置，分页靠这份坐标', (tester) async {
    final note = Note(
      id: 'paged',
      title: '一封很长的信',
      delta: [
        for (var i = 1; i <= 6; i++) ...[
          {'insert': '第 $i 段：写一点足够长的话，好让这一行走完一整行。'},
          {'insert': '\n'},
        ],
        {
          'insert': '结尾',
          'attributes': {'header': 2},
        },
        {'insert': '\n'},
      ],
      text: '长文',
      kind: NoteKind.essay,
      createdAt: DateTime(2026, 10, 31),
      updatedAt: DateTime(2026, 10, 31),
      words: 120,
      day: '2026-10-31',
    );

    final keys = NoteImageLineKeys();
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundaryKey,
              child: NoteImageCard(
                note: note,
                theme: NoteImageTheme.paper,
                width: 420,
                lineKeys: keys,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(keys.count, greaterThan(3));
    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderBox;
    double? previous;
    for (var i = 0; i < keys.count; i++) {
      final box = keys.at(i).currentContext!.findRenderObject() as RenderBox;
      final top = box.localToGlobal(Offset.zero, ancestor: boundary).dy;
      expect(top, greaterThanOrEqualTo(0));
      if (previous != null) {
        expect(top, greaterThan(previous));
      }
      previous = top;
    }
    // 第一段之后才有可用的断点，所以卡片高度一定大于最后一段的起点。
    expect(boundary.size.height, greaterThan(previous!));
  });

  testWidgets('PNG 卡片保留字体、删除线、列表与代码块', (tester) async {
    final note = Note(
      id: 'styles',
      title: '效果都在',
      delta: [
        {'insert': '普通'},
        {'insert': '加粗', 'attributes': {'bold': true}},
        {'insert': '删除', 'attributes': {'strike': true}},
        {'insert': '行内码', 'attributes': {'code': true}},
        {'insert': '楷体', 'attributes': {'font': 'WenKai'}},
        {'insert': '\n'},
        {'insert': '圆点'},
        {'insert': '\n', 'attributes': {'list': 'bullet'}},
        {'insert': '有序'},
        {'insert': '\n', 'attributes': {'list': 'ordered'}},
        {'insert': '待办'},
        {'insert': '\n', 'attributes': {'list': 'checked'}},
        {'insert': '引用'},
        {'insert': '\n', 'attributes': {'blockquote': true}},
        {'insert': '大标题'},
        {'insert': '\n', 'attributes': {'header': 1}},
        {
          'insert': {
            'code-block': jsonEncode({'code': 'void main() {}', 'lang': 'dart'}),
          },
        },
        {'insert': '\n'},
        {'insert': {'divider': true}},
        {'insert': '\n'},
        {'insert': {'image': 'assets/missing.png'}},
        {'insert': '\n'},
        {'insert': {'image': 'assets/real.png'}},
        {'insert': '\n'},
      ],
      text: '效果都在',
      kind: NoteKind.note,
      createdAt: DateTime(2026, 11, 6),
      updatedAt: DateTime(2026, 11, 6),
      words: 40,
      day: '2026-11-06',
    );

    final boundaryKey = GlobalKey();
    // 用引擎现场画一张 1×1 的 PNG，用来看图片是否真的画进卡片。
    final pixel = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = Colors.red,
      );
      final image = await recorder.endRecording().toImage(1, 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: boundaryKey,
              child: NoteImageCard(
                note: note,
                theme: NoteImageTheme.paper,
                width: 520,
                images: {'assets/real.png': pixel!},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final runs = <(String, TextStyle?)>[];
    void walk(InlineSpan span, TextStyle? inherited) {
      final style = span.style ?? inherited;
      if (span is! TextSpan) return;
      if (span.text != null) runs.add((span.text!, style));
      for (final child in span.children ?? const <InlineSpan>[]) {
        walk(child, style);
      }
    }

    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      walk(rich.text, rich.text.style);
    }
    String? styleOf(String text, bool Function(TextStyle) test) {
      for (final run in runs) {
        if (run.$1 == text && run.$2 != null && test(run.$2!)) return run.$1;
      }
      return null;
    }

    expect(
      styleOf('加粗', (s) => s.fontWeight == FontWeight.w700),
      isNotNull,
    );
    expect(
      styleOf(
        '删除',
        (s) => s.decoration?.contains(TextDecoration.lineThrough) ?? false,
      ),
      isNotNull,
    );
    expect(
      styleOf(
        '行内码',
        (s) =>
            s.fontFamily == 'SourceHanMono' && s.backgroundColor != null,
      ),
      isNotNull,
    );
    expect(styleOf('楷体', (s) => s.fontFamily == 'WenKai'), isNotNull);
    expect(styleOf('大标题', (s) => s.fontFamily == 'WenKai'), isNotNull);
    for (final prefix in ['•  ', '1.  ', '☑  ']) {
      expect(runs.any((run) => run.$1 == prefix), isTrue,
          reason: '列表前缀 $prefix 应该出现');
    }
    final allText = runs.map((run) => run.$1).join();
    expect(allText.contains('void main'), isTrue);
    expect(allText.contains('［图片］'), isTrue);
    expect(allText.contains('引用'), isTrue);
    expect(find.byType(Image), findsOneWidget);

    final boundary =
        boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data;
    });
    Directory('test_out').createSync(recursive: true);
    File('test_out/note_card_formatted.png')
        .writeAsBytesSync(data!.buffer.asUint8List());
  });

  testWidgets('进度页盖住时仍能截出整张长图', (tester) async {
    final note = Note(
      id: 'long',
      title: '一张很长的纸',
      delta: [
        for (var i = 1; i <= 12; i++) ...[
          {'insert': '第 $i 段：把这一页写得足够长，好让截图高度超过一屏。'},
          {'insert': '\n'},
        ],
      ],
      text: '长文',
      kind: NoteKind.essay,
      createdAt: DateTime(2026, 10, 31),
      updatedAt: DateTime(2026, 10, 31),
      words: 240,
      day: '2026-10-31',
    );
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: 520,
              child: RepaintBoundary(
                key: key,
                child: NoteImageCard(
                  note: note,
                  theme: NoteImageTheme.paper,
                  width: 520,
                ),
              ),
            ),
            const Positioned.fill(
              child: ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(boundary.size.height, greaterThan(screen.height));

    final image = await tester.runAsync(
      () => boundary.toImage(pixelRatio: 1),
    );
    expect(image, isNotNull);
    expect(image!.height.toDouble(), closeTo(boundary.size.height, 1));
    image.dispose();
  });
}
