import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/typography.dart';
import '../data/activity.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/templates.dart';
import '../features/editor/huazi.dart';
import '../services/clipboard_image.dart';
import '../services/markdown_import.dart';

/// 只在状态层生成的几条文案（新建文件夹、副本、导入占位标题）。
const _en = <String, String>{
  '新文件夹': 'New folder',
  '{title} 副本': '{title} (copy)',
  '导入的笔记': 'Imported note',
};

enum SaveStatus { idle, saving, saved, error }

class AppState extends ChangeNotifier {
  AppState({NoteStore? store}) : store = store ?? NoteStore();

  final NoteStore store;
  final Uuid _uuid = const Uuid();

  bool ready = false;
  bool locked = false;
  String? startupError;
  AppSettings settings = AppSettings();
  List<NoteMeta> notes = [];
  List<Folder> folders = [];
  String? folderFilter;
  Note? current;
  EditorSession? session;
  String view = 'today';
  String? tagFilter;
  DateTime? selectedDay;
  String query = '';
  String sort = 'updated';
  SaveStatus saveStatus = SaveStatus.idle;
  String? lastSaveError;

  /// 每天实际写下的字数。今日进度、连续天数、热力图都读它，
  /// 这样续写旧稿也会算进今天。
  ActivityLog activity = ActivityLog();
  Timer? _activityTimer;

  bool _disposed = false;

  Future<void> init() async {
    startupError = null;
    await store.init();
    settings = await store.loadSettings();
    I18n.lang = AppLang.fromCode(settings.language);
    notes = await store.loadLibrary();
    folders = await store.loadFolders();
    activity = await store.loadActivity();
    await store.seedIfEmpty(notes);
    notes = await store.loadLibrary();
    view = settings.lastView;
    if (!const ['today', 'all', 'calendar', 'tags', 'stats', 'trash', 'search']
        .contains(view)) {
      view = 'today';
    }
    sort = settings.sort;
    locked = settings.lockEnabled && (settings.pinHash?.isNotEmpty ?? false);
    ready = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> retryInit() async {
    try {
      await init();
    } catch (e) {
      startupError = e.toString();
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _activityTimer?.cancel();
    session?.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 列表与筛选
  // ---------------------------------------------------------------------------

  List<NoteMeta> get activeNotes =>
      notes.where((n) => !n.isTrashed).toList(growable: false);

  List<NoteMeta> get trashedNotes =>
      notes.where((n) => n.isTrashed).toList(growable: false);

  List<NoteMeta> get visibleNotes {
    Iterable<NoteMeta> list;
    switch (view) {
      case 'trash':
        list = trashedNotes;
        break;
      case 'today':
        final today = dayKey(DateTime.now());
        list = activeNotes.where(
          (n) => n.day == today || dayKey(n.updatedAt) == today,
        );
        break;
      case 'calendar':
        final key = dayKey(selectedDay ?? DateTime.now());
        list = activeNotes.where((n) => n.day == key);
        break;
      case 'tags':
        if (tagFilter == null) {
          list = activeNotes;
        } else {
          list = activeNotes.where((n) => n.tags.contains(tagFilter));
        }
        break;
      default:
        list = activeNotes;
    }
    if (folderFilter != null) {
      if (folderFilter == '__unfiled__') {
        list = list.where((n) => n.folderId == null);
      } else {
        final ids = folderTreeIds(folderFilter!);
        list = list.where(
          (n) => n.folderId != null && ids.contains(n.folderId),
        );
      }
    }
    final q = query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) {
        return n.title.toLowerCase().contains(q) ||
            n.text.toLowerCase().contains(q) ||
            n.tags.any((t) => t.toLowerCase().contains(q));
      });
    }
    final result = list.toList();
    final grouped = view == 'all' || view == 'calendar';
    result.sort((a, b) {
      // 分组视图先按日期倒序，否则「最近更新」会把不同日期交错排在一起，
      // 分组标题会重复出现，手动排序也会被打散。手动排序本质上按天分组，
      // 所以扁平视图里也先按日期排。
      if ((grouped || sort == 'manual') && a.day != b.day) {
        return b.day.compareTo(a.day);
      }
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      switch (sort) {
        case 'created':
          return b.createdAt.compareTo(a.createdAt);
        case 'title':
          return a.title.compareTo(b.title);
        case 'words':
          return b.words.compareTo(a.words);
        case 'manual':
          final byOrder = a.sortOrder.compareTo(b.sortOrder);
          if (byOrder != 0) return byOrder;
          return b.updatedAt.compareTo(a.updatedAt);
        default:
          return b.updatedAt.compareTo(a.updatedAt);
      }
    });
    return result;
  }

