import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';

const Map<String, String> _en = <String, String>{
  '键盘快捷键': 'Keyboard shortcuts',
  '通用': 'General',
  '命令面板': 'Command palette',
  '新建随笔': 'New note',
  '立即保存': 'Save now',
  '设置': 'Settings',
  '编辑': 'Editing',
  '查找': 'Find',
  '当前笔记内替换': 'Replace in this note',
  '全局搜索替换': 'Search & replace everywhere',
  '粘贴为纯文本': 'Paste as plain text',
  '加粗': 'Bold',
  '倾斜': 'Italic',
  '下划线': 'Underline',
  '视图': 'View',
  '专注模式': 'Focus mode',
  '切换标签页': 'Switch tab',
  '关闭标签页': 'Close tab',
  '列表': 'List',
  '上一篇': 'Previous note',
  '下一篇': 'Next note',
  '关闭': 'Close',
  '界面里的按钮和菜单总能完成同样的动作。':
      'The buttons and menus can always do the same thing.',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<void> showShortcutSheet(BuildContext context) {
  final mod = I18n.isEn ? 'Ctrl/⌘' : 'Ctrl/⌘';
  return showDialog<void>(
    context: context,
    builder: (context) {
      final c = AppPalette.of(context);
      return Dialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: c.line),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.keyboard, size: 17, color: c.accent),
                    const SizedBox(width: 8),
                    Text(
                      _t('键盘快捷键'),
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 22,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _t('关闭'),
                      icon: Icon(LucideIcons.x, size: 17, color: c.inkMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  _t('界面里的按钮和菜单总能完成同样的动作。'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _group(context, _t('通用'), [
                          ('$mod + K', _t('命令面板')),
                          ('$mod + N', _t('新建随笔')),
                          ('$mod + S', _t('立即保存')),
                          ('$mod + ,', _t('设置')),
                        ]),
                        _group(context, _t('编辑'), [
                          ('$mod + F', _t('查找')),
                          ('$mod + H', _t('当前笔记内替换')),
                          ('$mod + Shift + H', _t('全局搜索替换')),
                          ('$mod + Shift + V', _t('粘贴为纯文本')),
                          ('$mod + B', _t('加粗')),
                          ('$mod + I', _t('倾斜')),
                          ('$mod + U', _t('下划线')),
                        ]),
                        _group(context, _t('视图'), [
                          ('$mod + Shift + F', _t('专注模式')),
                          ('$mod + Tab', _t('切换标签页')),
                          ('$mod + W', _t('关闭标签页')),
                          ('Alt + ↑ / ↓', '${_t('上一篇')} / ${_t('下一篇')}'),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

Widget _group(
  BuildContext context,
  String title,
  List<(String, String)> rows,
) {
  final c = AppPalette.of(context);
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 9.5,
            color: c.accent,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 190,
                  child: Kbd(row.$1),
                ),
                Expanded(
                  child: Text(
                    row.$2,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 11.5,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}