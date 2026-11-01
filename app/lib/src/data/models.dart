import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/format.dart';
import '../core/i18n.dart';

/// 只影响显示文案，枚举的 key / 分数 / id 一律不动，存档格式保持稳定。
const _kindEn = <String, String>{
  '日记': 'Diary',
  '作文': 'Essay',
  '随笔': 'Note',
  '写日记': 'Write a diary',
  '写作文': 'Write an essay',
  '写随笔': 'Write a note',
};

const _moodEn = <String, String>{
  '平静': 'Calm',
  '愉悦': 'Glad',
  '充实': 'Full',
  '疲惫': 'Tired',
  '低落': 'Low',
};

const _weatherEn = <String, String>{
  '晴': 'Sunny',
  '多云': 'Cloudy',
  '阴': 'Overcast',
  '雨': 'Rain',
  '雪': 'Snow',
  '风': 'Wind',
};

const _folderEn = <String, String>{
  '文件夹': 'Folder',
};

enum NoteKind { diary, essay, note }

extension NoteKindX on NoteKind {
  String get key => switch (this) {
        NoteKind.diary => 'diary',
        NoteKind.essay => 'essay',
        NoteKind.note => 'note',
      };

  String get label => switch (this) {
        NoteKind.diary => tr('日记', null, _kindEn),
        NoteKind.essay => tr('作文', null, _kindEn),
        NoteKind.note => tr('随笔', null, _kindEn),
      };

  String get verb => switch (this) {
        NoteKind.diary => tr('写日记', null, _kindEn),
        NoteKind.essay => tr('写作文', null, _kindEn),
        NoteKind.note => tr('写随笔', null, _kindEn),
      };

  static NoteKind fromKey(String? key) => switch (key) {
        'diary' => NoteKind.diary,
        'essay' => NoteKind.essay,
        _ => NoteKind.note,
      };
}

enum Mood { calm, glad, full, tired, low }

extension MoodX on Mood {
  int get score => index + 1;

  String get label => switch (this) {
        Mood.calm => tr('平静', null, _moodEn),
        Mood.glad => tr('愉悦', null, _moodEn),
        Mood.full => tr('充实', null, _moodEn),
        Mood.tired => tr('疲惫', null, _moodEn),
        Mood.low => tr('低落', null, _moodEn),
      };

  String get emoji => switch (this) {
        Mood.calm => '◡',
        Mood.glad => '⌣',
        Mood.full => '✦',
        Mood.tired => '﹏',
        Mood.low => '︵',
      };

  Color get color => switch (this) {
        Mood.calm => const Color(0xFF7C8B95),
        Mood.glad => const Color(0xFFB08A4F),
        Mood.full => const Color(0xFFB0573F),
        Mood.tired => const Color(0xFF8C7F6B),
        Mood.low => const Color(0xFF6C7A86),
      };

  static Mood? fromScore(int? score) {
    if (score == null || score < 1 || score > Mood.values.length) return null;
    return Mood.values[score - 1];
  }
}

enum Weather { sunny, cloudy, overcast, rain, snow, wind }

extension WeatherX on Weather {
  String get key => name;

  String get label => switch (this) {
        Weather.sunny => tr('晴', null, _weatherEn),
        Weather.cloudy => tr('多云', null, _weatherEn),
        Weather.overcast => tr('阴', null, _weatherEn),
        Weather.rain => tr('雨', null, _weatherEn),
        Weather.snow => tr('雪', null, _weatherEn),
        Weather.wind => tr('风', null, _weatherEn),
      };

  static Weather? fromKey(String? key) {
    if (key == null) return null;
    for (final w in Weather.values) {
      if (w.key == key) return w;
    }
    return null;
  }
}

class NoteMeta {
  NoteMeta({
    required this.id,
    required this.title,
    required this.text,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.mood,
    this.weather,
    this.pinned = false,
    this.favorite = false,
    this.deletedAt,
    this.words = 0,
    this.writingSeconds = 0,
    this.folderId,
    this.sortOrder = 0,
    required this.day,
  });

  final String id;
  String title;
  String text;
  NoteKind kind;
  List<String> tags;
  int? mood;
  String? weather;
  bool pinned;
  bool favorite;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;
  int words;

