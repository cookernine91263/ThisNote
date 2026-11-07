import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../services/style_check.dart';
import '../../state/app_state.dart';

const Map<String, String> _en = <String, String>{
  '文风检查': 'Style check',
  '这段文字很干净': 'This text is clean',
  '口水词': 'Filler',
  '重复': 'Repetition',
  '长句': 'Long sentence',
  '标点': 'Punctuation',
  '空格': 'Spacing',
  '笔误': 'Typo',
  '点击跳到那一句': 'Click to jump to the sentence',
  '{n} 处可以再斟酌': '{n} places to reconsider',
  '关闭': 'Close',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class StyleCheckPanel extends StatefulWidget {
  const StyleCheckPanel({
    required this.session,
    this.onClose,
    super.key,
  });

  final EditorSession session;
  final VoidCallback? onClose;

  @override
  State<StyleCheckPanel> createState() => _StyleCheckPanelState();
}

class _StyleCheckPanelState extends State<StyleCheckPanel> {
  int _revision = -1;
  List<StyleIssue> _issues = const [];

  void _refresh() {
    final revision = widget.session.revision;
    if (revision == _revision) return;
    _revision = revision;
    _issues = checkChineseStyle(widget.session.plainText);
  }

  String _kindLabel(StyleIssueKind kind) => switch (kind) {
        StyleIssueKind.filler => _t('口水词'),
        StyleIssueKind.repetition => _t('重复'),
        StyleIssueKind.longSentence => _t('长句'),
        StyleIssueKind.punctuation => _t('标点'),
        StyleIssueKind.spacing => _t('空格'),
        StyleIssueKind.typo => _t('笔误'),
      };

  String _snippet(String text, StyleIssue issue) {
    final start = (issue.offset - 12).clamp(0, text.length);
    final end = (issue.offset + issue.length + 12).clamp(0, text.length);
    return text.substring(start, end).replaceAll('\n', ' ').trim();
  }

  void _jump(StyleIssue issue) {
    final controller = widget.session.controller;
    controller.updateSelection(
      TextSelection(
        baseOffset: issue.offset,
        extentOffset: (issue.offset + issue.length)
            .clamp(0, controller.document.length),
      ),
      ChangeSource.local,
    );
    widget.session.editorFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    _refresh();
    final c = AppPalette.of(context);
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
                Icon(LucideIcons.spellCheck, size: 16, color: c.accent),
                const SizedBox(width: 7),
                Text(
                  _t('文风检查'),
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 17,
                    color: c.ink,
                  ),
                ),
                const Spacer(),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: _t('关闭'),
                    icon: Icon(LucideIcons.x, size: 15, color: c.inkMuted),
                    onPressed: widget.onClose,
                  )
                else
                  IconButton(
                    tooltip: _t('关闭'),
                    icon: Icon(LucideIcons.x, size: 15, color: c.inkMuted),
                    onPressed: widget.session.toggleStyleCheck,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              _issues.isEmpty
                  ? _t('这段文字很干净')
                  : _t('{n} 处可以再斟酌', {'n': _issues.length}),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: c.inkMuted,
              ),
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: _issues.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.checkCheck,
                          size: 28,
                          color: c.inkMuted.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t('点击跳到那一句'),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 10,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: _issues.length,
                    separatorBuilder: (context, _) => Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 16,
                      color: c.line.withValues(alpha: 0.6),
                    ),
                    itemBuilder: (context, index) {
                      final issue = _issues[index];
                      return InkWell(
                        onTap: () => _jump(issue),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 9, 12, 9),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    _kindLabel(issue.kind),
                                    style: TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      fontSize: 9.5,
                                      color: c.accent,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      issue.message,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'NotoSansSC',
                                        fontSize: 11,
                                        color: c.inkSoft,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _snippet(widget.session.plainText, issue),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'NotoSansSC',
                                  fontSize: 10.5,
                                  height: 1.5,
                                  color: c.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}