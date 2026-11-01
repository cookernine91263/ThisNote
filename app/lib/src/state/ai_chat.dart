import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/ai_service.dart';

/// 一篇笔记一段对话：消息、流式状态与落盘都在这里。
class AiChatController extends ChangeNotifier {
  AiChatController({
    required this.store,
    required this.noteId,
    required this.settings,
  });

  final NoteStore store;
  final String noteId;
  final AiSettings settings;

  AiConversation? _conversation;
  AiService? _service;
  bool _loading = false;
  bool _busy = false;
  bool _disposed = false;
  String _streamingText = '';
  String? _error;
  int _seq = 0;
  int _generation = 0;

  AiConversation? get conversation => _conversation;
  List<AiMessage> get messages =>
      _conversation?.messages ?? const <AiMessage>[];
  bool get loading => _loading;
  bool get busy => _busy;
  String get streamingText => _streamingText;
  String? get error => _error;
  bool get canRetry => !_busy && messages.any((e) => e.role == AiRole.user);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  static const String defaultSystem =
      '你是「此记」的写作助手。请理解用户笔记的上下文，用克制、自然的中文回答；'
      '不要虚构事实，不要添加与写作无关的闲聊。用户要求改写时，只输出改写后的正文。';

  String _id() {
    _seq++;
    return '${DateTime.now().microsecondsSinceEpoch}_$_seq';
  }

  Future<void> load() async {
    if (_disposed || _loading) return;
    _loading = true;
    _notify();
    try {
      _conversation = await store.loadConversation(noteId) ??
          AiConversation(noteId: noteId);
    } catch (_) {
      _conversation = AiConversation(noteId: noteId);
    }
    if (_disposed) return;
    _loading = false;
    _notify();
  }

  Future<void> send({
    required String prompt,
    String action = '',
    String system = '',
    String quote = '',
    int? quoteStart,
    int? quoteEnd,
    int? revision,
  }) async {
    final text = prompt.trim();
    if (_busy || text.isEmpty) return;
    if (_conversation == null) await load();
    final conversation = _conversation!;
    final generation = ++_generation;

    final history = _requestHistory(conversation.messages);
    final systemPrompt = system.trim().isNotEmpty
        ? system.trim()
        : (conversation.system.trim().isNotEmpty
            ? conversation.system
            : defaultSystem);
    conversation.system = systemPrompt;

    conversation.messages.add(
      AiMessage(
        id: _id(),
        role: AiRole.user,
        text: text,
        at: DateTime.now(),
        action: action,
        quote: quote,
        quoteStart: quoteStart,
        quoteEnd: quoteEnd,
        revision: revision,
      ),
    );
    _trim();
    _busy = true;
    _streamingText = '';
    _error = null;
    _notify();
    unawaited(_persist());

    final service = AiService(settings);
    _service = service;
    try {
      final result = await service.completeStream(
        system: systemPrompt,
        user: text,
        history: history,
        onDelta: (partial) {
          if (generation != _generation || _disposed) return;
          _streamingText = partial;
          _notify();
        },
      );
      if (generation != _generation) return;
      final answer = result.trim();
      if (service.cancelled) {
        _appendPartial(quoteStart, quoteEnd, revision, action, quote);
      } else if (answer.isEmpty) {
        _appendError('AI 没有返回内容', action);
      } else {
        conversation.messages.add(
          AiMessage(
            id: _id(),
            role: AiRole.assistant,
            text: answer,
            at: DateTime.now(),
            action: action,
            quote: quote,
            quoteStart: quoteStart,
            quoteEnd: quoteEnd,
            revision: revision,
          ),
        );
      }
    } on AiException catch (e) {
      if (generation != _generation) return;
      if (service.cancelled) {
        _appendPartial(quoteStart, quoteEnd, revision, action, quote);
      } else {
        _appendError(e.message, action);
      }
    } catch (e) {
      if (generation != _generation) return;
      if (service.cancelled) {
        _appendPartial(quoteStart, quoteEnd, revision, action, quote);
      } else {
        _appendError('$e', action);
      }
    } finally {
      if (identical(_service, service)) _service = null;
      if (generation == _generation) {
        _busy = false;
        _streamingText = '';
        _trim();
        _notify();
        await _persist();
      }
    }
  }

  void _appendPartial(
    int? quoteStart,
    int? quoteEnd,
    int? revision,
    String action,
    String quote,
  ) {
    final partial = _streamingText.trim();
    if (partial.isEmpty) return;
    _conversation?.messages.add(
      AiMessage(
        id: _id(),
        role: AiRole.assistant,
        text: partial,
        at: DateTime.now(),
        action: action,
        quote: quote,
        quoteStart: quoteStart,
        quoteEnd: quoteEnd,
        revision: revision,
        interrupted: true,
      ),
    );
  }

  void _appendError(String message, String action) {
    _error = message;
    _conversation?.messages.add(
      AiMessage(
        id: _id(),
        role: AiRole.assistant,
        text: message,
        at: DateTime.now(),
        action: action,
        error: true,
      ),
    );
  }

  void cancel() {
    _service?.cancel();
  }

  Future<void> clear() async {
    cancel();
    _generation++;
    _busy = false;
    _conversation = AiConversation(noteId: noteId);
    _streamingText = '';
    _error = null;
    _notify();
    await store.deleteConversation(noteId);
  }

  Future<void> retryLast() async {
    if (_busy) return;
    final conversation = _conversation;
    if (conversation == null) return;
    final index = conversation.messages.lastIndexWhere(
      (e) => e.role == AiRole.user,
    );
    if (index < 0) return;
    final user = conversation.messages[index];
    conversation.messages.removeRange(index, conversation.messages.length);
    _notify();
    await _persist();
    await send(
      prompt: user.text,
      action: user.action,
      system: conversation.system,
      quote: user.quote,
      quoteStart: user.quoteStart,
      quoteEnd: user.quoteEnd,
      revision: user.revision,
    );
  }

  List<Map<String, String>> _requestHistory(List<AiMessage> messages) {
    final result = <Map<String, String>>[];
    var total = 0;
    const maxMessages = 12;
    const maxChars = 24000;
    for (final message in messages.reversed) {
      if (result.length >= maxMessages) break;
      if (message.error) continue;
      final text = message.text.length > 6000
          ? message.text.substring(0, 6000)
          : message.text;
      if (text.trim().isEmpty) continue;
      if (total + text.length > maxChars) break;
      total += text.length;
      result.add({
        'role': message.role == AiRole.assistant ? 'assistant' : 'user',
        'content': text,
      });
    }
    return result.reversed.toList(growable: false);
  }

  void _trim() {
    final conversation = _conversation;
    if (conversation == null) return;
    while (conversation.messages.length > 80) {
      conversation.messages.removeAt(0);
    }
    var total = 0;
    for (var i = conversation.messages.length - 1; i >= 0; i--) {
      total += conversation.messages[i].text.length;
      if (total > 120000) {
        conversation.messages.removeRange(0, i + 1);
        break;
      }
    }
  }

  Future<void> _persist() async {
    if (_disposed) return;
    final conversation = _conversation;
    if (conversation == null) return;
    conversation.updatedAt = DateTime.now();
    try {
      await store.saveConversation(conversation);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    cancel();
    super.dispose();
  }
}
