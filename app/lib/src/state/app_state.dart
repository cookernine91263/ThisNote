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
import '../features/editor/code_block.dart';
import '../features/editor/huazi.dart';
import '../services/clipboard_image.dart';
import '../services/docx_import.dart';
import '../services/markdown_import.dart';
import '../services/secrets_store.dart';
import '../services/search_replace.dart';
import 'ai_chat.dart';

/// 只在状态层生成的几条文案（新建文件夹、副本、导入占位标题）。
const _en = <String, String>{
  '新文件夹': 'New folder',
  '{title} 副本': '{title} (copy)',
  '导入的笔记': 'Imported note',
  '无题': 'Untitled',
};

enum SaveStatus { idle, saving, saved, error }

class AppState extends ChangeNotifier {
  AppState({NoteStore? store}) : store = store ?? NoteStore();

  final NoteStore store;
  final SecretsStore secrets = SecretsStore();
  final Uuid _uuid = const Uuid();
  bool _secretsExternal = false;

  bool ready = false;
  bool locked = false;
  String? startupError;
  AppSettings settings = AppSettings();
  List<NoteMeta> notes = [];
  List<UserTemplate> userTemplates = [];
  List<Folder> folders = [];
  List<JournalEntry> pendingRecovery = [];
  Map<String, String> _indexTexts = <String, String>{};
  int _dataRevision = 0;
  int _tagRevision = -1;
  Map<String, int> _tagCache = const {};
  int _dayRevision = -1;
  Map<String, int> _dayCache = const {};
  int _foldersRevision = 0;
  int _settingsRevision = 0;
  String _visibleKey = '';
  List<NoteMeta> _visibleCache = const [];

  void _touchData() => _dataRevision++;
  void _touchFolders() => _foldersRevision++;

  int get dataRevision => _dataRevision;
  int get foldersRevision => _foldersRevision;
  int get settingsRevision => _settingsRevision;
  String? folderFilter;
  Note? current;
  EditorSession? session;

  /// 桌面分屏的第二个编辑会话。
  Note? secondaryNote;
  EditorSession? secondarySession;
  String view = 'today';
  String? tagFilter;
  DateTime? selectedDay;
  String query = '';
  String _filterQuery = '';
  Timer? _queryTimer;
  String sort = 'updated';
  SaveStatus saveStatus = SaveStatus.idle;
  String? lastSaveError;

  /// 每天实际写下的字数。今日进度、连续天数、热力图都读它，
  /// 这样续写旧稿也会算进今天。
  ActivityLog activity = ActivityLog();
  Timer? _activityTimer;
  Timer? _libraryTimer;
  Timer? _settingsTimer;

  bool _disposed = false;

  Future<void> init() async {
    startupError = null;
    await store.init();
    settings = await store.loadSettings();
    await _loadSecrets();
    I18n.lang = AppLang.fromCode(settings.language);
    notes = await store.loadLibrary();
    folders = await store.loadFolders();
    activity = await store.loadActivity();
    userTemplates = await store.loadTemplates();
    await store.seedIfEmpty(notes);
    await _prepareIndex();
    await _prepareRecovery();
    // 用户字体只影响个别笔记，没必要挡住首帧；注册完再通知一次即可。
    unawaited(_loadCustomFonts().then((_) => _notify()));
    const listViews = {
      'today',
      'all',
      'time',
      'favorites',
      'tags',
      'trash',
      'search',
    };
    if (!listViews.contains(settings.lastListView)) {
      settings.lastListView = 'today';
    }
    view = settings.lastView;
    // 回收站和搜索只是临时视图：重启后回到上次的列表，避免一开机就停在回收站。
    if (view == 'trash' || view == 'search') view = settings.lastListView;
    if (!const [
      'today',
      'all',
      'time',
      'calendar',
      'tags',
      'stats',
      'trash',
      'search',
    ].contains(view)) {
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

  Future<void> _loadSecrets() async {
    final apiKey = await secrets.read('ai_api_key');
    final password = await secrets.read('webdav_password');
    if (apiKey != null) settings.aiSettings.apiKey = apiKey;
    if (password != null) settings.webdavSettings.password = password;
    _secretsExternal = apiKey != null || password != null;
    // 旧版本把密钥放在 settings.json 里：能写进钥匙串就顺手迁走。
    if (!_secretsExternal) {
      if (settings.aiSettings.apiKey.isNotEmpty) {
        _secretsExternal = await secrets.write(
          'ai_api_key',
          settings.aiSettings.apiKey,
        );
      }
      if (settings.webdavSettings.password.isNotEmpty) {
        final ok = await secrets.write(
          'webdav_password',
          settings.webdavSettings.password,
        );
        _secretsExternal = _secretsExternal || ok;
      }
      if (_secretsExternal) await _persistSettings();
    }
  }

  Future<void> _persistSettings() async {
    if (_secretsExternal) {
      if (settings.aiSettings.apiKey.isEmpty) {
        await secrets.delete('ai_api_key');
      } else {
        await secrets.write('ai_api_key', settings.aiSettings.apiKey);
      }
      if (settings.webdavSettings.password.isEmpty) {
        await secrets.delete('webdav_password');
      } else {
        await secrets.write(
          'webdav_password',
          settings.webdavSettings.password,
        );
      }
    }
    await store.saveSettings(settings, includeSecrets: !_secretsExternal);
  }

  Future<void> _prepareRecovery() async {
    final entries = await store.loadJournals();
    final valid = <JournalEntry>[];
    for (final entry in entries) {
      final matches = notes.where((meta) => meta.id == entry.id);
      final meta = matches.isEmpty ? null : matches.first;
      if (meta == null || entry.savedAt.isAfter(meta.updatedAt)) {
        valid.add(entry);
      } else {
        await store.deleteJournal(entry.id);
      }
    }
    pendingRecovery = valid;
  }

  Future<void> recoverJournal(JournalEntry entry) async {
    final note = await store.loadNote(entry.id);
    if (note != null) {
      note.title = entry.title;
      note.delta = entry.delta;
      note.text = entry.text;
      note.words = countWords(entry.text);
      note.updatedAt = DateTime.now();
      await store.saveNote(note);
      final index = notes.indexWhere((meta) => meta.id == note.id);
      if (index >= 0) {
        notes[index] = note.toMeta();
      } else {
        notes.insert(0, note.toMeta());
      }
      _indexTexts[note.id] = note.text;
      await store.persistLibrary(notes);
      await openNote(note.id, force: true);
    }
    await store.deleteJournal(entry.id);
    pendingRecovery = pendingRecovery
        .where((item) => item.id != entry.id)
        .toList(growable: false);
    _notify();
  }

  Future<void> discardJournal(JournalEntry entry) async {
    await store.deleteJournal(entry.id);
    pendingRecovery = pendingRecovery
        .where((item) => item.id != entry.id)
        .toList(growable: false);
    _notify();
  }

  Future<void> _prepareIndex() async {
    var index = await store.loadIndexTexts();
    final legacy = notes.any((meta) => meta.text.isNotEmpty);
    final missing = notes.any((meta) => !index.containsKey(meta.id));
    if (legacy) await store.backupLibraryForMigration();
    if (legacy || missing) {
      await store.rebuildIndex(notes);
      index = await store.loadIndexTexts();
      await store.persistLibrary(notes);
    }
    _indexTexts = index;
  }

  /// 列表搜索、反链和替换都从这里取全文；当前打开的笔记优先用未保存的草稿。
  String noteText(String id) {
    final active = session;
    if (active != null && active.note.id == id) return active.plainText;
    final second = secondarySession;
    if (second != null && second.note.id == id) return second.plainText;
    final indexed = _indexTexts[id];
    if (indexed != null) return indexed;
    final matches = notes.where((meta) => meta.id == id);
    return matches.isEmpty ? '' : matches.first.text;
  }

  Future<void> retryInit() async {
    try {
      await init();
    } catch (e) {
      reportStartupError(e);
    }
  }

  void reportStartupError(Object error) {
    startupError = error.toString();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _activityTimer?.cancel();
    _libraryTimer?.cancel();
    _settingsTimer?.cancel();
    _queryTimer?.cancel();
    session?.dispose();
    secondarySession?.dispose();
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
    final key = '$view|$tagFilter|$folderFilter|$_filterQuery|$sort|'
        '${selectedDay?.millisecondsSinceEpoch}|$_dataRevision|$_foldersRevision';
    if (key == _visibleKey) return _visibleCache;
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
      case 'time':
        list = activeNotes;
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
      case 'favorites':
        list = activeNotes.where((n) => n.favorite);
        break;
      default:
        list = activeNotes;
    }
    // 「全部」是文件式的平铺列表：文件夹卡片代替里面的笔记，
    // 所以这里只留下本层的笔记；进入文件夹后也只显示直属笔记。
    if (view == 'all') {
      if (folderFilter == null || folderFilter == '__unfiled__') {
        list = list.where((n) => n.folderId == null);
      } else {
        list = list.where((n) => n.folderId == folderFilter);
      }
    }
    final q = _filterQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((n) {
        return n.title.toLowerCase().contains(q) ||
            noteText(n.id).toLowerCase().contains(q) ||
            n.tags.any((t) => t.toLowerCase().contains(q));
      });
    }
    final result = list.toList();
    final grouped = view == 'time' || view == 'calendar';
    result.sort((a, b) {
      // 「时间」按天分组倒序；「全部」是平铺的，不插日期标题。
      if (grouped && a.day != b.day) return b.day.compareTo(a.day);
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return compareSort(a, b);
    });
    // 「全部」里固定的笔记停在手动顺序的位置，不参与「最近 / 创建 / 字数」重排。
    final ordered = view == 'all' && sort != 'manual'
        ? _withFixedAnchors(result)
        : result;
    _visibleKey = key;
    _visibleCache = ordered;
    return ordered;
  }

