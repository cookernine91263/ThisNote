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
          'attributes': {
            'font': 'WenKai',
            'size': 'large',
            'color': '#A84637',
          },
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

    final boundary = key.currentContext!.findRenderObject()
        as RenderRepaintBoundary;
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
}
