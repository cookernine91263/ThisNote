import '../core/i18n.dart';
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

/// 用户自己存下来的模板。只在这台设备上，随备份一起走。
class UserTemplate {
  const UserTemplate({
    required this.id,
    required this.name,
    required this.title,
    required this.delta,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String title;
  final List<dynamic> delta;
  final List<String> tags;

  NoteTemplate toNoteTemplate() => NoteTemplate(
        id: id,
        name: name,
        description: '我的模板',
        kind: NoteKind.note,
        delta: delta,
        tags: tags,
        title: title,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'title': title,
        'delta': delta,
        'tags': tags,
      };

  factory UserTemplate.fromJson(Map<String, dynamic> json) => UserTemplate(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        title: (json['title'] as String?) ?? '',
        delta: (json['delta'] as List?) ?? const [],
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );

  bool get valid => id.isNotEmpty && name.isNotEmpty;
}

Map<String, dynamic> _text(String s, [Map<String, dynamic>? attrs]) => {
      'insert': s,
      if (attrs != null && attrs.isNotEmpty) 'attributes': attrs,
    };

Map<String, dynamic> _line([Map<String, dynamic>? attrs]) => {
      'insert': '\n',
      if (attrs != null && attrs.isNotEmpty) 'attributes': attrs,
    };

/// 模板与示例笔记的英文表。模板在每次取用时按当前语言翻译，
/// 所以切换语言后新建的笔记会立刻用上新语言的标题、标签与正文。
const _en = <String, String>{
  // —— 模板元信息 ——
  '空白页': 'Blank page',
  '从第一行开始，什么都可以': 'Start with the first line. Anything goes.',
  '今日日记': "Today's diary",
  '天气、心情、三件小事与一句摘录':
      'Weather, mood, three small things, and a line worth keeping',
  '作文': 'Essay',
  '题目、开头、正文与结尾的结构':
      'A title, an opening, a body, and a close',
  '题目': 'Title',
  '读书笔记': 'Reading notes',
  '书名、摘抄、想法与行动': 'Book, passages, thoughts, and one thing to do',
  '周记复盘': 'Weekly review',
  '本周高光、卡点、学到的事与下周计划':
      "This week's highlights, sticking points, lessons, and next week's plan",
  '一封信': 'A letter',
  '写给某个人，或写给一年后的自己':
      'To someone you miss, or to yourself a year from now',
  // —— 模板标签 ——
  '日记': 'Diary',
  '随笔': 'Note',
  '读书': 'Reading',
  '周记': 'Weekly',
  '信': 'Letter',
  // —— 模板正文 ——
  '今天的天气': 'Weather today',
  '此刻的心情': 'Mood right now',
  '三件小事': 'Three small things',
  '一、': '1. ',
  '二、': '2. ',
  '三、': '3. ',
  '今日摘录': 'A line worth keeping',
  '开头': 'Opening',
  '正文': 'Body',
  '结尾': 'Closing',
  '书名 / 作者': 'Title / Author',
  '摘抄': 'Passages',
  '想法': 'Thoughts',
  '可以去做的一件事': 'One thing to try',
  '本周高光': 'Highlights of the week',
  '卡住的地方': 'Where it got stuck',
  '学到的一件事': 'One thing I learned',
  '下周只做三件事': 'Three things for next week',
  '写给：': 'To: ',
  '见字如面。': 'I hope this finds you well.',
  // —— 示例笔记：欢迎页 ——
  '此记，从一页纸开始': 'ThisNote begins with a single page',
  '关于此记': 'About ThisNote',
  '开始': 'Start',
  '写给第一次打开它的你：': 'For you, opening this for the first time:',
  '这里没有社交、没有信息流，只有一张安静的纸。':
      'No feed, no followers — just one quiet sheet of paper.',
  '落笔即心安': 'Begin, and the mind settles',
  '你可以把它当作日记、随笔本，或是一篇作文的草稿纸。所有内容都保存在你自己的设备里。':
      'Use it as a diary, a notebook, or scratch paper for an essay. '
          'Everything stays on your own device.',
  '三个小建议': 'Three small suggestions',
  '· 按 ': '· Press ',
  ' 打开命令面板，几乎一切都能搜到。':
      ' to open the command palette — almost everything is searchable.',
  '· 选中文字，点工具栏里的 ': '· Select some text, then tap ',
  '花字': 'Flower Text',
  '，让一句话变得郑重。':
      ' in the toolbar to give a sentence a little ceremony.',
  '· 右下角的字数会安静地陪你，不催促。':
      '· The word count in the corner keeps you company, quietly, never rushing.',
  '“写作是把散落的自己，一页一页收回来。”':
      '“Writing is gathering your scattered self back, one page at a time.”',
  // —— 示例笔记：日记 ——
  '十月三十日 · 阴': 'October 30 · Overcast',
  '日常': 'Everyday',
  '阴天。窗外的银杏比昨天又黄了一点。':
      'Overcast. The ginkgo outside the window is a shade more yellow than yesterday.',
  '一、把拖了两周的事做完了，原来只需要一个上午。':
      '1. Finished the thing I had put off for two weeks. It took one morning.',
  '二、午后的咖啡太苦，加了一点盐，意外地好喝。':
      '2. The afternoon coffee was too bitter, so I added a pinch of salt. Surprisingly good.',
  '三、给很久没联系的朋友发了一条消息。':
      '3. Sent a message to a friend I had not spoken to in ages.',
  '今天学到：': 'Learned today: ',
  '焦虑常常不是因为事情太多，而是因为一直没有开始。':
      'Anxiety usually comes not from having too much to do, but from never starting.',
  // —— 示例笔记：作文 ——
  '慢一点，也是一种抵达': 'Going slower is also a way of arriving',
  '练习': 'Practice',
  '我们习惯了把日子过成一条不断加速的线。':
      'We are used to living our days as a line that keeps accelerating.',
  '可有些东西，只能在慢下来的时候出现：一顿饭的味道，一阵风的方向，一个人没有说出口的话。':
      'But some things only appear once we slow down: the taste of a meal, '
          'the direction of a breeze, the words someone never said aloud.',
  '慢不是停。慢是把每一步都走实。':
      'Slowing down is not stopping. It is making every step solid.',
  '就像写字。急的时候，笔画是飘的；静下来，墨才会落到纸上。':
      'Like writing. In a hurry the strokes float; when you settle, '
          'the ink finally lands on the page.',
  '—— 一个普通的下午': '— An ordinary afternoon',
};

String _t(String zh) => tr(zh, null, _en);

/// 模板列表不缓存：每次取用都按当前语言重建，
/// 避免应用启动时把某一门语言永久冻结在模板里。
List<NoteTemplate> get noteTemplates => [
      NoteTemplate(
        id: 'blank',
        name: _t('空白页'),
        description: _t('从第一行开始，什么都可以'),
        kind: NoteKind.note,
        delta: [_line()],
      ),
      NoteTemplate(
        id: 'diary',
        name: _t('今日日记'),
        description: _t('天气、心情、三件小事与一句摘录'),
        kind: NoteKind.diary,
        tags: [_t('日记')],
        delta: [
          _text(_t('今天的天气'), {'color': '#8D8576'}),
          _line(),
          _text(_t('此刻的心情'), {'color': '#8D8576'}),
          _line(),
          _text(_t('三件小事')),
          _line({'header': 2}),
          _text(_t('一、'), {'color': '#A84637'}),
          _line(),
          _text(_t('二、'), {'color': '#A84637'}),
          _line(),
          _text(_t('三、'), {'color': '#A84637'}),
          _line(),
          _text(_t('今日摘录')),
          _line({'header': 2}),
          _text('“', {'color': '#A8824B'}),
          _line(),
        ],
      ),
      NoteTemplate(
        id: 'essay',
        name: _t('作文'),
        description: _t('题目、开头、正文与结尾的结构'),
        kind: NoteKind.essay,
        tags: [_t('作文')],
        title: _t('题目'),
        delta: [
          _text(_t('开头')),
          _line({'header': 2}),
          _text(_t('正文')),
          _line({'header': 2}),
          _text(_t('结尾')),
          _line({'header': 2}),
        ],
      ),
      NoteTemplate(
        id: 'reading',
        name: _t('读书笔记'),
        description: _t('书名、摘抄、想法与行动'),
        kind: NoteKind.note,
        tags: [_t('读书')],
        delta: [
          _text(_t('书名 / 作者'), {'color': '#8D8576'}),
          _line(),
          _text(_t('摘抄')),
          _line({'header': 2}),
          _text(_t('想法')),
          _line({'header': 2}),
          _text(_t('可以去做的一件事')),
          _line({'header': 2}),
        ],
      ),
      NoteTemplate(
        id: 'weekly',
        name: _t('周记复盘'),
        description: _t('本周高光、卡点、学到的事与下周计划'),
        kind: NoteKind.diary,
        tags: [_t('周记')],
        delta: [
          _text(_t('本周高光')),
          _line({'header': 2}),
          _text(_t('卡住的地方')),
          _line({'header': 2}),
          _text(_t('学到的一件事')),
          _line({'header': 2}),
          _text(_t('下周只做三件事')),
          _line({'header': 2}),
          _text('· ', {'color': '#A84637'}),
          _line(),
        ],
      ),
      NoteTemplate(
        id: 'letter',
        name: _t('一封信'),
        description: _t('写给某个人，或写给一年后的自己'),
        kind: NoteKind.essay,
        tags: [_t('信')],
        delta: [
          _text(_t('写给：'), {'color': '#8D8576'}),
          _line(),
          _line(),
          _text(_t('见字如面。'), {'font': 'WenKai', 'size': 'large'}),
          _line(),
          _line(),
        ],
      ),
    ];

/// 首次启动的三篇示例，让空白不显得冷清。
///
/// 标题、标签与正文都在调用时翻译：种子笔记跟随「首次启动时的语言」。
List<Map<String, dynamic>> seedNotes(DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final welcome = {
    'id': 'seed-welcome',
    'title': _t('此记，从一页纸开始'),
    'kind': 'note',
    'tags': [_t('关于此记'), _t('开始')],
    'mood': null,
    'weather': null,
    'pinned': true,
    'favorite': true,
    'createdAt': today.toIso8601String(),
    'updatedAt': today.toIso8601String(),
    'day': _day(today),
    'delta': [
      _text(_t('写给第一次打开它的你：'), {'color': '#8D8576'}),
      _line(),
      _text(_t('这里没有社交、没有信息流，只有一张安静的纸。')),
      _line(),
      _text(_t('落笔即心安'), {
        'font': 'WenKai',
        'size': 'huge',
        'bold': true,
        'color': '#9E3F32',
      }),
      _line(),
      _text(_t('你可以把它当作日记、随笔本，或是一篇作文的草稿纸。所有内容都保存在你自己的设备里。')),
      _line(),
      _text(_t('三个小建议')),
      _line({'header': 2}),
      _text(_t('· 按 '), {}),
      _text(I18n.isEn ? 'Ctrl / Cmd + K' : 'Ctrl / ⌘ + K', {'code': true}),
      _text(_t(' 打开命令面板，几乎一切都能搜到。')),
      _line(),
      _text(_t('· 选中文字，点工具栏里的 '), {}),
      _text(_t('花字'), {'bold': true, 'color': '#A84637'}),
      _text(_t('，让一句话变得郑重。')),
      _line(),
      _text(_t('· 右下角的字数会安静地陪你，不催促。')),
      _line(),
      _line(),
      _text(_t('“写作是把散落的自己，一页一页收回来。”'), {
        'italic': true,
        'color': '#8D8576',
      }),
      _line(),
    ],
  };

  final diary = {
    'id': 'seed-diary',
    'title': _t('十月三十日 · 阴'),
    'kind': 'diary',
    'tags': [_t('日记'), _t('日常')],
    'mood': 3,
    'weather': 'overcast',
    'pinned': false,
    'favorite': false,
    'createdAt': today.subtract(const Duration(days: 1)).toIso8601String(),
    'updatedAt': today.subtract(const Duration(days: 1)).toIso8601String(),
    'day': _day(today.subtract(const Duration(days: 1))),
    'delta': [
      _text(_t('阴天。窗外的银杏比昨天又黄了一点。')),
      _line(),
      _text(_t('三件小事')),
      _line({'header': 2}),
      _text(_t('一、把拖了两周的事做完了，原来只需要一个上午。')),
      _line(),
      _text(_t('二、午后的咖啡太苦，加了一点盐，意外地好喝。')),
      _line(),
      _text(_t('三、给很久没联系的朋友发了一条消息。')),
      _line(),
      _line(),
      _text(_t('今天学到：'), {'bold': true}),
      _text(_t('焦虑常常不是因为事情太多，而是因为一直没有开始。')),
      _line(),
    ],
  };

  final essay = {
    'id': 'seed-essay',
    'title': _t('慢一点，也是一种抵达'),
    'kind': 'essay',
    'tags': [_t('作文'), _t('练习')],
    'mood': null,
    'weather': null,
    'pinned': false,
    'favorite': false,
    'createdAt': today.subtract(const Duration(days: 4)).toIso8601String(),
    'updatedAt': today.subtract(const Duration(days: 4)).toIso8601String(),
    'day': _day(today.subtract(const Duration(days: 4))),
    'delta': [
      _text(_t('我们习惯了把日子过成一条不断加速的线。')),
      _line(),
      _text(_t('可有些东西，只能在慢下来的时候出现：一顿饭的味道，一阵风的方向，一个人没有说出口的话。')),
      _line(),
      _text(_t('慢不是停。慢是把每一步都走实。'), {'bold': true}),
      _line(),
      _text(_t('就像写字。急的时候，笔画是飘的；静下来，墨才会落到纸上。')),
      _line(),
      _line(),
      _text(_t('—— 一个普通的下午'), {'color': '#8D8576', 'italic': true}),
      _line(),
    ],
  };

  return [welcome, diary, essay];
}

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
