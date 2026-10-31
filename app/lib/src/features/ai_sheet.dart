import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../services/ai_service.dart';
import '../state/app_state.dart';

/// 文案以中文为源，英文放在 [_en] 里。
/// [AiAction] 的 label / hint 也是中文原文，显示时再查这张表。
const Map<String, String> _en = <String, String>{
  '润色选中': 'Polish selection',
  '扩写一点': 'Expand a little',
  '压缩一下': 'Condense',
  '接着写': 'Continue writing',
  '起个标题': 'Give it a title',
  '生成提纲': 'Make an outline',
  '译成英文': 'Translate to English',
  '译成日文': 'Translate to Japanese',
  '让表达更准确、自然': 'Make it accurate and natural',
  '补充细节，不虚构事实': 'Add detail without inventing facts',
  '保留关键信息，更克制': 'Keep the key points, say less',
  '顺着现在的语气往下写': 'Continue in the same voice',
  '根据正文起一个标题': 'Title it from the body text',
  '把想法整理成结构': 'Turn the idea into structure',
  '保留语气的英文译文': 'English that keeps the tone',
  '保留语气的日文译文': 'Japanese that keeps the tone',
  '先配置 AI 助手': 'Set up the AI assistant first',
  '此记不绑定任何厂商。你可以在设置里填写任意 OpenAI 兼容接口的地址、模型与 API Key。\n\n只有在点击 AI 功能时，选中的文字才会被发送。':
      'ThisNote is not tied to any vendor. In Settings you can enter the address, model and API key of any OpenAI-compatible endpoint.\n\nText is only sent when you tap an AI action.',
  '稍后': 'Later',
  '去设置': 'Open settings',
  '先选中一段文字，再让 AI 帮忙': 'Select some text first, then ask AI',
  '先写一点内容': 'Write something first',
  '已停止生成': 'Stopped generating',
  'AI 没有返回内容': 'AI returned nothing',
  '标题已更新': 'Title updated',
  '已写入纸上': 'Written onto the page',
  'AI 助手': 'AI assistant',
  '可选': 'Optional',
  '先选中文字；标题/提纲/续写会使用当前正文。':
      'Select text first; Title, Outline and Continue use the whole note.',
  '正在停止…': 'Stopping…',
  '停止': 'Stop',
  '正在思考…': 'Thinking…',
  '生成时可以先读；完成后会请你预览，确认后才写进正文。':
      'You can read along as it writes; you will preview the result before it is added to the note.',
  'AI 的建议 · {action}': 'AI suggestion · {action}',
  '放弃': 'Discard',
  '替换选中': 'Replace selection',
  '插入': 'Insert',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

enum AiAction {
  polish,
  expand,
  shorten,
  continueWriting,
  title,
  outline,
  translateEn,
  translateJa,
}

extension AiActionX on AiAction {
  String get label => switch (this) {
        AiAction.polish => '润色选中',
        AiAction.expand => '扩写一点',
        AiAction.shorten => '压缩一下',
        AiAction.continueWriting => '接着写',
        AiAction.title => '起个标题',
        AiAction.outline => '生成提纲',
        AiAction.translateEn => '译成英文',
        AiAction.translateJa => '译成日文',
      };

  String get hint => switch (this) {
        AiAction.polish => '让表达更准确、自然',
        AiAction.expand => '补充细节，不虚构事实',
        AiAction.shorten => '保留关键信息，更克制',
        AiAction.continueWriting => '顺着现在的语气往下写',
        AiAction.title => '根据正文起一个标题',
        AiAction.outline => '把想法整理成结构',
        AiAction.translateEn => '保留语气的英文译文',
        AiAction.translateJa => '保留语气的日文译文',
      };

  IconData get icon => switch (this) {
        AiAction.polish => LucideIcons.wandSparkles,
        AiAction.expand => LucideIcons.maximize2,
        AiAction.shorten => LucideIcons.minimize2,
        AiAction.continueWriting => LucideIcons.penLine,
        AiAction.title => LucideIcons.heading1,
        AiAction.outline => LucideIcons.list,
        AiAction.translateEn => LucideIcons.languages,
        AiAction.translateJa => LucideIcons.languages,
      };

  bool get needsSelection => switch (this) {
        AiAction.continueWriting || AiAction.title || AiAction.outline => false,
        _ => true,
      };

  String get systemPrompt => switch (this) {
        AiAction.polish =>
          '你是一位克制、敏锐的中文写作编辑。请润色用户提供的文字：保持原意、语气与体裁，修正语病，让表达更准确、自然。不要添加解释，只输出润色后的正文。',
        AiAction.expand =>
          '你是一位中文写作助手。请在不虚构事实、不改变原意的前提下扩写用户提供的文字，补充可感知的细节与节奏。不要添加解释，只输出扩写后的正文。',
        AiAction.shorten =>
          '你是一位克制的中文编辑。请压缩用户提供的文字，保留关键信息与语气，删除重复和空话。不要添加解释，只输出压缩后的正文。',
        AiAction.continueWriting =>
          '你是一位中文写作助手。请顺着用户提供的文字与语气自然续写 2 到 3 段，不重复已有内容，不突然改变主题。不要添加解释，只输出续写部分。',
        AiAction.title =>
          '你是一位中文编辑。请为用户的文章起一个克制、有文学感、不超过 16 个字的标题。只输出标题本身，不要引号、编号或解释。',
        AiAction.outline =>
          '你是一位中文写作教练。请把用户的想法整理成一份简洁的写作提纲，使用「- 」列表，最多 7 条。只输出提纲。',
        AiAction.translateEn =>
          'You are a literary translator. Translate the text into natural English while preserving tone and nuance. Output only the translation.',
        AiAction.translateJa =>
          'あなたは文学的な翻訳者です。原文の語調とニュアンスを保ちながら、自然な日本語に翻訳してください。翻訳だけを出力してください。',
      };
}

Future<void> showAiSheet(BuildContext context, EditorSession session) async {
  final state = context.read<AppState>();
  final ai = state.settings.aiSettings;
  if (!ai.configured) {
    await _showConfigure(context, state);
    return;
  }
  final action = await showDialog<AiAction>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (context) => const _AiMenuDialog(),
  );
  if (action == null || !context.mounted) return;
  await _runAction(context, state, session, action);
}

