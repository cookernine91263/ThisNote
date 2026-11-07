import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

const Map<String, String> _en = <String, String>{
  '双向链接': 'Backlinks',
  '链接到这篇': 'Linked here',
  '这篇链接到': 'Links from here',
  '还没有链接': 'No links yet',
  '在「更多」里插入笔记链接，前后文就会连起来': 'Add a note link from More to connect them',
  '关闭': 'Close',
  '无题': 'Untitled',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class BacklinksPanel extends StatelessWidget {
  const BacklinksPanel({
    required this.session,
    this.onClose,
    super.key,
  });

  final EditorSession session;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final current = session.note.toMeta();
    final inbound = state.inboundLinksFor(current);
    final outbound = state.outgoingLinksFor(current);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(left: BorderSide(color: c.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
            child: Row(
              children: [
                Icon(LucideIcons.link, size: 16, color: c.accent),
                const SizedBox(width: 7),
                Text(
                  _t('双向链接'),
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 17,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: _t('关闭'),
                  icon: Icon(LucideIcons.x, size: 15, color: c.inkMuted),
                  onPressed: onClose ?? session.toggleBacklinks,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: inbound.isEmpty && outbound.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.link2,
                            size: 26,
                            color: c.inkMuted.withValues(alpha: 0.45),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t('还没有链接'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10.5,
                              color: c.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _t('在「更多」里插入笔记链接，前后文就会连起来'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 9.5,
                              height: 1.5,
                              color: c.inkMuted.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      _section(context, _t('链接到这篇'), inbound, state),
                      _section(context, _t('这篇链接到'), outbound, state),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<NoteMeta> notes,
    AppState state,
  ) {
    if (notes.isEmpty) return const SizedBox.shrink();
    final c = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Text(
            title,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9.5,
              color: c.inkMuted,
              letterSpacing: 0.8,
            ),
          ),
        ),
        for (final note in notes)
          InkWell(
            onTap: () => state.openNote(note.id),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 7, 14, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title.trim().isEmpty ? _t('无题') : note.title.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 11.5,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    note.excerpt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Divider(height: 18, color: c.line.withValues(alpha: 0.6)),
      ],
    );
  }
}