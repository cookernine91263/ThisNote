import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';

/// 标签编辑器：可以继续手打，也可以从写过用过的标签里点选，
/// 免得同一个意思写出「读书」「阅读」「看书」三个标签。
Future<List<String>?> showTagEditor(
  BuildContext context,
  AppState state,
  List<String> current,
) {
  return showDialog<List<String>>(
    context: context,
    builder: (_) => _TagEditorDialog(state: state, initial: current),
  );
}

class _TagEditorDialog extends StatefulWidget {
  const _TagEditorDialog({required this.state, required this.initial});

  final AppState state;
  final List<String> initial;

  @override
  State<_TagEditorDialog> createState() => _TagEditorDialogState();
}

class _TagEditorDialogState extends State<_TagEditorDialog> {
  late final List<String> _tags = List.of(widget.initial);
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final parts = raw
        .split(RegExp(r'[\s,，、#]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);
    if (parts.isEmpty) return;
    setState(() {
      for (final part in parts) {
        if (!_tags.contains(part)) _tags.add(part);
      }
      _input.clear();
    });
  }

  void _remove(String tag) {
    setState(() => _tags.remove(tag));
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final query = _input.text.trim().toLowerCase();
    final all = widget.state.allTags;
    final suggestions = all
        .where((tag) => !_tags.contains(tag))
        .where((tag) => query.isEmpty || tag.toLowerCase().contains(query))
        .take(14)
        .toList();

    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _t('标签'),
                    style: TextStyle(
                      fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                      fontSize: 22,
                      letterSpacing: 1,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  SoftIconButton(
                    icon: LucideIcons.x,
                    size: 28,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _t('回车添加；点下面的旧标签直接复用，避免同义标签越写越多。'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  height: 1.6,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: c.paper,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: c.line),
                ),
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tag in _tags)
                      TagChip(label: tag, onDelete: () => _remove(tag)),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        maxLines: 1,
                        textInputAction: TextInputAction.done,
                        onSubmitted: _add,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11.5,
                          color: c.ink,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: _tags.isEmpty
                              ? _t('如：日常 读书')
                              : _t('再加一个…'),
                          hintStyle: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 11,
                            color: c.inkMuted,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Icon(LucideIcons.history, size: 12, color: c.inkMuted),
                  const SizedBox(width: 5),
                  Text(
                    _t(query.isEmpty ? '用过的标签' : '匹配的标签'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      letterSpacing: 0.6,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: suggestions.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          _t(
                            all.isEmpty
                                ? '还没有历史标签。写下第一个，之后就能点选。'
                                : '没有匹配的旧标签，回车即可新建。',
                          ),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 10.5,
                            height: 1.7,
                            color: c.inkMuted,
                          ),
                        ),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final tag in suggestions)
                              _SuggestionChip(
                                label: tag,
                                count: widget.state.tagCounts[tag] ?? 0,
                                onTap: () => _add(tag),
                              ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(_t('取消'), style: TextStyle(color: c.inkMuted)),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.ink,
                      foregroundColor: c.paper,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    onPressed: () {
                      // 还没回车的半截标签也算上，别让用户白打。
                      _add(_input.text);
                      Navigator.of(context).pop(List.of(_tags));
                    },
                    child: Text(_t('保存')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: hovered ? c.accentSoft : c.paper,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: hovered ? c.accent.withValues(alpha: 0.4) : c.line,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '# $label',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10.5,
                    color: hovered ? c.accent : c.inkSoft,
                  ),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 英文文案。键是界面里的中文原文，值是对应的英文。
const Map<String, String> _en = <String, String>{
  '标签': 'Tags',
  '回车添加；点下面的旧标签直接复用，避免同义标签越写越多。':
      'Press Enter to add. Tap an old tag below to reuse it, so near-duplicates do not pile up.',
  '如：日常 读书': 'e.g. daily reading',
  '再加一个…': 'Add another…',
  '用过的标签': 'Tags used before',
  '匹配的标签': 'Matching tags',
  '还没有历史标签。写下第一个，之后就能点选。':
      'No tag history yet. Create the first one and it will show up here.',
  '没有匹配的旧标签，回车即可新建。': 'No matching tag. Press Enter to create it.',
  '取消': 'Cancel',
  '保存': 'Save',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);
