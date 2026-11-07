import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/icons.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../data/templates.dart';
import '../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。
/// 体裁与模板的名称、说明由 [NoteKind] / [noteTemplates] 自己翻译，这里不重复。
const Map<String, String> _en = <String, String>{
  '开始一页': 'Start a page',
  '选一种开始的方式': 'Pick a way to begin',
  '关闭': 'Close',
  '日期': 'Date',
  '所有内容只保存在本机': 'Everything stays on this device',
  '空白开始': 'Start blank',
  '用「{name}」开始': 'Start with “{name}”',
  '我的模板': 'My template',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<void> showNewNoteSheet(BuildContext context) async {
  final isMobile = MediaQuery.sizeOf(context).width < 760;
  if (isMobile) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _SheetShell(mobile: true),
    );
  } else {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.22),
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: _SheetShell(mobile: false),
      ),
    );
  }
}

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.mobile});
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final content = ClipRRect(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(mobile ? 22 : 20),
        bottom: Radius.circular(mobile ? 0 : 20),
      ),
      child: Container(
        width: mobile ? double.infinity : 660,
        constraints: BoxConstraints(maxHeight: mobile ? 640 : 590),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(mobile ? 22 : 20),
          border: Border.all(color: c.line),
        ),
        child: const _NewNoteSheet(),
      ),
    );
    if (mobile) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(top: false, child: content),
      );
    }
    return content;
  }
}

class _NewNoteSheet extends StatefulWidget {
  const _NewNoteSheet();

  @override
  State<_NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends State<_NewNoteSheet> {
  NoteKind _kind = NoteKind.note;
  NoteTemplate? _template;
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final templates = [
      ...noteTemplates,
      ...state.userTemplates.map((template) => template.toNoteTemplate()),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _t('开始一页'),
                style: TextStyle(
                  fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                  fontSize: I18n.isEn ? 21 : 25,
                  fontWeight: I18n.isEn ? FontWeight.w600 : null,
                  letterSpacing: I18n.isEn ? 0.3 : 1,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _t('选一种开始的方式'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 11,
                  color: c.inkMuted,
                ),
              ),
              const Spacer(),
              SoftIconButton(
                icon: LucideIcons.x,
                size: 30,
                tooltip: _t('关闭'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              for (final k in NoteKind.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _KindPill(
                    kind: k,
                    selected: _kind == k,
                    onTap: () => setState(() {
                      _kind = k;
                      _template = null;
                    }),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(
            child: SingleChildScrollView(
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: templates.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  // 英文模板说明较长，两列会把句子截断；英文改成单列，
                  // 中文仍保持紧凑的两列。
                  crossAxisCount: I18n.isEn ? 1 : 2,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: I18n.isEn ? 80 : 76,
                ),
                itemBuilder: (context, i) {
                  final t = templates[i];
                  final selected = _template?.id == t.id;
                  return _TemplateCard(
                    template: t,
                    selected: selected,
                    onTap: () => setState(() {
                      _template = t;
                      _kind = t.kind;
                    }),
                    onDelete: t.id.startsWith('user_')
                        ? () async {
                            await state.deleteUserTemplate(t.id);
                            if (!mounted) return;
                            setState(() {
                              if (_template?.id == t.id) _template = null;
                            });
                          }
                        : null,
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(LucideIcons.calendar, size: 14, color: c.inkMuted),
              const SizedBox(width: 6),
              Text(
                _t('日期'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 11.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.line),
                  ),
                  child: Text(
                    I18n.isEn
                        ? DateFormat.yMMMd().format(_date)
                        : '${_date.year}年${_date.month}月${_date.day}日',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 11,
                      color: c.inkSoft,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Text(
                _t('所有内容只保存在本机'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: c.ink,
                foregroundColor: c.paper,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final t = _template;
                await state.createNote(
                  kind: _kind,
                  template: t,
                  day: _kind == NoteKind.diary ? _date : null,
                );
                if (context.mounted) Navigator.of(context).pop();
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.penLine, size: 15),
                  const SizedBox(width: 8),
                  Text(
                    _template == null
                        ? _t('空白开始')
                        : _t('用「{name}」开始', {'name': _template!.name}),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  const _KindPill({
    required this.kind,
    required this.selected,
    required this.onTap,
  });
  final NoteKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? c.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c.ink : c.line),
        ),
        child: Row(
          children: [
            Icon(
              kindIcon(kind),
              size: 13,
              color: selected ? c.paper : c.inkSoft,
            ),
            const SizedBox(width: 6),
            Text(
              kind.label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 12,
                color: selected ? c.paper : c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.selected,
    required this.onTap,
    this.onDelete,
  });

  final NoteTemplate template;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
            decoration: BoxDecoration(
              color: selected
                  ? c.accentSoft
                  : hovered
                      ? c.paper
                      : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? c.accent.withValues(alpha: 0.4) : c.line,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  kindIcon(template.kind),
                  size: 15,
                  color: selected ? c.accent : c.inkMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        template.name,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        template.description,
                        // 英文模板说明比中文长，单行会只剩半句。
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          height: 1.3,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDelete != null && hovered)
                  GestureDetector(
                    onTap: onDelete,
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        LucideIcons.x,
                        size: 13,
                        color: c.inkMuted,
                      ),
                    ),
                  )
                else if (selected)
                  Icon(LucideIcons.check, size: 13, color: c.accent),
              ],
            ),
          ),
        );
      },
    );
  }
}