  /// 真正动笔的时长（秒），停顿超过一分钟不计入。见 [EditorSession]。
  int writingSeconds;
  String day;
  String? folderId;
  int sortOrder;

  String get excerpt => excerptOf(text);
  bool get isTrashed => deletedAt != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'text': text,
        'kind': kind.key,
        'tags': tags,
        'mood': mood,
        'weather': weather,
        'pinned': pinned,
        'favorite': favorite,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'deletedAt': deletedAt?.toIso8601String(),
        'words': words,
        'writingSeconds': writingSeconds,
        'day': day,
        'folderId': folderId,
        'sortOrder': sortOrder,
      };

  factory NoteMeta.fromJson(Map<String, dynamic> j) => NoteMeta(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        text: (j['text'] as String?) ?? '',
        kind: NoteKindX.fromKey(j['kind'] as String?),
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        mood: j['mood'] as int?,
        weather: j['weather'] as String?,
        pinned: (j['pinned'] as bool?) ?? false,
        favorite: (j['favorite'] as bool?) ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        deletedAt: j['deletedAt'] == null
            ? null
            : DateTime.tryParse(j['deletedAt'] as String),
        words: (j['words'] as int?) ?? 0,
        writingSeconds: (j['writingSeconds'] as int?) ?? 0,
        day: (j['day'] as String?) ?? dayKey(DateTime.now()),
        folderId: j['folderId'] as String?,
        sortOrder: (j['sortOrder'] as int?) ?? 0,
      );

  NoteMeta copyWith({
    String? title,
    String? text,
    NoteKind? kind,
    List<String>? tags,
    int? mood,
    String? weather,
    bool? pinned,
    bool? favorite,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    int? words,
    int? writingSeconds,
    String? day,
    String? folderId,
    bool clearFolder = false,
    int? sortOrder,
  }) =>
      NoteMeta(
        id: id,
        title: title ?? this.title,
        text: text ?? this.text,
        kind: kind ?? this.kind,
        tags: tags ?? this.tags,
        mood: mood ?? this.mood,
        weather: weather ?? this.weather,
        pinned: pinned ?? this.pinned,
        favorite: favorite ?? this.favorite,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        words: words ?? this.words,
        writingSeconds: writingSeconds ?? this.writingSeconds,
        day: day ?? this.day,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        sortOrder: sortOrder ?? this.sortOrder,
      );
}

class Folder {
  Folder({
    required this.id,
    required this.name,
    this.parentId,
    this.order = 0,
  });

  final String id;
  String name;
  String? parentId;
  int order;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'order': order,
      };

  factory Folder.fromJson(Map<String, dynamic> j) => Folder(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? tr('文件夹', null, _folderEn),
        parentId: j['parentId'] as String?,
        order: (j['order'] as int?) ?? 0,
      );

  Folder copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    int? order,
  }) =>
      Folder(
        id: id,
        name: name ?? this.name,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        order: order ?? this.order,
      );
}

class Note {
  Note({
    required this.id,
    required this.title,
    required this.delta,
    required this.text,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const [],
    this.mood,
    this.weather,
    this.pinned = false,
    this.favorite = false,
    this.deletedAt,
    this.words = 0,
    this.writingSeconds = 0,
    this.folderId,
    this.sortOrder = 0,
    required this.day,
  });

  final String id;
  String title;

  /// Quill Delta operations，直接序列化保存。
  List<dynamic> delta;
  String text;
  NoteKind kind;
  List<String> tags;
  int? mood;
  String? weather;
  bool pinned;
  bool favorite;
  DateTime createdAt;
  DateTime updatedAt;
  DateTime? deletedAt;
  int words;

  /// 真正动笔的时长（秒），停顿超过一分钟不计入。
  int writingSeconds;
  String day;
  String? folderId;
  int sortOrder;

  String get excerpt => excerptOf(text);
  bool get isTrashed => deletedAt != null;

  NoteMeta toMeta() => NoteMeta(
        id: id,
        title: title,
        text: text,
        kind: kind,
        tags: tags,
        mood: mood,
        weather: weather,
        pinned: pinned,
        favorite: favorite,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        words: words,
        writingSeconds: writingSeconds,
        day: day,
        folderId: folderId,
        sortOrder: sortOrder,
      );