  int compareSort(NoteMeta a, NoteMeta b) {
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
  }

  /// 固定笔记按记录下来的顺序位置插回排好序的列表：
  /// 其它笔记在空位之间正常排序，固定笔记本身不会被「最近修改」顶下去。
  List<NoteMeta> _withFixedAnchors(List<NoteMeta> sorted) {
    final fixed = sorted.where((n) => n.fixed && !n.pinned).toList();
    if (fixed.isEmpty) return sorted;
    fixed.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final movable = sorted.where((n) => !(n.fixed && !n.pinned)).toList();
    final result = <NoteMeta>[];
    var movableIndex = 0;
    var fixedBefore = 0;
    for (final note in fixed) {
      final wantBefore = ((note.sortOrder / 10).round() - fixedBefore)
          .clamp(0, movable.length);
      while (movableIndex < wantBefore) {
        result.add(movable[movableIndex++]);
      }
      result.add(note);
      fixedBefore++;
    }
    result.addAll(movable.skip(movableIndex));
    return result;
  }

  Map<String, int> get tagCounts {
    if (_tagRevision == _dataRevision) return _tagCache;
    final map = <String, int>{};
    for (final n in activeNotes) {
      for (final t in n.tags) {
        map[t] = (map[t] ?? 0) + 1;
      }
    }
    final entries = map.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _tagRevision = _dataRevision;
    _tagCache = Map.fromEntries(entries);
    return _tagCache;
  }

  List<String> get allTags => tagCounts.keys.toList();

  // ---------------------------------------------------------------------------
  // 统计
  // ---------------------------------------------------------------------------

  int get totalWords => activeNotes.fold(0, (s, n) => s + n.words);

  int get totalWritingSeconds =>
      activeNotes.fold(0, (s, n) => s + n.writingSeconds);

  /// 每天写下的字数：以活跃度日志为准（续写旧稿也算），
  /// 没有日志的历史日期回退到按创建日归集。
  Map<String, int> get wordsByDay {
    if (_dayRevision == _dataRevision) return _dayCache;
    final map = <String, int>{};
    for (final n in activeNotes) {
      map[n.day] = (map[n.day] ?? 0) + n.words;
    }
    for (final entry in activity.days.entries) {
      final recorded = entry.value.words;
      if (recorded > (map[entry.key] ?? 0)) map[entry.key] = recorded;
    }
    _dayRevision = _dataRevision;
    _dayCache = map;
    return _dayCache;
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
    const listViews = {
      'today',
      'all',
      'time',
      'favorites',
      'tags',
      'trash',
      'search',
    };
    final listChanged =
        listViews.contains(v) && settings.lastListView != v;
    if (listViews.contains(v)) settings.lastListView = v;
    if (view == v && tagFilter == null && folderFilter == null) {
      if (listChanged) unawaited(_persistSettings());
      return;
    }
    view = v;
    tagFilter = null;
    folderFilter = null;
    if (v == 'today') selectedDay = null;
    if (v != 'search') {
      // query 和 _filterQuery 必须一起清：只清前者会让列表继续按旧
      // 关键词过滤，但搜索框已经消失。
      query = '';
      _filterQuery = '';
      _queryTimer?.cancel();
    }
    settings.lastView = v;
    unawaited(_persistSettings());
    _notify();
  }

  /// 手机底部「笔记」tab 回到这里。
  String get listView => settings.lastListView;

  /// 列表的 select 需要监听它；防抖结束后过滤词变了，列表才会重排。
  String get filterQuery => _filterQuery;

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

  void setQuery(String q, {bool debounce = false}) {
    query = q;
    if (q.isNotEmpty) {
      view = 'search';
      // 全局搜索不应该继承上一次的文件夹/标签筛选，否则结果会莫名少一截。
      tagFilter = null;
      folderFilter = null;
    }
    _queryTimer?.cancel();
    if (!debounce || q.isEmpty) {
      _filterQuery = q;
      _notify();
      return;
    }
    _notify();
    _queryTimer = Timer(const Duration(milliseconds: 160), () {
      _filterQuery = q;
      _notify();
    });
  }

  /// 替换前给界面一个「会改多少处」的估计。
  int countMatchesInLibrary(String query, {bool caseSensitive = false}) {
    if (query.isEmpty) return 0;
    var total = 0;
    for (final meta in activeNotes) {
      total += countOccurrences(
        noteText(meta.id),
        query,
        caseSensitive: caseSensitive,
      );
    }
    return total;
  }

