import 'dart:convert';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format.dart';
import '../core/i18n.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../features/editor/code_block.dart';
import '../features/editor/huazi.dart';

/// 导出文件里会出现的固定文案（标题占位、作者、日期标签等）。
const _en = <String, String>{
  'Word 文档': 'Word document',
  'PNG 图片': 'PNG image',
  '网页 HTML': 'Web page (HTML)',
  '纯文本': 'Plain text',
  '保留标题、加粗、颜色与图片': 'Keeps headings, bold, color and images',
  '适合打印与分享的固定版式': 'A fixed layout for printing and sharing',
  '一张排版好的长图，适合收藏与分享':
      'One long, well-set image for keeping or sharing',
  '通用纯文本格式，便于迁移': 'A universal plain-text format, easy to move',
  '带排版的网页，可直接打开': 'A styled web page you can open directly',
  '只要文字，不要格式': 'Just the words, no formatting',
  '无题': 'Untitled',
  '图片': 'image',
  '此记 · ThisNote': 'ThisNote',
  '此记 · ThisNote · 导出于 {date}': 'ThisNote · Exported on {date}',
};

enum ExportFormat { docx, pdf, png, markdown, html, txt }

extension ExportFormatX on ExportFormat {
  String get label => switch (this) {
        ExportFormat.docx => tr('Word 文档', null, _en),
        ExportFormat.pdf => tr('PDF', null, _en),
        ExportFormat.png => tr('PNG 图片', null, _en),
        ExportFormat.markdown => tr('Markdown', null, _en),
        ExportFormat.html => tr('网页 HTML', null, _en),
        ExportFormat.txt => tr('纯文本', null, _en),
      };

  String get extension => switch (this) {
        ExportFormat.docx => 'docx',
        ExportFormat.pdf => 'pdf',
        ExportFormat.png => 'png',
        ExportFormat.markdown => 'md',
        ExportFormat.html => 'html',
        ExportFormat.txt => 'txt',
      };

  String get description => switch (this) {
        ExportFormat.docx => tr('保留标题、加粗、颜色与图片', null, _en),
        ExportFormat.pdf => tr('适合打印与分享的固定版式', null, _en),
        ExportFormat.png => tr('一张排版好的长图，适合收藏与分享', null, _en),
        ExportFormat.markdown => tr('通用纯文本格式，便于迁移', null, _en),
        ExportFormat.html => tr('带排版的网页，可直接打开', null, _en),
        ExportFormat.txt => tr('只要文字，不要格式', null, _en),
      };
}

/// 没有标题时的占位。
String _titleOf(Note note) =>
    note.title.trim().isEmpty ? tr('无题', null, _en) : note.title.trim();

/// 导出页眉/正文里那行「文体 · 日期 · 字数」。
/// [compact] 用短日期（Markdown 头部沿用原来的短日期）。
String _metaLine(Note note, {bool compact = false}) =>
    '${note.kind.label} · '
    '${compact ? shortDate(note.createdAt) : dateLabel(note.createdAt)} · '
    '${I18n.count(note.words, '字', 'word')}';