  factory Note.fromMeta(NoteMeta meta, {List<dynamic>? delta, String? text}) =>
      Note(
        id: meta.id,
        title: meta.title,
        delta: delta ?? [
          {'insert': '\n'}
        ],
        text: text ?? meta.text,
        kind: meta.kind,
        tags: meta.tags,
        mood: meta.mood,
        weather: meta.weather,
        pinned: meta.pinned,
        favorite: meta.favorite,
        createdAt: meta.createdAt,
        updatedAt: meta.updatedAt,
        deletedAt: meta.deletedAt,
        words: meta.words,
        writingSeconds: meta.writingSeconds,
        day: meta.day,
        folderId: meta.folderId,
        sortOrder: meta.sortOrder,
      );

  Map<String, dynamic> toJson() => {
        ...toMeta().toJson(),
        'delta': delta,
      };

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        delta: (j['delta'] as List?) ?? [
          {'insert': '\n'}
        ],
        text: (j['text'] as String?) ?? '',
        kind: NoteKindX.fromKey(j['kind'] as String?),
        tags: (j['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
        mood: j['mood'] as int?,
        weather: j['weather'] as String?,
        pinned: (j['pinned'] as bool?) ?? false,
        favorite: (j['favorite'] as bool?) ?? false,
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        deletedAt: j['deletedAt'] == null
            ? null
            : DateTime.tryParse(j['deletedAt'] as String),
        words: (j['words'] as int?) ?? 0,
        writingSeconds: (j['writingSeconds'] as int?) ?? 0,
        day: (j['day'] as String?) ?? dayKey(DateTime.now()),
        folderId: j['folderId'] as String?,
        sortOrder: (j['sortOrder'] as int?) ?? 0,
      );
}

class Snapshot {
  Snapshot({
    required this.savedAt,
    required this.title,
    required this.delta,
    required this.text,
    required this.words,
  });

  final DateTime savedAt;
  final String title;
  final List<dynamic> delta;
  final String text;
  final int words;

  Map<String, dynamic> toJson() => {
        'savedAt': savedAt.toIso8601String(),
        'title': title,
        'delta': delta,
        'text': text,
        'words': words,
      };

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        savedAt: DateTime.tryParse(j['savedAt'] as String? ?? '') ??
            DateTime.now(),
        title: (j['title'] as String?) ?? '',
        delta: (j['delta'] as List?) ?? const [],
        text: (j['text'] as String?) ?? '',
        words: (j['words'] as int?) ?? 0,
      );
}

/// 思考强度：决定给模型的输出预算、温度，也决定界面上的默认语气。
///
/// 很多「思考型」模型会把一部分预算花在推理上，预算给小了就会只返回思考、
/// 没有正文。这里给三档，由用户自己选，而不是藏在代码里。
enum AiThinking {
  fast('fast', 900, 0.4),
  balanced('balanced', 2000, 0.7),
  deep('deep', 4000, 0.9);

  const AiThinking(this.key, this.maxTokens, this.temperature);

  final String key;
  final int maxTokens;
  final double temperature;

  static AiThinking fromKey(String? key) => values.firstWhere(
        (level) => level.key == key,
        orElse: () => balanced,
      );
}

class AiSettings {
  AiSettings({
    this.enabled = false,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.thinking = 'balanced',
  });

  bool enabled;
  String baseUrl;
  String apiKey;
  String model;

  /// 'fast' / 'balanced' / 'deep'，见 [AiThinking]。
  String thinking;

  AiThinking get thinkingLevel => AiThinking.fromKey(thinking);

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'model': model,
        'thinking': thinking,
      };

  factory AiSettings.fromJson(Map<String, dynamic>? j) => AiSettings(
        enabled: (j?['enabled'] as bool?) ?? false,
        baseUrl: (j?['baseUrl'] as String?) ?? 'https://api.deepseek.com/v1',
        apiKey: (j?['apiKey'] as String?) ?? '',
        model: (j?['model'] as String?) ?? 'deepseek-chat',
        thinking: (j?['thinking'] as String?) ?? 'balanced',
      );

  bool get configured => enabled && apiKey.trim().isNotEmpty;
}

enum AiRole { user, assistant }

