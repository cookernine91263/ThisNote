import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/templates.dart';

class NoteStore {
  NoteStore({this.rootOverride});
  final String? rootOverride;

  late Directory root;
  late Directory notesDir;
  late Directory historyDir;
  late Directory assetsDir;

  bool _initialized = false;

  String get dataPath => root.path;

  Future<void> init() async {
    if (_initialized) return;
    if (rootOverride != null) {
      root = Directory(rootOverride!);
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final base = appData == null || appData.isEmpty
          ? (await getApplicationSupportDirectory()).path
          : appData;
      root = Directory(p.join(base, 'ThisNote', 'data'));
    } else {
      final base = await getApplicationSupportDirectory();
      root = Directory(p.join(base.path, 'ThisNote'));
    }
    notesDir = Directory(p.join(root.path, 'notes'));
    historyDir = Directory(p.join(root.path, 'history'));
    assetsDir = Directory(p.join(root.path, 'assets'));
    for (final d in [root, notesDir, historyDir, assetsDir]) {
      if (!await d.exists()) await d.create(recursive: true);
    }
    _initialized = true;
  }

  File get _libraryFile => File(p.join(root.path, 'library.json'));
  File get _settingsFile => File(p.join(root.path, 'settings.json'));

  File _noteFile(String id) => File(p.join(notesDir.path, '$id.json'));

  Future<List<NoteMeta>> loadLibrary() async {
    if (await _libraryFile.exists()) {
      try {
        final raw = await _libraryFile.readAsString();
        final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
        final metas = list.map(NoteMeta.fromJson).toList();
        if (metas.isNotEmpty) return _sorted(metas);
      } catch (_) {
        // 损坏则从 note 文件重建
      }
    }
    return rebuildLibrary();
  }

  Future<List<NoteMeta>> rebuildLibrary() async {
    final metas = <NoteMeta>[];
    if (await notesDir.exists()) {
      await for (final entity in notesDir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        try {
          final j = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
          metas.add(Note.fromJson(j).toMeta());
        } catch (_) {}
      }
    }
    if (metas.isNotEmpty) await persistLibrary(metas);
    return _sorted(metas);
  }

  List<NoteMeta> _sorted(List<NoteMeta> metas) {
    metas.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return metas;
  }

  Future<void> persistLibrary(List<NoteMeta> metas) async {
    final raw = jsonEncode(metas.map((e) => e.toJson()).toList());
    await _writeAtomic(_libraryFile, raw);
  }

  Future<Note?> loadNote(String id) async {
    final f = _noteFile(id);
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return Note.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveNote(Note note) async {
    await _writeAtomic(_noteFile(note.id), jsonEncode(note.toJson()));
  }

  Future<void> deleteNoteFile(String id) async {
    final f = _noteFile(id);
    if (await f.exists()) await f.delete();
    final h = Directory(p.join(historyDir.path, id));
    if (await h.exists()) await h.delete(recursive: true);
  }

  Future<void> saveSnapshot(Note note) async {
    final dir = Directory(p.join(historyDir.path, note.id));
    if (!await dir.exists()) await dir.create(recursive: true);
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final snap = Snapshot(
      savedAt: DateTime.now(),
      title: note.title,
      delta: note.delta,
      text: note.text,
      words: note.words,
    );
    await _writeAtomic(
      File(p.join(dir.path, '$stamp.json')),
      jsonEncode(snap.toJson()),
    );
    final files = await dir.list().where((e) => e is File).toList();
    files.sort((a, b) => b.path.compareTo(a.path));
    for (var i = 40; i < files.length; i++) {
      try {
        await files[i].delete();
      } catch (_) {}
    }
  }

  Future<List<Snapshot>> loadSnapshots(String id) async {
    final dir = Directory(p.join(historyDir.path, id));
    if (!await dir.exists()) return [];
    final result = <Snapshot>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
        result.add(Snapshot.fromJson(j));
      } catch (_) {}
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
  }

  Future<String> saveAsset(Uint8List bytes, String ext) async {
    final safeExt = ext.replaceAll('.', '').toLowerCase();
    final name = '${DateTime.now().microsecondsSinceEpoch}_${bytes.length}.$safeExt';
    final f = File(p.join(assetsDir.path, name));
    await f.writeAsBytes(bytes, flush: true);
    return 'assets/$name';
  }

  String resolveAsset(String rel) {
    if (rel.startsWith('assets/')) return p.join(root.path, rel);
    return rel;
  }

  Future<Uint8List?> readAsset(String rel) async {
    final path = resolveAsset(rel);
    final f = File(path);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  Future<AppSettings> loadSettings() async {
    if (!await _settingsFile.exists()) return AppSettings();
    try {
      return AppSettings.fromJsonString(await _settingsFile.readAsString());
    } catch (_) {
      return AppSettings();
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    await _writeAtomic(_settingsFile, jsonEncode(settings.toJson()));
  }

  Future<void> seedIfEmpty(List<NoteMeta> metas) async {
    if (metas.isNotEmpty) return;
    final now = DateTime.now();
    for (final raw in seedNotes(now)) {
      final note = Note.fromJson(raw);
      final buffer = StringBuffer();
      for (final op in note.delta) {
        if (op is Map && op['insert'] is String) {
          buffer.write(op['insert'] as String);
        }
      }
      note.text = buffer.toString().trimRight();
      note.words = countWords(note.text);
      await saveNote(note);
      metas.add(note.toMeta());
    }
    await persistLibrary(metas);
  }

  /// 把所有内容打包成 zip，返回文件路径。
  Future<String> createBackup() async {
    final archive = Archive();
    Future<void> addDirectory(Directory dir, String prefix) async {
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is! File) continue;
        final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
        final data = await entity.readAsBytes();
        archive.addFile(ArchiveFile('$prefix/$rel', data.length, data));
      }
    }

    await addDirectory(notesDir, 'notes');
    await addDirectory(assetsDir, 'assets');
    await addDirectory(historyDir, 'history');
    if (await _libraryFile.exists()) {
      final data = await _libraryFile.readAsBytes();
      archive.addFile(ArchiveFile('library.json', data.length, data));
    }
    if (await _settingsFile.exists()) {
      final data = await _settingsFile.readAsBytes();
      archive.addFile(ArchiveFile('settings.json', data.length, data));
    }
    final bytes = ZipEncoder().encode(archive);
    final name = 'ThisNote-backup-${DateTime.now().millisecondsSinceEpoch}.zip';
    final out = File(p.join(root.path, name));
    await out.writeAsBytes(bytes, flush: true);
    return out.path;
  }

  /// 从 zip 恢复（覆盖当前数据，恢复前会自动做一次备份）。
  Future<int> restoreBackup(String zipPath) async {
    await createBackup();
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    var count = 0;
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      if (name == 'library.json' || name == 'settings.json') {
        final out = File(p.join(root.path, name));
        await out.writeAsBytes(file.content as List<int>, flush: true);
        count++;
      } else if (name.startsWith('notes/') ||
          name.startsWith('assets/') ||
          name.startsWith('history/')) {
        final out = File(p.join(root.path, name));
        await out.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>, flush: true);
        count++;
      }
    }
    return count;
  }

  Future<void> _writeAtomic(File file, String content) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    await tmp.rename(file.path);
  }
}
