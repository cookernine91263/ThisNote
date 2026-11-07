import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/services/docx_import.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('导入 DOCX 的标题、粗体、表格与图片', () async {
    final archive = Archive();
    void add(String name, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('word/document.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
  <w:body>
    <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>标题</w:t></w:r></w:p>
    <w:p>
      <w:r><w:rPr><w:b/></w:rPr><w:t xml:space="preserve">粗体</w:t></w:r>
      <w:r><w:t>普通</w:t></w:r>
    </w:p>
    <w:p><w:r><w:drawing><a:blip r:embed="rId1"/></w:drawing></w:r></w:p>
    <w:tbl>
      <w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>
      <w:tc><w:p><w:r><w:t>B</w:t></w:r></w:p></w:tc></w:tr>
    </w:tbl>
  </w:body>
</w:document>''');
    add('word/_rels/document.xml.rels', '''<?xml version="1.0" encoding="UTF-8"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
</Relationships>''');
    add('docProps/core.xml', '''<?xml version="1.0" encoding="UTF-8"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties"
  xmlns:dc="http://purl.org/dc/elements/1.1/">
  <dc:title>我的文档</dc:title>
</cp:coreProperties>''');
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
    archive.addFile(ArchiveFile('word/media/image1.png', png.length, png));

    var savedImage = 0;
    final result = await parseDocx(
      Uint8List.fromList(ZipEncoder().encode(archive)),
      saveImage: (bytes, extension) async {
        savedImage++;
        expect(extension, 'png');
        return 'assets/image1.png';
      },
    );

    expect(result, isNotNull);
    expect(result!.title, '我的文档');
    expect(result.text, contains('标题'));
    expect(result.text, contains('粗体普通'));
    expect(result.text, contains('A | B'));
    expect(savedImage, 1);
    expect(
      result.delta.any(
        (op) => op is Map && op['insert'] is Map && (op['insert'] as Map)['image'] == 'assets/image1.png',
      ),
      isTrue,
    );
    expect(
      result.delta.any(
        (op) => op is Map && op['insert'] is Map && (op['insert'] as Map).containsKey('table'),
      ),
      isTrue,
    );
  });
}