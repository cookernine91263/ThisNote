import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../features/editor/huazi.dart';

enum ExportFormat { docx, pdf, markdown, html, txt }

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
        ExportFormat.docx => 'Word 文档',
        ExportFormat.pdf => 'PDF',
        ExportFormat.markdown => 'Markdown',
        ExportFormat.html => '网页 HTML',
        ExportFormat.txt => '纯文本',
      };

  String get extension => switch (this) {
        ExportFormat.docx => 'docx',
        ExportFormat.pdf => 'pdf',
        ExportFormat.markdown => 'md',
        ExportFormat.html => 'html',
        ExportFormat.txt => 'txt',
      };

  String get description => switch (this) {
        ExportFormat.docx => '保留标题、加粗、颜色与图片',
        ExportFormat.pdf => '适合打印与分享的固定版式',
        ExportFormat.markdown => '通用纯文本格式，便于迁移',
        ExportFormat.html => '带排版的网页，可直接打开',
        ExportFormat.txt => '只要文字，不要格式',
      };
}

class NoteExporter {
  NoteExporter(this.store);
  final NoteStore store;

  Future<Uint8List> docx(Note note) async {
    final parser = _DeltaParser(note);
    await parser.parse(store);
    final imageParts = parser.images;
    final links = parser.links;

    final document = StringBuffer();
    document.write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>');
    document.write(
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
      '<w:body>',
    );
    final blocks = parser.blocks;
    var orderedIndex = 0;
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i];
      if (block.isDivider) {
        document.write(
          '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="D3C7B0"/></w:pBdr>'
          '<w:spacing w:before="180" w:after="180"/></w:pPr></w:p>',
        );
        continue;
      }
      if (block.runs.isEmpty) {
        document.write('<w:p><w:pPr><w:spacing w:line="360" w:lineRule="auto" w:after="120"/></w:pPr></w:p>');
        continue;
      }
      if (block.runs.any((r) => r.isImage)) {
        final textRuns = block.runs.where((r) => !r.isImage).toList();
        if (textRuns.isNotEmpty) {
          document.write('<w:p><w:pPr><w:spacing w:line="360" w:lineRule="auto" w:after="120"/></w:pPr>');
          for (final run in textRuns) {
            final rPr = _runProps(run.attrs, code: false, quote: false);
            document.write('<w:r>$rPr<w:t xml:space="preserve">${_esc(run.text)}</w:t></w:r>');
          }
          document.write('</w:p>');
        }
        for (final run in block.runs.where((r) => r.isImage)) {
          final img = imageParts[run.imageIndex!];
          document.write(_imageXml(img));
        }
        continue;
      }
      final header = block.attrs['header'];
      final list = block.attrs['list'];
      final quote = block.attrs['blockquote'] == true;
      final code = block.attrs['code-block'] == true;
      final align = block.attrs['align'];
      final pPr = StringBuffer('<w:pPr>');
      pPr.write('<w:spacing w:line="360" w:lineRule="auto" w:after="120"');
      if (header is int) {
        final before = switch (header) { 1 => 360, 2 => 300, _ => 240 };
        pPr.write(' w:before="$before"');
      }
      pPr.write('/>');
      if (header is int) {
        pPr.write('<w:keepNext/>');
      }
      if (align is String && align != 'left') {
        final val = switch (align) {
          'center' => 'center',
          'right' => 'right',
          'justify' => 'both',
          _ => 'left',
        };
        pPr.write('<w:jc w:val="$val"/>');
      }
      if (quote) {
        pPr.write(
          '<w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="A84637"/></w:pBdr>'
          '<w:shd w:val="clear" w:color="auto" w:fill="F7EEE9"/>'
          '<w:ind w:left="240" w:right="120"/>',
        );
      }
      if (code) {
        pPr.write(
          '<w:shd w:val="clear" w:color="auto" w:fill="F1EDE4"/>'
          '<w:ind w:left="180" w:right="180"/>',
        );
      }
      String? prefix;
      if (list is String) {
        if (list == 'ordered') {
          final prevList = i > 0 ? blocks[i - 1].attrs['list'] : null;
          orderedIndex = prevList == 'ordered' ? orderedIndex + 1 : 1;
          prefix = '$orderedIndex. ';
        } else if (list == 'checked') {
          prefix = '☑ ';
        } else if (list == 'unchecked') {
          prefix = '☐ ';
        } else {
          prefix = '• ';
        }
        pPr.write('<w:ind w:left="420" w:hanging="270"/>');
      }
      pPr.write('</w:pPr>');
      document.write('<w:p>$pPr');
      if (prefix != null) {
        document.write(
          '<w:r><w:rPr><w:rFonts w:ascii="微软雅黑" w:eastAsia="微软雅黑" w:hAnsi="微软雅黑"/></w:rPr>'
          '<w:t xml:space="preserve">${_esc(prefix)}</w:t></w:r>',
        );
      }
      for (final run in block.runs) {
        if (run.isImage) {
          final img = imageParts[run.imageIndex!];
          document.write(_imageXml(img));
          continue;
        }
        final rPr = _runProps(run.attrs, header: header, code: code, quote: quote);
        final text = '<w:t xml:space="preserve">${_esc(run.text)}</w:t>';
        final runXml = '<w:r>$rPr$text</w:r>';
        if (run.linkId != null) {
          document.write('<w:hyperlink r:id="${run.linkId}">$runXml</w:hyperlink>');
        } else {
          document.write(runXml);
        }
      }
      document.write('</w:p>');
    }
    document.write(
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" '
      'w:header="851" w:footer="992" w:gutter="0"/></w:sectPr>',
    );
    document.write('</w:body></w:document>');

    final archive = Archive();
    void addText(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addText('[Content_Types].xml', _contentTypes(imageParts));
    addText('_rels/.rels', _rootRels());
    addText('word/document.xml', document.toString());
    addText('word/styles.xml', _styles());
    addText('word/_rels/document.xml.rels', _docRels(imageParts, links));
    addText('docProps/core.xml', _core(note));
    addText('docProps/app.xml', _app());
    for (final img in imageParts) {
      archive.addFile(
        ArchiveFile('word/media/${img.fileName}', img.bytes.length, img.bytes),
      );
    }
    final bytes = ZipEncoder().encode(archive);
    return Uint8List.fromList(bytes);
  }

  static pw.Font? _pdfRegular;
  static pw.Font? _pdfBold;
  static pw.Font? _pdfLight;
  static pw.Font? _pdfOblique;
  static pw.Font? _pdfWenKai;

  Future<void> _loadPdfFonts() async {
    if (_pdfRegular != null) return;
    _pdfRegular = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'),
    );
    _pdfBold = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansSC-Bold.ttf'),
    );
    _pdfLight = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansSC-Light.ttf'),
    );
    _pdfOblique = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSansSC-Oblique.ttf'),
    );
    _pdfWenKai = pw.Font.ttf(
      await rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'),
    );
  }

  Future<Uint8List> pdf(Note note) async {
    await _loadPdfFonts();
    final parser = _DeltaParser(note);
    await parser.parse(store);
    final regular = _pdfRegular!;
    final bold = _pdfBold!;
    final light = _pdfLight!;
    final oblique = _pdfOblique!;
    final wenkai = _pdfWenKai!;
    final title = note.title.trim().isEmpty ? '无题' : note.title.trim();

    final doc = pw.Document(
      title: title,
      author: '此记 · ThisNote',
      creator: '此记 · ThisNote',
    );

    final widgets = <pw.Widget>[
      pw.Text(
        title,
        style: pw.TextStyle(
          font: wenkai,
          fontSize: 27,
          lineSpacing: 6,
          color: PdfColor.fromHex('#211E19'),
        ),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        '${note.kind.label} · ${dateLabel(note.createdAt)} · ${note.words} 字',
        style: pw.TextStyle(
          font: regular,
          fontSize: 9,
          color: PdfColor.fromHex('#8D8576'),
          letterSpacing: 0.4,
        ),
      ),
      pw.SizedBox(height: 18),
      pw.Divider(color: PdfColor.fromHex('#E3DAC8'), height: 1),
      pw.SizedBox(height: 16),
    ];

    var ordered = 0;
    for (final block in parser.blocks) {
      if (block.isDivider) {
        widgets.add(pw.Divider(color: PdfColor.fromHex('#E3DAC8')));
        continue;
      }
      if (block.runs.any((r) => r.isImage)) {
        for (final run in block.runs.where((r) => r.isImage)) {
          final img = parser.images[run.imageIndex!];
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Image(
                pw.MemoryImage(img.bytes),
                width: 430,
                fit: pw.BoxFit.contain,
              ),
            ),
          );
        }
        continue;
      }
      if (block.runs.isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
        continue;
      }
      final header = block.attrs['header'];
      final list = block.attrs['list'];
      final quote = block.attrs['blockquote'] == true;
      final code = block.attrs['code-block'] == true;
      final align = switch (block.attrs['align']) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        'justify' => pw.TextAlign.justify,
        _ => pw.TextAlign.left,
      };
      var prefix = '';
      if (list == 'ordered') {
        ordered++;
        prefix = '$ordered. ';
      } else if (list == 'checked') {
        prefix = '☑ ';
      } else if (list == 'unchecked') {
        prefix = '☐ ';
      } else if (list == 'bullet') {
        prefix = '• ';
      } else {
        ordered = 0;
      }
      final spans = <pw.InlineSpan>[
        if (prefix.isNotEmpty)
          pw.TextSpan(
            text: prefix,
            style: pw.TextStyle(
              font: regular,
              fontSize: 10,
              color: PdfColor.fromHex('#8D8576'),
            ),
          ),
        for (final run in block.runs)
          pw.TextSpan(
            text: run.text,
            style: _pdfRunStyle(
              run.attrs,
              regular: regular,
              bold: bold,
              light: light,
              oblique: oblique,
              wenkai: wenkai,
              header: header,
              code: code,
              quote: quote,
            ),
          ),
      ];
      final rich = pw.RichText(
        text: pw.TextSpan(children: spans),
        textAlign: align,
        lineSplitter: (line) => line.split(''),
      );
      if (code) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1EDE4'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: rich,
          ),
        );
      } else if (quote) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF7EEE9),
              border: pw.Border(
                left: pw.BorderSide(
                  color: PdfColor.fromInt(0xFFA84637),
                  width: 2,
                ),
              ),
            ),
            child: rich,
          ),
        );
      } else {
        widgets.add(
          pw.Padding(
            padding: pw.EdgeInsets.only(
              top: header != null ? 10 : 2,
              bottom: header != null ? 3 : 5,
            ),
            child: rich,
          ),
        );
      }
    }

    widgets.add(pw.SizedBox(height: 16));
    widgets.add(
      pw.Text(
        '此记 · ThisNote · 导出于 ${dateLabel(DateTime.now())}',
        style: pw.TextStyle(
          font: regular,
          fontSize: 8,
          color: PdfColor.fromHex('#8D8576'),
        ),
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(56, 54, 56, 52),
        theme: pw.ThemeData.withFont(
          base: regular,
          bold: bold,
          italic: oblique,
          boldItalic: bold,
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(
              font: regular,
              fontSize: 8,
              color: PdfColor.fromHex('#8D8576'),
            ),
          ),
        ),
        build: (context) => widgets,
      ),
    );
    return doc.save();
  }

  pw.TextStyle _pdfRunStyle(
    Map<String, dynamic> attrs, {
    required pw.Font regular,
    required pw.Font bold,
    required pw.Font light,
    required pw.Font oblique,
    required pw.Font wenkai,
    Object? header,
    required bool code,
    required bool quote,
  }) {
    var font = regular;
    var size = 11.0;
    var color = PdfColor.fromHex('#211E19');
    var weight = pw.FontWeight.normal;
    var style = pw.FontStyle.normal;
    var decoration = pw.TextDecoration.none;
    PdfColor? background;
    var spacing = 1.9;

    if (attrs['bold'] == true || header != null) {
      font = bold;
      weight = pw.FontWeight.bold;
    }
    if (attrs['italic'] == true) {
      font = oblique;
      style = pw.FontStyle.italic;
    }
    if (attrs['font'] == 'style:thin') {
      font = light;
      weight = pw.FontWeight.normal;
    }
    if (attrs['underline'] == true) decoration = pw.TextDecoration.underline;
    if (attrs['strike'] == true) decoration = pw.TextDecoration.lineThrough;
    if (attrs['code'] == true) {
      size = 9.5;
      font = regular;
      background = PdfColor.fromHex('#F1EDE4');
    }
    if (quote) color = PdfColor.fromHex('#575149');
    if (code) {
      size = 9.5;
      color = PdfColor.fromHex('#575149');
    }
    final c = attrs['color'];
    if (c is String && c.isNotEmpty) color = PdfColor.fromHex(_hex(c));
    final bg = attrs['background'];
    if (bg is String && bg.isNotEmpty) background = PdfColor.fromHex(_hex(bg));
    final fontAttr = attrs['font'];
    if (fontAttr is String && fontAttr.startsWith('huazi:')) {
      font = wenkai;
      size = 18;
      spacing = 1.4;
      final preset = huaziPresetById(fontAttr.split(':')[1]);
      if (preset != null) {
        color = PdfColor.fromHex(_hex(hexOf(preset.colors.first)));
      }
      weight = pw.FontWeight.bold;
    } else if (fontAttr == 'WenKai') {
      font = wenkai;
      if (attrs['size'] != null) {
        size = 18;
        weight = pw.FontWeight.bold;
        spacing = 1.4;
      }
    }
    if (header is int) {
      size = switch (header) { 1 => 22, 2 => 17, _ => 14 };
      font = wenkai;
      spacing = 1.5;
    }
    return pw.TextStyle(
      font: font,
      fontSize: size,
      color: color,
      fontWeight: weight,
      fontStyle: style,
      decoration: decoration,
      decorationColor: color,
      background:
          background == null ? null : pw.BoxDecoration(color: background),
      lineSpacing: (size * (spacing - 1)).clamp(1, 20).toDouble(),
      letterSpacing: fontAttr is String && fontAttr.startsWith('huazi:') ? 0.8 : 0,
    );
  }

  String markdown(Note note) {
    final parser = _DeltaParser(note);
    parser.parseSync();
    final out = StringBuffer();
    final title = note.title.trim().isEmpty ? '无题' : note.title.trim();
    out.writeln('# $title');
    out.writeln();
    out.writeln('> ${note.kind.label} · ${shortDate(note.createdAt)} · ${note.words} 字');
    out.writeln();
    var ordered = 0;
    for (final block in parser.blocks) {
      if (block.isDivider) {
        out.writeln('---');
        out.writeln();
        continue;
      }
      final text = block.runs.map((r) {
        if (r.isImage) return '![图片](${r.imagePath})';
        var t = r.text;
        final a = r.attrs;
        if (a['code'] == true) t = '`$t`';
        if (a['strike'] == true) t = '~~$t~~';
        if (a['italic'] == true) t = '*$t*';
        if (a['bold'] == true) t = '**$t**';
        final link = a['link'];
        if (link is String && link.isNotEmpty) t = '[$t]($link)';
        return t;
      }).join();
      final header = block.attrs['header'];
      final list = block.attrs['list'];
      final quote = block.attrs['blockquote'] == true;
      final code = block.attrs['code-block'] == true;
      if (code) {
        out.writeln('```');
        out.writeln(text);
        out.writeln('```');
      } else if (header is int) {
        out.writeln('${'#' * (header + 1)} $text');
      } else if (quote) {
        out.writeln('> $text');
      } else if (list == 'ordered') {
        ordered++;
        out.writeln('$ordered. $text');
      } else if (list is String) {
        ordered = 0;
        out.writeln('- ${list == 'checked' ? '[x] ' : list == 'unchecked' ? '[ ] ' : ''}$text');
      } else {
        ordered = 0;
        out.writeln(text);
      }
      out.writeln();
    }
    return out.toString();
  }

  Future<String> html(Note note) async {
    final parser = _DeltaParser(note);
    await parser.parse(store);
    final c = StringBuffer();
    final title = note.title.trim().isEmpty ? '无题' : note.title.trim();
    c.writeln('<!doctype html><html lang="zh-CN"><head><meta charset="utf-8">');
    c.writeln('<meta name="viewport" content="width=device-width,initial-scale=1">');
    c.writeln('<title>${_esc(title)}</title>');
    c.writeln('''<style>
      :root { color-scheme: light; }
      body { margin:0; background:#F4EFE4; color:#211E19;
        font-family:"Noto Sans SC","Source Han Sans SC","Microsoft YaHei",sans-serif;
        font-size:17px; line-height:1.9; }
      main { max-width: 760px; margin: 0 auto; padding: 72px 32px 96px; }
      h1.title { font-family:"LXGW WenKai","KaiTi",serif; font-size: 38px; line-height:1.4; letter-spacing:1px; margin:0 0 10px; }
      .meta { color:#8D8576; font-size:12px; letter-spacing:.5px; margin-bottom:34px; }
      h1,h2,h3 { font-family:"LXGW WenKai","KaiTi",serif; font-weight:600; line-height:1.5; margin:1.6em 0 .5em; }
      h1 { font-size:30px } h2 { font-size:24px } h3 { font-size:20px }
      p { margin: 0 0 .8em; }
      blockquote { margin: 1.2em 0; padding: 12px 18px; border-left:3px solid #A84637;
        background:#F7EEE9; color:#575149; border-radius:0 6px 6px 0; }
      pre { background:#F1EDE4; padding:14px 16px; border-radius:8px; overflow:auto;
        font-family: ui-monospace,Consolas,monospace; font-size:14px; line-height:1.7; }
      ul,ol { padding-left: 1.6em; margin:.4em 0 .9em; }
      img { max-width:100%; border-radius:6px; margin:10px 0; }
      hr { border:none; border-top:1px solid #E3DAC8; margin:26px 0; }
      a { color:#56697D; text-decoration:underline; text-underline-offset:2px; }
      .huazi { font-family:"LXGW WenKai","KaiTi",serif; font-size:30px; letter-spacing:1.5px;
        background: linear-gradient(92deg,#9E3F32,#D08A66,#8E3227); -webkit-background-clip:text;
        background-clip:text; color:transparent; font-weight:600; }
      footer { color:#8D8576; font-size:11px; margin-top:50px; border-top:1px solid #E3DAC8; padding-top:14px; }
      @media print { body { background:#fff } main { padding:0 } }
    </style></head><body><main>''');
    c.writeln('<div class="title">${_esc(title)}</div>');
    c.writeln(
      '<div class="meta">${note.kind.label} · ${dateLabel(note.createdAt)} · ${note.words} 字</div>',
    );
    var ordered = 0;
    for (final block in parser.blocks) {
      if (block.isDivider) {
        c.writeln('<hr>');
        continue;
      }
      final text = StringBuffer();
      for (final run in block.runs) {
        if (run.isImage) {
          final bytes = await store.readAsset(run.imagePath!);
          if (bytes != null) {
            final ext = p.extension(run.imagePath!).replaceAll('.', '');
            final mime = switch (ext.toLowerCase()) {
              'jpg' || 'jpeg' => 'image/jpeg',
              'gif' => 'image/gif',
              'webp' => 'image/webp',
              _ => 'image/png',
            };
            text.write('<img src="data:$mime;base64,${base64Encode(bytes)}">');
          }
          continue;
        }
        var inner = _esc(run.text);
        final a = run.attrs;
        if (a['code'] == true) inner = '<code>$inner</code>';
        if (a['strike'] == true) inner = '<del>$inner</del>';
        if (a['italic'] == true) inner = '<em>$inner</em>';
        if (a['bold'] == true) inner = '<strong>$inner</strong>';
        if (a['underline'] == true) inner = '<u>$inner</u>';
        final link = a['link'];
        if (link is String && link.isNotEmpty) {
          inner = '<a href="${_esc(link)}">$inner</a>';
        }
        final styles = <String>[];
        final color = a['color'];
        if (color is String) styles.add('color:${_cssColor(color)}');
        final bg = a['background'];
        if (bg is String) styles.add('background:${_cssColor(bg)};padding:0 2px;border-radius:2px');
        final font = a['font'];
        if (font is String && font.startsWith('huazi:')) {
          final preset = huaziPresetById(font.split(':')[1]);
          final colors = preset?.colors ?? const [];
          final gradient = colors.map((e) => _cssColor(hexOf(e))).join(',');
          inner = '<span class="huazi" style="background-image:linear-gradient(92deg,$gradient)">$inner</span>';
        } else if (font == 'WenKai') {
          styles.add('font-family:"LXGW WenKai","KaiTi",serif');
          if (a['size'] != null) {
            styles.add('font-size:1.65em;font-weight:600;line-height:1.4');
          }
        } else if (font == 'NotoSansSCLight' || font == 'style:thin') {
          styles.add('font-weight:300');
        }
        if (styles.isNotEmpty) {
          inner = '<span style="${styles.join(';')}">$inner</span>';
        }
        text.write(inner);
      }
      final header = block.attrs['header'];
      final list = block.attrs['list'];
      final quote = block.attrs['blockquote'] == true;
      final code = block.attrs['code-block'] == true;
      if (code) {
        c.writeln('<pre>${text.toString().replaceAll('<br>', '\n')}</pre>');
      } else if (header is int) {
        final tag = 'h${header.clamp(1, 3)}';
        c.writeln('<$tag>$text</$tag>');
      } else if (quote) {
        c.writeln('<blockquote>$text</blockquote>');
      } else if (list == 'ordered') {
        ordered++;
        c.writeln('<ol start="$ordered"><li>$text</li></ol>');
      } else if (list is String) {
        ordered = 0;
        final prefix = list == 'checked' ? '☑ ' : list == 'unchecked' ? '☐ ' : '• ';
        c.writeln('<div style="padding-left:1.2em">$prefix$text</div>');
      } else {
        ordered = 0;
        c.writeln('<p>$text</p>');
      }
    }
    c.writeln('<footer>此记 · ThisNote · 导出于 ${dateLabel(DateTime.now())}</footer>');
    c.writeln('</main></body></html>');
    return c.toString();
  }

  String txt(Note note) {
    final title = note.title.trim().isEmpty ? '无题' : note.title.trim();
    return '$title\n\n${note.kind.label} · ${dateLabel(note.createdAt)} · ${note.words} 字\n\n${note.text}\n';
  }

  // ---------------------------------------------------------------------------
  // DOCX helpers
  // ---------------------------------------------------------------------------

  String _runProps(
    Map<String, dynamic> attrs, {
    Object? header,
    required bool code,
    required bool quote,
  }) {
    final b = StringBuffer('<w:rPr>');
    var font = 'Noto Sans SC';
    var size = code ? 19 : 22;
    var color = '#211E19';
    var bold = false;
    final fontAttr = attrs['font'];
    final huazi = fontAttr is String && fontAttr.startsWith('huazi:');
    if (huazi) {
      font = 'LXGW WenKai';
      size = 32;
      bold = true;
      final preset = huaziPresetById(fontAttr.split(':')[1]);
      if (preset != null) color = hexOf(preset.colors.first);
    } else if (fontAttr == 'WenKai') {
      font = 'LXGW WenKai';
      if (attrs['size'] != null) {
        size = 32;
        bold = true;
      }
    } else if (fontAttr == 'NotoSansSCLight') {
      font = 'Noto Sans SC Light';
    } else if (fontAttr == 'style:thin') {
      font = 'Noto Sans SC Light';
    } else if (fontAttr is String && fontAttr.isNotEmpty && fontAttr != 'NotoSansSC') {
      font = fontAttr;
    }
    if (header is int) {
      size = switch (header) { 1 => 44, 2 => 36, _ => 30 };
      font = 'LXGW WenKai';
      bold = true;
    }
    if (quote) color = '#575149';
    final c = attrs['color'];
    if (c is String && c.isNotEmpty) color = c;
    if (attrs['bold'] == true) bold = true;
    b.write('<w:rFonts w:ascii="$font" w:eastAsia="$font" w:hAnsi="$font"/>');
    if (bold) b.write('<w:b/>');
    if (attrs['italic'] == true) b.write('<w:i/>');
    if (attrs['underline'] == true) b.write('<w:u w:val="single"/>');
    if (attrs['strike'] == true) b.write('<w:strike/>');
    if (attrs['code'] == true || code) {
      b.write('<w:shd w:val="clear" w:color="auto" w:fill="F1EDE4"/>');
      b.write('<w:rFonts w:ascii="Consolas" w:eastAsia="Consolas" w:hAnsi="Consolas"/>');
    }
    b.write('<w:color w:val="${_hex(color)}"/>');
    b.write('<w:sz w:val="$size"/><w:szCs w:val="$size"/>');
    final bg = attrs['background'];
    if (bg is String && bg.isNotEmpty) {
      b.write('<w:shd w:val="clear" w:color="auto" w:fill="${_hex(bg)}"/>');
    }
    b.write('</w:rPr>');
    return b.toString();
  }

  String _imageXml(_ImagePart img) {
    const maxEmu = 5486400;
    const maxHeightEmu = 6858000;
    var cx = img.width * 9525;
    var cy = img.height * 9525;
    if (cx > maxEmu) {
      final ratio = maxEmu / cx;
      cx = maxEmu;
      cy = (cy * ratio).round();
    }
    if (cy > maxHeightEmu) {
      final ratio = maxHeightEmu / cy;
      cy = maxHeightEmu;
      cx = (cx * ratio).round();
    }
    return '<w:p><w:pPr><w:spacing w:before="120" w:after="180"/></w:pPr><w:r><w:drawing>'
        '<wp:inline distT="0" distB="0" distL="0" distR="0">'
        '<wp:extent cx="$cx" cy="$cy"/><wp:docPr id="${img.index}" name="${img.fileName}"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="${img.index}" name="${img.fileName}"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="${img.relId}"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        '<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="$cx" cy="$cy"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>';
  }

  String _hex(String value) {
    var v = value.replaceAll('#', '');
    if (v.length == 8) v = v.substring(2);
    return v.toUpperCase();
  }

  String _cssColor(String value) {
    var v = value.replaceAll('#', '');
    if (v.length == 8) v = '${v.substring(2)}${v.substring(0, 2)}';
    return '#$v';
  }

  String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String _contentTypes(List<_ImagePart> images) {
    final exts = images.map((e) => e.extension).toSet();
    final defaults = <String>[];
    for (final ext in exts) {
      final mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/png',
      };
      defaults.add('<Default Extension="$ext" ContentType="$mime"/>');
    }
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '${defaults.join()}'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
        '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
        '</Types>';
  }

  String _rootRels() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
      '</Relationships>';

  String _docRels(List<_ImagePart> images, List<_LinkPart> links) {
    final b = StringBuffer('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
    for (final img in images) {
      b.write('<Relationship Id="${img.relId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/${img.fileName}"/>');
    }
    for (final link in links) {
      b.write('<Relationship Id="${link.relId}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="${_esc(link.url)}" TargetMode="External"/>');
    }
    b.write('</Relationships>');
    return b.toString();
  }

  String _styles() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:docDefaults><w:rPrDefault><w:rPr>'
      '<w:rFonts w:ascii="Noto Sans SC" w:eastAsia="Noto Sans SC" w:hAnsi="Noto Sans SC"/>'
      '<w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault>'
      '<w:pPrDefault><w:pPr><w:spacing w:line="360" w:lineRule="auto" w:after="120"/></w:pPr></w:pPrDefault>'
      '</w:docDefaults>'
      '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>'
      '</w:styles>';

  String _core(Note note) => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(note.title.isEmpty ? '无题' : note.title)}</dc:title>'
      '<dc:creator>此记 · ThisNote</dc:creator>'
      '<cp:lastModifiedBy>此记 · ThisNote</cp:lastModifiedBy>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${note.createdAt.toUtc().toIso8601String()}</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">${DateTime.now().toUtc().toIso8601String()}</dcterms:modified>'
      '</cp:coreProperties>';

  String _app() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>此记 · ThisNote</Application></Properties>';
}

