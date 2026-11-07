import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/format.dart';
import '../data/activity.dart';
import '../data/models.dart';
import '../data/templates.dart';

class NoteStore {
  NoteStore({this.rootOverride});
  final String? rootOverride;

  late Directory root;
  late Directory notesDir;
  late Directory historyDir;
  late Directory assetsDir;
  late Directory fontsDir;
  late Directory conversationsDir;
  late Directory indexDir;
  late Directory indexTextDir;
  late Directory journalDir;

  bool _initialized = false;

  String get dataPath => root.path;

  /// Windows 上的默认数据目录。启动早期（还没 init）也要用，所以保持同步。
  /// 设置 THISNOTE_DATA_DIR 可以临时换一个数据目录（便携版、截图与测试都用它）。
  static Directory defaultRootDirectory() {
    final override = Platform.environment['THISNOTE_DATA_DIR'];
    if (override != null && override.trim().isNotEmpty) {
      return Directory(override.trim());
    }
    final appData = Platform.environment['APPDATA'] ??
        Platform.environment['LOCALAPPDATA'] ??
        Directory.current.path;
    return Directory(p.join(appData, 'ThisNote', 'data'));
  }

  /// 同一个数据目录只允许一个进程写。双开会让两份内存状态互相覆盖，
  /// 这不是防抖或原子写能兜住的问题。
  static RandomAccessFile? _processLock;

