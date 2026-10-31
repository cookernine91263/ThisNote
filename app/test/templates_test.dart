import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/templates.dart';

void main() {
  test('所有模板的标题属性都挂在段尾换行上', () {
    for (final template in noteTemplates) {
      for (final op in template.delta) {
        if (op is! Map) continue;
        final attrs = op['attributes'];
        if (attrs is Map && attrs.containsKey('header')) {
          expect(
            op['insert'],
            '\n',
            reason: '${template.id} 的 header 应该写给段尾的换行，而不是文字本身',
          );
        }
      }
    }
  });

  test('每个模板都以换行结尾，正文可以接着写', () {
    for (final template in noteTemplates) {
      expect(template.delta, isNotEmpty, reason: template.id);
      final last = template.delta.last;
      expect(
        last is Map && last['insert'] == '\n',
        isTrue,
        reason: '${template.id} 的最后一个片段应该是换行',
      );
    }
  });
}