  /// 跨笔记替换。每篇改动前先留一份历史快照，出错也能回到原稿。
  Future<int> replaceAllInLibrary(
    String query,
    String replacement, {
    bool caseSensitive = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (query.isEmpty) return 0;
    final candidates = activeNotes
        .where((meta) =>
            countOccurrences(
              noteText(meta.id),
              query,
              caseSensitive: caseSensitive,
            ) >
            0)
        .toList();
    if (candidates.isEmpty) return 0;
    final currentId = current?.id;
    final reopenCurrent =
        currentId != null && candidates.any((meta) => meta.id == currentId);
    if (reopenCurrent) await closeEditor();

    var replaced = 0;
    var done = 0;
    for (final meta in candidates) {
      try {
        final note = await store.loadNote(meta.id);
        if (note != null) {
          final result = replaceInDelta(
            note.delta,
            query,
            replacement,
            caseSensitive: caseSensitive,
          );
          if (result.count > 0) {
            await store.saveSnapshot(note);
            note.delta = result.delta;
            note.text = result.text;
            note.words = countWords(note.text);
            note.updatedAt = DateTime.now();
            await store.saveNote(note);
            final index = notes.indexWhere((item) => item.id == note.id);
            if (index >= 0) notes[index] = note.toMeta();
            replaced += result.count;
          }
        }
      } catch (_) {
        // 单篇失败不拖垮整批；下一轮可以再替换。
      }
      done++;
      onProgress?.call(done, candidates.length);
    }
    await _flushLibrary();
    if (reopenCurrent) await openNote(currentId, autofocus: false);
    _notify();
    return replaced;
  }

  void setSort(String s) {
    // 切到手动排序时，把眼前「文件夹 + 笔记」的顺序原样冻结成共用顺序。
    if (s == 'manual' && sort != 'manual') {
      if (view == 'all') {
        prepareUnifiedOrder();
        unawaited(store.persistFolders(folders));
        unawaited(store.persistLibrary(notes));
      } else {
        prepareManualOrder();
      }
    }
    sort = s;
    settings.sort = s;
    unawaited(_persistSettings());
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

  int folderWords(String id) {
    final ids = folderTreeIds(id);
    return activeNotes
        .where((n) => n.folderId != null && ids.contains(n.folderId))
        .fold(0, (sum, n) => sum + n.words);
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
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
    return folder;
  }

  Future<void> renameFolder(String id, String name) async {
    final folder = folderById(id);
    if (folder == null) return;
    folder.name = name.trim().isEmpty ? folder.name : name.trim();
    _touchFolders();
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
      _syncOpenMeta(note);
    }
    folders.removeWhere((f) => f.id == id);
    if (folderFilter == id) folderFilter = null;
    _touchFolders();
    _touchData();
    await store.persistFolders(folders);
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> toggleFolderPin(Folder folder) async {
    folder.pinned = !folder.pinned;
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
  }

  Future<void> toggleFolderFixed(Folder folder) async {
    folder.fixed = !folder.fixed;
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
  }

  Future<void> setFoldersPinned(Iterable<String> ids, bool value) async {
    final idSet = ids.toSet();
    for (final folder in folders) {
      if (idSet.contains(folder.id)) folder.pinned = value;
    }
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
  }

  Future<void> setFoldersFixed(Iterable<String> ids, bool value) async {
    final idSet = ids.toSet();
    for (final folder in folders) {
      if (idSet.contains(folder.id)) folder.fixed = value;
    }
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
  }

  /// 把若干文件夹移到 [parentId] 下面；null 表示放到最外层。
  Future<void> moveFoldersToFolder(
    Iterable<String> ids,
    String? parentId,
  ) async {
    final idSet = ids.toSet();
    var order = childFolders(parentId)
        .where((f) => !idSet.contains(f.id))
        .fold<int>(0, (max, f) => f.order > max ? f.order : max);
    for (final id in ids) {
      final folder = folderById(id);
      if (folder == null) continue;
      if (parentId != null &&
          (id == parentId || folderTreeIds(id).contains(parentId))) {
        continue;
      }
      folder.parentId = parentId;
      order += 10;
      folder.order = order;
    }
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
  }

  Future<void> deleteFolders(Iterable<String> ids) async {
    final list = ids.toList();
    for (final id in list) {
      await deleteFolder(id);
    }
  }

  Future<void> moveNoteToFolder(String noteId, String? folderId) async {
    final index = notes.indexWhere((n) => n.id == noteId);
    if (index < 0) return;
    final note = notes[index];
    note.folderId = folderId;
    if (sort == 'manual') {
      final siblings = notes
          .where((n) =>
              n.folderId == folderId && !n.isTrashed && n.id != noteId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      note.sortOrder = siblings.isEmpty ? 10 : siblings.last.sortOrder + 10;
    }
    _syncOpenMeta(note);
    _touchData();
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
    if (view == 'all') {
      prepareUnifiedOrder();
    } else {
      prepareManualOrder();
    }
    sort = 'manual';
    settings.sort = 'manual';
    _touchData();
    await store.persistLibrary(notes);
    if (view == 'all') await store.persistFolders(folders);
    await _persistSettings();
    _notify();
  }

  /// 把 [noteId] 移到 [targetId] 的前面或后面。
  /// 只在同一天内允许排序；跨日期返回 false，由界面给出提示。
  Future<bool> reorderNote(
    String noteId,
    String targetId, {
    bool after = false,
  }) async {    if (noteId == targetId) return false;
    final sourceIndex = notes.indexWhere((n) => n.id == noteId);
    final targetIndex = notes.indexWhere((n) => n.id == targetId);
    if (sourceIndex < 0 || targetIndex < 0) return false;
    final source = notes[sourceIndex];
    final target = notes[targetIndex];
    if (source.isTrashed || target.isTrashed) return false;
    if (source.fixed) return false;
    if (source.day != target.day) return false;
    // 置顶的笔记在列表里永远排在最前，跨过这条界线调序不会生效。
    if (source.pinned != target.pinned) return false;
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
    _touchData();
    // 先把新顺序推给界面，再落盘：拖拽松手时列表要停在预览的位置，
    // 不能先闪回旧顺序再跳一次。
    _notify();
    await store.persistLibrary(notes);
    await _persistSettings();
    return true;
  }

  NoteMeta? metaById(String id) {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }

  /// 「全部」里当前这一层要显示的文件夹卡片。
  List<Folder> levelFolders() {
    if (view != 'all' || folderFilter == '__unfiled__') return const [];
    return childFolders(folderFilter);
  }

  int _entryKey(Object entry) =>
      entry is Folder ? entry.order : (entry as NoteMeta).sortOrder;

  bool _entryFixed(Object entry) =>
      entry is Folder ? entry.fixed : (entry as NoteMeta).fixed;

  /// 文件夹卡片和笔记卡片在「全部」里共用一条顺序。
  /// 非手动排序时文件夹先排成一组；手动排序时两者按同一条数字顺序合并。
  List<Object> get listEntries {
    if (view != 'all') return List<Object>.from(visibleNotes);
    final folders = levelFolders();
    final notes = visibleNotes;
    if (sort != 'manual') {
      final pinnedNotes = notes.where((n) => n.pinned).toList();
      final pinnedFolders = folders.where((f) => f.pinned).toList();
      final restFolders = folders.where((f) => !f.pinned).toList();
      final restNotes = notes.where((n) => !n.pinned).toList();
      return [
        ...pinnedNotes,
        ...pinnedFolders,
        ...restFolders,
        ...restNotes,
      ];
    }
    final pinned = <Object>[
      ...notes.where((n) => n.pinned),
      ...folders.where((f) => f.pinned),
    ]..sort((a, b) => _entryKey(a).compareTo(_entryKey(b)));
    final merged = <Object>[
      ...folders.where((f) => !f.pinned),
      ...notes.where((n) => !n.pinned),
    ]..sort((a, b) {
        final byKey = _entryKey(a).compareTo(_entryKey(b));
        if (byKey != 0) return byKey;
        final aFolder = a is Folder;
        final bFolder = b is Folder;
        if (aFolder != bFolder) return aFolder ? -1 : 1;
        if (a is Folder && b is Folder) {
          return a.name.compareTo(b.name);
        }
        if (a is NoteMeta && b is NoteMeta) {
          return a.title.compareTo(b.title);
        }
        return 0;
      });
    return [...pinned, ...merged];
  }

  /// 拖动开始时冻结「文件夹 + 笔记」的当前顺序，不改排序模式、不通知界面。
  void prepareUnifiedOrder() {
    if (view != 'all') {
      prepareManualOrder();
      return;
    }
    var order = 0;
    for (final entry in listEntries) {
      order += 10;
      if (entry is Folder) {
        entry.order = order;
      } else {
        (entry as NoteMeta).sortOrder = order;
      }
    }
    _touchData();
    _touchFolders();
  }

  /// 在「全部」里把一张卡片插到另一张卡片的上面或下面。
  /// [sourceIsFolder] / [targetIsFolder] 区分文件夹卡片与笔记卡片。
  Future<bool> reorderListEntry(
    String sourceId,
    String targetId, {
    bool after = false,
    bool sourceIsFolder = false,
    bool targetIsFolder = false,
  }) async {
    if (sourceId == targetId) return false;
    final sourceFolder = sourceIsFolder ? folderById(sourceId) : null;
    final sourceNote = sourceIsFolder ? null : metaById(sourceId);
    if (sourceFolder == null && sourceNote == null) return false;
    if (sourceNote != null && sourceNote.isTrashed) return false;
    if (sourceFolder?.fixed == true || sourceNote?.fixed == true) return false;
    // 调用方没标类型时，按 id 推断目标是不是文件夹。
    final folderTarget = targetIsFolder ||
        (!targetIsFolder &&
            metaById(targetId) == null &&
            folderById(targetId) != null);
    if (folderTarget && folderById(targetId) == null) return false;
    if (!folderTarget) {
      final target = metaById(targetId);
      if (target == null || target.isTrashed) return false;
      if (sourceNote != null && sourceNote.pinned != target.pinned) return false;
    }
    if (sourceFolder != null &&
        folderTarget &&
        folderTreeIds(sourceId).contains(targetId)) {
      return false;
    }

    // 固定卡片只锁住自己的位置：其它卡片可以自由跨过它，
    // 移动时只重排「非固定」卡片，固定卡片仍留在原来的槽位。
    final before = listEntries;
    final sourceIsNote = sourceNote != null;
    final sourcePinned = sourceNote?.pinned ?? false;
    bool movableEntry(Object entry) {
      if (_entryFixed(entry)) return false;
      if (entry is NoteMeta) {
        return sourceIsNote ? entry.pinned == sourcePinned : !entry.pinned;
      }
      return sourceIsNote ? !sourcePinned : true;
    }

    final sourceIndex = before.indexWhere(
      (e) => e is Folder ? e.id == sourceId : (e as NoteMeta).id == sourceId,
    );
    if (sourceIndex < 0) return false;
    final source = before[sourceIndex];
    final fixedIndices = <int>{};
    for (var i = 0; i < before.length; i++) {
      if (!movableEntry(before[i])) fixedIndices.add(i);
    }
    final freeSlots = <int>[
      for (var i = 0; i < before.length; i++)
        if (!fixedIndices.contains(i)) i,
    ];
    if (freeSlots.isEmpty) return false;
    final movable = before
        .where(movableEntry)
        .where((e) => (e is Folder ? e.id : (e as NoteMeta).id) != sourceId)
        .toList();

    final targetIndex = before.indexWhere(
      (e) => e is Folder ? e.id == targetId : (e as NoteMeta).id == targetId,
    );
    int rank;
    if (targetIndex < 0) {
      rank = movable.length;
    } else if (movableEntry(before[targetIndex])) {
      final target = before[targetIndex];
      rank = movable.indexWhere(
        (e) => (e is Folder ? e.id : (e as NoteMeta).id) ==
            (target is Folder ? target.id : (target as NoteMeta).id),
      );
      if (rank < 0) rank = movable.length;
      if (after) rank += 1;
    } else {
      final left = freeSlots.where((s) => s < targetIndex).toList();
      final right = freeSlots.where((s) => s > targetIndex).toList();
      final slot = after
          ? (right.isNotEmpty ? right.first : left.last)
          : (left.isNotEmpty ? left.last : right.first);
      rank = freeSlots.where((s) => s < slot).length;
    }
    movable.insert(rank.clamp(0, movable.length), source);

    final entries = List<Object?>.filled(before.length, null);
    for (final i in fixedIndices) {
      entries[i] = before[i];
    }
    var next = 0;
    for (var i = 0; i < entries.length; i++) {
      entries[i] ??= movable[next++];
    }
    for (var i = 0; i < entries.length; i++) {
      final order = (i + 1) * 10;
      if (entries[i] is Folder) {
        (entries[i] as Folder).order = order;
      } else {
        (entries[i] as NoteMeta).sortOrder = order;
      }
    }
    sort = 'manual';
    settings.sort = 'manual';
    _touchData();
    _touchFolders();
    _notify();
    await store.persistLibrary(notes);
    await store.persistFolders(folders);
    await _persistSettings();
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
    _touchFolders();
    await store.persistFolders(folders);
    _notify();
  }

  // ---------------------------------------------------------------------------
  // 笔记
  // ---------------------------------------------------------------------------

  /// 桌面标签页里打开的笔记 id，按打开顺序排列。
  final List<String> openTabs = <String>[];

  /// 拖动标签栏调整打开顺序。[index] 是移除前的插入位置。
  void moveTabToIndex(String id, int index) {
    final from = openTabs.indexOf(id);
    if (from < 0) return;
    openTabs.removeAt(from);
    final target = index > from ? index - 1 : index;
    openTabs.insert(target.clamp(0, openTabs.length), id);
    _notify();
  }

  Future<void> openNote(
    String id, {
    bool autofocus = true,
    bool force = false,
  }) async {
    if (current?.id == id) return;
    if (secondaryNote?.id == id) await closeSecondary();
    await closeEditor();
    final note = await store.loadNote(id);
    if (note == null) return;
    final matches = notes.where((n) => n.id == id);
    final meta = matches.isEmpty ? null : matches.first;
    if (meta != null) {
      note
        ..folderId = meta.folderId
        ..sortOrder = meta.sortOrder
        ..pinned = meta.pinned
        ..fixed = meta.fixed
        ..favorite = meta.favorite;
    }
    if (!openTabs.contains(id)) {
      openTabs.add(id);
      while (openTabs.length > 8) {
        openTabs.removeAt(0);
      }
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
    await _flushLibrary();
    await persistActivity();
    _notify();
  }

  /// 关窗/退出前调用：正文与活跃度都落盘，再交给窗口销毁。
  Future<void> closeApp() async {
    await closeSecondary();
    await closeEditor();
    openTabs.clear();
    await persistSettingsNow();
    await _flushLibrary();
    await persistActivity();
  }

  Future<void> openSecondaryNote(String id) async {
    if (id == current?.id || id == secondaryNote?.id) return;
    await closeSecondary();
    final note = await store.loadNote(id);
    if (note == null) return;
    final matches = notes.where((item) => item.id == id);
    final meta = matches.isEmpty ? null : matches.first;
    if (meta != null) {
      note
        ..folderId = meta.folderId
        ..sortOrder = meta.sortOrder
        ..pinned = meta.pinned
        ..fixed = meta.fixed
        ..favorite = meta.favorite;
    }
    secondaryNote = note;
    secondarySession = EditorSession(app: this, note: note);
    _notify();
  }

  Future<void> closeSecondary() async {
    final s = secondarySession;
    if (s != null) {
      await s.flush();
      s.dispose();
    }
    secondarySession = null;
    secondaryNote = null;
    _notify();
  }

  Future<void> switchTab(String id) => openNote(id);

  /// Alt+↑/↓ 在当前列表里换一篇，不抢编辑器焦点。
  Future<void> openRelativeNote(int delta) async {
    final list = visibleNotes;
    if (list.isEmpty) return;
    final currentId = current?.id;
    final index = currentId == null
        ? -1
        : list.indexWhere((meta) => meta.id == currentId);
    var next = index < 0
        ? (delta > 0 ? 0 : list.length - 1)
        : index + delta;
    next = next.clamp(0, list.length - 1);
    if (list[next].id == currentId) return;
    await openNote(list[next].id, autofocus: false);
  }

  Future<void> switchToNextTab({bool backwards = false}) async {
    if (openTabs.length < 2) return;
    final currentId = current?.id;
    final index = currentId == null ? -1 : openTabs.indexOf(currentId);
    if (index < 0) {
      await openNote(openTabs.first);
      return;
    }
    final next = backwards
        ? (index - 1 + openTabs.length) % openTabs.length
        : (index + 1) % openTabs.length;
    await openNote(openTabs[next]);
  }

  Future<void> closeTab(String id) async {
    final index = openTabs.indexOf(id);
    if (index < 0) return;
    openTabs.removeAt(index);
    if (current?.id != id) {
      _notify();
      return;
    }
    if (openTabs.isEmpty) {
      await closeEditor();
      return;
    }
    final next = openTabs[index.clamp(0, openTabs.length - 1)];
    await openNote(next);
  }

  void _scheduleLibraryPersist() {
    _libraryTimer?.cancel();
    _libraryTimer = Timer(const Duration(milliseconds: 1200), () {
      _libraryTimer = null;
      unawaited(store.persistLibrary(notes));
    });
  }

  Future<void> _flushLibrary() async {
    _libraryTimer?.cancel();
    _libraryTimer = null;
    try {
      await store.persistLibrary(notes);
    } catch (_) {
      // 索引写失败不该影响正文；下次保存或重建会补上。
    }
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
    final expandedDelta = _expandTemplateDelta(t.delta);
    // 在文件夹里点「新建」时，笔记应该直接落在这个文件夹里。
    final targetFolder = view == 'all' &&
            folderFilter != null &&
            folderFilter != '__unfiled__'
        ? folderFilter
        : null;
    final note = Note(
      id: _uuid.v4(),
      title: title ?? _expandTemplateText(t.title),
      delta: expandedDelta,
      text: '',
      kind: kind,
      tags: List.of(t.tags),
      createdAt: date,
      updatedAt: now,
      day: dayKey(date),
      folderId: targetFolder,
    );
    final parts = <String>[];
    for (final op in expandedDelta) {
      if (op is Map && op['insert'] is String) {
        final s = op['insert'] as String;
        if (s != '\n') parts.add(s);
      }
    }
    note.text = parts.join();
    note.words = countWords(note.text);
    await store.saveNote(note);
    notes.insert(0, note.toMeta());
    _touchData();
    await store.persistLibrary(notes);
    await openNote(note.id, force: true);
    saveStatus = SaveStatus.saved;
    _notify();
    return note;
  }

  /// 从 Markdown / 纯文本导入一篇笔记。
  String _templateWeekday(DateTime date) {
  const zh = ['一', '二', '三', '四', '五', '六', '日'];
  const en = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return I18n.isEn ? en[date.weekday - 1] : '星期${zh[date.weekday - 1]}';
}

String _expandTemplateText(String input) {
  if (!input.contains('{{')) return input;
  final now = DateTime.now();
  final date = I18n.isEn
      ? '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}'
      : '${now.year}年${now.month}月${now.day}日';
  final time = '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}';
  return input
      .replaceAll('{{date}}', date)
      .replaceAll('{{weekday}}', _templateWeekday(now))
      .replaceAll('{{time}}', time);
}

List<dynamic> _expandTemplateDelta(List<dynamic> delta) {
  return [
    for (final op in delta)
      if (op is Map && op['insert'] is String)
        {
          ...op.cast<dynamic, dynamic>(),
          'insert': _expandTemplateText(op['insert'] as String),
        }
      else
        op,
  ];
}

Future<UserTemplate?> saveCurrentAsTemplate(String name) async {
    final s = session;
    if (s == null) return null;
    await s.flush();
    final template = UserTemplate(
      id: 'user_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? tr('我的模板') : name.trim(),
      title: s.titleController.text.trim(),
      delta: s.controller.document.toDelta().toJson(),
      tags: List.of(s.note.tags),
    );
    userTemplates = [...userTemplates, template];
    await store.saveTemplates(userTemplates);
    _notify();
    return template;
  }

  Future<void> deleteUserTemplate(String id) async {
    userTemplates = userTemplates.where((t) => t.id != id).toList();
    await store.saveTemplates(userTemplates);
    _notify();
  }

  /// 今天已经写过日记就打开它，否则用日记模板新建一篇。
  Future<void> openTodayDiary() async {
    final today = dayKey(DateTime.now());
    for (final meta in activeNotes) {
      if (meta.day == today && meta.kind == NoteKind.diary) {
        await openNote(meta.id);
        return;
      }
    }
    await createNote(kind: NoteKind.diary, day: DateTime.now());
  }

  /// 从 Word 文档导入一篇新笔记。
  Future<Note?> importDocx(Uint8List bytes, String filename) async {
    final result = await parseDocx(
      bytes,
      saveImage: (data, extension) => store.saveAsset(data, extension),
    );
    if (result == null) return null;
    final now = DateTime.now();
    final note = Note(
      id: _uuid.v4(),
      title: result.title.trim().isEmpty
          ? _titleFromFilename(filename)
          : result.title.trim(),
      delta: result.delta,
      text: result.text,
      kind: NoteKind.note,
      tags: const <String>[],
      createdAt: now,
      updatedAt: now,
      day: dayKey(now),
      words: countWords(result.text),
    );
    await store.saveNote(note);
    notes.insert(0, note.toMeta());
    _touchData();
    await store.persistLibrary(notes);
    await openNote(note.id, force: true);
    return note;
  }

  /// 从系统分享接收一段文字/链接，落到一篇新笔记里。
  Future<void> importSharedText(String text) async {
    final shared = text.trim();
    if (shared.isEmpty) return;
    final first = shared.split('\n').first.trim();
    final title = first.isEmpty
        ? '来自分享'
        : (first.length > 40 ? first.substring(0, 40) : first);
    await createNote(title: title);
    final s = session;
    if (s == null) return;
    s.controller.replaceText(
      0,
      0,
      shared,
      TextSelection.collapsed(offset: shared.length),
    );
    await s.flush();
  }

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
        } else if (ext == '.docx') {
          final bytes = await File(path).readAsBytes();
          if (await importDocx(bytes, p.basename(path)) != null) imported++;
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
    _syncOpenMeta(meta);
    _touchData();
    await store.persistLibrary(notes);
    _notify();
  }

  /// 编辑会话里的 Note 是另一份对象；列表里改的元数据要同步过去，
  /// 否则下一次自动保存会用旧的 pinned / fixed / folderId 覆盖回来。
  void _syncOpenMeta(NoteMeta meta) {
    void sync(Note? note) {
      if (note == null || note.id != meta.id) return;
      note
        ..pinned = meta.pinned
        ..fixed = meta.fixed
        ..favorite = meta.favorite
        ..folderId = meta.folderId
        ..sortOrder = meta.sortOrder;
    }

    sync(current);
    sync(secondaryNote);
  }

  Future<void> togglePin(NoteMeta meta) async {
    meta.pinned = !meta.pinned;
    await updateMeta(meta);
  }

  Future<void> toggleFavorite(NoteMeta meta) async {
    meta.favorite = !meta.favorite;
    await updateMeta(meta);
  }

  /// 固定后记录当前位置；之后「最近 / 创建 / 字数」重排都不会把它挤走。
  Future<void> toggleFixed(NoteMeta meta) async {
    if (!meta.fixed) {
      final index = visibleNotes.indexWhere((n) => n.id == meta.id);
      if (index >= 0) meta.sortOrder = index * 10;
      meta.fixed = true;
    } else {
      meta.fixed = false;
    }
    await updateMeta(meta);
  }

  Future<void> setPinnedMany(Iterable<String> ids, bool value) async {
    final idSet = ids.toSet();
    for (final note in notes) {
      if (idSet.contains(note.id)) {
        note.pinned = value;
        _syncOpenMeta(note);
      }
    }
    _touchData();
    await store.persistLibrary(notes);
    _notify();
  }

  /// 笔记和文件夹的批量置顶 / 固定：先改完内存再一起落盘，
  /// 界面立刻拿到新状态，也让两类条目在同一帧里更新。
  Future<void> setPinnedFor(
    Iterable<String> noteIds,
    Iterable<String> folderIds,
    bool value,
  ) async {
    final noteSet = noteIds.toSet();
    final folderSet = folderIds.toSet();
    for (final note in notes) {
      if (noteSet.contains(note.id)) {
        note.pinned = value;
        _syncOpenMeta(note);
      }
    }
    for (final folder in folders) {
      if (folderSet.contains(folder.id)) folder.pinned = value;
    }
    _touchData();
    _touchFolders();
    _notify();
    await store.persistLibrary(notes);
    await store.persistFolders(folders);
  }

  Future<void> setFixedFor(
    Iterable<String> noteIds,
    Iterable<String> folderIds,
    bool value,
  ) async {
    final noteSet = noteIds.toSet();
    final folderSet = folderIds.toSet();
    if (value) {
      final positions = <String, int>{};
      final visible = visibleNotes;
      for (var i = 0; i < visible.length; i++) {
        positions[visible[i].id] = i;
      }
      for (final note in notes) {
        if (!noteSet.contains(note.id)) continue;
        final index = positions[note.id];
        if (index != null) note.sortOrder = index * 10;
        note.fixed = true;
        _syncOpenMeta(note);
      }
    } else {
      for (final note in notes) {
        if (noteSet.contains(note.id)) {
          note.fixed = false;
          _syncOpenMeta(note);
        }
      }
    }
    for (final folder in folders) {
      if (folderSet.contains(folder.id)) folder.fixed = value;
    }
    _touchData();
    _touchFolders();
    _notify();
    await store.persistLibrary(notes);
    await store.persistFolders(folders);
  }

  Future<void> setFavoriteMany(Iterable<String> ids, bool value) async {
    final idSet = ids.toSet();
    for (final note in notes) {
      if (idSet.contains(note.id)) {
        note.favorite = value;
        _syncOpenMeta(note);
      }
    }
    _touchData();
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> setFixedMany(Iterable<String> ids, bool value) async {
    final idSet = ids.toSet();
    if (value) {
      final positions = <String, int>{};
      final visible = visibleNotes;
      for (var i = 0; i < visible.length; i++) {
        positions[visible[i].id] = i;
      }
      for (final note in notes) {
        if (!idSet.contains(note.id)) continue;
        final index = positions[note.id];
        if (index != null) note.sortOrder = index * 10;
        note.fixed = true;
        _syncOpenMeta(note);
      }
    } else {
      for (final note in notes) {
        if (idSet.contains(note.id)) {
          note.fixed = false;
          _syncOpenMeta(note);
        }
      }
    }
    _touchData();
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> trashMany(Iterable<String> ids) async {
    final idSet = ids.toSet();
    final now = DateTime.now();
    var closedCurrent = false;
    for (final note in notes) {
      if (!idSet.contains(note.id) || note.deletedAt != null) continue;
      note.deletedAt = now;
      if (current?.id == note.id) {
        session?.note.deletedAt = now;
        openTabs.remove(note.id);
        closedCurrent = true;
      }
      if (secondaryNote?.id == note.id) {
        secondarySession?.note.deletedAt = now;
      }
    }
    _touchData();
    await store.persistLibrary(notes);
    if (closedCurrent) await closeEditor();
    _notify();
  }

  Future<void> moveNotesToFolder(
    Iterable<String> ids,
    String? folderId,
  ) async {
    final idSet = ids.toSet();
    var nextOrder = 0;
    if (sort == 'manual') {
      final siblings = notes
          .where((n) =>
              n.folderId == folderId && !n.isTrashed && !idSet.contains(n.id))
          .toList();
      siblings.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      nextOrder = siblings.isEmpty ? 10 : siblings.last.sortOrder + 10;
    }
    for (final note in notes) {
      if (!idSet.contains(note.id)) continue;
      note.folderId = folderId;
      if (sort == 'manual') {
        note.sortOrder = nextOrder;
        nextOrder += 10;
      }
      _syncOpenMeta(note);
    }
    _touchData();
    await store.persistLibrary(notes);
    _notify();
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
    _touchData();
    await store.persistLibrary(notes);
    if (current?.id == id) {
      session?.note.deletedAt = notes[i].deletedAt;
      openTabs.remove(id);
      await closeEditor();
      if (openTabs.isNotEmpty) await openNote(openTabs.last);
    }
    _notify();
  }

  Future<void> restoreNote(String id) async {
    final i = notes.indexWhere((e) => e.id == id);
    if (i < 0) return;
    notes[i].deletedAt = null;
    _touchData();
    await store.persistLibrary(notes);
    _notify();
  }

  Future<void> purgeNote(String id) async {
    openTabs.remove(id);
    if (current?.id == id) {
      // 永久删除时不能再 flush，否则刚删掉的 note 文件会被写回来。
      final s = session;
      session = null;
      current = null;
      saveStatus = SaveStatus.idle;
      s?.dispose();
    }
    notes.removeWhere((e) => e.id == id);
    _indexTexts.remove(id);
    _touchData();
    await store.deleteNoteFile(id);
    await store.persistLibrary(notes);
    if (session == null && openTabs.isNotEmpty) {
      await openNote(openTabs.last);
    }
    _notify();
  }

  Future<void> emptyTrash() async {
    final ids = trashedNotes.map((note) => note.id).toSet();
    openTabs.removeWhere(ids.contains);
    if (current != null && ids.contains(current!.id)) {
      final s = session;
      session = null;
      current = null;
      saveStatus = SaveStatus.idle;
      s?.dispose();
    }
    for (final n in trashedNotes) {
      await store.deleteNoteFile(n.id);
      _indexTexts.remove(n.id);
    }
    notes.removeWhere((n) => n.isTrashed);
    _touchData();
    await store.persistLibrary(notes);
    if (session == null && openTabs.isNotEmpty) {
      await openNote(openTabs.last);
    }
    _notify();
  }

  /// 由 EditorSession 调用，保存正文并同步索引。
  Future<void> persistNote(Note note, {bool snapshot = false}) async {
    saveStatus = SaveStatus.saving;
    _notify();
    try {
      await store.saveNote(note);
      await store.deleteJournal(note.id);
      if (snapshot) await store.saveSnapshot(note);
      final meta = note.toMeta();
      final i = notes.indexWhere((e) => e.id == note.id);
      if (i >= 0) {
        notes[i] = meta;
      } else {
        notes.insert(0, meta);
      }
      _indexTexts[note.id] = note.text;
      _touchData();
      // note 文件与全文索引已经落盘；library 索引晚一点写，避免每 900ms 重写整份。
      _scheduleLibraryPersist();
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
    _touchData();
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

  Future<void> insertNoteLink(EditorSession session, NoteMeta target) async {
    final controller = session.controller;
    final selection = controller.selection;
    if (!selection.isValid) return;
    final start = selection.start;
    final title = target.title.trim().isEmpty ? tr('无题') : target.title.trim();
    final label = '[[$title]]';
    controller.replaceText(
      start,
      selection.end - start,
      label,
      TextSelection.collapsed(offset: start + label.length),
    );
    controller.formatText(
      start,
      label.length,
      LinkAttribute('thisnote://${target.id}'),
    );
    await session.flush();
  }

  String _liveTextOf(NoteMeta meta) => noteText(meta.id);

  /// 明确写了 [[标题]] 的笔记。
  List<NoteMeta> inboundLinksFor(NoteMeta target) {
    final title = target.title.trim();
    if (title.isEmpty) return const [];
    final needle = '[[$title]]'.toLowerCase();
    return activeNotes
        .where((meta) =>
            meta.id != target.id &&
            _liveTextOf(meta).toLowerCase().contains(needle))
        .toList();
  }

  /// 当前笔记里 [[...]] 指向的笔记。
  List<NoteMeta> outgoingLinksFor(NoteMeta source) {
    final text = _liveTextOf(source);
    final titles = RegExp(r'\[\[([^\]\n]{1,80})\]\]')
        .allMatches(text)
        .map((m) => m.group(1)!.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    if (titles.isEmpty) return const [];
    return activeNotes
        .where((meta) =>
            meta.id != source.id &&
            titles.contains(meta.title.trim().toLowerCase()))
        .toList();
  }

  Future<void> setNoteGoal(int words) async {
    final s = session;
    if (s == null) return;
    s.note.goalWords = words.clamp(0, 100000);
    s.dirty = true;
    await s.flush();
    _notify();
  }

  Future<void> saveNow() async {
    await session?.flush();
    await _flushLibrary();
    await persistActivity();
    _notify();
  }

  Future<void> reload() async {
    await closeSecondary();
    await closeEditor();
    openTabs.clear();
    settings = await store.loadSettings();
    await _loadSecrets();
    I18n.lang = AppLang.fromCode(settings.language);
    await _loadCustomFonts();
    notes = await store.loadLibrary();
    folders = await store.loadFolders();
    await _prepareIndex();
    await _prepareRecovery();
    _touchData();
    _settingsRevision++;
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
    _settingsTimer?.cancel();
    mutate(settings);
    _settingsRevision++;
    await _persistSettings();
    _notify();
  }

  /// 滑块拖动时只更新内存，松手后再落盘。
  void previewSettings(void Function(AppSettings s) mutate) {
    mutate(settings);
    _settingsRevision++;
    _notify();
    _settingsTimer?.cancel();
    _settingsTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_persistSettings());
    });
  }

  Future<void> persistSettingsNow() async {
    _settingsTimer?.cancel();
    _settingsTimer = null;
    await _persistSettings();
  }

  /// 把用户导入过的字体重新注册进字体引擎。放在启动和恢复备份之后调用，
  /// 正文里的 font 属性只存字体族名，字形由这里补上。
  Future<void> _loadCustomFonts() async {
    for (final font in settings.customFonts) {
      try {
        final file = File(store.resolveFont(font.file));
        if (!await file.exists()) continue;
        final bytes = await file.readAsBytes();
        await (FontLoader(font.id)
              ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
            .load();
      } catch (_) {
        // 字体文件损坏、或平台不支持：跳过，界面照常打开。
      }
    }
  }

  /// 导入一个 TTF / OTF 字体，返回 null 表示文件不可用。
  Future<CustomFont?> importCustomFont({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final ext = p.extension(fileName).toLowerCase();
    if (ext != '.ttf' && ext != '.otf') return null;
    if (bytes.length > 80 * 1024 * 1024) return null;
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await (FontLoader(id)
            ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes))))
          .load();
    } catch (_) {
      return null;
    }
    final file = await store.saveFont(bytes, ext.replaceAll('.', ''));
    final raw = p.basenameWithoutExtension(fileName).trim();
    final name = raw.isEmpty
        ? '我的字体'
        : (raw.length > 40 ? raw.substring(0, 40) : raw);
    final font = CustomFont(id: id, name: name, file: file);
    await updateSettings(
      (s) => s.customFonts = [...s.customFonts, font],
    );
    return font;
  }

  Future<void> removeCustomFont(CustomFont font) async {
    await updateSettings(
      (s) => s.customFonts =
          s.customFonts.where((e) => e.id != font.id).toList(growable: false),
    );
    await store.deleteFont(font.file);
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
    final cursor = note.cursorOffset.clamp(0, controller.document.length);
    if (cursor > 0) {
      controller.updateSelection(
        TextSelection.collapsed(offset: cursor),
        ChangeSource.local,
      );
    }
    _changesSub = controller.changes.listen(_onDocChanged);
    controller.addListener(_onControllerChanged);
    titleController.addListener(_onTitleChanged);
    _lastSelection = controller.selection;
    _lastDocLength = controller.document.length;
    _lastTitle = titleController.text;
    styleCheckOpen = app.settings.styleCheck;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients || note.scrollOffset <= 0) return;
      final target = note.scrollOffset.clamp(
        0.0,
        scrollController.position.maxScrollExtent,
      );
      if (target > 0) scrollController.jumpTo(target);
    });
    // 旧笔记没有记录过写作时长：用创建到最近修改的跨度做一个保守估计，
    // 只接受一分钟到十二小时之间，太久远的笔记宁可不猜。
    _writingMs = note.writingSeconds * 1000;
    if (_writingMs <= 0) {
      final span = note.updatedAt.difference(note.createdAt);
      if (span > const Duration(minutes: 1) &&
          span <= const Duration(hours: 12)) {
        _writingMs = span.inMilliseconds;
        note.writingSeconds = _writingMs ~/ 1000;
      }
    }
    _lastEditAt = DateTime.now();
    // 记下「今天第一次打开这篇时」的字数，续写才算得出今天新增了多少。
    app.activity.startSession(dayKey(DateTime.now()), note.id, words);
    aiChat = AiChatController(
      store: app.store,
      noteId: note.id,
      settings: app.settings.aiSettings,
    );
    unawaited(aiChat.load());
    _snapshotTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (dirty) flush(snapshot: true);
    });
    _journalTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!dirty) return;
      final entry = JournalEntry(
        id: note.id,
        title: titleController.text,
        delta: controller.document.toDelta().toJson(),
        text: plainText,
        savedAt: DateTime.now(),
      );
      unawaited(app.store.saveJournal(note.id, entry.toJson()));
    });
  }

  final AppState app;
  final Note note;
  late final QuillController controller;
  late final TextEditingController titleController;
  final FocusNode editorFocus = FocusNode();
  final FocusNode titleFocus = FocusNode();
  final ScrollController scrollController = ScrollController();
  final GlobalKey<EditorState> editorKey = GlobalKey<EditorState>();

  late final AiChatController aiChat;
  bool aiOpen = false;

  void setAiOpen(bool open) {
    if (aiOpen == open) return;
    aiOpen = open;
    notifyListeners();
  }

  Timer? _debounce;
  Timer? _snapshotTimer;
  Timer? _journalTimer;
  StreamSubscription<dynamic>? _changesSub;
  TextSelection _lastSelection = const TextSelection.collapsed(offset: 0);
  int _lastDocLength = -1;
  String _lastTitle = '';
  bool dirty = false;
  DateTime? lastSaved;
  int renderEpoch = 0;

  /// 实际动笔的毫秒数：按两次输入之间的间隔累加，超过一分钟的停顿不算。
  int _writingMs = 0;
  DateTime _lastEditAt = DateTime.now();

  int get writingSeconds => _writingMs ~/ 1000;

  DateTime? _sprintEnd;
  int _sprintStartWords = 0;
  Timer? _sprintTimer;

  bool get sprintActive => _sprintEnd != null;
  int get sprintWords => words - _sprintStartWords;
  int get sprintRemainingSeconds {
    final end = _sprintEnd;
    if (end == null) return 0;
    final value = end.difference(DateTime.now()).inSeconds;
    return value < 0 ? 0 : value;
  }

  void startSprint(int minutes) {
    stopSprint();
    _sprintStartWords = words;
    _sprintEnd = DateTime.now().add(Duration(minutes: minutes));
    _sprintTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sprintEnd == null) return;
      if (sprintRemainingSeconds <= 0) {
        stopSprint();
      } else {
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void stopSprint() {
    _sprintTimer?.cancel();
    _sprintTimer = null;
    _sprintEnd = null;
    notifyListeners();
  }

  void _accumulateWriting() {
    final now = DateTime.now();
    final gap = now.difference(_lastEditAt);
    if (gap > Duration.zero && gap <= const Duration(minutes: 1)) {
      _writingMs += gap.inMilliseconds;
    }
    _lastEditAt = now;
  }

  /// 文档每改一次自增，用来复用字数/纯文本的计算结果。
  int _revision = 0;

  int get revision => _revision;
  int _wordsRevision = -1;
  int _wordsCache = 0;
  int _plainRevision = -1;
  String _plainCache = '';

  int get words {
    if (_wordsRevision != _revision) {
      _wordsRevision = _revision;
      _wordsCache = countWords(
        deltaPlainText(controller.document.toDelta()),
      );
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
  bool styleCheckOpen = false;
  bool backlinksOpen = false;

  void toggleOutline() {
    outlineOpen = !outlineOpen;
    if (outlineOpen) {
      findOpen = false;
      styleCheckOpen = false;
      backlinksOpen = false;
    }
    notifyListeners();
  }

  void toggleStyleCheck() {
    styleCheckOpen = !styleCheckOpen;
    if (styleCheckOpen) {
      findOpen = false;
      outlineOpen = false;
      backlinksOpen = false;
    }
    notifyListeners();
  }

  void toggleBacklinks() {
    backlinksOpen = !backlinksOpen;
    if (backlinksOpen) {
      findOpen = false;
      outlineOpen = false;
      styleCheckOpen = false;
    }
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
  Future<void> insertTableOfContents() async {
    final entries = outline;
    if (entries.isEmpty) return;
    final buffer = StringBuffer();
    for (final entry in entries) {
      buffer
        ..write('  ' * (entry.level - 1))
        ..writeln('· ${entry.text}');
    }
    buffer.writeln();
    final text = buffer.toString();
    final selection = controller.selection;
    if (!selection.isValid) return;
    final offset = selection.start;
    controller.replaceText(
      offset,
      selection.end - offset,
      text,
      TextSelection.collapsed(offset: offset + text.length),
    );
    await flush();
  }

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
      _plainCache =
          deltaPlainText(controller.document.toDelta()).trimRight();
    }
    return _plainCache;
  }

  /// 文档变化只做增量标记：不再为每次按键编码整篇 Delta。
  void _onDocChanged(dynamic change) {
    _accumulateWriting();
    _findCacheKey = '';
    _revision++;
    dirty = true;
    notifyListeners();
    scheduleSave();
  }

  /// 文档长度变化同步处理，保证输入后立刻能读到时序/字数；
  /// 纯格式变化由异步 changes 流补上。
  void _onControllerChanged() {
    var changed = false;
    final selection = controller.selection;
    if (selection != _lastSelection) {
      _lastSelection = selection;
      changed = true;
    }
    final length = controller.document.length;
    if (length != _lastDocLength) {
      _lastDocLength = length;
      _accumulateWriting();
      _revision++;
      _findCacheKey = '';
      dirty = true;
      changed = true;
      scheduleSave();
    }
    if (changed) notifyListeners();
  }

  void _onTitleChanged() {
    if (titleController.text != _lastTitle) {
      _accumulateWriting();
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
    note.cursorOffset = controller.selection.extentOffset;
    note.scrollOffset = scrollController.hasClients
        ? scrollController.offset
        : note.scrollOffset;
    note.delta = controller.document.toDelta().toJson();
    note.text = text;
    note.words = countWords(text);
    note.writingSeconds = writingSeconds;
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
    _journalTimer?.cancel();
    _sprintTimer?.cancel();
    _changesSub?.cancel();
    aiChat.dispose();
    controller.removeListener(_onControllerChanged);
    titleController.removeListener(_onTitleChanged);
    controller.dispose();
    titleController.dispose();
    editorFocus.dispose();
    titleFocus.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