/// 导出文件末尾的落款。
String _exportedOn(DateTime when) =>
    tr('此记 · ThisNote · 导出于 {date}', {'date': dateLabel(when)}, _en);

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
    final orderedNumIds = <int>[];
    var lastList = '';
    for (final block in blocks) {
      if (block.isDivider) {
        document.write(
          '<w:p><w:pPr><w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="D3C7B0"/></w:pBdr>'
          '<w:spacing w:before="180" w:after="180"/></w:pPr></w:p>',
        );
        lastList = '';
        continue;
      }
      if (block.isCode) {
        document.write(_docxCodeBlock(block));
        lastList = '';
        continue;
      }
      if (block.runs.isEmpty) {
        document.write('<w:p><w:pPr><w:spacing w:line="360" w:lineRule="auto" w:after="120"/></w:pPr></w:p>');
        lastList = '';
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
          document.write(_imageXml(img, run.attrs));
        }
        lastList = '';
        continue;
      }
      final header = block.attrs['header'];
      final list = block.attrs['list'];
      final quote = block.attrs['blockquote'] == true;
      final align = block.attrs['align'];
      final checked = list == 'checked';
      final pPr = StringBuffer('<w:pPr>');
      if (header is int) {
        pPr.write('<w:pStyle w:val="Heading${header.clamp(1, 3)}"/>');
        pPr.write('<w:keepNext/>');
      } else if (quote) {
        pPr.write('<w:pStyle w:val="Quote"/>');
      }
      String? prefix;
      String? numPr;
      var hanging = false;
      if (list is String) {
        if (list == 'ordered') {
          if (lastList != 'ordered') {
            orderedNumIds.add(2 + orderedNumIds.length);
          }
          numPr =
              '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="${orderedNumIds.last}"/></w:numPr>';
        } else if (list == 'bullet') {
          numPr =
              '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>';
        } else if (list == 'checked') {
          prefix = '☑ ';
          hanging = true;
        } else if (list == 'unchecked') {
          prefix = '☐ ';
          hanging = true;
        } else {
          prefix = '• ';
          hanging = true;
        }
      }
      if (numPr != null) pPr.write(numPr);
      if (quote) {
        pPr.write(
          '<w:pBdr><w:left w:val="single" w:sz="12" w:space="8" w:color="A84637"/></w:pBdr>'
          '<w:shd w:val="clear" w:color="auto" w:fill="F7EEE9"/>',
        );
      }
      final before = header is int ? switch (header) {
        1 => 360,
        2 => 300,
        _ => 240,
      } : 0;
      pPr.write(
        '<w:spacing w:line="360" w:lineRule="auto" w:after="120"'
        '${before > 0 ? ' w:before="$before"' : ''}/>',
      );
      if (quote) {
        pPr.write('<w:ind w:left="240" w:right="120"/>');
      } else if (hanging) {
        pPr.write('<w:ind w:left="420" w:hanging="270"/>');
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
      pPr.write('</w:pPr>');
      document.write('<w:p>$pPr');
      if (prefix != null) {
        document.write(
          '<w:r><w:rPr><w:rFonts w:ascii="微软雅黑" w:eastAsia="微软雅黑" w:hAnsi="微软雅黑"/>'
          '${checked ? '<w:strike/>' : ''}</w:rPr>'
          '<w:t xml:space="preserve">${_esc(prefix)}</w:t></w:r>',
        );
      }
      for (final run in block.runs) {
        if (run.isImage) {
          final img = imageParts[run.imageIndex!];
          document.write(_imageXml(img, run.attrs));
          continue;
        }
        final runAttrs = checked
            ? <String, dynamic>{...run.attrs, 'strike': true}
            : run.attrs;
        final rPr = _runProps(
          runAttrs,
          header: header,
          code: false,
          quote: quote,
        );
        final text = '<w:t xml:space="preserve">${_esc(run.text)}</w:t>';
        final runXml = '<w:r>$rPr$text</w:r>';
        if (run.linkId != null) {
          document.write('<w:hyperlink r:id="${run.linkId}">$runXml</w:hyperlink>');
        } else {
          document.write(runXml);
        }
      }
      document.write('</w:p>');
      lastList = list is String ? list : '';
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
    addText('word/numbering.xml', _numbering(orderedNumIds));
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
  static pw.Font? _pdfMono;

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
    // 中文没有随字体分发的可靠斜体字面；导出时用常规字重保持版面稳定。
    _pdfOblique = _pdfRegular;
    _pdfWenKai = pw.Font.ttf(
      await rootBundle.load('assets/fonts/LXGWWenKai-Regular.ttf'),
    );
    try {
      _pdfMono = pw.Font.ttf(
        await rootBundle.load('assets/fonts/SourceHanMonoSC-Regular.otf'),
      );
    } catch (_) {
      _pdfMono = _pdfRegular;
    }
  }

  Future<Uint8List> pdf(Note note, {Color? accent}) async {
    await _loadPdfFonts();
    final parser = _DeltaParser(note);
    await parser.parse(store);
    final regular = _pdfRegular!;
    final bold = _pdfBold!;
    final light = _pdfLight!;
    final oblique = _pdfOblique!;
    final wenkai = _pdfWenKai!;
    final mono = _pdfMono ?? regular;
    final accentColor = PdfColor.fromInt(accent?.toARGB32() ?? 0xFFA84637);
    final title = _titleOf(note);

    final doc = pw.Document(
      title: title,
      author: tr('此记 · ThisNote', null, _en),
      creator: tr('此记 · ThisNote', null, _en),
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
        _metaLine(note),
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
      if (block.isCode) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#F1EDE4'),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
            ),
            child: pw.Text(
              block.code ?? block.runs.map((r) => r.text).join(),
              style: pw.TextStyle(
                font: mono,
                fontFallback: [regular],
                fontSize: 9.2,
                lineSpacing: 2,
                color: PdfColor.fromHex('#211E19'),
              ),
            ),
          ),
        );
        continue;
      }
      if (block.runs.any((r) => r.isImage)) {
        for (final run in block.runs.where((r) => r.isImage)) {
          final img = parser.images[run.imageIndex!];
          final factor = _imageFactor(run.attrs);
          final alignment = switch (_imageAlign(run.attrs)) {
            'center' => pw.Alignment.center,
            'right' => pw.Alignment.centerRight,
            _ => pw.Alignment.centerLeft,
          };
          widgets.add(
            pw.Container(
              margin: const pw.EdgeInsets.symmetric(vertical: 8),
              child: pw.Align(
                alignment: alignment,
                child: pw.Image(
                  pw.MemoryImage(img.bytes),
                  width: 430 * factor,
                  fit: pw.BoxFit.contain,
                ),
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
      final checked = list == 'checked';
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
        prefix = '[x] ';
      } else if (list == 'unchecked') {
        prefix = '[ ] ';
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
              decoration:
                  checked ? pw.TextDecoration.lineThrough : pw.TextDecoration.none,
            ),
          ),
        for (final run in block.runs)
          pw.TextSpan(
            text: run.text,
            style: _pdfRunStyle(
              checked
                  ? <String, dynamic>{...run.attrs, 'strike': true}
                  : run.attrs,
              regular: regular,
              bold: bold,
              light: light,
              oblique: oblique,
              wenkai: wenkai,
              header: header,
              code: false,
              quote: quote,
              mono: mono,
            ),
          ),
      ];
      final rich = pw.RichText(
        text: pw.TextSpan(children: spans),
        textAlign: align,
        lineSplitter: (line) => line.split(''),
      );
      if (quote) {
        widgets.add(
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFF7EEE9),
              border: pw.Border(
                left: pw.BorderSide(
                  color: accentColor,
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
              left: list is String ? 14 : 0,
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
        _exportedOn(DateTime.now()),
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
    pw.Font? mono,
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
      font = mono ?? regular;
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
    final title = _titleOf(note);
    out.writeln('# $title');
    out.writeln();
    out.writeln('> ${_metaLine(note, compact: true)}');
    out.writeln();
    var ordered = 0;
    for (final block in parser.blocks) {
      if (block.isDivider) {
        out.writeln('---');
        out.writeln();
        continue;
      }
      if (block.isCode) {
        final code = block.code ?? block.runs.map((r) => r.text).join();
        out.writeln('```${block.codeLanguage}');
        out.writeln(code);
        out.writeln('```');
        out.writeln();
        continue;
      }
      final text = block.runs.map((r) {
        if (r.isImage) return '![${tr('图片', null, _en)}](${r.imagePath})';
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
      if (header is int) {
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
    final title = _titleOf(note);
    final lang = I18n.isEn ? 'en' : 'zh-CN';
    c.writeln('<!doctype html><html lang="$lang"><head><meta charset="utf-8">');
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
      '<div class="meta">${_metaLine(note)}</div>',
    );
    String? openList;
    void closeList() {
      if (openList != null) {
        c.writeln('</$openList>');
        openList = null;
      }
    }

    for (final block in parser.blocks) {
      if (block.isDivider) {
        closeList();
        c.writeln('<hr>');
        continue;
      }
      if (block.isCode) {
        closeList();
        final code = block.code ?? block.runs.map((r) => r.text).join();
        final language = block.codeLanguage;
        final cls = language.isEmpty
            ? ''
            : ' class="language-${_esc(language)}"';
        c.writeln('<pre><code$cls>${_esc(code)}</code></pre>');
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
      final checked = list == 'checked';
      if (header is int) {
        closeList();
        final tag = 'h${header.clamp(1, 3)}';
        c.writeln('<$tag>$text</$tag>');
      } else if (quote) {
        closeList();
        c.writeln('<blockquote>$text</blockquote>');
      } else if (list is String) {
        final target = list == 'ordered' ? 'ol' : 'ul';
        if (openList != target) {
          closeList();
          openList = target;
          c.writeln('<$target>');
        }
        if (list == 'ordered') {
          c.writeln('<li>$text</li>');
        } else if (checked) {
          c.writeln('<li><del>☑ $text</del></li>');
        } else if (list == 'unchecked') {
          c.writeln('<li>☐ $text</li>');
        } else {
          c.writeln('<li>$text</li>');
        }
      } else {
        closeList();
        c.writeln('<p>$text</p>');
      }
    }
    closeList();
    c.writeln('<footer>${_exportedOn(DateTime.now())}</footer>');
    c.writeln('</main></body></html>');
    return c.toString();
  }

  String txt(Note note) {
    final title = _titleOf(note);
    return '$title\n\n${_metaLine(note)}\n\n${note.text}\n';
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

  String _docxCodeBlock(_Block block) {
    final code = block.code ?? block.runs.map((r) => r.text).join();
    final lines = code.split('\n');
    final b = StringBuffer(
      '<w:p><w:pPr><w:pStyle w:val="ThisNoteCode"/>'
      '<w:shd w:val="clear" w:color="auto" w:fill="F1EDE4"/>'
      '<w:spacing w:before="120" w:after="120" w:line="300" w:lineRule="auto"/>'
      '<w:ind w:left="180" w:right="180"/></w:pPr>',
    );
    final rPr = _runProps(const {}, code: true, quote: false);
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) b.write('<w:r><w:br/></w:r>');
      b.write(
        '<w:r>$rPr<w:t xml:space="preserve">${_esc(lines[i])}</w:t></w:r>',
      );
    }
    b.write('</w:p>');
    return b.toString();
  }

  String _numbering(List<int> orderedNumIds) {
    final b = StringBuffer(
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">',
    );
    b.write(
      '<w:abstractNum w:abstractNumId="0">'
      '<w:multiLevelType w:val="singleLevel"/>'
      '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
      '<w:lvlText w:val="•"/><w:lvlJc w:val="left"/>'
      '<w:pPr><w:ind w:left="420" w:hanging="270"/></w:pPr></w:lvl>'
      '</w:abstractNum>',
    );
    b.write(
      '<w:abstractNum w:abstractNumId="1">'
      '<w:multiLevelType w:val="singleLevel"/>'
      '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
      '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>'
      '<w:pPr><w:ind w:left="420" w:hanging="270"/></w:pPr></w:lvl>'
      '</w:abstractNum>',
    );
    b.write('<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>');
    for (final id in orderedNumIds) {
      b.write(
        '<w:num w:numId="$id"><w:abstractNumId w:val="1"/>'
        '<w:lvlOverride w:ilvl="0"><w:startOverride w:val="1"/></w:lvlOverride>'
        '</w:num>',
      );
    }
    b.write('</w:numbering>');
    return b.toString();
  }

  String _imageXml(_ImagePart img, Map<String, dynamic> attrs) {
    final factor = _imageFactor(attrs);
    final maxEmu = (5486400 * factor).round();
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
    final jc = switch (_imageAlign(attrs)) {
      'center' => '<w:jc w:val="center"/>',
      'right' => '<w:jc w:val="right"/>',
      _ => '',
    };
    return '<w:p><w:pPr>$jc<w:spacing w:before="120" w:after="180"/></w:pPr><w:r><w:drawing>'
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
        '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
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
    b.write('<Relationship Id="rIdNum1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>');
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
      '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/>'
      '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:outlineLvl w:val="0"/><w:spacing w:before="360" w:after="120"/></w:pPr>'
      '<w:rPr><w:rFonts w:ascii="LXGW WenKai" w:eastAsia="LXGW WenKai" w:hAnsi="LXGW WenKai"/>'
      '<w:b/><w:sz w:val="44"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/>'
      '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:outlineLvl w:val="1"/><w:spacing w:before="300" w:after="120"/></w:pPr>'
      '<w:rPr><w:rFonts w:ascii="LXGW WenKai" w:eastAsia="LXGW WenKai" w:hAnsi="LXGW WenKai"/>'
      '<w:b/><w:sz w:val="36"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/>'
      '<w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/>'
      '<w:pPr><w:keepNext/><w:outlineLvl w:val="2"/><w:spacing w:before="240" w:after="120"/></w:pPr>'
      '<w:rPr><w:b/><w:sz w:val="30"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/>'
      '<w:basedOn w:val="Normal"/><w:pPr><w:spacing w:before="120" w:after="120"/></w:pPr>'
      '<w:rPr><w:color w:val="575149"/></w:rPr></w:style>'
      '<w:style w:type="paragraph" w:styleId="ThisNoteCode"><w:name w:val="ThisNote Code"/>'
      '<w:basedOn w:val="Normal"/><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F1EDE4"/>'
      '<w:spacing w:before="120" w:after="120" w:line="300" w:lineRule="auto"/>'
      '<w:ind w:left="180" w:right="180"/></w:pPr>'
      '<w:rPr><w:rFonts w:ascii="Consolas" w:eastAsia="Noto Sans SC" w:hAnsi="Consolas"/>'
      '<w:sz w:val="19"/><w:szCs w:val="19"/></w:rPr></w:style>'
      '</w:styles>';

  String _core(Note note) => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(_titleOf(note))}</dc:title>'
      '<dc:creator>${_esc(tr('此记 · ThisNote', null, _en))}</dc:creator>'
      '<cp:lastModifiedBy>${_esc(tr('此记 · ThisNote', null, _en))}</cp:lastModifiedBy>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">${note.createdAt.toUtc().toIso8601String()}</dcterms:created>'
      '<dcterms:modified xsi:type="dcterms:W3CDTF">${DateTime.now().toUtc().toIso8601String()}</dcterms:modified>'
      '</cp:coreProperties>';

  String _app() => '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
      'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes">'
      '<Application>${_esc(tr('此记 · ThisNote', null, _en))}</Application></Properties>';
}

/// 图片宽度（相对正文宽度）与对齐，写在 embed 的 attributes 上。
double _imageFactor(Map<String, dynamic> attrs) {
  final raw = attrs['imageWidth']?.toString();
  final value = double.tryParse(raw ?? '') ?? 1;
  return value.clamp(0.2, 1.0);
}

String _imageAlign(Map<String, dynamic> attrs) {
  final raw = attrs['imageAlign']?.toString();
  return raw == 'center' || raw == 'right' ? raw! : 'left';
}

class _Run {
  _Run(    this.text, {
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
    this.code,
    this.codeLanguage = '',
  });

  final List<_Run> runs;
  final Map<String, dynamic> attrs;
  final bool isDivider;

  /// 非空表示这是一个代码块（自定义 embed 或合并后的旧版行属性代码块）。
  final String? code;
  final String codeLanguage;

  bool get isCode => code != null || attrs['code-block'] == true;
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
        final code = CodeBlockData.fromRaw(insert[codeBlockKey]);
        if (code != null) {
          if (runs.isNotEmpty) {
            blocks.add(_Block(runs: runs, attrs: const {}));
            runs = <_Run>[];
          }
          blocks.add(
            _Block(
              runs: const [],
              attrs: const {},
              code: code.code,
              codeLanguage: code.language,
            ),
          );
          continue;
        }
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
              attrs: attrs,
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
    _normalizeCodeBlocks();
    if (blocks.isEmpty) blocks.add(_Block(runs: const [], attrs: const {}));
  }

  void _normalizeCodeBlocks() {
    final merged = <_Block>[];
    for (final block in blocks) {
      if (!block.isCode) {
        merged.add(block);
        continue;
      }
      final text = block.code ?? block.runs.map((r) => r.text).join();
      final language = block.codeLanguage;
      if (merged.isNotEmpty && merged.last.isCode) {
        final previous = merged.removeLast();
        final previousText =
            previous.code ?? previous.runs.map((r) => r.text).join();
        merged.add(
          _Block(
            runs: const [],
            attrs: const {},
            code: '$previousText\n$text',
            codeLanguage: previous.codeLanguage.isNotEmpty
                ? previous.codeLanguage
                : language,
          ),
        );
      } else {
        merged.add(
          _Block(
            runs: const [],
            attrs: const {},
            code: text,
            codeLanguage: language,
          ),
        );
      }
    }
    blocks
      ..clear()
      ..addAll(merged);
  }

  void parseSync() {
    var runs = <_Run>[];
    for (final raw in note.delta) {
      if (raw is! Map) continue;
      final insert = raw['insert'];
      final attrs = (raw['attributes'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (insert is! String) {
        if (insert is Map) {
          final code = CodeBlockData.fromRaw(insert[codeBlockKey]);
          if (code != null) {
            if (runs.isNotEmpty) {
              blocks.add(_Block(runs: runs, attrs: const {}));
              runs = <_Run>[];
            }
            blocks.add(
              _Block(
                runs: const [],
                attrs: const {},
                code: code.code,
                codeLanguage: code.language,
              ),
            );
            continue;
          }
          if (insert['image'] is String) {
            runs.add(_Run(
              '',
              attrs: attrs,
              isImage: true,
              imagePath: insert['image'] as String,
            ));
          } else if (insert['divider'] != null) {
            blocks.add(_Block(runs: const [], attrs: const {}, isDivider: true));
          }
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
    _normalizeCodeBlocks();
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