class _Run {
  _Run(
    this.text, {
    this.attrs = const {},
    this.isImage = false,
    this.imagePath,
    this.imageIndex,
    this.linkId,
  });

  final String text;
  final Map<String, dynamic> attrs;
  final bool isImage;
  final String? imagePath;
  final int? imageIndex;
  final String? linkId;
}

class _Block {
  _Block({
    required this.runs,
    required this.attrs,
    this.isDivider = false,
  });

  final List<_Run> runs;
  final Map<String, dynamic> attrs;
  final bool isDivider;
}

class _ImagePart {
  _ImagePart({
    required this.index,
    required this.bytes,
    required this.extension,
    required this.width,
    required this.height,
  });

  final int index;
  final Uint8List bytes;
  final String extension;
  final int width;
  final int height;

  String get fileName => 'img$index.$extension';
  String get relId => 'rIdImg$index';
}

class _LinkPart {
  _LinkPart(this.url, this.relId);
  final String url;
  final String relId;
}

class _DeltaParser {
  _DeltaParser(this.note);
  final Note note;

  final List<_Block> blocks = [];
  final List<_ImagePart> images = [];
  final List<_LinkPart> links = [];

  Future<void> parse(NoteStore store) async {
    final existing = note.delta;
    var runs = <_Run>[];
    for (final raw in existing) {
      if (raw is! Map) continue;
      final insert = raw['insert'];
      final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (insert is String) {
        final parts = insert.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            runs.add(_Run(
              parts[i],
              attrs: attrs,
              linkId: await _linkId(attrs),
            ));
          }
          if (i < parts.length - 1) {
            blocks.add(_Block(runs: runs, attrs: attrs));
            runs = <_Run>[];
          }
        }
      } else if (insert is Map) {
        if (insert['image'] is String) {
          final path = insert['image'] as String;
          final bytes = await store.readAsset(path);
          if (bytes != null) {
            var width = 640;
            var height = 400;
            try {
              final codec = await ui.instantiateImageCodec(bytes);
              final frame = await codec.getNextFrame();
              width = frame.image.width;
              height = frame.image.height;
              frame.image.dispose();
              codec.dispose();
            } catch (_) {}
            final ext = p.extension(path).replaceAll('.', '').toLowerCase();
            final index = images.length + 1;
            images.add(_ImagePart(
              index: index,
              bytes: bytes,
              extension: ext.isEmpty ? 'png' : ext,
              width: width,
              height: height,
            ));
            runs.add(_Run(
              '',
              isImage: true,
              imagePath: path,
              imageIndex: images.length - 1,
            ));
          }
        } else if (insert['divider'] != null) {
          blocks.add(_Block(runs: const [], attrs: const {}, isDivider: true));
        }
      }
    }
    if (runs.isNotEmpty) blocks.add(_Block(runs: runs, attrs: const {}));
    if (blocks.isEmpty) blocks.add(_Block(runs: const [], attrs: const {}));
  }

  void parseSync() {
    var runs = <_Run>[];
    for (final raw in note.delta) {
      if (raw is! Map) continue;
      final insert = raw['insert'];
      final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (insert is! String) {
        if (insert is Map && insert['image'] is String) {
          runs.add(_Run('', isImage: true, imagePath: insert['image'] as String));
        } else if (insert is Map && insert['divider'] != null) {
          blocks.add(_Block(runs: const [], attrs: const {}, isDivider: true));
        }
        continue;
      }
      final parts = insert.split('\n');
      for (var i = 0; i < parts.length; i++) {
        if (parts[i].isNotEmpty) runs.add(_Run(parts[i], attrs: attrs));
        if (i < parts.length - 1) {
          blocks.add(_Block(runs: runs, attrs: attrs));
          runs = <_Run>[];
        }
      }
    }
    if (runs.isNotEmpty) blocks.add(_Block(runs: runs, attrs: const {}));
  }

  Future<String?> _linkId(Map<String, dynamic> attrs) async {
    final link = attrs['link'];
    if (link is! String || link.isEmpty) return null;
    final existing = links.where((e) => e.url == link);
    if (existing.isNotEmpty) return existing.first.relId;
    final id = 'rIdLink${links.length + 1}';
    links.add(_LinkPart(link, id));
    return id;
  }
}
