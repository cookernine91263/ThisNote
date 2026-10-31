/// 中文排版的轻量整理规则：中英之间加空格、半角标点转全角、省略号/破折号规范化。
///
/// 只做「几乎是共识」的替换，不碰引号风格，也不改代码块和网址内部。
library;

const String _cjk =
    r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]';

final RegExp _cjkBeforeLatin = RegExp('(?<=$_cjk)(?=[A-Za-z0-9])');
final RegExp _latinBeforeCjk = RegExp('(?<=[A-Za-z0-9])(?=$_cjk)');

/// 把一段文字整理成更接近中文排版习惯的样子。
/// 行数（换行）保持不变，方便按段落应用。
String normalizeChineseTypography(String input) {
  if (input.trim().isEmpty) return input;
  var text = input;

  // 省略号与破折号：英文输入法里常见的写法。
  text = text.replaceAll('...', '……');
  text = text.replaceAll('--', '——');

  // 紧挨中文的半角标点，转成全角。
  text = text.replaceAllMapped(
    RegExp('(?<=$_cjk)([,;:?!])|([,;:?!])(?=$_cjk)'),
    (match) {
      final mark = match.group(1) ?? match.group(2)!;
      return switch (mark) {
        ',' => '，',
        ';' => '；',
        ':' => '：',
        '?' => '？',
        '!' => '！',
        _ => mark,
      };
    },
  );

  // 中文后面的句号；小数点（3.14）和英文句点不动。
  text = text.replaceAllMapped(
    RegExp('(?<=$_cjk)\\.(?=$_cjk|\$)', multiLine: true),
    (_) => '。',
  );

  // 中文旁边的括号用全角。
  text = text.replaceAllMapped(
    RegExp('\\((?=$_cjk)'),
    (_) => '（',
  );
  text = text.replaceAllMapped(
    RegExp('(?<=$_cjk)\\)'),
    (_) => '）',
  );

  // 去掉全角标点前多余的空格，以及括号内侧的空格。
  text = text.replaceAllMapped(
    RegExp(r'[ \t]+([，。！？；：、）])'),
    (match) => match.group(1)!,
  );
  text = text.replaceAll(RegExp(r'（[ \t]+'), '（');
  text = text.replaceAll(RegExp(r'[ \t]+）'), '）');
  // 全角标点后面紧跟中文时，不需要空格。
  text = text.replaceAllMapped(
    RegExp('([，。！？；：、])[ \\t]+(?=$_cjk)'),
    (match) => match.group(1)!,
  );

  // 中英文之间加一个空格。
  text = text.replaceAll(_cjkBeforeLatin, ' ');
  text = text.replaceAll(_latinBeforeCjk, ' ');

  // 连续空格收成一个，行尾空格去掉。
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  text = text.replaceAllMapped(
    RegExp(r'[ \t]+(\r?\n)'),
    (match) => match.group(1)!,
  );
  text = text.replaceAll(RegExp(r'[ \t]+$'), '');

  return text;
}
