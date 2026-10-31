import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';

/// 长文写作者的「目录」：从正文的标题 1–3 实时生成，点一下跳过去。
/// 桌面上是停靠在右侧的栏，手机上浮在纸面上。
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({
    required this.session,
    this.docked = false,
    super.key,
  });

  final EditorSession session;
  final bool docked;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        final entries = session.outline;
        final list = entries.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                child: Text(
                  '这篇还没有标题。\n用标题 1–3 分段，这里就会长出一张地图。',
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
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return HoverBuilder(
                    builder: (context, hovered, t) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => session.jumpTo(entry.offset),
                        child: Container(
                          color: hovered ? c.paper : Colors.transparent,
                          padding: EdgeInsets.fromLTRB(
                            12 + (entry.level - 1) * 12,
                            7,
                            10,
                            7,
                          ),
                          child: Text(
                            entry.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily:
                                  entry.level == 1 ? 'WenKai' : 'NotoSansSC',
                              fontSize: entry.level == 1 ? 13 : 12,
                              height: 1.4,
                              color: entry.level == 1 ? c.ink : c.inkSoft,
                            ),
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
                      '目录',
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 14,
                        letterSpacing: 1,
                        color: c.ink,
                      ),
                    ),
                    const Spacer(),
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
