import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';

const Map<String, String> _en = <String, String>{
  '全局搜索替换': 'Search & replace everywhere',
  '查找': 'Find',
  '替换为': 'Replace with',
  '区分大小写': 'Match case',
  '将替换全部笔记中的 {n} 处': 'Replace {n} matches across all notes',
  '没有找到可替换的文字': 'No matches found',
  '取消': 'Cancel',
  '替换全部': 'Replace all',
  '正在替换 {done}/{total}': 'Replacing {done}/{total}',
  '已替换 {n} 处': 'Replaced {n} matches',
  '替换前会为每篇笔记留一份历史版本': 'A version is kept for every note before replacing',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<void> showGlobalReplaceDialog(BuildContext context) async {
  final count = await showDialog<int>(
    context: context,
    builder: (_) => const _GlobalReplaceDialog(),
  );
  if (context.mounted && count != null) {
    showToast(
      context,
      _t('已替换 {n} 处', {'n': count}),
      icon: LucideIcons.check,
    );
  }
}

class _GlobalReplaceDialog extends StatefulWidget {
  const _GlobalReplaceDialog();

  @override
  State<_GlobalReplaceDialog> createState() => _GlobalReplaceDialogState();
}

class _GlobalReplaceDialogState extends State<_GlobalReplaceDialog> {
  final TextEditingController _query = TextEditingController();
  final TextEditingController _replacement = TextEditingController();
  bool _caseSensitive = false;
  bool _busy = false;
  int _done = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _query.addListener(_refresh);
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _query.dispose();
    _replacement.dispose();
    super.dispose();
  }

  Future<void> _run(AppState state) async {
    if (_busy || _query.text.isEmpty) return;
    setState(() {
      _busy = true;
      _done = 0;
      _total = 0;
    });
    final count = await state.replaceAllInLibrary(
      _query.text,
      _replacement.text,
      caseSensitive: _caseSensitive,
      onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _done = done;
          _total = total;
        });
      },
    );
    if (mounted) Navigator.of(context).pop(count);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final matches = state.countMatchesInLibrary(
      _query.text,
      caseSensitive: _caseSensitive,
    );
    return AlertDialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      title: Text(
        _t('全局搜索替换'),
        style: TextStyle(
          fontFamily: 'WenKai',
          fontSize: 22,
          color: c.ink,
        ),
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DialogField(
              controller: _query,
              label: _t('查找'),
              autofocus: true,
            ),
            const SizedBox(height: 10),
            _DialogField(
              controller: _replacement,
              label: _t('替换为'),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _busy
                  ? null
                  : () => setState(() => _caseSensitive = !_caseSensitive),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      _caseSensitive
                          ? LucideIcons.checkSquare
                          : LucideIcons.square,
                      size: 15,
                      color: _caseSensitive ? c.accent : c.inkMuted,
                    ),
                    const SizedBox(width: 7),
                    Text(
                      _t('区分大小写'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11.5,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _query.text.isEmpty
                  ? _t('替换前会为每篇笔记留一份历史版本')
                  : matches == 0
                      ? _t('没有找到可替换的文字')
                      : _t('将替换全部笔记中的 {n} 处', {'n': matches}),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                height: 1.5,
                color: matches == 0 && _query.text.isNotEmpty
                    ? c.danger
                    : c.inkMuted,
              ),
            ),
            if (_busy) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _total == 0 ? null : _done / _total,
                minHeight: 2,
                color: c.accent,
                backgroundColor: c.line,
              ),
              const SizedBox(height: 6),
              Text(
                _t('正在替换 {done}/{total}', {
                  'done': _done,
                  'total': _total == 0 ? '…' : _total,
                }),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(
            _t('取消'),
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 12,
              color: c.inkSoft,
            ),
          ),
        ),
        FilledButton(
          onPressed: _busy || _query.text.isEmpty || matches == 0
              ? null
              : () => _run(state),
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: c.onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(
            _t('替换全部'),
            style: const TextStyle(fontFamily: 'NotoSansSC', fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return TextField(
      controller: controller,
      autofocus: autofocus,
      style: TextStyle(fontFamily: 'NotoSansSC', fontSize: 13, color: c.ink),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 11,
          color: c.inkMuted,
        ),
        isDense: true,
        filled: true,
        fillColor: c.paper,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
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
          borderSide: BorderSide(color: c.accent.withValues(alpha: 0.6)),
        ),
      ),
    );
  }
}