  Map<String, int> get tagCounts {
    final map = <String, int>{};
    for (final n in activeNotes) {
      for (final t in n.tags) {
        map[t] = (map[t] ?? 0) + 1;
      }
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  List<String> get allTags => tagCounts.keys.toList();

  // ---------------------------------------------------------------------------
  // 统计
  // ---------------------------------------------------------------------------

  int get totalWords => activeNotes.fold(0, (s, n) => s + n.words);

  /// 每天写下的字数：以活跃度日志为准（续写旧稿也算），
  /// 没有日志的历史日期回退到按创建日归集。
  Map<String, int> get wordsByDay {
    final map = <String, int>{};
    for (final n in activeNotes) {
      map[n.day] = (map[n.day] ?? 0) + n.words;
    }
    for (final entry in activity.days.entries) {
      final recorded = entry.value.words;
      if (recorded > (map[entry.key] ?? 0)) map[entry.key] = recorded;
    }
    return map;
  }

  int get todayWords => wordsByDay[dayKey(DateTime.now())] ?? 0;

  int get streak {
    final map = wordsByDay;
    final written = <String>{
      for (final e in map.entries)
        if (e.value > 0) e.key,
    };
    var cursor = DateTime.now();
    if (!written.contains(dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!written.contains(dayKey(cursor))) return 0;
    }
    var count = 0;
    while (written.contains(dayKey(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  List<DayStat> get last7Days {
    final map = wordsByDay;
    final today = DateTime.now();
    final result = <DayStat>[];
    for (var i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      result.add(DayStat(d, map[dayKey(d)] ?? 0));
    }
    return result;
  }

  /// 最近一年的写作热力图数据（按每天的字数）。
  Map<String, int> get heatmap => wordsByDay;

  int get diaryCount =>
      activeNotes.where((n) => n.kind == NoteKind.diary).length;
  int get essayCount =>
      activeNotes.where((n) => n.kind == NoteKind.essay).length;
  int get noteCount => activeNotes.where((n) => n.kind == NoteKind.note).length;

  // ---------------------------------------------------------------------------
  // 导航
  // ---------------------------------------------------------------------------

  void setView(String v) {
    if (view == v && tagFilter == null && folderFilter == null) return;
    view = v;
    tagFilter = null;
    folderFilter = null;
    if (v == 'today') selectedDay = null;
    if (v != 'search') query = '';
    settings.lastView = v;
    store.saveSettings(settings);
    _notify();
  }

  void selectTag(String tag) {
    view = 'tags';
    tagFilter = tag;
    folderFilter = null;
    _notify();
  }

  void selectDay(DateTime date) {
    view = 'calendar';
    selectedDay = DateTime(date.year, date.month, date.day);
    folderFilter = null;
    _notify();
  }

  void setFolderFilter(String? id) {
    view = 'all';
    tagFilter = null;
    folderFilter = id;
    _notify();
  }

  void setQuery(String q) {
    query = q;
    if (view != 'search' && q.isNotEmpty) view = 'search';
    _notify();
  }

  void setSort(String s) {
    sort = s;
    settings.sort = s;
    store.saveSettings(settings);
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 文件夹与手动排序
  // ---------------------------------------------------------------------------

  List<Folder> rootFolders() {
    final result = folders.where((f) => f.parentId == null).toList();
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  List<Folder> childFolders(String? parentId) {
    final result = folders.where((f) => f.parentId == parentId).toList();
    result.sort((a, b) => a.order.compareTo(b.order));
    return result;
  }

  Folder? folderById(String? id) {
    if (id == null) return null;
    for (final folder in folders) {
      if (folder.id == id) return folder;
    }
    return null;
  }

  Set<String> folderTreeIds(String id) {
    final result = <String>{id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final folder in folders) {
        if (folder.parentId != null &&
            result.contains(folder.parentId) &&
            result.add(folder.id)) {
          changed = true;
        }
      }
    }
    return result;
  }

  int folderCount(String id, {bool includeChildren = true}) {
    final ids = includeChildren ? folderTreeIds(id) : {id};
    return activeNotes
        .where((n) => n.folderId != null && ids.contains(n.folderId))
        .length;
  }

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final siblings = childFolders(parentId);
    final folder = Folder(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? tr('新文件夹', null, _en) : name.trim(),
      parentId: parentId,
      order: siblings.isEmpty ? 0 : siblings.last.order + 10,
    );
    folders.add(folder);
    await store.persistFolders(folders);
    _notify();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final folder = folderById(id);
    if (folder == null) return;
    folder.name = name.trim().isEmpty ? folder.name : name.trim();
    await store.persistFolders(folders);
    _notify();
  }

  Future<void> deleteFolder(String id) async {
    final folder = folderById(id);
    if (folder == null) return;
    final parent = folder.parentId;
    for (final child in folders.where((f) => f.parentId == id)) {
      child.parentId = parent;
    }
    for (final note in notes.where((n) => n.folderId == id)) {
      note.folderId = parent;
    }
    folders.removeWhere((f) => f.id == id);
    if (folderFilter == id) folderFilter = null;
    await store.persistFolders(folders);
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> moveNoteToFolder(String noteId, String? folderId) async {
    final index = notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;
    notes[index].folderId = folderId;
    if (current?.id == noteId) current!.folderId = folderId;
    await store.persistLibrary(notes);
    _notify();
  }

  /// 只把当前看到的顺序写进 sortOrder，不切换排序模式、不通知界面。
  /// 长按开始拖动时调用：这时列表不能重建，否则拖动会被打断。
  void prepareManualOrder() {
    if (sort == 'manual') return;
    final ordered = visibleNotes;
    final seen = <String>{};
    var order = 0;
    for (final note in ordered) {
      seen.add(note.id);
      note.sortOrder = order += 10;
    }
    final rest = notes.where((n) => !seen.contains(n.id)).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final note in rest) {
      note.sortOrder = order += 10;
    }
  }

  /// 把当前看到的顺序冻结成手动顺序。
  Future<void> beginManualOrder() async {
    if (sort == 'manual') return;
    prepareManualOrder();
    sort = 'manual';
    settings.sort = 'manual';
    await store.persistLibrary(notes);
    await store.saveSettings(settings);
    _notify();
  }

  /// 把 [noteId] 移到 [targetId] 的前面或后面。
  /// 只在同一天内允许排序；跨日期返回 false，由界面给出提示。
  Future<bool> reorderNote(
    String noteId,
    String targetId, {
    bool after = false,
  }) async {
    if (noteId == targetId) return false;
    final sourceIndex = notes.indexWhere((n) => n.id == noteId);
    final targetIndex = notes.indexWhere((n) => n.id == targetId);
    if (sourceIndex < 0 || targetIndex < 0) return false;
    final source = notes[sourceIndex];
    final target = notes[targetIndex];
    if (source.isTrashed || target.isTrashed) return false;
    if (source.day != target.day) return false;
    // 没有手动顺序时先把眼前看到的顺序冻结下来，拖完才不会跳。
    prepareManualOrder();

    final group = notes
        .where((n) => n.day == source.day && !n.isTrashed)
        .toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : b.updatedAt.compareTo(a.updatedAt);
      });
    group.removeWhere((n) => n.id == noteId);
    var index = group.indexWhere((n) => n.id == targetId);
    if (index < 0) index = group.length;
    if (after) index += 1;
    group.insert(index.clamp(0, group.length), source);
    for (var i = 0; i < group.length; i++) {
      group[i].sortOrder = (i + 1) * 10;
    }
    sort = 'manual';
    settings.sort = 'manual';
    await store.persistLibrary(notes);
    await store.saveSettings(settings);
    _notify();
    return true;
  }

  Future<void> moveFolder(
    String folderId,
    String targetId, {
    required String mode, // before, after, inside
  }) async {
    if (folderId == targetId) return;
    final folder = folderById(folderId);
    final target = folderById(targetId);
    if (folder == null || target == null) return;
    if (folderTreeIds(folderId).contains(targetId)) return;
    if (mode == 'inside') {
      folder.parentId = targetId;
      final siblings =
          childFolders(targetId).where((f) => f.id != folderId).toList();
      folder.order = siblings.isEmpty ? 0 : siblings.last.order + 10;
    } else {
      final parentId = target.parentId;
      folder.parentId = parentId;
      final siblings = childFolders(parentId).where((f) => f.id != folderId).toList();
      final index = siblings.indexWhere((f) => f.id == targetId);
      final insertAt = mode == 'after' ? index + 1 : index;
      siblings.insert(insertAt.clamp(0, siblings.length), folder);
      for (var i = 0; i < siblings.length; i++) {
        siblings[i].order = (i + 1) * 10;
      }
    }
    await store.persistFolders(folders);
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 笔记
  // ---------------------------------------------------------------------------

  Future<void> openNote(
    String id, {
    bool autofocus = true,
    bool force = false,
  }) async {
    if (current?.id == id) return;
    await closeEditor();
    final note = await store.loadNote(id);
    if (note == null) return;
    final matches = notes.where((n) => n.id == id);
    final meta = matches.isEmpty ? null : matches.first;
    if (meta != null) {
      note.folderId = meta.folderId;
      note.sortOrder = meta.sortOrder;
    }
    current = note;
    session = EditorSession(app: this, note: note);
    saveStatus = SaveStatus.saved;
    _notify();
    // 打开后把光标放进纸里：第一下键盘输入不该被吞掉。
    // 手机上只有"新建"才主动弹键盘，翻看旧笔记不打扰。
    if (autofocus && (force || _isDesktop)) _focusEditorSoon();
  }

  bool get _isDesktop =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  void _focusEditorSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final s = session;
      if (_disposed || s == null) return;
      if (s.titleController.text.trim().isEmpty) {
        s.titleFocus.requestFocus();
      } else {
        s.editorFocus.requestFocus();
      }
    });
  }

  Future<void> closeEditor() async {
    final s = session;
    if (s != null) {
      await s.flush();
      s.dispose();
    }
    session = null;
    current = null;
    saveStatus = SaveStatus.idle;
    await persistActivity();
    _notify();
  }

  /// 关窗/退出前调用：正文与活跃度都落盘，再交给窗口销毁。
  Future<void> closeApp() async {
    await closeEditor();
    await persistActivity();
  }

  Future<Note> createNote({
    NoteKind kind = NoteKind.note,
    NoteTemplate? template,
    DateTime? day,
    String? title,
  }) async {
    final now = DateTime.now();
    final date = day ?? now;
    final t = template ??
        (kind == NoteKind.diary
            ? noteTemplates.firstWhere((e) => e.id == 'diary')
            : kind == NoteKind.essay
                ? noteTemplates.firstWhere((e) => e.id == 'essay')
                : noteTemplates.firstWhere((e) => e.id == 'blank'));
    final note = Note(
      id: _uuid.v4(),
      title: title ?? t.title,
      delta: t.delta,
      text: '',
      kind: kind,
      tags: List.of(t.tags),
      createdAt: date,
      updatedAt: now,
      day: dayKey(date),
    );
    final parts = <String>[];
    for (final op in t.delta) {
      if (op is Map && op['insert'] is String) {
        final s = op['insert'] as String;
        if (s != '\n') parts.add(s);
      }
    }
    note.text = parts.join();
    note.words = countWords(note.text);
    await store.saveNote(note);
    notes.insert(0, note.toMeta());
    await store.persistLibrary(notes);
    await openNote(note.id, force: true);
    saveStatus = SaveStatus.saved;
    _notify();
    return note;
  }

  /// 从 Markdown / 纯文本导入一篇笔记。
  Future<Note> importMarkdown({
    required String content,
    required String filename,
  }) async {
    final parsed = parseMarkdown(
      content,
      fallbackTitle: _titleFromFilename(filename),
    );
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: parsed.title,
      delta: parsed.delta,
      text: parsed.text,
      kind: NoteKind.note,
      tags: <String>[],
      createdAt: now,
      updatedAt: now,
      day: dayKey(now),
      words: countWords(parsed.text),
    );
    await store.saveNote(note);
    notes.insert(0, note.toMeta());
    await store.persistLibrary(notes);
    _notify();
    return note;
  }

  String _titleFromFilename(String name) {
    final base = name.replaceAll(RegExp(r'\.[^.]+$'), '').trim();
    return base.isEmpty ? tr('导入的笔记', null, _en) : base;
  }

  /// 接收从窗口拖进来的文件：图片插入当前笔记，md / txt 导入成新笔记。
  Future<({int images, int imported})> acceptDroppedFiles(
    List<String> paths,
  ) async {
    var images = 0;
    var imported = 0;
    for (final path in paths) {
      final ext = p.extension(path).toLowerCase();
      try {
        if (const ['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']
            .contains(ext)) {
          if (session == null) await createNote();
          final bytes = await File(path).readAsBytes();
          final rel = await store.saveAsset(
            bytes,
            ext.replaceFirst('.', ''),
          );
          session?.insertImage(rel);
          images++;
        } else if (const ['.md', '.markdown', '.txt'].contains(ext)) {
          final content = await File(path).readAsString();
          await importMarkdown(
            content: content,
            filename: p.basename(path),
          );
          imported++;
        }
      } catch (_) {
        // 单个文件失败不影响其它文件
      }
    }
    return (images: images, imported: imported);
  }

  Future<void> updateMeta(NoteMeta meta) async {
    final i = notes.indexWhere((e) => e.id == meta.id);
    if (i >= 0) notes[i] = meta;
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> togglePin(NoteMeta meta) async {
    meta.pinned = !meta.pinned;
    await updateMeta(meta);
  }

  Future<void> toggleFavorite(NoteMeta meta) async {
    meta.favorite = !meta.favorite;
    await updateMeta(meta);
  }

  /// 复制一份，插到列表最前面。返回副本，源笔记不存在时返回 null。
  Future<Note?> duplicateNote(String id) async {    final source = await store.loadNote(id);
    if (source == null) return null;
    final now = DateTime.now();
    final copy = Note.fromJson({
      ...source.toJson(),
      'id': '${source.id}-copy-${now.millisecondsSinceEpoch}',
      'title': tr('{title} 副本', {'title': source.title}, _en),
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });
    await store.saveNote(copy);
    notes.insert(0, copy.toMeta());
    await store.persistLibrary(notes);
    _notify();
    return copy;
  }

  Future<void> trashNote(String id) async {
    final i = notes.indexWhere((e) => e.id == id);
    if (i < 0) return;
    notes[i].deletedAt = DateTime.now();
    await store.persistLibrary(notes);
    if (current?.id == id) await closeEditor();
    _notify();
  }

  Future<void> restoreNote(String id) async {
    final i = notes.indexWhere((e) => e.id == id);
    if (i < 0) return;
    notes[i].deletedAt = null;
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> purgeNote(String id) async {
    notes.removeWhere((e) => e.id == id);
    await store.deleteNoteFile(id);
    await store.persistLibrary(notes);
    if (current?.id == id) await closeEditor();
    _notify();
  }

  Future<void> emptyTrash() async {
    for (final n in trashedNotes) {
      await store.deleteNoteFile(n.id);
    }
    notes.removeWhere((n) => n.isTrashed);
    await store.persistLibrary(notes);
    _notify();
  }

  /// 由 EditorSession 调用，保存正文并同步索引。
  Future<void> persistNote(Note note, {bool snapshot = false}) async {
    saveStatus = SaveStatus.saving;
    _notify();
    try {
      await store.saveNote(note);
      if (snapshot) await store.saveSnapshot(note);
      final meta = note.toMeta();
      final i = notes.indexWhere((e) => e.id == note.id);
      if (i >= 0) {
        notes[i] = meta;
      } else {
        notes.insert(0, meta);
      }
      await store.persistLibrary(notes);
      saveStatus = SaveStatus.saved;
      lastSaveError = null;
    } catch (e) {
      saveStatus = SaveStatus.error;
      lastSaveError = e.toString();
    }
    _notify();
  }

  /// 记录今天实际写下的字数（由 EditorSession 在自动保存时调用）。
  void recordActivity(String noteId, int words) {
    final day = dayKey(DateTime.now());
    final before = activity.wordsOn(day);
    activity.touch(day, noteId, words);
    if (activity.wordsOn(day) == before) return;
    _activityTimer?.cancel();
    _activityTimer = Timer(const Duration(seconds: 2), persistActivity);
    _notify();
  }

  /// 活跃度只是统计，写失败不该影响正文保存。
  Future<void> persistActivity() async {
    _activityTimer?.cancel();
    _activityTimer = null;
    if (activity.days.isEmpty) return;
    activity.pruneBefore(
      dayKey(DateTime.now().subtract(const Duration(days: 400))),
    );
    try {
      await store.saveActivity(activity);
    } catch (_) {}
  }

  Future<void> saveNow() async {
    await session?.flush();
    await persistActivity();
    _notify();
  }

  Future<void> reload() async {
    await closeEditor();
    settings = await store.loadSettings();
    I18n.lang = AppLang.fromCode(settings.language);
    notes = await store.loadLibrary();
    folders = await store.loadFolders();
    query = '';
    tagFilter = null;
    folderFilter = null;
    _notify();
  }

  Future<List<Snapshot>> historyFor(String id) => store.loadSnapshots(id);

  Future<void> restoreSnapshot(Snapshot snapshot) async {
    final s = session;
    if (s == null) return;
    // 先把「现在」留成一个版本：恢复本身也必须是可回溯的。
    await s.flush(snapshot: true);
    s.controller.document = Document.fromJson(snapshot.delta);
    s.titleController.text = snapshot.title;
    s.dirty = true;
    await s.flush();
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 设置
  // ---------------------------------------------------------------------------

  Future<void> updateSettings(void Function(AppSettings s) mutate) async {
    mutate(settings);
    await store.saveSettings(settings);
    _notify();
  }

  Future<void> setThemeMode(ThemeMode mode) => updateSettings((s) => s.themeMode = mode);

  /// 切换界面语言：先改全局状态再通知，MaterialApp 的 locale 跟着换，
  /// 整棵界面树会在同一帧里以新语言重排。
  Future<void> setLanguage(String code) async {
    final next = code == 'en' ? 'en' : 'zh';
    I18n.lang = AppLang.fromCode(next);
    await updateSettings((s) => s.language = next);
  }

  Future<void> setAccent(String accent) => updateSettings((s) => s.accent = accent);

  Future<void> setDailyGoal(int goal) => updateSettings((s) => s.dailyGoal = goal);

  Future<void> saveColor(String hex) async {
    final normalized = hex.toUpperCase();
    await updateSettings((s) {
      final next = <String>[
        normalized,
        ...s.savedColors.where((e) => e.toUpperCase() != normalized),
      ];
      s.savedColors = next.take(14).toList();
    });
  }

  Future<void> removeSavedColor(String hex) async {
    await updateSettings((s) {
      s.savedColors = s.savedColors
          .where((e) => e.toUpperCase() != hex.toUpperCase())
          .toList();
    });
  }

  Future<bool> enableLock(String pin) async {
    final salt = _randomSalt();
    final hash = _hash(pin, salt);
    await updateSettings((s) {
      s.lockEnabled = true;
      s.pinSalt = salt;
      s.pinHash = hash;
    });
    return true;
  }

  Future<void> disableLock(String pin) async {
    if (!verifyPin(pin)) return;
    await updateSettings((s) {
      s.lockEnabled = false;
      s.pinSalt = null;
      s.pinHash = null;
    });
    locked = false;
    _notify();
  }

  bool verifyPin(String pin) {
    final salt = settings.pinSalt;
    final hash = settings.pinHash;
    if (salt == null || hash == null) return false;
    return _hash(pin, salt) == hash;
  }

  void unlock() {
    locked = false;
    _notify();
  }

  void lock() {
    if (!settings.lockEnabled) return;
    locked = true;
    _notify();
  }

  String _randomSalt() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }

  String _hash(String pin, String salt) =>
      sha256.convert(utf8.encode('$salt::$pin::thisnote')).toString();
}

class DayStat {
  DayStat(this.date, this.words);
  final DateTime date;
  final int words;
}

/// 大纲里的一条标题。
class OutlineEntry {
  const OutlineEntry({
    required this.level,
    required this.text,
    required this.offset,
  });

  final int level;
  final String text;
  final int offset;
}

class EditorSession extends ChangeNotifier {
  EditorSession({required this.app, required this.note}) {
    controller = QuillController(
      document: Document.fromJson(note.delta),
      selection: const TextSelection.collapsed(offset: 0),
    );
    titleController = TextEditingController(text: note.title);
    controller.addListener(_onEditorChanged);
    titleController.addListener(_onTitleChanged);
    _lastDelta = jsonEncode(controller.document.toDelta().toJson());
    _lastTitle = titleController.text;
    // 记下「今天第一次打开这篇时」的字数，续写才算得出今天新增了多少。
    app.activity.startSession(dayKey(DateTime.now()), note.id, words);
    _snapshotTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (dirty) flush(snapshot: true);
    });
  }

  final AppState app;
  final Note note;
  late final QuillController controller;
  late final TextEditingController titleController;
  final FocusNode editorFocus = FocusNode();
  final FocusNode titleFocus = FocusNode();
  final ScrollController scrollController = ScrollController();

  Timer? _debounce;
  Timer? _snapshotTimer;
  String _lastDelta = '';
  String _lastTitle = '';
  bool dirty = false;
  DateTime? lastSaved;
  int renderEpoch = 0;

  /// 文档每改一次自增，用来复用字数/纯文本的计算结果。
  int _revision = 0;
  int _wordsRevision = -1;
  int _wordsCache = 0;
  int _plainRevision = -1;
  String _plainCache = '';

  int get words {
    if (_wordsRevision != _revision) {
      _wordsRevision = _revision;
      _wordsCache = countWords(controller.document.toPlainText());
    }
    return _wordsCache;
  }

  /// 当前选中的字数，投稿有字数限制时比总字数更常用。
  int get selectedWords {
    final sel = controller.selection;
    if (sel.isCollapsed || sel.end <= sel.start) return 0;
    final length = controller.document.length;
    final start = sel.start.clamp(0, length);
    final end = sel.end.clamp(0, length);
    if (end <= start) return 0;
    return countWords(controller.document.getPlainText(start, end - start));
  }

  // ---------------------------------------------------------------------------
  // 查找与替换
  // ---------------------------------------------------------------------------

  bool findOpen = false;
  bool findReplaceVisible = false;
  bool findCaseSensitive = false;
  String findQuery = '';
  String replaceQuery = '';

  /// 每次打开查找时自增，用来让输入框重新获得焦点。
  int findFocusTick = 0;

  List<int>? _findCache;
  String _findCacheKey = '';

  List<int> get findMatches {
    if (findQuery.isEmpty) return const <int>[];
    final key = '$findQuery|$findCaseSensitive|${controller.document.length}';
    if (key != _findCacheKey) {
      _findCacheKey = key;
      _findCache = controller.document.search(
        findQuery,
        caseSensitive: findCaseSensitive,
      );
    }
    return _findCache ?? const <int>[];
  }

  int get findTotal => findMatches.length;

  int get findCurrent {
    final matches = findMatches;
    if (matches.isEmpty) return 0;
    final sel = controller.selection;
    if (sel.isCollapsed || sel.end - sel.start != findQuery.length) return 0;
    final index = matches.indexOf(sel.start);
    return index < 0 ? 0 : index + 1;
  }

  void openFind({bool withReplace = false}) {
    findOpen = true;
    if (withReplace) findReplaceVisible = true;
    findFocusTick++;
    final sel = controller.selection;
    if (!sel.isCollapsed && sel.end > sel.start) {
      final picked = controller.document
          .getPlainText(sel.start, sel.end - sel.start)
          .trim();
      if (picked.isNotEmpty && !picked.contains('\n') && picked.length <= 80) {
        findQuery = picked;
      }
    }
    notifyListeners();
  }

  void closeFind() {
    findOpen = false;
    notifyListeners();
  }

  void setFindQuery(String value) {
    findQuery = value;
    notifyListeners();
  }

  void setReplaceQuery(String value) {
    replaceQuery = value;
    notifyListeners();
  }

  void toggleFindCase() {
    findCaseSensitive = !findCaseSensitive;
    notifyListeners();
  }

  void toggleReplaceRow() {
    findReplaceVisible = !findReplaceVisible;
    notifyListeners();
  }

  void findNext({bool backwards = false}) {
    final matches = findMatches;
    if (matches.isEmpty) {
      notifyListeners();
      return;
    }
    final sel = controller.selection;
    // 只有当前选区正好是一处完整命中时，才从它的下一处开始；
    // 否则从光标位置开始找（包括光标正落在命中开头的情况）。
    final onMatch = !sel.isCollapsed &&
        sel.end - sel.start == findQuery.length &&
        matches.contains(sel.start);
    final index = onMatch ? matches.indexOf(sel.start) : -1;
    int target;
    if (index >= 0) {
      target = backwards
          ? matches[(index - 1 + matches.length) % matches.length]
          : matches[(index + 1) % matches.length];
    } else if (backwards) {
      final before = matches.where((m) => m < sel.start).toList();
      target = before.isNotEmpty ? before.last : matches.last;
    } else {
      final after = matches.where((m) => m >= sel.start).toList();
      target = after.isNotEmpty ? after.first : matches.first;
    }
    _selectRange(target, findQuery.length);
    notifyListeners();
  }

  /// 替换当前选中的那一处；没选中命中时先跳到下一处。
  bool replaceCurrent() {
    final matches = findMatches;
    if (matches.isEmpty) return false;
    final sel = controller.selection;
    final length = findQuery.length;
    final onMatch =
        sel.end - sel.start == length && matches.contains(sel.start);
    if (!onMatch) {
      findNext();
      return false;
    }
    controller.replaceText(
      sel.start,
      length,
      replaceQuery,
      TextSelection.collapsed(offset: sel.start + replaceQuery.length),
    );
    findNext();
    return true;
  }

  /// 从后往前替换，避免前面的替换让后面的偏移失效。返回替换处数。
  int replaceAll() {
    final matches = findMatches;
    if (matches.isEmpty) return 0;
    for (final start in matches.reversed) {
      controller.replaceText(
        start,
        findQuery.length,
        replaceQuery,
        TextSelection.collapsed(offset: start + replaceQuery.length),
      );
    }
    notifyListeners();
    return matches.length;
  }

  // ---------------------------------------------------------------------------
  // 大纲
  // ---------------------------------------------------------------------------

  bool outlineOpen = false;

  void toggleOutline() {
    outlineOpen = !outlineOpen;
    if (outlineOpen) findOpen = false;
    notifyListeners();
  }

  List<OutlineEntry> get outline {
    final result = <OutlineEntry>[];
    for (final node in controller.document.root.children) {
      if (node is! Line) continue;
      final level = _headerLevel(node);
      if (level == null) continue;
      final text = node.toPlainText().trim();
      if (text.isEmpty) continue;
      result.add(
        OutlineEntry(level: level, text: text, offset: node.documentOffset),
      );
    }
    return result;
  }

  /// 标题是块级属性，规范位置在段尾的换行上。
  /// 早期模板把 header 写在了文字本身，这里兼容一下，老笔记也能进目录。
  int? _headerLevel(Line line) {
    final own = line.style.attributes[Attribute.header.key]?.value;
    if (own is int) return own;
    for (final leaf in line.children) {
      final value = leaf.style.attributes[Attribute.header.key]?.value;
      if (value is int) return value;
    }
    return null;
  }

  void jumpTo(int offset) {
    final length = controller.document.length;
    final target = offset.clamp(0, length);
    _selectRange(target, 0);
    notifyListeners();
  }

  void _selectRange(int start, int length) {
    final total = controller.document.length;
    final base = start.clamp(0, total);
    final extent = (start + length).clamp(base, total);
    controller.updateSelection(
      TextSelection(baseOffset: base, extentOffset: extent),
      ChangeSource.local,
    );
    editorFocus.requestFocus();
  }

  /// Ctrl+Shift+V：只贴文字，不带网页里的字体和颜色。
  Future<void> pastePlainText() async {    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    final sel = controller.selection;
    final total = controller.document.length;
    final start = sel.start.clamp(0, total);
    final end = sel.end.clamp(0, total);
    controller.replaceText(
      start,
      end - start,
      text,
      TextSelection.collapsed(offset: start + text.length),
    );
    scheduleSave();
  }

  /// 一键整理排版：中英之间加空格、半角标点转全角、省略号规范化。
  /// 有选区时只整理选区，否则整理全文；返回改动了几段文字。
  /// 换行本身不动，所以标题、列表这些块级格式不会被改掉。
  int normalizeTypography({bool selectionOnly = true}) {
    final sel = controller.selection;
    final hasSelection = !sel.isCollapsed && sel.end > sel.start;
    final useSelection = selectionOnly && hasSelection;
    final start = useSelection ? sel.start : 0;
    final end = useSelection ? sel.end : controller.document.length;
    if (end <= start) return 0;

    final changes = <({int offset, int length, String text})>[];
    var offset = 0;
    for (final op in controller.document.toDelta().toJson()) {
      final data = op['insert'];
      if (data is! String) {
        offset += 1;
        continue;
      }
      final opStart = offset;
      offset += data.length;
      final from = start > opStart ? start : opStart;
      final to = end < opStart + data.length ? end : opStart + data.length;
      if (to <= from) continue;

      // 按换行切开，只替换文字片段，保留段尾换行上的块级属性。
      var cursor = from;
      while (cursor < to) {
        final local = cursor - opStart;
        final newline = data.indexOf('\n', local);
        final segmentEnd =
            (newline == -1 || opStart + newline >= to) ? to : opStart + newline;
        if (segmentEnd > cursor) {
          final slice = data.substring(local, segmentEnd - opStart);
          final changed = normalizeChineseTypography(slice);
          if (changed != slice) {
            changes.add((
              offset: cursor,
              length: segmentEnd - cursor,
              text: changed,
            ));
          }
        }
        if (newline == -1 || opStart + newline >= to) break;
        cursor = opStart + newline + 1;
      }
    }

    for (final change in changes.reversed) {
      controller.replaceText(
        change.offset,
        change.length,
        change.text,
        TextSelection.collapsed(offset: change.offset + change.text.length),
      );
    }
    if (changes.isNotEmpty) {
      scheduleSave();
      notifyListeners();
    }
    return changes.length;
  }

  String get plainText {
    if (_plainRevision != _revision) {
      _plainRevision = _revision;
      _plainCache = controller.document.toPlainText().trimRight();
    }
    return _plainCache;
  }

  void _onEditorChanged() {
    final now = jsonEncode(controller.document.toDelta().toJson());
    if (now != _lastDelta) {
      _lastDelta = now;
      _findCacheKey = '';
      _revision++;
      dirty = true;
      notifyListeners();
      scheduleSave();
    }
  }

  void _onTitleChanged() {
    if (titleController.text != _lastTitle) {
      _lastTitle = titleController.text;
      dirty = true;
      notifyListeners();
      scheduleSave();
    }
  }

  void scheduleSave({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      flush();
    } else {
      _debounce = Timer(const Duration(milliseconds: 900), () => flush());
    }
  }

  Future<void> flush({bool snapshot = false}) async {
    _debounce?.cancel();
    if (!dirty && !snapshot) return;
    final text = plainText;
    note.title = titleController.text.trim();
    note.delta = controller.document.toDelta().toJson();
    note.text = text;
    note.words = countWords(text);
    note.updatedAt = DateTime.now();
    if (note.day.isEmpty) note.day = dayKey(note.createdAt);
    app.recordActivity(note.id, note.words);
    dirty = false;
    lastSaved = DateTime.now();
    notifyListeners();
    await app.persistNote(note, snapshot: snapshot);
  }

  /// 标签、心情这类元数据改动不经过正文，dirty 可能还是 false。
  /// 显式标脏，保证立刻落盘并刷新界面。
  Future<void> _flushMeta() async {
    dirty = true;
    await flush();
  }

  Future<void> setMood(int? mood) async {
    note.mood = mood;
    await _flushMeta();
  }

  Future<void> setWeather(String? weather) async {
    note.weather = weather;
    await _flushMeta();
  }

  Future<void> setKind(NoteKind kind) async {
    note.kind = kind;
    await _flushMeta();
  }

  Future<void> setTags(List<String> tags) async {
    note.tags = tags;
    await _flushMeta();
  }

  Future<void> setDay(DateTime day) async {
    note.day = dayKey(day);
    await _flushMeta();
  }

  /// 应用花字。选中文字后才能使用。
  bool applyHuazi(String presetId, {String size = 'm'}) {
    final sel = controller.selection;
    if (sel.isCollapsed || sel.start >= sel.end) return false;
    final preset = huaziPresetById(presetId);
    if (preset == null) return false;
    final style = huaziInlineAttributes(preset, size);
    final delta = Delta()
      ..retain(sel.start)
      ..retain(sel.end - sel.start, style);
    controller.compose(delta, sel, ChangeSource.local);
    // 应用后收起选区，避免选中高亮盖住刚变大的花字。
    controller.updateSelection(
      TextSelection.collapsed(offset: sel.end),
      ChangeSource.local,
    );
    scheduleSave();
    return true;
  }

  void clearFont() {
    controller.formatSelection(Attribute.clone(Attribute.font, null));
    controller.formatSelection(Attribute.clone(Attribute.size, null));
    controller.formatSelection(Attribute.clone(Attribute.bold, null));
    controller.formatSelection(Attribute.clone(Attribute.color, null));
    scheduleSave();
  }

  void applyThin() {
    controller.formatSelection(
      const Attribute<String?>(
        'font',
        AttributeScope.inline,
        'NotoSansSCLight',
      ),
    );
    controller.formatSelection(Attribute.clone(Attribute.bold, null));
    scheduleSave();
  }

  void clearFormatting() {
    for (final attr in <Attribute>[
      Attribute.bold,
      Attribute.italic,
      Attribute.underline,
      Attribute.strikeThrough,
      Attribute.font,
      Attribute.size,
      Attribute.color,
      Attribute.background,
      Attribute.link,
    ]) {
      controller.formatSelection(Attribute.clone(attr, null));
    }
    scheduleSave();
  }

  void insertImage(String relativePath) {
    final sel = controller.selection;
    if (!sel.isCollapsed) {
      controller.document.delete(sel.start, sel.end - sel.start);
    }
    final index = controller.selection.start;
    controller.document.insert(index, BlockEmbed.image(relativePath));
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 1),
      ChangeSource.local,
    );
    scheduleSave(immediate: true);
  }

  /// 从 Windows 剪贴板粘贴一张图（截图、复制的图片）。成功返回 true。
  Future<bool> pasteImageFromClipboard() async {
    if (!Platform.isWindows) return false;
    final png = await ClipboardImage.readPng();
    if (png == null) return false;
    final rel = await app.store.saveAsset(png, 'png');
    insertImage(rel);
    return true;
  }

  void insertDivider() {
    final index = controller.selection.start;
    controller.document.insert(index, const BlockEmbed('divider', 'hr'));
    controller.updateSelection(
      TextSelection.collapsed(offset: index + 1),
      ChangeSource.local,
    );
    scheduleSave(immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _snapshotTimer?.cancel();
    controller.removeListener(_onEditorChanged);
    titleController.removeListener(_onTitleChanged);
    controller.dispose();
    titleController.dispose();
    editorFocus.dispose();
    titleFocus.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
