import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';

const Map<String, String> _en = <String, String>{
  '上次没有正常结束': 'Last time did not end cleanly',
  '这些草稿比磁盘上的版本更新。要捡回来吗？':
      'These drafts are newer than the files on disk. Recover them?',
  '恢复': 'Recover',
  '丢弃': 'Discard',
  '{n} 字': '{n} words',
  '没有标题': 'Untitled',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({required this.state, super.key});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final live = context.watch<AppState>();
    final entries = live.pendingRecovery;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: PaperSurface(
                padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(LucideIcons.history, size: 20, color: c.accent),
                        const SizedBox(width: 9),
                        Text(
                          _t('上次没有正常结束'),
                          style: TextStyle(
                            fontFamily: 'WenKai',
                            fontSize: 25,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t('这些草稿比磁盘上的版本更新。要捡回来吗？'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11.5,
                        height: 1.7,
                        color: c.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final entry in entries) ...[
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
                        decoration: BoxDecoration(
                          color: c.paper,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: c.line),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title.trim().isEmpty
                                  ? _t('没有标题')
                                  : entry.title.trim(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 13,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${shortDate(entry.savedAt)} · '
                              '${_t('{n} 字', {'n': entry.text.length})}',
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 9.5,
                                color: c.inkMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: () => state.discardJournal(entry),
                                  child: Text(
                                    _t('丢弃'),
                                    style: TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      fontSize: 11.5,
                                      color: c.inkMuted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                FilledButton(
                                  onPressed: () => state.recoverJournal(entry),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: c.accent,
                                    foregroundColor: c.onAccent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                  ),
                                  child: Text(
                                    _t('恢复'),
                                    style: const TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      fontSize: 11.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}