/// AI 对话里的一条消息。用户消息可以带「引用选区」，
/// 助手消息会把它记在 quoteStart/quoteEnd 上，方便稍后替换回正文。
class AiMessage {
  AiMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.action = '',
    this.quote = '',
    this.quoteStart,
    this.quoteEnd,
    this.revision,
    this.error = false,
    this.interrupted = false,
  });

  final String id;
  final AiRole role;
  final String text;
  final DateTime at;
  final String action;
  final String quote;
  final int? quoteStart;
  final int? quoteEnd;
  final int? revision;
  final bool error;
  final bool interrupted;

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'text': text,
        'at': at.toIso8601String(),
        'action': action,
        'quote': quote,
        'quoteStart': quoteStart,
        'quoteEnd': quoteEnd,
        'revision': revision,
        'error': error,
        'interrupted': interrupted,
      };

  factory AiMessage.fromJson(Map<String, dynamic> j) => AiMessage(
        id: (j['id'] as String?) ?? '',
        role: (j['role'] as String?) == 'assistant'
            ? AiRole.assistant
            : AiRole.user,
        text: (j['text'] as String?) ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        action: (j['action'] as String?) ?? '',
        quote: (j['quote'] as String?) ?? '',
        quoteStart: (j['quoteStart'] as num?)?.toInt(),
        quoteEnd: (j['quoteEnd'] as num?)?.toInt(),
        revision: (j['revision'] as num?)?.toInt(),
        error: (j['error'] as bool?) ?? false,
        interrupted: (j['interrupted'] as bool?) ?? false,
      );
}

/// 一篇笔记对应一段持久的 AI 对话，存放在 `conversations/<noteId>.json`。
class AiConversation {
  AiConversation({
    required this.noteId,
    List<AiMessage>? messages,
    this.system = '',
    DateTime? updatedAt,
    this.version = 1,
  })  : messages = messages ?? <AiMessage>[],
        updatedAt = updatedAt ?? DateTime.now();

  final String noteId;
  final List<AiMessage> messages;
  String system;
  DateTime updatedAt;
  final int version;

  Map<String, dynamic> toJson() => {
        'version': version,
        'noteId': noteId,
        'system': system,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((e) => e.toJson()).toList(),
      };

  factory AiConversation.fromJson(String noteId, Map<String, dynamic> j) =>
      AiConversation(
        noteId: (j['noteId'] as String?) ?? noteId,
        system: (j['system'] as String?) ?? '',
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        version: (j['version'] as num?)?.toInt() ?? 1,
        messages: ((j['messages'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => AiMessage.fromJson(e.cast<String, dynamic>()))
            .toList(),
      );
}

class WebDavSettings {
  WebDavSettings({
    this.enabled = false,
    this.url = '',
    this.username = '',
    this.password = '',
    this.folder = '/ThisNote',
  });

  bool enabled;
  String url;
  String username;
  String password;
  String folder;

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'url': url,
        'username': username,
        'password': password,
        'folder': folder,
      };

  factory WebDavSettings.fromJson(Map<String, dynamic>? j) => WebDavSettings(
        enabled: (j?['enabled'] as bool?) ?? false,
        url: (j?['url'] as String?) ?? '',
        username: (j?['username'] as String?) ?? '',
        password: (j?['password'] as String?) ?? '',
        folder: (j?['folder'] as String?) ?? '/ThisNote',
      );

  bool get configured =>
      enabled && url.trim().isNotEmpty && username.trim().isNotEmpty;
}

/// 用户自己导入的字体。文件放在数据目录的 `fonts/` 下，
/// [id] 同时作为运行时注册的字体族名，写进正文的 `font` 属性里。
class CustomFont {
  CustomFont({
    required this.id,
    required this.name,
    required this.file,
  });

  final String id;
  String name;
  String file;

  bool get valid => id.trim().isNotEmpty && file.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'file': file,
      };

  factory CustomFont.fromJson(Map<String, dynamic>? j) => CustomFont(
        id: (j?['id'] as String?) ?? '',
        name: (j?['name'] as String?) ?? '',
        file: (j?['file'] as String?) ?? '',
      );
}

