import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/features/editor/image_embed.dart';

void main() {
  Document docWithImage() => Document.fromJson([
        {
          'insert': {'image': 'assets/a.png'},
        },
        {'insert': '\n'},
      ]);

  Embed firstEmbed(Document doc) {
    for (final node in doc.root.children) {
      if (node is! Line) continue;
      for (final leaf in node.children) {
        if (leaf is Embed) return leaf;
      }
    }
    throw StateError('文档里没有图片');
  }

  test('旧图片默认满宽、左对齐', () {
    final embed = firstEmbed(docWithImage());
    expect(imageWidthOf(embed), 1.0);
    expect(imageAlignOf(embed), 'left');
  });

  test('宽度和对齐写进 embed 属性，能读回来也不影响正文', () {
    // 图片前面先放一段文字，确认属性落在这张图上，而不是行首。
    final doc = Document.fromJson([
      {
        'insert': '前面\n',
      },
      {
        'insert': {'image': 'assets/a.png'},
      },
      {'insert': '\n'},
    ]);
    final controller = QuillController(
      document: doc,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final embed = firstEmbed(controller.document);
    expect(embed.documentOffset, 3);

    applyImageLayout(
      controller,
      embed.documentOffset,
      width: '0.50',
      align: 'center',
    );

    final updated = firstEmbed(controller.document);
    expect(imageWidthOf(updated), 0.5);
    expect(imageAlignOf(updated), 'center');

    final json = controller.document.toDelta().toJson();
    final imageOp = json.firstWhere((op) => op['insert'] is Map);
    final textOp = json.firstWhere(
      (op) => op['insert'] is String && op['insert'].toString().startsWith('前面'),
    );
    expect(textOp['attributes'], isNull, reason: '正文文字不该被写上图片属性');
    expect((imageOp['attributes'] as Map)['imageWidth'], '0.50');
    expect((imageOp['attributes'] as Map)['imageAlign'], 'center');
  });

  test('删除图片会把这个 embed 从正文里去掉', () {
    final controller = QuillController(
      document: docWithImage(),
      selection: const TextSelection.collapsed(offset: 0),
    );
    controller.replaceText(
      0,
      1,
      '',
      const TextSelection.collapsed(offset: 0),
    );
    final delta = controller.document.toDelta().toJson();
    expect(
      delta.any((op) => op['insert'] is Map),
      isFalse,
      reason: '删除后不应再留下图片 embed',
    );
  });
}
