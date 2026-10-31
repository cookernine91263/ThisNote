import '../data/models.dart';

/// 模板是一段 Quill Delta + 元信息，用户可一键开始。
class NoteTemplate {
  const NoteTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.kind,
    required this.delta,
    this.tags = const [],
    this.title = '',
  });

  final String id;
  final String name;
  final String description;
  final NoteKind kind;
  final List<dynamic> delta;
  final List<String> tags;
  final String title;
}

Map<String, dynamic> _text(String s, [Map<String, dynamic>? attrs]) => {
      'insert': s,
      if (attrs != null && attrs.isNotEmpty) 'attributes': attrs,
    };

Map<String, dynamic> _line([Map<String, dynamic>? attrs]) => {
      'insert': '\n',
      if (attrs != null && attrs.isNotEmpty) 'attributes': attrs,
    };

final List<NoteTemplate> noteTemplates = [
  NoteTemplate(
    id: 'blank',
    name: '空白页',
    description: '从第一行开始，什么都可以',
    kind: NoteKind.note,
    delta: [_line()],
  ),
  NoteTemplate(
    id: 'diary',
    name: '今日日记',
    description: '天气、心情、三件小事与一句摘录',
    kind: NoteKind.diary,
    tags: const ['日记'],
    delta: [
      _text('今天的天气', {'color': '#8D8576'}),
      _line(),
      _text('此刻的心情', {'color': '#8D8576'}),
      _line(),
      _text('三件小事'),
      _line({'header': 2}),
      _text('一、', {'color': '#A84637'}),
      _line(),
      _text('二、', {'color': '#A84637'}),
      _line(),
      _text('三、', {'color': '#A84637'}),
      _line(),
      _text('今日摘录'),
      _line({'header': 2}),
      _text('“', {'color': '#A8824B'}),
      _line(),
    ],
  ),
  NoteTemplate(
    id: 'essay',
    name: '作文',
    description: '题目、开头、正文与结尾的结构',
    kind: NoteKind.essay,
    tags: const ['作文'],
    title: '题目',
    delta: [
      _text('开头'),
      _line({'header': 2}),
      _text('正文'),
      _line({'header': 2}),
      _text('结尾'),
      _line({'header': 2}),
    ],
  ),
  NoteTemplate(
    id: 'reading',
    name: '读书笔记',
    description: '书名、摘抄、想法与行动',
    kind: NoteKind.note,
    tags: const ['读书'],
    delta: [
      _text('书名 / 作者', {'color': '#8D8576'}),
      _line(),
      _text('摘抄'),
      _line({'header': 2}),
      _text('想法'),
      _line({'header': 2}),
      _text('可以去做的一件事'),
      _line({'header': 2}),
    ],
  ),
  NoteTemplate(
    id: 'weekly',
    name: '周记复盘',
    description: '本周高光、卡点、学到的事与下周计划',
    kind: NoteKind.diary,
    tags: const ['周记'],
    delta: [
      _text('本周高光'),
      _line({'header': 2}),
      _text('卡住的地方'),
      _line({'header': 2}),
      _text('学到的一件事'),
      _line({'header': 2}),
      _text('下周只做三件事'),
      _line({'header': 2}),
      _text('· ', {'color': '#A84637'}),
      _line(),
    ],
  ),
  NoteTemplate(
    id: 'letter',
    name: '一封信',
    description: '写给某个人，或写给一年后的自己',
    kind: NoteKind.essay,
    tags: const ['信'],
    delta: [
      _text('写给：', {'color': '#8D8576'}),
      _line(),
      _line(),
      _text('见字如面。', {'font': 'WenKai', 'size': 'large'}),
      _line(),
      _line(),
    ],
  ),
];

/// 首次启动的三篇示例，让空白不显得冷清。
List<Map<String, dynamic>> seedNotes(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final welcome = {
    'id': 'seed-welcome',
    'title': '此记，从一页纸开始',
    'kind': 'note',
    'tags': ['关于此记', '开始'],
    'mood': null,
    'weather': null,
    'pinned': true,
    'favorite': true,
    'createdAt': today.toIso8601String(),
    'updatedAt': today.toIso8601String(),
    'day': _day(today),
    'delta': [
      _text('写给第一次打开它的你：', {'color': '#8D8576'}),
      _line(),
      _text('这里没有社交、没有信息流，只有一张安静的纸。'),
      _line(),
      _text('落笔即心安', {
        'font': 'WenKai',
        'size': 'huge',
        'bold': true,
        'color': '#9E3F32',
      }),
      _line(),
      _text('你可以把它当作日记、随笔本，或是一篇作文的草稿纸。所有内容都保存在你自己的设备里。'),
      _line(),
      _text('三个小建议'),
      _line({'header': 2}),
      _text('· 按 ', {}),
      _text('Ctrl / ⌘ + K', {'code': true}),
      _text(' 打开命令面板，几乎一切都能搜到。'),
      _line(),
      _text('· 选中文字，点工具栏里的 ', {}),
      _text('花字', {'bold': true, 'color': '#A84637'}),
      _text('，让一句话变得郑重。'),
      _line(),
      _text('· 右下角的字数会安静地陪你，不催促。'),
      _line(),
      _line(),
      _text('“写作是把散落的自己，一页一页收回来。”', {
        'italic': true,
        'color': '#8D8576',
      }),
      _line(),
    ],
  };

  final diary = {
    'id': 'seed-diary',
    'title': '十月三十日 · 阴',
    'kind': 'diary',
    'tags': ['日记', '日常'],
    'mood': 3,
    'weather': 'overcast',
    'pinned': false,
    'favorite': false,
    'createdAt': today.subtract(const Duration(days: 1)).toIso8601String(),
    'updatedAt': today.subtract(const Duration(days: 1)).toIso8601String(),
    'day': _day(today.subtract(const Duration(days: 1))),
    'delta': [
      _text('阴天。窗外的银杏比昨天又黄了一点。'),
      _line(),
      _text('三件小事'),
      _line({'header': 2}),
      _text('一、把拖了两周的事做完了，原来只需要一个上午。'),
      _line(),
      _text('二、午后的咖啡太苦，加了一点盐，意外地好喝。'),
      _line(),
      _text('三、给很久没联系的朋友发了一条消息。'),
      _line(),
      _line(),
      _text('今天学到：', {'bold': true}),
      _text('焦虑常常不是因为事情太多，而是因为一直没有开始。'),
      _line(),
    ],
  };

  final essay = {
    'id': 'seed-essay',
    'title': '慢一点，也是一种抵达',
    'kind': 'essay',
    'tags': ['作文', '练习'],
    'mood': null,
    'weather': null,
    'pinned': false,
    'favorite': false,
    'createdAt': today.subtract(const Duration(days: 4)).toIso8601String(),
    'updatedAt': today.subtract(const Duration(days: 4)).toIso8601String(),
    'day': _day(today.subtract(const Duration(days: 4))),
    'delta': [
      _text('我们习惯了把日子过成一条不断加速的线。'),
      _line(),
      _text('可有些东西，只能在慢下来的时候出现：一顿饭的味道，一阵风的方向，一个人没有说出口的话。'),
      _line(),
      _text('慢不是停。慢是把每一步都走实。', {'bold': true}),
      _line(),
      _text('就像写字。急的时候，笔画是飘的；静下来，墨才会落到纸上。'),
      _line(),
      _line(),
      _text('—— 一个普通的下午', {'color': '#8D8576', 'italic': true}),
      _line(),
    ],
  };

  return [welcome, diary, essay];
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