class AppSettings {
  AppSettings({
    this.themeMode = ThemeMode.light,
    this.language = 'zh',
    this.accent = 'vermilion',
    this.uiScale = 1.0,
    this.paperTexture = true,
    this.editorWidth = 720,
    this.editorScale = 1,
    this.lineHeight = 1.9,
    this.paragraphGap = 0,
    this.letterSpacing = 0.15,
    this.dailyGoal = 500,
    this.lockEnabled = false,
    this.pinHash,
    this.pinSalt,
    this.onboardingDone = false,
    this.lastView = 'today',
    this.lastListView = 'today',
    this.sort = 'updated',
    this.savedColors = const [],
    this.customFonts = const [],
    this.ai,
    this.webdav,
  });

  ThemeMode themeMode;

  /// 'zh' 或 'en'。界面语言，首次启动的引导页可以直接选。
  String language;
  String accent;
  double uiScale;
  bool paperTexture;
  double editorWidth;
  double editorScale;
  double lineHeight;
  double paragraphGap;
  double letterSpacing;
  int dailyGoal;
  bool lockEnabled;
  String? pinHash;
  String? pinSalt;
  bool onboardingDone;
  String lastView;

  /// 手机底部「笔记」tab 上次停留的列表视图（today / all / tags / trash / search）。
  String lastListView;
  String sort;
  List<String> savedColors;
  List<CustomFont> customFonts;
  AiSettings? ai;
  WebDavSettings? webdav;

  AiSettings get aiSettings => ai ??= AiSettings();
  WebDavSettings get webdavSettings => webdav ??= WebDavSettings();

  Map<String, dynamic> toJson() => {
        'themeMode': themeMode.name,
        'language': language,
        'accent': accent,
        'uiScale': uiScale,
        'paperTexture': paperTexture,
        'editorWidth': editorWidth,
        'editorScale': editorScale,
        'lineHeight': lineHeight,
        'paragraphGap': paragraphGap,
        'letterSpacing': letterSpacing,
        'dailyGoal': dailyGoal,
        'lockEnabled': lockEnabled,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'onboardingDone': onboardingDone,
        'lastView': lastView,
        'lastListView': lastListView,
        'sort': sort,
        'savedColors': savedColors,
        'customFonts': customFonts.map((e) => e.toJson()).toList(),
        'ai': aiSettings.toJson(),
        'webdav': webdavSettings.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        themeMode: switch (j['themeMode']) {
          'system' => ThemeMode.system,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.light,
        },
        language: (j['language'] as String?) == 'en' ? 'en' : 'zh',
        accent: (j['accent'] as String?) ?? 'vermilion',
        uiScale: ((j['uiScale'] as num?) ?? 1.0).toDouble(),
        paperTexture: (j['paperTexture'] as bool?) ?? true,
        editorWidth: ((j['editorWidth'] as num?) ?? 720).toDouble(),
        editorScale: ((j['editorScale'] as num?) ?? 1).toDouble(),
        lineHeight: ((j['lineHeight'] as num?) ?? 1.9).toDouble(),
        paragraphGap: ((j['paragraphGap'] as num?) ?? 0).toDouble(),
        letterSpacing: ((j['letterSpacing'] as num?) ?? 0.15).toDouble(),
        dailyGoal: (j['dailyGoal'] as int?) ?? 500,
        lockEnabled: (j['lockEnabled'] as bool?) ?? false,
        pinHash: j['pinHash'] as String?,
        pinSalt: j['pinSalt'] as String?,
        onboardingDone: (j['onboardingDone'] as bool?) ?? false,
        lastView: (j['lastView'] as String?) ?? 'today',
        lastListView: (j['lastListView'] as String?) ?? 'today',
        sort: (j['sort'] as String?) ?? 'updated',
        savedColors: (j['savedColors'] as List?)
                ?.whereType<String>()
                .toList(growable: true) ??
            <String>[],
        customFonts: ((j['customFonts'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => CustomFont.fromJson(e.cast<String, dynamic>()))
            .where((e) => e.valid)
            .toList(growable: true),
        ai: j['ai'] is Map<String, dynamic>
            ? AiSettings.fromJson(j['ai'] as Map<String, dynamic>)
            : null,
        webdav: j['webdav'] is Map<String, dynamic>
            ? WebDavSettings.fromJson(j['webdav'] as Map<String, dynamic>)
            : null,
      );

  static AppSettings fromJsonString(String raw) {
    try {
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings();
    }
  }
}
