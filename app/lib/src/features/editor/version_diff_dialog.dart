import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../services/text_diff.dart';

const Map<String, String> _en = <String, String>{
  '与当前版本对比': 'Compare with current',
  '历史版本': 'Snapshot',
  '当前': 'Current',
  '新增': 'Added',
  '删除': 'Removed',
  '没有可显示的差异': 'No differences to show',
  '字': 'words',
  '关闭': 'Close',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<void> showVersionDiff(
  BuildContext context, {
  required Snapshot snapshot,
  required String currentText,
}) {
  final runs = diffText(snapshot.text, currentText);
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
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 620),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(LucideIcons.gitCompare, size: 16, color: c.accent),
                    const SizedBox(width: 8),
                    Text(
                      _t('与当前版本对比'),
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 21,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${shortDate(snapshot.savedAt)} · ${snapshot.words} '
                      '${_t('字')}',
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 10,
                        color: c.inkMuted,
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: _t('关闭'),
                      icon: Icon(LucideIcons.x, size: 17, color: c.inkMuted),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _Legend(color: c.inkSoft, label: _t('历史版本')),
                    const SizedBox(width: 12),
                    _Legend(color: c.danger, label: _t('删除'), strike: true),
                    const SizedBox(width: 12),
                    _Legend(color: c.accent, label: _t('新增')),
                  ],
                ),
                Divider(height: 20, color: c.line),
                Flexible(
                  child: runs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 30),
                          child: Text(
                            _t('没有可显示的差异'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 11,
                              color: c.inkMuted,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          child: SelectableText.rich(
                            TextSpan(
                              children: [
                                for (final run in runs)
                                  TextSpan(
                                    text: run.text,
                                    style: TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      fontSize: 13,
                                      height: 1.85,
                                      color: switch (run.kind) {
                                        DiffKind.equal => c.ink,
                                        DiffKind.delete => c.danger,
                                        DiffKind.insert => c.accent,
                                      },
                                      decoration: run.kind == DiffKind.delete
                                          ? TextDecoration.lineThrough
                                          : null,
                                      backgroundColor:
                                          run.kind == DiffKind.insert
                                              ? c.accentSoft.withValues(
                                                  alpha: 0.55,
                                                )
                                              : null,
                                    ),
                                  ),
                              ],
                            ),
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

class _Legend extends StatelessWidget {
  const _Legend({
    required this.color,
    required this.label,
    this.strike = false,
  });

  final Color color;
  final String label;
  final bool strike;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 9.5,
            color: color,
            decoration: strike ? TextDecoration.lineThrough : null,
          ),
        ),
      ],
    );
  }
}