Future<void> _showConfigure(BuildContext context, AppState state) async {
  final c = AppPalette.of(context);
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: c.surface,
      title: Text(
        _t('先配置 AI 助手'),
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: c.ink,
        ),
      ),
      content: Text(
        _t('此记不绑定任何厂商。你可以在设置里填写任意 OpenAI 兼容接口的地址、模型与 API Key。\n\n只有在点击 AI 功能时，选中的文字才会被发送。'),
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 12,
          height: 1.8,
          color: c.inkSoft,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(_t('稍后'), style: TextStyle(color: c.inkMuted)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: c.ink,
            foregroundColor: c.paper,
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(_t('去设置')),
        ),
      ],
    ),
  );
  if (go == true) state.setView('settings');
}

Future<void> _runAction(
  BuildContext context,
  AppState state,
  EditorSession session,
  AiAction action,
) async {
  final selection = session.controller.selection;
  final selected = selection.isCollapsed
      ? ''
      : session.controller.document
          .toPlainText()
          .substring(selection.start, selection.end);
  if (action.needsSelection && selected.trim().isEmpty) {
    showToast(
      context,
      _t('先选中一段文字，再让 AI 帮忙'),
      icon: LucideIcons.textCursor,
    );
    return;
  }
  final contextText = action.needsSelection
      ? selected
      : session.plainText.length > 6000
          ? session.plainText.substring(0, 6000)
          : session.plainText;
  if (contextText.trim().isEmpty) {
    showToast(context, _t('先写一点内容'));
    return;
  }

  final partial = ValueNotifier<String>('');
  final service = AiService(state.settings.aiSettings);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.2),
    builder: (_) => _AiStreaming(
      action: action,
      partial: partial,
      onCancel: service.cancel,
    ),
  );
  String? result;
  String? error;
  try {
    final user = StringBuffer();
    if (session.note.title.trim().isNotEmpty) {
      user.writeln('标题：${session.note.title.trim()}');
    }
    user.writeln('类型：${session.note.kind.label}');
    user.writeln();
    user.writeln(contextText);
    result = await service.completeStream(
      system: action.systemPrompt,
      user: user.toString(),
      onDelta: (text) => partial.value = text,
    );
  } catch (e) {
    error = e.toString();
  }
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();

  if (service.cancelled) {
    showToast(context, _t('已停止生成'), icon: LucideIcons.circleStop);
    return;
  }
  if (error != null) {
    showToast(context, error, icon: LucideIcons.alertCircle);
    return;
  }
  final text = result!.trim();
  if (text.isEmpty) {
    showToast(context, _t('AI 没有返回内容'));
    return;
  }
  if (action == AiAction.title) {
    session.titleController.text = text.replaceAll(RegExp(r'^["「『]|["」』]$'), '');
    session.scheduleSave(immediate: true);
    showToast(context, _t('标题已更新'), icon: LucideIcons.sparkles);
    return;
  }

  final accept = await showDialog<bool>(
    context: context,
    builder: (context) => _AiResultDialog(
      action: action,
      result: text,
      canReplace: !selection.isCollapsed &&
          const [
            AiAction.polish,
            AiAction.expand,
            AiAction.shorten,
            AiAction.translateEn,
            AiAction.translateJa,
          ].contains(action),
    ),
  );
  if (accept != true || !context.mounted) return;

  if (const [
    AiAction.polish,
    AiAction.expand,
    AiAction.shorten,
    AiAction.translateEn,
    AiAction.translateJa,
  ].contains(action) && !selection.isCollapsed) {
    session.controller.replaceText(
      selection.start,
      selection.end - selection.start,
      text,
      TextSelection.collapsed(offset: selection.start + text.length),
    );
  } else {
    session.controller.replaceText(
      selection.start,
      0,
      text,
      TextSelection.collapsed(offset: selection.start + text.length),
    );
  }
  session.scheduleSave(immediate: true);
  if (context.mounted) {
    showToast(context, _t('已写入纸上'), icon: LucideIcons.sparkles);
  }
}

