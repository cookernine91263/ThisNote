import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('备份包含 manifest，恢复后笔记仍在', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-backup-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();
    await store.seedIfEmpty([]);
    final before = await store.loadLibrary();
    expect(before, isNotEmpty);

    final path = await store.createBackup();
    final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
    final manifests = archive.files
        .where((file) => file.name == 'backup-manifest.json')
        .toList();
    expect(manifests, isNotEmpty);
    final json = jsonDecode(
      utf8.decode(manifests.first.content as List<int>),
    ) as Map<String, dynamic>;
    expect(json['app'], 'ThisNote');
    expect((json['files'] as List), isNotEmpty);

    final restored = await store.restoreBackup(path);
    expect(restored, greaterThan(0));
    final after = await store.loadLibrary();
    expect(after.map((meta) => meta.id).toSet(),
        before.map((meta) => meta.id).toSet());
  });
}