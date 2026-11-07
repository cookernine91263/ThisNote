import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '这篇还没有标题。\n用标题 1–3 分段，这里就会长出一张地图。':
      'This note has no headings yet.\nUse Heading 1–3 to grow a map here.',
  '目录': 'Outline',
  '插入目录': 'Insert contents',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

/// 长文写作者的「目录」：从正文的标题 1–3 实时生成，点一下跳过去。
/// 桌面上是停靠在右侧的栏，手机上浮在纸面上。
class OutlinePanel extends StatefulWidget {
  const OutlinePanel({
    required this.session,
    this.docked = false,
    super.key,
  });

  final EditorSession session;
  final bool docked;

  @override
  State<OutlinePanel> createState() => _OutlinePanelState();
}

class _OutlinePanelState extends State<OutlinePanel> {
  final Set<int> _collapsed = <int>{};

  EditorSession get session => widget.session;
  bool get docked => widget.docked;

  bool _hidden(List<OutlineEntry> entries, int index) {
    var level = entries[index].level;
    for (var i = index - 1; i >= 0; i--) {
      if (entries[i].level < level) {
        if (_collapsed.contains(i)) return true;
        level = entries[i].level;
      }
    }
    return false;
  }

  bool _hasChildren(List<OutlineEntry> entries, int index) =>
      index + 1 < entries.length &&
      entries[index + 1].level > entries[index].level;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final entries = session.outline;
        final cursor = session.controller.selection.extentOffset;
        var active = -1;
        for (var i = 0; i < entries.length; i++) {
          if (entries[i].offset <= cursor) active = i;
        }
        final visible = [
          for (var i = 0; i < entries.length; i++)
            if (!_hidden(entries, i)) i,
        ];
        final list = entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Text(
                  _t('这篇还没有标题。\n用标题 1–3 分段，这里就会长出一张地图。'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10.5,
                    height: 1.7,
                    color: c.inkMuted,
                  ),
                ),
              )
            : ListView.builder(
                shrinkWrap: !docked,
                padding: const EdgeInsets.symmetric(vertical: 5),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final entryIndex = visible[index];
                  final entry = entries[entryIndex];
                  final current = entryIndex == active;
                  return HoverBuilder(
                    builder: (context, hovered, t) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => session.jumpTo(entry.offset),
                        child: Container(
                          decoration: BoxDecoration(
                            color: current
                                ? c.accentSoft.withValues(
                                    alpha: c.isDark ? 0.55 : 0.7,
                                  )
                                : hovered
                                    ? c.paper
                                    : Colors.transparent,
                            border: Border(
                              left: BorderSide(
                                color: current ? c.accent : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          padding: EdgeInsets.fromLTRB(
                            10 + (entry.level - 1) * 12,
                            7,
                            10,
                            7,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_hasChildren(entries, entryIndex))
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => setState(() {
                                    if (!_collapsed.remove(entryIndex)) {
                                      _collapsed.add(entryIndex);
                                    }
                                  }),
                                  child: Padding(
                                    padding: const EdgeInsets.only(
                                      top: 2,
                                      right: 3,
                                    ),
                                    child: Icon(
                                      _collapsed.contains(entryIndex)
                                          ? LucideIcons.chevronRight
                                          : LucideIcons.chevronDown,
                                      size: 11,
                                      color: c.inkMuted,
                                    ),
                                  ),
                                )
                              else
                                const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  entry.text,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: entry.level == 1
                                        ? 'WenKai'
                                        : 'NotoSansSC',
                                    fontSize: entry.level == 1 ? 13 : 12,
                                    height: 1.4,
                                    color: current
                                        ? c.accent
                                        : entry.level == 1
                                            ? c.ink
                                            : c.inkSoft,
                                    fontWeight: current
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              );

        return Container(
          width: docked ? null : 214,
          constraints: docked
              ? null
              : BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.52,
                ),
          decoration: docked
              ? BoxDecoration(
                  color: c.surface,
                  border: Border(left: BorderSide(color: c.line)),
                )
              : BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.line),
                  boxShadow: [
                    BoxShadow(
                      color: c.shadow.withValues(alpha: c.isDark ? 0.3 : 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
          child: Column(
            mainAxisSize: docked ? MainAxisSize.max : MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 4),
                child: Row(
                  children: [
                    Icon(LucideIcons.listTree, size: 14, color: c.inkMuted),
                    const SizedBox(width: 6),
                    Text(
                      _t('目录'),
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 14,
                        letterSpacing: 1,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
                    SoftIconButton(
                      icon: LucideIcons.listPlus,
                      tooltip: _t('插入目录'),
                      size: 24,
                      iconSize: 13,
                      onPressed: entries.isEmpty
                          ? null
                          : () => session.insertTableOfContents(),
                    ),
                    SoftIconButton(
                      icon: LucideIcons.x,
                      size: 24,
                      iconSize: 13,
                      onPressed: session.toggleOutline,
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: c.line),
              if (docked)
                Expanded(child: list)
              else
                Flexible(child: list),
            ],
          ),
        );
      },
    );
  }
}