class _AiMenuDialog extends StatelessWidget {
  const _AiMenuDialog();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _t('AI 助手'),
                    style: TextStyle(
                      fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                      fontSize: I18n.isEn ? 20 : 24,
                      fontWeight: I18n.isEn ? FontWeight.w600 : null,
                      letterSpacing: I18n.isEn ? 0.3 : 1,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _t('可选'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 8.5,
                        color: c.accent,
                      ),
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
                _t('先选中文字；标题/提纲/续写会使用当前正文。'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 12),
              for (final action in AiAction.values)
                HoverBuilder(
                  builder: (context, hovered, t) => GestureDetector(
                    onTap: () => Navigator.of(context).pop(action),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      margin: const EdgeInsets.only(bottom: 2),
                      decoration: BoxDecoration(
                        color: hovered ? c.paper : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            action.icon,
                            size: 14,
                            color: hovered ? c.accent : c.inkMuted,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            _t(action.label),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 12,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _t(action.hint),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiStreaming extends StatefulWidget {
  const _AiStreaming({
    required this.action,
    required this.partial,
    required this.onCancel,
  });

  final AiAction action;
  final ValueNotifier<String> partial;
  final VoidCallback onCancel;

  @override
  State<_AiStreaming> createState() => _AiStreamingState();
}

class _AiStreamingState extends State<_AiStreaming> {
  final ScrollController _scroll = ScrollController();
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    widget.partial.addListener(_follow);
  }

  @override
  void dispose() {
    widget.partial.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.sparkles, size: 15, color: c.accent),
                  const SizedBox(width: 8),
                  Text(
                    '${_t(widget.action.label)}…',
                    style: TextStyle(
                      fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                      fontSize: 19,
                      fontWeight: I18n.isEn ? FontWeight.w600 : null,
                      letterSpacing: 0.5,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _stopping
                        ? null
                        : () {
                            setState(() => _stopping = true);
                            widget.onCancel();
                          },
                    child: Text(
                      _stopping ? _t('正在停止…') : _t('停止'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11.5,
                        color: _stopping ? c.inkMuted : c.accent,
                      ),
                    ),
                  ),
                ],
              ),
              Divider(height: 14, color: c.line),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scroll,
                  child: ValueListenableBuilder<String>(
                    valueListenable: widget.partial,
                    builder: (context, text, _) {
                      if (text.isEmpty) {
                        return Text(
                          _t('正在思考…'),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 12,
                            color: c.inkMuted,
                          ),
                        );
                      }
                      return SelectableText(
                        text,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 13,
                          height: 1.8,
                          color: c.ink,
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _t('生成时可以先读；完成后会请你预览，确认后才写进正文。'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9.5,
                  height: I18n.isEn ? 1.5 : null,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}class _AiResultDialog extends StatelessWidget {
  const _AiResultDialog({
    required this.action,
    required this.result,
    required this.canReplace,
  });

  final AiAction action;
  final String result;
  final bool canReplace;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(LucideIcons.sparkles, size: 15, color: c.accent),
                  const SizedBox(width: 7),
                  Text(
                    _t('AI 的建议 · {action}', {
                      'action': _t(action.label),
                    }),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  SoftIconButton(
                    icon: LucideIcons.x,
                    size: 28,
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: c.paper,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.line),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      result,
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 12.5,
                        height: 1.8,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      _t('放弃'),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 11,
                        color: c.inkMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.ink,
                      foregroundColor: c.paper,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      canReplace ? _t('替换选中') : _t('插入'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
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
