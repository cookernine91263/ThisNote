class NoteFont {
  const NoteFont({
    required this.value,
    required this.label,
    required this.description,
  });

  final String? value;
  final String label;
  final String description;

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

String fontLabel(String? value) {
  if (value == null || value.isEmpty || value == 'NotoSansSC') return '黑体';
  if (value == 'style:thin') return '细黑';
  for (final font in noteFonts) {
    if (font.value == value) return font.label;
  }
  return '黑体';
}

NoteFont fontFor(String? value) {
  for (final font in noteFonts) {
    if (font.value == value) return font;
  }
  return noteFonts.first;
}
