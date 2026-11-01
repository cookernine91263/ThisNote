import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:this_note/src/core/theme.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/features/editor/code_block.dart';
import 'package:this_note/src/features/editor/editor_page.dart';
import 'package:this_note/src/features/editor/huazi.dart';
import 'package:this_note/src/services/exporter.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('code block embed round-trips and contributes plain text', () {
    const data = CodeBlockData(
      code: 'def f():\n    return 1',
      language: 'python',
    );
    final embed = codeBlockEmbed(data);
    expect(embed.type, codeBlockKey);
    expect(codeBlockOf(embed)!.language, 'python');
    expect(codeBlockOf(embed)!.code, data.code);

    final delta = Delta()
      ..insert('前文\n')
      ..insert(embed)
      ..insert('\n');
    final text = deltaPlainText(delta);
    expect(text, contains('def f():'));
    expect(text, contains('前文'));
  });

  test('legacy line-attribute code blocks can be found and upgraded', () {
    final document = Document.fromJson([
      {'insert': '前文\n'},
      {
        'insert': 'line one\n',
        'attributes': {'code-block': true},
      },
      {
        'insert': 'line two\n',
        'attributes': {'code-block': true},
      },
      {'insert': 'after\n'},
    ]);
    final controller = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 4),
    );
    final legacy = legacyCodeBlockAt(controller);
    expect(legacy, isNotNull);
    expect(legacy!.code, 'line one\nline two');
    expect(legacy.end - legacy.start, 'line one\nline two\n'.length);
    expect(legacyCodeBlockAt(
      QuillController(
        document: document,
        selection: const TextSelection.collapsed(offset: 0),
      ),
    ), isNull);
    controller.dispose();
  });

  test('checked checklists get display strikethrough', () {
    final checked = quillCustomStyle(
      const Attribute('list', AttributeScope.block, 'checked'),
      dark: false,
      muted: Colors.grey,
    );
    expect(checked.decoration, TextDecoration.lineThrough);
    final unchecked = quillCustomStyle(
      const Attribute('list', AttributeScope.block, 'unchecked'),
      dark: false,
      muted: Colors.grey,
    );
    expect(unchecked.decoration, isNot(TextDecoration.lineThrough));
  });

  test('exports keep code language, code lines, checklists and lists', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-code-export-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();

    final code = const CodeBlockData(
      code: 'def f():\n    return 1',
      language: 'python',
    );
    final note = Note(
      id: 'code-note',
      title: '代码导出',
      kind: NoteKind.note,
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      day: '2026-11-01',
      text: '',
      delta: [
        {
          'insert': '导出标题\n',
          'attributes': {'header': 1},
        },
        {
          'insert': '待办\n',
          'attributes': {'list': 'checked'},
        },
        {'insert': '第一项\n', 'attributes': {'list': 'bullet'}},
        {'insert': '第二项\n', 'attributes': {'list': 'ordered'}},
        {
          'insert': {codeBlockKey: jsonEncode(code.toJson())},
        },
        {'insert': '\n'},
      ],
    );

    final exporter = NoteExporter(store);
    final docx = await exporter.docx(note);
    final html = await exporter.html(note);
    final markdown = exporter.markdown(note);
    final pdf = await exporter.pdf(note);

    final archive = ZipDecoder().decodeBytes(docx);
    final documentXml = utf8.decode(
      (archive.findFile('word/document.xml')!.content as List<int>),
    );
    expect(documentXml, contains('<w:pStyle w:val="Heading1"/>'),
        reason: '标题样式应写入');
    expect(documentXml, contains('<w:numPr>'));
    expect(documentXml, contains('<w:strike/>'));
    expect(documentXml, contains('<w:br/>'));
    expect(documentXml, contains('def f():'));
    expect(archive.findFile('word/numbering.xml'), isNotNull);

    expect(html, contains('<pre><code class="language-python">'));
    expect(html, contains('<del>☑'));
    expect(html, contains('<ol>'));
    expect(markdown, contains('```python'));
    expect(markdown, contains('- [x]'));
    expect(pdf.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]);
  });

  testWidgets('editor inserts a new code card from the toolbar',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-code-insert-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      await state.createNote(title: '空白');
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 1),
          home: Scaffold(body: EditorPage(onBack: () {})),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byTooltip('代码块'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('代码块'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('code-block-input')),
      'print("hello")',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('code-block-input')))
          .controller!
          .text,
      'print("hello")',
    );
    await tester.tap(find.byKey(const Key('code-block-save')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    final text = deltaPlainText(
      state.session!.controller.document.toDelta(),
    );
    expect(text, contains('print("hello")'));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    state.dispose();
  });

  testWidgets('editor renders and edits a code card', (tester) async {    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final temp = Directory.systemTemp.createTempSync('thisnote-code-card-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });

    late AppState state;
    await tester.runAsync(() async {
      state = AppState(store: NoteStore(rootOverride: temp.path));
      await state.init();
      final note = await state.importMarkdown(
        content: '```python\nprint(1)\n```\n',
        filename: 'code.md',
      );
      await state.openNote(note.id, autofocus: false);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light, 1),
          home: Scaffold(body: EditorPage(onBack: () {})),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('Python'), findsWidgets);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().contains('print(1)'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('编辑代码'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('代码块'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('code-block-input')),
      'print(2)',
    );
    await tester.tap(find.text('保存'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    final text = deltaPlainText(
      state.session!.controller.document.toDelta(),
    );
    expect(text, contains('print(2)'));

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    state.dispose();
  });
}
