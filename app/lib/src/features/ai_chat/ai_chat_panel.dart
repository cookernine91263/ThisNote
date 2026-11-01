import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../state/ai_chat.dart';
import '../../state/app_state.dart';
import '../ai_sheet.dart';
import '../editor/code_block.dart';

const Map<String, String> _en = <String, String>{
  'AI 助手': 'AI assistant',
  '清空对话': 'Clear chat',
  '清空这段对话？': 'Clear this conversation?',
  '清空后可以从头再问。': 'You can start over after clearing.',
  '清空': 'Clear',
  '聊天': 'Chat',
  '有什么想一起写的？': 'What shall we write together?',
  '可以让我润色、续写，或者直接聊聊你的想法。':
      'Ask me to polish, continue, or just talk through an idea.',
  '和 AI 说点什么…': 'Ask the AI something…',
  '发送': 'Send',
  '停止': 'Stop',
  '正在思考…': 'Thinking…',
  '插入': 'Insert',
  '替换选中': 'Replace selection',
  '用作标题': 'Use as title',
  '复制': 'Copy',
  '已插入纸上': 'Inserted into the note',
  '已替换选中': 'Replaced the selection',
  '已复制': 'Copied',
  '正文已经变了，改为插入到光标处':
      'The note changed; inserted at the cursor instead',
  '标题已更新': 'Title updated',
  '再试一次': 'Retry',
  '重试': 'Retry',
  '已停止': 'Stopped',
  '对话已清空': 'Conversation cleared',
  '可选': 'Optional',
  '先选中一段文字': 'Select some text first',
  '先写一点内容': 'Write something first',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<void> openAiChat(
  BuildContext context,
  EditorSession session,
) async {
  final ai = session.app.settings.aiSettings;
  if (!ai.configured) {
    await showAiConfigure(context, session.app);
    if (!context.mounted) return;
    if (!session.app.settings.aiSettings.configured) return;
  }
  if (MediaQuery.sizeOf(context).width < 900) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppPalette.of(context).surface,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92,
        child: AiChatPanel(
          session: session,
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    );
    return;
  }
  session.setAiOpen(!session.aiOpen);
}

class AiChatPanel extends StatefulWidget {
  const AiChatPanel({
    super.key,
    required this.session,
    this.onClose,
    this.docked = false,
  });

  final EditorSession session;
  final VoidCallback? onClose;
  final bool docked;

