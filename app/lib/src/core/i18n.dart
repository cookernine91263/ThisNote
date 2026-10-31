import 'package:flutter/widgets.dart';

/// 界面语言。设置里可以切换，首次启动的引导页也可以直接选。
enum AppLang {
  zh,
  en;

  static AppLang fromCode(String? code) =>
      code == 'en' ? AppLang.en : AppLang.zh;

  String get code => this == AppLang.en ? 'en' : 'zh';

  /// 给 MaterialApp 用的 locale。
  Locale get locale =>
      this == AppLang.en ? const Locale('en', 'US') : const Locale('zh', 'CN');
}

/// 全局语言状态。
///
/// 界面里的中文原文直接写在调用处（`tr('保存')`），英文放在各文件自己的
/// [_en] 表里；这样改文案时中文和英文就在同一个屏幕上，不需要记 key。
/// 语言切换时 AppState 会更新 [I18n.lang]，MaterialApp 的 locale 跟着换，
/// 整棵树重建，表格里的英文即时生效。
class I18n {
  static AppLang lang = AppLang.zh;

  static bool get isEn => lang == AppLang.en;

  /// 全局通用词。各页面自己的表优先，找不到再回落到这里。
  static const Map<String, String> common = <String, String>{
    '此记': 'ThisNote',
    '此记 · ThisNote': 'ThisNote',
    '确定': 'OK',
    '取消': 'Cancel',
    '保存': 'Save',
    '删除': 'Delete',
    '关闭': 'Close',
    '重试': 'Retry',
    '恢复': 'Restore',
    '编辑': 'Edit',
    '复制': 'Duplicate',
    '新建': 'New',
    '搜索': 'Search',
    '设置': 'Settings',
    '今日': 'Today',
    '全部': 'All',
    '日历': 'Calendar',
    '标签': 'Tags',
    '统计': 'Stats',
    '命令': 'Commands',
    '专注': 'Focus',
    '外观': 'Appearance',
    '回收': 'Trash',
    '文件夹': 'Folder',
    '无题': 'Untitled',
    '完成': 'Done',
    '下一步': 'Next',
    '跳过': 'Skip',
    '继续': 'Continue',
    '更多': 'More',
    '返回': 'Back',
    '上一步': 'Back',
    '开始写': 'Start writing',
    '写一句': 'Write a line',
    '保存中': 'Saving',
    '已保存': 'Saved',
    '未保存': 'Unsaved',
    '字数': 'Words',
    '篇': 'notes',
    '字': 'words',
    '今天': 'Today',
    '昨天': 'Yesterday',
    '刚刚': 'just now',
    '星期一': 'Monday',
    '星期二': 'Tuesday',
    '星期三': 'Wednesday',
    '星期四': 'Thursday',
    '星期五': 'Friday',
    '星期六': 'Saturday',
    '星期日': 'Sunday',
    '日记': 'Diary',
    '随笔': 'Note',
    '作文': 'Essay',
    '写日记': 'Write a diary',
    '写随笔': 'Write a note',
    '写作文': 'Write an essay',
    '平静': 'Calm',
    '愉悦': 'Glad',
    '充实': 'Full',
    '疲惫': 'Tired',
    '低落': 'Low',
    '晴': 'Sunny',
    '多云': 'Cloudy',
    '阴': 'Overcast',
    '雨': 'Rain',
    '雪': 'Snow',
    '风': 'Wind',
    '未命名': 'Untitled',
    '暂无': 'None',
    '所有笔记': 'All notes',
    '新建笔记': 'New note',
    '粘贴为纯文本': 'Paste as plain text',
    '立即保存': 'Save now',
    '查找': 'Find',
    '查找替换': 'Find & replace',
    '加粗': 'Bold',
    '倾斜': 'Italic',
    '下划线': 'Underline',
    '专注模式': 'Focus mode',
    '命令面板': 'Command palette',
    '返回首页': 'Back to home',
    '语言': 'Language',
    '中文': '中文',
    'English': 'English',
    '界面语言': 'Interface language',
    '选择语言': 'Choose a language',
    '随时可在设置里更改': 'You can change this later in Settings',
  };

  static String tr(
    String zh, [
    Map<String, Object?>? args,
    Map<String, String>? table,
  ]) {
    var text = zh;
    if (lang == AppLang.en) {
      text = table?[zh] ?? common[zh] ?? zh;
    }
    if (args != null && args.isNotEmpty) {
      args.forEach((key, value) {
        text = text.replaceAll('{$key}', '$value');
      });
    }
    return text;
  }

  /// 英文数量：1 note / 2 notes。
  static String plural(int n, String one, [String? many]) =>
      n == 1 ? one : (many ?? '${one}s');

  /// 中文量词在英文里通常要跟着名词一起变，集中放这里方便复用。
  static String count(int n, String zhUnit, String enOne, [String? enMany]) {
    if (lang == AppLang.zh) return '$n $zhUnit';
    return '$n ${plural(n, enOne, enMany)}';
  }

  /// 读取当前 locale 对应的语言，让依赖 Localizations 的组件在切换时重建。
  static AppLang of(BuildContext context) {
    final code = Localizations.maybeLocaleOf(context)?.languageCode;
    return code == 'en' ? AppLang.en : lang;
  }
}

/// 全局翻译入口。带 `{name}` 的占位符由 [args] 填入。
String tr(
  String zh, [
  Map<String, Object?>? args,
  Map<String, String>? table,
]) =>
    I18n.tr(zh, args, table);
