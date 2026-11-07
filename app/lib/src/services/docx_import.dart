import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../features/editor/table_embed.dart';

/// DOCX 导入结果。delta 可以直接写进 Note。
class DocxImportResult {
  const DocxImportResult({
    required this.title,
    required this.delta,
    required this.text,
  });

  final String title;
  final List<dynamic> delta;
  final String text;
}

/// 读取 Word 文档的正文段落、标题、粗斜体、链接、表格和图片。
///
/// 复杂域、脚注、批注和浮动排版不做承诺；它们会被忽略或退化为普通文字。
Future<DocxImportResult?> parseDocx(
  Uint8List bytes, {
  required Future<String?> Function(Uint8List bytes, String extension)
      saveImage,
}) async {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    return null;
  }

  ArchiveFile? find(String name) {
    for (final file in archive.files) {
      if (file.name == name) return file;
    }
    return null;
  }

  final documentFile = find('word/document.xml');
  if (documentFile == null) return null;

  final rels = <String, String>{};
  final relFile = find('word/_rels/document.xml.rels');
  if (relFile != null) {
    try {
      final relDoc = XmlDocument.parse(
        utf8.decode(relFile.content as List<int>, allowMalformed: true),
      );
      for (final node in relDoc.descendants.whereType<XmlElement>()) {
        if (node.localName != 'Relationship') continue;
        final id = _attr(node, 'Id');
        final target = _attr(node, 'Target');
        if (id != null && target != null) rels[id] = target;
      }
    } catch (_) {
      // 关系缺失时仍能导入文字。
    }
  }

  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(
      utf8.decode(documentFile.content as List<int>, allowMalformed: true),
    );
  } catch (_) {
    return null;
  }

  final body = _first(doc.descendants
      .whereType<XmlElement>()
      .where((element) => element.localName == 'body'));
  if (body == null) return null;

  final delta = <dynamic>[];
  final text = StringBuffer();
  for (final child in body.childElements) {
    if (child.localName == 'p') {
      await _paragraph(
        child,
        delta: delta,
        text: text,
        rels: rels,
        archive: archive,
        saveImage: saveImage,
      );
    } else if (child.localName == 'tbl') {
      _table(child, delta: delta, text: text);
    }
  }
  if (delta.isEmpty) delta.add({'insert': '\n'});

  var title = '';
  final core = find('docProps/core.xml');
  if (core != null) {
    try {
      final coreDoc = XmlDocument.parse(
        utf8.decode(core.content as List<int>, allowMalformed: true),
      );
      title = _first(coreDoc.descendants
                  .whereType<XmlElement>()
                  .where((element) => element.localName == 'title')
                  .map((element) => element.innerText.trim())) ??
              '';
    } catch (_) {}
  }
  if (title.isEmpty) {
    title = text
        .toString()
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  }
  if (title.length > 80) title = title.substring(0, 80);

  return DocxImportResult(
    title: title,
    delta: delta,
    text: text.toString().trimRight(),
  );
}

Future<void> _paragraph(
  XmlElement paragraph, {
  required List<dynamic> delta,
  required StringBuffer text,
  required Map<String, String> rels,
  required Archive archive,
  required Future<String?> Function(Uint8List bytes, String extension)
      saveImage,
}) async {
  final pPr = _child(paragraph, 'pPr');
  final attrs = <String, dynamic>{};
  final style = _val(pPr, 'pStyle')?.toLowerCase() ?? '';
  final heading = RegExp(r'heading\s*([1-6])').firstMatch(style);
  if (heading != null) {
    attrs['header'] = int.parse(heading.group(1)!) - 1;
  } else if (style.contains('title')) {
    attrs['header'] = 0;
  } else if (style.contains('quote')) {
    attrs['blockquote'] = true;
  }
  if (pPr != null && _child(pPr, 'numPr') != null) {
    attrs['list'] = 'bullet';
  }
  final align = _val(pPr, 'jc');
  if (align == 'center' || align == 'right') {
    attrs['align'] = align;
  } else if (align == 'both') {
    attrs['align'] = 'justify';
  }

  final runs = <dynamic>[];
  await _collectRuns(
    paragraph,
    runs,
    rels: rels,
    archive: archive,
    saveImage: saveImage,
    link: null,
  );
  if (runs.isEmpty) {
    delta.add({'insert': '\n', if (attrs.isNotEmpty) 'attributes': attrs});
  } else {
    delta.addAll(runs);
    delta.add({'insert': '\n', if (attrs.isNotEmpty) 'attributes': attrs});
  }
  for (final run in runs) {
    if (run is Map && run['insert'] is String) text.write(run['insert']);
  }
  text.write('\n');
}

