import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../state/app_state.dart';

/// 编辑器内的查找 / 替换条。Ctrl+F 打开查找，Ctrl+H 打开并展开替换。
class FindBar extends StatefulWidget {
  const FindBar({required this.session, this.mobile = false, super.key});

  final EditorSession session;
  final bool mobile;

  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  late final TextEditingController _find;
  late final TextEditingController _replace;
  final FocusNode _findFocus = FocusNode();
  final FocusNode _replaceFocus = FocusNode();
  late int _tick;

  @override
  void initState() {
    super.initState();
    _find = TextEditingController(text: widget.session.findQuery);
    _replace = TextEditingController(text: widget.session.replaceQuery);
    _tick = widget.session.findFocusTick;
    _focusFind();
  }

  @override
  void didUpdateWidget(covariant FindBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.session.findFocusTick != _tick) {
      _tick = widget.session.findFocusTick;
      _find.text = widget.session.findQuery;
      _focusFind();
    }
    if (_replace.text != widget.session.replaceQuery) {
      _replace.text = widget.session.replaceQuery;
    }
  }

  void _focusFind() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _findFocus.requestFocus();
      _find.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _find.text.length,
      );
    });
  }

  @override
  void dispose() {
    _find.dispose();
    _replace.dispose();
    _findFocus.dispose();
    _replaceFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final session = widget.session;
    final width = widget.mobile
        ? MediaQuery.sizeOf(context).width - 16
        : 438.0;
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width.clamp(220.0, 438.0),
        decoration: BoxDecoration(
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
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              session.closeFind();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
                child: Row(
                  children: [
                    Icon(LucideIcons.search, size: 14, color: c.inkMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _find,
                        focusNode: _findFocus,
                        autofocus: true,
                        onChanged: session.setFindQuery,
                        onSubmitted: (_) => session.findNext(),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 12.5,
                          color: c.ink,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '查找…',
                          hintStyle: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 12.5,
                            color: c.inkMuted,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    _Counter(session: session),
                    _BarIcon(
                      icon: LucideIcons.chevronUp,
                      tooltip: '上一处 · Shift Enter',
                      onPressed: () => session.findNext(backwards: true),
                    ),
                    _BarIcon(
                      icon: LucideIcons.chevronDown,
                      tooltip: '下一处 · Enter',
                      onPressed: () => session.findNext(),
                    ),
                    _CaseToggle(session: session),
                    _BarIcon(
                      icon: session.findReplaceVisible
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      tooltip: session.findReplaceVisible ? '收起替换' : '替换',
                      onPressed: session.toggleReplaceRow,
                    ),
                    _BarIcon(
                      icon: LucideIcons.x,
                      tooltip: '关闭 · Esc',
                      onPressed: session.closeFind,
                    ),
                  ],
                ),
              ),
              if (session.findReplaceVisible) ...[
                Divider(height: 1, color: c.line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
                  child: Row(
                    children: [
                      Icon(
                        LucideIcons.replace,
                        size: 14,
                        color: c.inkMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _replace,
                          focusNode: _replaceFocus,
                          onChanged: session.setReplaceQuery,
                          onSubmitted: (_) => _replaceOne(context),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 12.5,
                            color: c.ink,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '替换为…',
                            hintStyle: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 12.5,
                              color: c.inkMuted,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _replaceOne(context),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '替换',
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _replaceAll(context),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '全部',
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _replaceOne(BuildContext context) {
    final replaced = widget.session.replaceCurrent();
    if (!replaced && widget.session.findQuery.isNotEmpty) {
      showToast(context, '先选中一处命中再替换', icon: LucideIcons.info);
    }
  }

  void _replaceAll(BuildContext context) {
    final count = widget.session.replaceAll();
    if (count == 0) {
      showToast(context, '没有可替换的内容');
    } else {
      showToast(context, '已替换 $count 处', icon: LucideIcons.check);
    }
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final total = session.findTotal;
    final current = session.findCurrent;
    if (session.findQuery.isEmpty) return const SizedBox(width: 8);
    final text = total == 0
        ? '无结果'
        : current > 0
            ? '$current/$total'
            : '$total 处';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 10,
          color: total == 0 ? c.danger : c.inkMuted,
        ),
      ),
    );
  }
}

class _CaseToggle extends StatelessWidget {
  const _CaseToggle({required this.session});

  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Tooltip(
      message: session.findCaseSensitive ? '区分大小写：开' : '区分大小写：关',
      child: GestureDetector(
        onTap: session.toggleFindCase,
        child: Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: session.findCaseSensitive ? c.accentSoft : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            'Aa',
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 10.5,
              color: session.findCaseSensitive ? c.accent : c.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _BarIcon extends StatelessWidget {
  const _BarIcon({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SoftIconButton(
      icon: icon,
      tooltip: tooltip,
      size: 26,
      iconSize: 14,
      onPressed: onPressed,
    );
  }
}
