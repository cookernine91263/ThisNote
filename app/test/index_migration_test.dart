import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('旧 library 的全文会迁到 index，并从 library 移除', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-index-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();
    final note = Note(
      id: 'legacy-note',
      title: '旧稿',
      kind: NoteKind.note,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      day: '2026-01-01',
      text: '这是一段旧稿的全文，用来验证迁移。',
      delta: [
        {'insert': '这是一段旧稿的全文，用来验证迁移。\n'},
      ],
    );
    await File(p.join(temp.path, 'notes', 'legacy-note.json'))
        .writeAsString(jsonEncode(note.toJson()));
    await File(p.join(temp.path, 'library.json')).writeAsString(
      jsonEncode([note.toMeta().toJson()]),
    );

    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(state.dispose);
    await state.init();

    final library = jsonDecode(
      await File(p.join(temp.path, 'library.json')).readAsString(),
    ) as List;
    expect((library.first as Map).containsKey('text'), isFalse);
    expect((library.first as Map)['preview'], contains('旧稿'));
    final index = File(p.join(temp.path, 'index', 'text', 'legacy-note.txt'));
    expect(await index.exists(), isTrue);
    expect(await index.readAsString(), contains('旧稿的全文'));
    expect(state.noteText('legacy-note'), contains('旧稿的全文'));
    expect(
      Directory(p.join(temp.path, 'backups')).listSync(),
      isNotEmpty,
      reason: '迁移前应留一份 v1 library',
    );

    state.setQuery('全文');
    expect(state.visibleNotes.map((n) => n.id), contains('legacy-note'));

    final reopened = AppState(store: NoteStore(rootOverride: temp.path));
    await reopened.init();
    expect(reopened.notes.first.text, isEmpty);
    expect(reopened.noteText('legacy-note'), contains('旧稿的全文'));
    reopened.setQuery('验证');
    expect(reopened.visibleNotes.map((n) => n.id), contains('legacy-note'));
    reopened.dispose();
  });
}