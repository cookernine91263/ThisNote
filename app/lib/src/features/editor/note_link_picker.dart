import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';

const Map<String, String> _en = <String, String>{
  '链接到一篇笔记': 'Link to a note',
  '搜索笔记标题…': 'Search note titles…',
  '没有找到笔记': 'No notes found',
  '取消': 'Cancel',
  '无题': 'Untitled',
  '字': 'words',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<NoteMeta?> showNoteLinkPicker(
  BuildContext context, {
  required AppState state,
  String? excludeId,
}) {
  return showDialog<NoteMeta>(
    context: context,
    builder: (_) => _NoteLinkPicker(state: state, excludeId: excludeId),
  );
}

class _NoteLinkPicker extends StatefulWidget {
  const _NoteLinkPicker({required this.state, this.excludeId});

  final AppState state;
  final String? excludeId;

  @override
  State<_NoteLinkPicker> createState() => _NoteLinkPickerState();
}

class _NoteLinkPickerState extends State<_NoteLinkPicker> {
  final TextEditingController _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final query = _query.text.trim().toLowerCase();
    final notes = state.activeNotes
        .where((meta) =>
            meta.id != widget.excludeId &&
            (query.isEmpty ||
                meta.title.toLowerCase().contains(query) ||
                meta.tags.any((tag) => tag.toLowerCase().contains(query))))
        .take(80)
        .toList();
    return AlertDialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      title: Row(
        children: [
          Icon(LucideIcons.link, size: 17, color: c.accent),
          const SizedBox(width: 8),
          Text(
            _t('链接到一篇笔记'),
            style: TextStyle(
              fontFamily: 'WenKai',
              fontSize: 21,
              color: c.ink,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        height: 380,
        child: Column(
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 13,
                color: c.ink,
              ),
              decoration: InputDecoration(
                hintText: _t('搜索笔记标题…'),
                hintStyle: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 12,
                  color: c.inkMuted,
                ),
                filled: true,
                fillColor: c.paper,
                isDense: true,
                prefixIcon: Icon(
                  LucideIcons.search,
                  size: 15,
                  color: c.inkMuted,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: c.accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: notes.isEmpty
                  ? Center(
                      child: Text(
                        _t('没有找到笔记'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 11,
                          color: c.inkMuted,
                        ),
                      ),
                    )
                  : ListView.separated(
                      itemCount: notes.length,
                      separatorBuilder: (_, _) =>
                          Divider(height: 1, color: c.line),
                      itemBuilder: (context, index) {
                        final note = notes[index];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          leading: Icon(
                            LucideIcons.fileText,
                            size: 15,
                            color: c.inkMuted,
                          ),
                          title: Text(
                            note.title.trim().isEmpty
                                ? _t('无题')
                                : note.title.trim(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 12.5,
                              color: c.ink,
                            ),
                          ),
                          subtitle: Text(
                            '${note.words} ${_t('字')}',
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 9.5,
                              color: c.inkMuted,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(note),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _t('取消'),
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 12,
              color: c.inkSoft,
            ),
          ),
        ),
      ],
    );
  }
}