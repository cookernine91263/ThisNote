import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/templates.dart';
import '../features/editor/huazi.dart';

enum SaveStatus { idle, saving, saved, error }

class AppState extends ChangeNotifier {
  final NoteStore store = NoteStore();
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

  bool _disposed = false;

  Future<void> init() async {
    startupError = null;
    await store.init();
    settings = await store.loadSettings();
    notes = await store.loadLibrary();
    folders = await store.loadFolders();
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
    result.sort((a, b) {
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

  int get todayWords {
    final today = dayKey(DateTime.now());
    return activeNotes
        .where((n) => n.day == today)
        .fold(0, (s, n) => s + n.words);
  }

  int get streak {
    final days = activeNotes.map((n) => n.day).toSet();
    var cursor = DateTime.now();
    if (!days.contains(dayKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (!days.contains(dayKey(cursor))) return 0;
    }
    var count = 0;
    while (days.contains(dayKey(cursor))) {
      count++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return count;
  }

  List<DayStat> get last7Days {
    final today = DateTime.now();
    final result = <DayStat>[];
    for (var i = 6; i >= 0; i--) {
      final d = today.subtract(Duration(days: i));
      final key = dayKey(d);
      final words = activeNotes
          .where((n) => n.day == key)
          .fold(0, (s, n) => s + n.words);
      result.add(DayStat(d, words));
    }
    return result;
  }

  /// 最近 [days] 天的写作热力图数据
  Map<String, int> get heatmap {
    final map = <String, int>{};
    for (final n in activeNotes) {
      map[n.day] = (map[n.day] ?? 0) + n.words;
    }
    return map;
  }

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
      name: name.trim().isEmpty ? '新文件夹' : name.trim(),
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

  Future<void> reorderNote(String noteId, String targetId) async {
    final dragged = notes.indexWhere((n) => n.id == noteId);
    final target = notes.indexWhere((n) => n.id == targetId);
    if (dragged < 0 || target < 0 || noteId == targetId) return;
    final day = notes[dragged].day;
    if (notes[target].day != day) return;
    final group = notes.where((n) => n.day == day).toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : b.updatedAt.compareTo(a.updatedAt);
      });
    final item = group.removeAt(group.indexWhere((n) => n.id == noteId));
    var to = group.indexWhere((n) => n.id == targetId);
    if (to < 0) to = group.length;
    group.insert(to, item);
    for (var i = 0; i < group.length; i++) {
      group[i].sortOrder = (i + 1) * 10;
    }
    sort = 'manual';
    settings.sort = 'manual';
    await store.persistLibrary(notes);
    await store.saveSettings(settings);
    _notify();
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

  Future<void> openNote(String id) async {
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
    _notify();
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
    await openNote(note.id);
    saveStatus = SaveStatus.saved;
    _notify();
    return note;
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
    } catch (_) {
      saveStatus = SaveStatus.error;
    }
    _notify();
  }

  Future<void> saveNow() async {
    await session?.flush();
    _notify();
  }

  Future<void> reload() async {
    await closeEditor();
    settings = await store.loadSettings();
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
    s.controller.document = Document.fromJson(snapshot.delta);
    s.titleController.text = snapshot.title;
    s.scheduleSave(immediate: true);
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

  int get words => countWords(controller.document.toPlainText());

  String get plainText => controller.document.toPlainText().trimRight();

  void _onEditorChanged() {
    final now = jsonEncode(controller.document.toDelta().toJson());
    if (now != _lastDelta) {
      _lastDelta = now;
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
    dirty = false;
    lastSaved = DateTime.now();
    notifyListeners();
    await app.persistNote(note, snapshot: snapshot);
  }

  Future<void> setMood(int? mood) async {
    note.mood = mood;
    await flush();
  }

  Future<void> setWeather(String? weather) async {
    note.weather = weather;
    await flush();
  }

  Future<void> setKind(NoteKind kind) async {
    note.kind = kind;
    await flush();
  }

  Future<void> setTags(List<String> tags) async {
    note.tags = tags;
    await flush();
  }

  Future<void> setDay(DateTime day) async {
    note.day = dayKey(day);
    await flush();
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
