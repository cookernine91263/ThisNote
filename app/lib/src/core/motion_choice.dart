import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/motion.dart';
import '../core/theme.dart';

class MotionChoice extends StatelessWidget {
  const MotionChoice({
    required this.value,
    required this.selected,
    required this.onTap,
    super.key,
    this.compact = false,
  });

  final String value;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final morph = value == 'morph';
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: EdgeInsets.fromLTRB(
          compact ? 11 : 14,
          compact ? 10 : 13,
          compact ? 9 : 12,
          compact ? 10 : 13,
        ),
        decoration: BoxDecoration(
          color: selected ? c.accentSoft : c.paper,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? c.accent.withValues(alpha: 0.55) : c.line,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.accent.withValues(alpha: 0.08),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: compact ? 28 : 34,
              height: compact ? 28 : 34,
              decoration: BoxDecoration(
                color: selected ? c.accent : c.surfaceAlt,
                borderRadius: BorderRadius.circular(compact ? 8 : 9),
              ),
              child: Icon(
                morph ? LucideIcons.scanFace : LucideIcons.moveRight,
                size: compact ? 14 : 16,
                color: selected ? c.onAccent : c.inkSoft,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    morph ? '平滑' : '滑入',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: compact ? 10.5 : 11.5,
                      fontWeight: FontWeight.w600,
                      color: selected ? c.accent : c.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    morph ? 'Morph · 慢慢展开' : '轻快 · 像推开一页',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: compact ? 8 : 8.5,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? LucideIcons.checkCircle2 : LucideIcons.circle,
              size: compact ? 13 : 15,
              color: selected ? c.accent : c.lineStrong,
            ),
          ],
        ),
      ),
    );
  }
}