  static Future<bool> acquireProcessLock() async {
    if (!Platform.isWindows) return true;
    if (_processLock != null) return true;
    try {
      final root = defaultRootDirectory();
      if (!await root.exists()) await root.create(recursive: true);
      final handle = await File(p.join(root.path, '.instance.lock'))
          .open(mode: FileMode.write);
      try {
        handle.lockSync(FileLock.exclusive);
      } catch (_) {
        await handle.close();
        return false;
      }
      _processLock = handle;
      return true;
    } catch (_) {
      // 锁文件本身出问题时不要拦着用户写字。
      return true;
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    if (rootOverride != null) {
      root = Directory(rootOverride!);
    } else if (Platform.isWindows) {
      root = defaultRootDirectory();
    } else {
      final base = await getApplicationSupportDirectory();
      root = Directory(p.join(base.path, 'ThisNote'));
    }
    notesDir = Directory(p.join(root.path, 'notes'));
    historyDir = Directory(p.join(root.path, 'history'));
    assetsDir = Directory(p.join(root.path, 'assets'));
    fontsDir = Directory(p.join(root.path, 'fonts'));
    conversationsDir = Directory(p.join(root.path, 'conversations'));
    indexDir = Directory(p.join(root.path, 'index'));
    indexTextDir = Directory(p.join(indexDir.path, 'text'));
    journalDir = Directory(p.join(root.path, 'journal'));
    for (final d in [
      root,
      notesDir,
      historyDir,
      assetsDir,
      fontsDir,
      conversationsDir,
      indexDir,
      indexTextDir,
      journalDir,
    ]) {
      if (!await d.exists()) await d.create(recursive: true);
    }
    _initialized = true;
  }

  File get _libraryFile => File(p.join(root.path, 'library.json'));
  File get _settingsFile => File(p.join(root.path, 'settings.json'));
  File get _foldersFile => File(p.join(root.path, 'folders.json'));
  File get _activityFile => File(p.join(root.path, 'activity.json'));
  File get _templatesFile => File(p.join(root.path, 'templates.json'));

  /// 先读正文，读不出来再退到上一次写入留下的 .bak。
  Future<String?> _readWithBackup(File file) async {
    for (final f in [file, File('${file.path}.bak')]) {
      try {
        if (!await f.exists()) continue;
        final raw = await f.readAsString();
        if (raw.trim().isNotEmpty) return raw;
      } catch (_) {
        // 损坏就试下一个
      }
    }
    return null;
  }

  File _noteFile(String id) => File(p.join(notesDir.path, '$id.json'));

  Future<List<NoteMeta>> loadLibrary() async {
    final raw = await _readWithBackup(_libraryFile);
    if (raw != null) {
      try {
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
    // 索引只写摘要；全文在 notes/ 与 index/text/ 里，不再重复塞进 library。
    final raw = jsonEncode(metas.map((e) => e.toIndexJson()).toList());
    await _writeAtomic(_libraryFile, raw);
  }

  File _indexTextFile(String id) =>
      File(p.join(indexTextDir.path, '$id.txt'));

  Future<Map<String, String>> loadIndexTexts() {
    final path = indexTextDir.path;
    return Isolate.run(() => _loadIndexAt(path));
  }

  Future<void> rebuildIndex(List<NoteMeta> metas) async {
    for (final meta in metas) {
      var text = meta.text;
      if (text.isEmpty) {
        final note = await loadNote(meta.id);
        text = note?.text ?? '';
      }
      await _writeAtomic(_indexTextFile(meta.id), text);
      meta.preview = excerptOf(text);
    }
  }

  /// 迁移前把旧 library 单独留一份；失败时还能用旧读取器启动。
  Future<void> backupLibraryForMigration() async {
    if (!await _libraryFile.exists()) return;
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final dir = Directory(p.join(root.path, 'backups', 'v1-$stamp'));
    await dir.create(recursive: true);
    await _libraryFile.copy(p.join(dir.path, 'library.json'));
  }

  Future<List<Folder>> loadFolders() async {
    final raw = await _readWithBackup(_foldersFile);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list.map(Folder.fromJson).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> persistFolders(List<Folder> folders) async {
    await _writeAtomic(
      _foldersFile,
      jsonEncode(folders.map((e) => e.toJson()).toList()),
    );
  }

  Future<Note?> loadNote(String id) async {
    // 主文件可能是写到一半断电留下的半截 JSON，这种情况也要退到 .bak。
    final file = _noteFile(id);
    for (final candidate in [file, File('${file.path}.bak')]) {
      try {
        if (!await candidate.exists()) continue;
        final raw = await candidate.readAsString();
        if (raw.trim().isEmpty) continue;
        return Note.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } catch (_) {
        // 换下一个候选
      }
    }
    return null;
  }

  Future<void> saveNote(Note note) async {
    await _writeAtomic(_noteFile(note.id), jsonEncode(note.toJson()));
    await _writeAtomic(_indexTextFile(note.id), note.text);
  }

  Future<void> deleteNoteFile(String id) async {
    for (final path in [_noteFile(id).path, '${_noteFile(id).path}.bak']) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    final index = _indexTextFile(id);
    if (await index.exists()) {
      try {
        await index.delete();
      } catch (_) {}
    }
    await deleteJournal(id);
    final h = Directory(p.join(historyDir.path, id));
    if (await h.exists()) await h.delete(recursive: true);
    await deleteConversation(id);
  }

  File _conversationFile(String noteId) =>
      File(p.join(conversationsDir.path, '$noteId.json'));

  Future<AiConversation?> loadConversation(String noteId) async {
    final raw = await _readWithBackup(_conversationFile(noteId));
    if (raw == null) return null;
    try {
      return AiConversation.fromJson(
        noteId,
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveConversation(AiConversation conversation) =>
      _writeAtomic(
        _conversationFile(conversation.noteId),
        jsonEncode(conversation.toJson()),
      );

  Future<void> deleteConversation(String noteId) async {
    final file = _conversationFile(noteId);
    for (final path in [file.path, '${file.path}.bak']) {
      final f = File(path);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
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

  /// 保存用户导入的字体文件，返回 `fonts/` 下的文件名。
  Future<String> saveFont(Uint8List bytes, String ext) async {
    final safeExt = ext.replaceAll('.', '').toLowerCase();
    final name =
        '${DateTime.now().microsecondsSinceEpoch}_${bytes.length}.$safeExt';
    await File(p.join(fontsDir.path, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  String resolveFont(String file) => p.join(fontsDir.path, file);

  Future<void> deleteFont(String file) async {
    final f = File(resolveFont(file));
    if (await f.exists()) {
      try {
        await f.delete();
      } catch (_) {
        // 文件被占用时先留着，下次启动不会再加载它。
      }
    }
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
    final raw = await _readWithBackup(_settingsFile);
    if (raw == null) return AppSettings();
    try {
      return AppSettings.fromJsonString(raw);
    } catch (_) {
      return AppSettings();
    }
  }

  Future<ActivityLog> loadActivity() async {
    return ActivityLog.decode(await _readWithBackup(_activityFile));
  }

  Future<List<UserTemplate>> loadTemplates() async {
    final raw = await _readWithBackup(_templatesFile);
    if (raw == null) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return list
          .map(UserTemplate.fromJson)
          .where((template) => template.valid)
          .toList();
    } catch (_) {
      return [];
    }
  }

  File _journalFile(String id) => File(p.join(journalDir.path, '$id.json'));

  Future<void> saveJournal(String id, Map<String, dynamic> data) async {
    await _writeAtomic(_journalFile(id), jsonEncode(data));
  }

  Future<List<JournalEntry>> loadJournals() async {
    final result = <JournalEntry>[];
    if (!await journalDir.exists()) return result;
    await for (final entity in journalDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(await entity.readAsString());
        if (json is Map) {
          final entry = JournalEntry.fromJson(json.cast<String, dynamic>());
          if (entry.id.isNotEmpty) result.add(entry);
        }
      } catch (_) {}
    }
    result.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return result;
  }

  Future<void> deleteJournal(String id) async {
    final file = _journalFile(id);
    if (!await file.exists()) return;
    try {
      await file.delete();
    } catch (_) {}
  }

  Future<void> saveTemplates(List<UserTemplate> templates) async {
    await _writeAtomic(
      _templatesFile,
      jsonEncode(templates.map((template) => template.toJson()).toList()),
    );
  }

  Future<void> saveActivity(ActivityLog log) async {
    await _writeAtomic(_activityFile, log.encode());
  }

  Future<void> saveSettings(
    AppSettings settings, {
    bool includeSecrets = true,
  }) async {
    await _writeAtomic(
      _settingsFile,
      jsonEncode(settings.toJson(includeSecrets: includeSecrets)),
    );
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

  /// 把所有内容打包成 zip，返回文件路径。压缩在独立 isolate 里跑。
  Future<String> createBackup() {
    final path = root.path;
    return Isolate.run(() => _createBackupAt(path));
  }

  Future<Map<String, dynamic>?> readBackupManifest(String zipPath) {
    final path = zipPath;
    return Isolate.run(() => _readManifestAt(path));
  }

  /// 从 zip 恢复（覆盖当前数据，恢复前会自动做一次备份）。
  Future<int> restoreBackup(String zipPath) {
    final path = root.path;
    return Isolate.run(() => _restoreBackupAt(path, zipPath));
  }

  /// 同一个文件的写入串行执行：切换视图、改设置都可能连续触发保存，
  /// 两个写入共用 settings.json.tmp 时会在 Windows 上抢同一个重命名。
  static final Map<String, Future<void>> _writeChains = <String, Future<void>>{};

  Future<void> _writeAtomic(File file, String content) {
    final key = file.path;
    final previous = _writeChains[key] ?? Future<void>.value();
    final next = previous
        .catchError((Object _) {})
        .then((_) => _writeNow(file, content));
    _writeChains[key] = next;
    return next.whenComplete(() {
      if (identical(_writeChains[key], next)) _writeChains.remove(key);
    });
  }

  /// 等待所有排队中的写入结束（测试收尾、退出前都可以用）。
  Future<void> flushWrites() async {
    while (_writeChains.isNotEmpty) {
      await Future.wait(_writeChains.values.toList());
    }
  }

  Future<void> _writeNow(File file, String content) async {
    final tmp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(content, flush: true);
    if (await file.exists()) {
      // 先把旧文件留成 .bak：删旧名和改名之间若断电，还能从 .bak 读回上一版。
      try {
        await file.copy('${file.path}.bak');
      } catch (_) {}
      try {
        await file.delete();
      } catch (_) {}
    }
    await tmp.rename(file.path);
  }
}

Future<Map<String, String>> _loadIndexAt(String dirPath) async {
  final result = <String, String>{};
  final dir = Directory(dirPath);
  if (!await dir.exists()) return result;
  await for (final entity in dir.list()) {
    if (entity is! File || !entity.path.endsWith('.txt')) continue;
    try {
      result[p.basenameWithoutExtension(entity.path)] =
          await entity.readAsString();
    } catch (_) {
      // 单个索引损坏时退回全文重建。
    }
  }
  return result;
}

Future<Map<String, dynamic>?> _readManifestAt(String zipPath) async {
  final file = File(zipPath);
  if (!await file.exists()) return null;
  final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
  for (final entry in archive.files) {
    if (entry.name != 'backup-manifest.json') continue;
    final decoded = jsonDecode(
      utf8.decode(entry.content as List<int>, allowMalformed: true),
    );
    return decoded is Map ? decoded.cast<String, dynamic>() : null;
  }
  return null;
}

Future<String> _createBackupAt(String rootPath) async {
  final root = Directory(rootPath);
  final archive = Archive();
  Future<void> addDirectory(String name, String prefix) async {
    final dir = Directory(p.join(root.path, name));
    if (!await dir.exists()) return;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      final rel = p.relative(entity.path, from: dir.path).replaceAll('\\', '/');
      final data = await entity.readAsBytes();
      archive.addFile(ArchiveFile('$prefix/$rel', data.length, data));
    }
  }

  for (final entry in const {
    'notes': 'notes',
    'assets': 'assets',
    'history': 'history',
    'fonts': 'fonts',
    'conversations': 'conversations',
    'index': 'index',
    'journal': 'journal',
  }.entries) {
    await addDirectory(entry.key, entry.value);
  }
  for (final name in const [
    'library.json',
    'settings.json',
    'folders.json',
    'activity.json',
    'templates.json',
  ]) {
    final file = File(p.join(root.path, name));
    if (!await file.exists()) continue;
    final data = await file.readAsBytes();
    archive.addFile(ArchiveFile(name, data.length, data));
  }
  final manifest = utf8.encode(
    jsonEncode({
      'app': 'ThisNote',
      'format': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'files': archive.files
          .where((file) => file.isFile)
          .map((file) => file.name)
          .toList(growable: false),
    }),
  );
  archive.addFile(
    ArchiveFile('backup-manifest.json', manifest.length, manifest),
  );
  final bytes = ZipEncoder().encode(archive);
  final name = 'ThisNote-backup-${DateTime.now().millisecondsSinceEpoch}.zip';
  final out = File(p.join(root.path, name));
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}

Future<int> _restoreBackupAt(String rootPath, String zipPath) async {
  await _createBackupAt(rootPath);
  final root = Directory(rootPath);
  final bytes = await File(zipPath).readAsBytes();
  final archive = ZipDecoder().decodeBytes(bytes);
  var count = 0;
  for (final file in archive) {
    if (!file.isFile) continue;
    final name = file.name.replaceAll('\\', '/');
    if (name == 'backup-manifest.json') continue;
    final isRootFile = const {
      'library.json',
      'settings.json',
      'folders.json',
      'activity.json',
      'templates.json',
    }.contains(name);
    final isFolderFile = name.startsWith('notes/') ||
        name.startsWith('assets/') ||
        name.startsWith('fonts/') ||
        name.startsWith('history/') ||
        name.startsWith('conversations/') ||
        name.startsWith('index/') ||
        name.startsWith('journal/');
    if (!isRootFile && !isFolderFile) continue;
    final out = File(p.join(root.path, name));
    await out.create(recursive: true);
    await out.writeAsBytes(file.content as List<int>, flush: true);
    count++;
  }
  return count;
}