Future<void> _collectRuns(
  XmlElement parent,
  List<dynamic> out, {
  required Map<String, String> rels,
  required Archive archive,
  required Future<String?> Function(Uint8List bytes, String extension)
      saveImage,
  required String? link,
}) async {
  for (final child in parent.childElements) {
    final name = child.localName;
    if (name == 'hyperlink') {
      final id = _attr(child, 'id');
      await _collectRuns(
        child,
        out,
        rels: rels,
        archive: archive,
        saveImage: saveImage,
        link: id == null ? link : rels[id],
      );
      continue;
    }
    if (name != 'r') {
      if (name == 'ins' || name == 'smartTag' || name == 'sdtContent') {
        await _collectRuns(
          child,
          out,
          rels: rels,
          archive: archive,
          saveImage: saveImage,
          link: link,
        );
      }
      continue;
    }

    final rPr = _child(child, 'rPr');
    final runAttrs = <String, dynamic>{};
    if (_on(rPr, 'b')) runAttrs['bold'] = true;
    if (_on(rPr, 'i')) runAttrs['italic'] = true;
    if (_on(rPr, 'u')) runAttrs['underline'] = true;
    if (_on(rPr, 'strike') || _on(rPr, 'dstrike')) runAttrs['strike'] = true;
    final color = _val(rPr, 'color');
    if (color != null && color.length == 6) {
      runAttrs['color'] = '#$color';
    }
    if (link != null && link.startsWith('http')) runAttrs['link'] = link;

    final buffer = StringBuffer();
    for (final part in child.childElements) {
      switch (part.localName) {
        case 't':
          buffer.write(part.innerText);
          break;
        case 'tab':
          buffer.write('\t');
          break;
        case 'br':
          buffer.write('\n');
          break;
        case 'drawing':
        case 'pict':
          final blip = _first(part.descendants
              .whereType<XmlElement>()
              .where((element) => element.localName == 'blip'));
          final embedId = blip == null ? null : _attr(blip, 'embed');
          final target = embedId == null ? null : rels[embedId];
          if (target == null) continue;
          final imageFile = _archiveImage(archive, target);
          if (imageFile == null) continue;
          final dot = target.lastIndexOf('.');
          final ext = dot < 0 ? 'png' : target.substring(dot + 1);
          final saved = await saveImage(
            Uint8List.fromList(imageFile.content as List<int>),
            ext,
          );
          if (saved != null) out.add({'insert': {'image': saved}});
          break;
      }
    }
    if (buffer.isEmpty) continue;
    out.add({
      'insert': buffer.toString(),
      if (runAttrs.isNotEmpty) 'attributes': runAttrs,
    });
  }
}

void _table(XmlElement table, {
  required List<dynamic> delta,
  required StringBuffer text,
}) {
  final rows = <List<String>>[];
  for (final tr in table.childElements.where((e) => e.localName == 'tr')) {
    final cells = <String>[];
    for (final tc in tr.childElements.where((e) => e.localName == 'tc')) {
      final buffer = StringBuffer();
      for (final p in tc.descendants
          .whereType<XmlElement>()
          .where((e) => e.localName == 'p')) {
        for (final t in p.descendants
            .whereType<XmlElement>()
            .where((e) => e.localName == 't')) {
          buffer.write(t.innerText);
        }
        buffer.write(' ');
      }
      cells.add(buffer.toString().trim());
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  if (rows.isEmpty) return;
  final data = TableData(rows: rows, header: true);
  delta.add({
    'insert': {tableKey: jsonEncode(data.toJson())},
  });
  delta.add({'insert': '\n'});
  for (final row in rows) {
    text
      ..write(row.join(' | '))
      ..write('\n');
  }
}

XmlElement? _child(XmlElement? parent, String name) {
  if (parent == null) return null;
  for (final child in parent.childElements) {
    if (child.localName == name) return child;
  }
  return null;
}

String? _attr(XmlElement element, String name) {
  for (final attr in element.attributes) {
    if (attr.name.local == name) return attr.value;
  }
  return null;
}

String? _val(XmlElement? element, String name) =>
    element == null ? null : _attr(element, name);

bool _on(XmlElement? parent, String name) {
  final element = _child(parent, name);
  if (element == null) return false;
  final value = _attr(element, 'val');
  return value == null || (value != '0' && value != 'false');
}

T? _first<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

ArchiveFile? _archiveImage(Archive archive, String target) {
  final clean = target.startsWith('/') ? target.substring(1) : target;
  final name = clean.startsWith('word/') ? clean : 'word/$clean';
  for (final file in archive.files) {
    if (file.name == name) return file;
  }
  return null;
}