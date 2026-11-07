import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('崩溃草稿会被发现并可恢复', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-journal-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();
    final note = Note(
      id: 'journal-note',
      title: '旧标题',
      kind: NoteKind.note,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      day: '2026-01-01',
      text: '磁盘上的正文\n',
      delta: [
        {'insert': '磁盘上的正文\n'},
      ],
    );
    await store.saveNote(note);
    await store.saveTemplates(const []);

    final entry = JournalEntry(
      id: note.id,
      title: '恢复后的标题',
      delta: [
        {'insert': '崩溃前写下的最后一句\n'},
      ],
      text: '崩溃前写下的最后一句\n',
      savedAt: DateTime(2026, 1, 2),
    );
    await store.saveJournal(note.id, entry.toJson());

    final state = AppState(store: NoteStore(rootOverride: temp.path));
    addTearDown(state.dispose);
    await state.init();
    expect(state.pendingRecovery, hasLength(1));

    await state.recoverJournal(state.pendingRecovery.first);
    expect(state.pendingRecovery, isEmpty);
    final restored = await state.store.loadNote(note.id);
    expect(restored?.title, '恢复后的标题');
    expect(restored?.text, contains('崩溃前写下的最后一句'));
    expect(state.current?.id, note.id);
  });
}