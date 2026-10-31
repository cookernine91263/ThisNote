import '../../data/models.dart';

class NoteFont {
  const NoteFont({
    required this.value,
    required this.label,
    required this.description,
    this.custom = false,
  });

  final String? value;
  final String label;
  final String description;

  /// 用户自己导入的字体（可删除、不随安装包分发）。
  final bool custom;

  String get family => value ?? 'NotoSansSC';
}

const noteFonts = <NoteFont>[
  NoteFont(
    value: null,
    label: '黑体',
    description: '思源黑体 · 默认，安静清楚',
  ),
  NoteFont(
    value: 'NotoSerifSC',
    label: '宋体',
    description: '思源宋体 · 长文与书信',
  ),
  NoteFont(
    value: 'WenKai',
    label: '文楷',
    description: '霞鹜文楷 · 手写的温度',
  ),
  NoteFont(
    value: 'MaShanZheng',
    label: '手写',
    description: '马善政毛笔 · 一句题目',
  ),
  NoteFont(
    value: 'ZCOOLXiaoWei',
    label: '小薇',
    description: '站酷小薇 · 雅致的标题',
  ),
  NoteFont(
    value: 'NotoSansSCLight',
    label: '细黑',
    description: '思源细体 · 轻盈的呼吸',
  ),
];

String fontLabel(String? value, [List<CustomFont> customFonts = const []]) {
  if (value == null || value.isEmpty || value == 'NotoSansSC') return '黑体';
  if (value == 'style:thin') return '细黑';
  for (final font in allNoteFonts(customFonts)) {
    if (font.value == value) return font.label;
  }
  return '黑体';
}

NoteFont fontFor(String? value, [List<CustomFont> customFonts = const []]) {
  for (final font in allNoteFonts(customFonts)) {
    if (font.value == value) return font;
  }
  return noteFonts.first;
}

/// 内置字体 + 用户导入的字体，顺序固定：内置在前，自己的排在后面。
List<NoteFont> allNoteFonts([List<CustomFont> customFonts = const []]) => [
      ...noteFonts,
      for (final font in customFonts)
        NoteFont(
          value: font.id,
          label: font.name,
          description: '导入的字体 · 本地文件',
          custom: true,
        ),
    ];
