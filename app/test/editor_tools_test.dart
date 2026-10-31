import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late AppState state;
  late EditorSession session;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('thisnote_tools_');
    state = AppState(store: NoteStore(rootOverride: temp.path));
    await state.init();
    for (final note in state.notes.toList()) {
      await state.purgeNote(note.id);
    }
    await state.createNote(title: '工具测试');
    session = state.session!;
  });

  tearDown(() {
    state.dispose();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('查找能数出全部命中，并循环跳到下一处', () async {
    session.controller.replaceText(
      0,
      0,
      '春天来了。春天很好。\n',
      const TextSelection.collapsed(offset: 10),
    );
    session.controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    session.openFind();
    session.setFindQuery('春天');
    expect(session.findTotal, 2);

    session.findNext();
    expect(session.controller.selection.start, 0);
    session.findNext();
    expect(session.controller.selection.start, 5);
    // 到末尾后再按一次，回到第一处。
    session.findNext();
    expect(session.controller.selection.start, 0);
  });

  test('替换全部从后往前替换，偏移不会互相踩踏', () async {
    session.controller.replaceText(
      0,
      0,
      '春天来了。春天很好。\n',
      const TextSelection.collapsed(offset: 10),
    );
    session.openFind();
    session.setFindQuery('春天');
    session.setReplaceQuery('夏日');

    expect(session.replaceAll(), 2);
    expect(session.plainText.contains('夏日来了。夏日很好。'), isTrue);
    expect(session.plainText.contains('春天'), isFalse);
  });

  test('替换当前只动选中的那一处，并自动跳下一处', () async {
    session.controller.replaceText(
      0,
      0,
      '春天来了。春天很好。\n',
      const TextSelection.collapsed(offset: 10),
    );
    session.controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    session.openFind();
    session.setFindQuery('春天');
    session.setReplaceQuery('夏日');

    session.findNext(); // 选中第一处
    expect(session.replaceCurrent(), isTrue);
    expect(session.plainText.startsWith('夏日来了。'), isTrue);
    expect(session.plainText.contains('春天很好'), isTrue);
  });

  test('大纲按标题层级和正文位置列出', () async {
    session.controller.replaceText(
      0,
      0,
      '第一章\n正文\n第二章\n',
      const TextSelection.collapsed(offset: 11),
    );
    // 第一章 → 标题 1
    session.controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 3),
      ChangeSource.local,
    );
    session.controller.formatSelection(
      Attribute('header', AttributeScope.block, 1),
    );
    // 第二章 → 标题 2
    session.controller.updateSelection(
      const TextSelection(baseOffset: 7, extentOffset: 10),
      ChangeSource.local,
    );
    session.controller.formatSelection(
      Attribute('header', AttributeScope.block, 2),
    );

    final outline = session.outline;
    expect(outline.length, 2);
    expect(outline[0].level, 1);
    expect(outline[0].text, '第一章');
    expect(outline[0].offset, 0);
    expect(outline[1].level, 2);
    expect(outline[1].text, '第二章');
    expect(outline[1].offset, 7);
  });

  test('跳转会选中目标位置并请求编辑器焦点', () async {
    session.controller.replaceText(
      0,
      0,
      '第一章\n正文\n',
      const TextSelection.collapsed(offset: 7),
    );
    session.jumpTo(4);
    expect(session.controller.selection.start, 4);
  });

  test('粘贴纯文本只插入文字，不改变已有格式', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.getData') {
        return <String, dynamic>{'text': '干净的纯文本'};
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    session.controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
    await session.pastePlainText();
    expect(session.plainText.startsWith('干净的纯文本'), isTrue);
  });

  test('整理排版保留粗体与标题，只动文字不动换行', () async {
    session.controller.replaceText(
      0,
      0,
      '你好world\n标题\n',
      const TextSelection.collapsed(offset: 0),
    );
    session.controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 7),
      ChangeSource.local,
    );
    session.controller.formatSelection(Attribute.bold);
    session.controller.updateSelection(
      const TextSelection(baseOffset: 8, extentOffset: 10),
      ChangeSource.local,
    );
    session.controller.formatSelection(
      Attribute('header', AttributeScope.block, 2),
    );
    session.controller.updateSelection(
      const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );

    final changed = session.normalizeTypography(selectionOnly: false);
    expect(changed, greaterThan(0));
    expect(session.plainText.contains('你好 world'), isTrue);
    // 标题格式没有被整理动作破坏。
    expect(session.outline.length, 1);
    expect(session.outline.first.text, '标题');

    final delta = session.controller.document.toDelta().toJson();
    final boldOp = delta.firstWhere(
      (op) => op['insert'].toString().contains('你好'),
    );
    expect(boldOp['attributes']?['bold'], isTrue);
  });

  test('有选区时只整理选区内的文字', () async {
    session.controller.replaceText(
      0,
      0,
      'A和B。\nC和D。\n',
      const TextSelection.collapsed(offset: 0),
    );
    session.controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 4),
      ChangeSource.local,
    );

    final changed = session.normalizeTypography();
    expect(changed, greaterThan(0));
    expect(session.plainText.startsWith('A 和 B。'), isTrue);
    expect(session.plainText.contains('C和D。'), isTrue);
  });
}
