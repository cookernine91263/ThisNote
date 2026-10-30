import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/core/format.dart';

void main() {
  test('word count counts CJK characters and latin words', () {
    expect(countWords('你好 world 123'), 4);
    expect(countWords(''), 0);
    expect(countWords('日本語 テスト'), 6);
  });
}