  @override
  State<AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<AiChatPanel> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.session.aiChat.addListener(_follow);
  }

  @override
  void dispose() {
    widget.session.aiChat.removeListener(_follow);
    _composer.dispose();
    _composerFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: Motion.fast,
        curve: Motion.enter,
      );
    });
  }

  String _selectedText() {
    final session = widget.session;
    final selection = session.controller.selection;
    if (selection.isCollapsed || selection.start >= selection.end) return '';
    return deltaPlainText(
      session.controller.document
          .toDelta()
          .slice(selection.start, selection.end - selection.start),
    );
  }

  Future<void> _runAction(AiAction action) async {
    final session = widget.session;
    final chat = session.aiChat;
    if (chat.busy) return;
    final selected = _selectedText();
    final whole = session.plainText.length > 6000
        ? session.plainText.substring(0, 6000)
        : session.plainText;
    if (action.needsSelection && selected.trim().isEmpty) {
      showToast(
        context,
        _t('先选中一段文字'),
        icon: LucideIcons.textCursor,
      );
      return;
    }
    if (!action.needsSelection && whole.trim().isEmpty) {
      showToast(context, _t('先写一点内容'));
      return;
    }
    final prompt = action.needsSelection ? selected : whole;
    await chat.send(
      prompt: prompt,
      action: action.name,
      system: action.systemPrompt,
      quote: selected,
      quoteStart: action.needsSelection ? session.controller.selection.start : null,
      quoteEnd: action.needsSelection ? session.controller.selection.end : null,
      revision: session.revision,
    );
  }

  Future<void> _sendMessage() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    final session = widget.session;
    final selected = _selectedText();
    final selection = session.controller.selection;
    final prompt = selected.trim().isEmpty
        ? text
        : '选中的文字：\n$selected\n\n我的问题：\n$text';
    _composer.clear();
    await session.aiChat.send(
      prompt: prompt,
      system: AiChatController.defaultSystem,
      quote: selected,
      quoteStart: selection.isCollapsed ? null : selection.start,
      quoteEnd: selection.isCollapsed ? null : selection.end,
      revision: session.revision,
    );
  }

  Future<void> _clear() async {
    final ok = await showConfirm(
      context,
      title: _t('清空这段对话？'),
      message: _t('清空后可以从头再问。'),
      confirmLabel: _t('清空'),
      danger: true,
    );
    if (!ok) return;
    await widget.session.aiChat.clear();
    if (mounted) showToast(context, _t('对话已清空'));
  }

  void _copy(AiMessage message) {
    Clipboard.setData(ClipboardData(text: message.text));
    showToast(context, _t('已复制'));
  }

  void _apply(AiMessage message, {required bool replace, bool asTitle = false}) {
    final session = widget.session;
    final controller = session.controller;
    final canReplace = replace &&
        message.quoteStart != null &&
        message.quoteEnd != null &&
        message.revision == session.revision &&
        message.quoteEnd! > message.quoteStart!;
    final text = message.text.trim();
    if (text.isEmpty) return;

    if (asTitle && message.action == AiAction.title.name) {
      session.titleController.text =
          text.replaceAll(RegExp(r'^["「『]|["」』]$'), '');
      session.scheduleSave(immediate: true);
      showToast(context, _t('标题已更新'), icon: LucideIcons.heading1);
      return;
    }

    if (canReplace) {
      controller.replaceText(
        message.quoteStart!,
        message.quoteEnd! - message.quoteStart!,
        text,
        TextSelection.collapsed(offset: message.quoteStart! + text.length),
      );
    } else {
      final selection = controller.selection;
      final start = selection.isValid ? selection.start : controller.document.length - 1;
      final end = selection.isValid ? selection.end : start;
      controller.replaceText(
        start,
        end - start,
        text,
        TextSelection.collapsed(offset: start + text.length),
      );
      if (replace) {
        showToast(context, _t('正文已经变了，改为插入到光标处'));
      }
    }
    session.scheduleSave(immediate: true);
    showToast(
      context,
      canReplace ? _t('已替换选中') : _t('已插入纸上'),
      icon: LucideIcons.sparkles,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final chat = widget.session.aiChat;
    final settings = widget.session.app.settings.aiSettings;
    final content = Container(
      decoration: BoxDecoration(
        color: c.surface,
        border: widget.docked ? Border(left: BorderSide(color: c.line)) : null,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                Icon(LucideIcons.sparkles, size: 16, color: c.accent),
                const SizedBox(width: 8),
                Text(
                  _t('AI 助手'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${_thinkingLabel(settings.thinkingLevel)} · ${settings.model}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9,
                      color: c.inkMuted,
                    ),
                  ),
                ),
                const Spacer(),
                SoftIconButton(
                  icon: LucideIcons.eraser,
                  tooltip: _t('清空对话'),
                  size: 28,
                  onPressed: _clear,
                ),
                if (widget.onClose != null)
                  SoftIconButton(
                    icon: LucideIcons.x,
                    size: 28,
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          SizedBox(
            height: 42,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              children: [
                for (final action in AiAction.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _ActionChip(
                      icon: action.icon,
                      label: _t(action.label),
                      enabled: !chat.busy,
                      onTap: () => _runAction(action),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: c.line),
          Expanded(
            child: AnimatedBuilder(
              animation: chat,
              builder: (context, _) {
                final messages = chat.messages;
                final streaming = chat.busy && chat.streamingText.isNotEmpty;
                if (messages.isEmpty && !streaming) {
                  return _EmptyChat(muted: c.inkMuted, accent: c.accent);
                }
                final count = messages.length + (streaming ? 1 : 0);
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  itemCount: count,
                  itemBuilder: (context, index) {
                    if (streaming && index == messages.length) {
                      return _Bubble(
                        role: AiRole.assistant,
                        text: chat.streamingText,
                        busy: true,
                        onStop: chat.cancel,
                      );
                    }
                    final message = messages[index];
                    return _Bubble(
                      role: message.role,
                      text: message.text,
                      error: message.error,
                      interrupted: message.interrupted,
                      onRetry: message.error ? chat.retryLast : null,
                      actions: message.role == AiRole.assistant &&
                              !message.error &&
                              !message.interrupted
                          ? _MessageActions(
                              showReplace: message.quoteStart != null &&
                                  message.quoteEnd != null,
                              onReplace: () => _apply(message, replace: true),
                              onInsert: () => _apply(message, replace: false),
                              onCopy: () => _copy(message),
                              onTitle: message.action == AiAction.title.name
                                  ? () => _apply(
                                        message,
                                        replace: false,
                                        asTitle: true,
                                      )
                                  : null,
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
          Divider(height: 1, color: c.line),
          Padding(
            padding: EdgeInsets.fromLTRB(
              10,
              8,
              10,
              8 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 112),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: c.paper,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.line),
                    ),
                    child: TextField(
                      controller: _composer,
                      focusNode: _composerFocus,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.newline,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 12.5,
                        height: 1.6,
                        color: c.ink,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: _t('和 AI 说点什么…'),
                        hintStyle: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 12.5,
                          color: c.inkMuted,
                        ),
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedBuilder(
                  animation: chat,
                  builder: (context, _) {
                    final busy = chat.busy;
                    return GestureDetector(
                      onTap: busy ? chat.cancel : _sendMessage,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: busy ? c.danger : c.ink,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          busy ? LucideIcons.square : LucideIcons.arrowUp,
                          size: 17,
                          color: c.paper,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (!widget.docked) return content;
    return SafeArea(top: false, child: content);
  }
}

String _thinkingLabel(AiThinking level) => switch (level) {
      AiThinking.fast => _t('快'),
      AiThinking.balanced => _t('标准'),
      AiThinking.deep => _t('深入'),
    };

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: c.paper,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: c.inkMuted),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.muted, required this.accent});
  final Color muted;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.sparkles, size: 28, color: accent),
            const SizedBox(height: 12),
            Text(
              _t('有什么想一起写的？'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: muted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _t('可以让我润色、续写，或者直接聊聊你的想法。'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                height: 1.7,
                color: muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.role,
    required this.text,
    this.error = false,
    this.interrupted = false,
    this.busy = false,
    this.onStop,
    this.onRetry,
    this.actions,
  });

  final AiRole role;
  final String text;
  final bool error;
  final bool interrupted;
  final bool busy;
  final VoidCallback? onStop;
  final VoidCallback? onRetry;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final user = role == AiRole.user;
    return Padding(
      padding: EdgeInsets.only(
        left: user ? 34 : 0,
        right: user ? 0 : 22,
        bottom: 10,
      ),
      child: Column(
        crossAxisAlignment:
            user ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
            decoration: BoxDecoration(
              color: error
                  ? c.danger.withValues(alpha: 0.08)
                  : user
                      ? c.accentSoft
                      : c.paper,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: error ? c.danger.withValues(alpha: 0.4) : c.line,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  text,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 12.5,
                    height: 1.75,
                    color: error ? c.danger : c.inkSoft,
                  ),
                ),
                if (busy) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _t('正在思考…'),
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: onStop,
                        child: Text(
                          _t('停止'),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 9.5,
                            color: c.accent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (interrupted)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _t('已停止'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (error && onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: onRetry,
                child: Text(
                  _t('重试'),
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.accent,
                  ),
                ),
              ),
            ),
          if (actions != null) ...[
            const SizedBox(height: 4),
            actions!,
          ],
        ],
      ),
    );
  }
}

class _MessageActions extends StatelessWidget {
  const _MessageActions({
    required this.showReplace,
    required this.onReplace,
    required this.onInsert,
    required this.onCopy,
    this.onTitle,
  });

  final bool showReplace;
  final VoidCallback onReplace;
  final VoidCallback onInsert;
  final VoidCallback onCopy;
  final VoidCallback? onTitle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        if (onTitle != null) ...[
          _MiniAction(label: _t('用作标题'), onTap: onTitle!),
          _MiniAction(label: _t('复制'), onTap: onCopy),
        ] else ...[
          if (showReplace)
            _MiniAction(label: _t('替换选中'), onTap: onReplace),
          _MiniAction(label: _t('插入'), onTap: onInsert),
          _MiniAction(label: _t('复制'), onTap: onCopy),
        ],
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: c.paper,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: c.line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 9,
            color: c.inkMuted,
          ),
        ),
      ),
    );
  }
}
