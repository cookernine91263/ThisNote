import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/i18n.dart';
import '../data/models.dart';

/// 错误提示与系统提示的语言补丁。
const _en = <String, String>{
  '还没有配置 API Key': 'No API key configured yet',
  '接口地址为空': 'The API base URL is empty',
  '接口地址格式不正确': 'The API base URL is not valid',
  '请求超时，请检查网络或接口地址':
      'The request timed out. Check your network or the API URL.',
  '无法连接接口：{error}': 'Could not reach the API: {error}',
  '接口返回 {status}：{body}': 'The API returned {status}: {body}',
  '已取消': 'Cancelled',
  '接口没有返回文字': 'The API returned no text',
  '返回内容无法解析：{error}': 'Could not parse the response: {error}',
  '请用自然、地道的英文回答。': 'Respond in natural, polished English.',
  '模型只返回了思考过程，没有给出正文。换一个模型，或把思考强度调低一点再试。': 'The model only returned its reasoning, with no answer. Try another model, or lower the thinking level.',
  '接口没有返回文字（已自动重试一次非流式请求）':
      'The API returned no text (a non-streaming retry was already made)',
  '接口返回错误：{error}': 'The API returned an error: {error}',
};

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiService {
  AiService(this.settings);
  final AiSettings settings;

  http.Client? _client;
  bool _cancelled = false;

  /// 用户在中途点了「停止」。
  bool get cancelled => _cancelled;

  /// 中止正在进行的流式请求。已经收到的部分内容由界面自行处理。
  void cancel() {
    _cancelled = true;
    _client?.close();
    _client = null;
  }

  Uri _uri() {
    if (!settings.configured) {
      throw AiException(tr('还没有配置 API Key', null, _en));
    }
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw AiException(tr('接口地址为空', null, _en));
    final uri = Uri.tryParse(
      base.endsWith('/chat/completions') ? base : '$base/chat/completions',
    );
    if (uri == null) throw AiException(tr('接口地址格式不正确', null, _en));
    return uri;
  }

  /// 英文界面时给系统提示补一句语言要求，让模型也用英文作答；
  /// 中文界面的提示本身就是中文，原样发送。
  String _system(String system) {
    if (!I18n.isEn) return system;
    final directive = tr('请用自然、地道的英文回答。', null, _en);
    return system.trim().isEmpty ? directive : '$system\n\n$directive';
  }

  AiThinking get _level => settings.thinkingLevel;

  Map<String, dynamic> _body({
    required String system,
    required String user,
    required bool stream,
    required double temperature,
    required int maxTokens,
  }) => {
    'model': settings.model.trim().isEmpty
        ? 'deepseek-chat'
        : settings.model.trim(),
    'messages': [
      {'role': 'system', 'content': _system(system)},
      {'role': 'user', 'content': _safeText(user)},
    ],
    'temperature': temperature,
    'max_tokens': maxTokens,
    'stream': stream,
  };

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ${settings.apiKey.trim()}',
    'Accept': '*/*',
  };

  /// 非流式调用，保留给不支持 SSE 的网关、连通性测试，以及流式返回空内容时的重试。
  Future<String> complete({
    required String system,
    required String user,
    double? temperature,
    int? maxTokens,
  }) async {
    final uri = _uri();
    final body = _body(
      system: system,
      user: user,
      stream: false,
      temperature: temperature ?? _level.temperature,
      maxTokens: maxTokens ?? _level.maxTokens,
    );
    late http.Response response;
    try {
      response = await http
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw AiException(tr('请求超时，请检查网络或接口地址', null, _en));
    } catch (e) {
      throw AiException(tr('无法连接接口：{error}', {'error': e}, _en));
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AiException(
        tr('接口返回 {status}：{body}', {
          'status': response.statusCode,
          'body': _brief(utf8.decode(response.bodyBytes, allowMalformed: true)),
        }, _en),
      );
    }
    return _contentOf(utf8.decode(response.bodyBytes, allowMalformed: true));
  }

  /// 流式调用：每收到一段文字就回调 [onDelta]（参数是累积到现在的全文）。
  /// 用户调用 [cancel] 会抛出「已取消」。
  Future<String> completeStream({
    required String system,
    required String user,
    required void Function(String partial) onDelta,
    double? temperature,
    int? maxTokens,
  }) async {
    final uri = _uri();
    _cancelled = false;
    final level = _level;
    final wantTemperature = temperature ?? level.temperature;
    final wantTokens = maxTokens ?? level.maxTokens;
    final client = http.Client();
    _client = client;
    var reasoningOnly = '';
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({..._headers, 'Accept': 'text/event-stream'})
        ..body = jsonEncode(
          _body(
            system: system,
            user: user,
            stream: true,
            temperature: wantTemperature,
            maxTokens: wantTokens,
          ),
        );
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 90));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw AiException(
          tr('接口返回 {status}：{body}', {
            'status': response.statusCode,
            'body': _brief(body),
          }, _en),
        );
      }
      final type = response.headers['content-type'] ?? '';
      if (type.contains('application/json')) {
        // 有些网关会忽略 stream 参数，直接返回整段 JSON。
        return _contentOf(await response.stream.bytesToString());
      }

      final buffer = StringBuffer();
      final reasoning = StringBuffer();
      await for (final line
          in response.stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        if (_cancelled) break;
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        dynamic data;
        try {
          data = jsonDecode(payload);
        } catch (_) {
          // 心跳或半截 JSON，跳过就好
          continue;
        }
        if (data is! Map) continue;
        // 网关有时把错误塞在流里，这时要把它显示出来，而不是说「没有返回文字」。
        if (data['error'] != null) {
          throw AiException(_errorOf(data['error']));
        }
        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final choice = choices.first;
        if (choice is! Map) continue;
        final delta = choice['delta'];
        String? piece;
        String? thought;
        if (delta is Map) {
          piece = _textOf(delta['content']);
          thought =
              _textOf(delta['reasoning_content']) ??
              _textOf(delta['reasoning']);
        }
        // 少数网关在「流式」里发的是完整 message，这里一起兜住。
        final message = choice['message'];
        piece ??= message is Map ? _textOf(message['content']) : null;
        piece ??= _textOf(choice['text']);
        if (thought != null && thought.isNotEmpty) reasoning.write(thought);
        if (piece != null && piece.isNotEmpty) {
          buffer.write(piece);
          onDelta(buffer.toString());
        }
      }
      if (_cancelled) throw AiException(tr('已取消', null, _en));
      final text = buffer.toString().trim();
      if (text.isNotEmpty) return text;
      reasoningOnly = reasoning.toString().trim();
    } on TimeoutException {
      throw AiException(tr('请求超时，请检查网络或接口地址', null, _en));
    } on http.ClientException catch (e) {
      if (_cancelled) throw AiException(tr('已取消', null, _en));
      throw AiException(tr('无法连接接口：{error}', {'error': e}, _en));
    } finally {
      _client = null;
      client.close();
    }

    if (_cancelled) throw AiException(tr('已取消', null, _en));
    // 走到这里说明流结束了却一个字也没有：有的网关只是不认 SSE，
    // 有的思考型模型把预算全花在推理上。先原样再请求一次非流式，
    // 通常就能拿到正文；仍然为空时，再给出更准确的解释。
    try {
      final retry = await complete(
        system: system,
        user: user,
        temperature: wantTemperature,
        maxTokens: wantTokens,
      );
      if (retry.trim().isNotEmpty) {
        onDelta(retry);
        return retry;
      }
    } on AiException catch (e) {
      if (reasoningOnly.isNotEmpty && !_cancelled) {
        throw AiException(
          tr('模型只返回了思考过程，没有给出正文。换一个模型，或把思考强度调低一点再试。', null, _en),
        );
      }
      if (e.message == tr('接口没有返回文字', null, _en)) {
        throw AiException(
          tr('接口没有返回文字（已自动重试一次非流式请求）', null, _en),
        );
      }
      // 网关本来就支持流式但这次失败了，把流式的结果当成最终结果更诚实。
      if (reasoningOnly.isNotEmpty) {
        throw AiException(
          tr('模型只返回了思考过程，没有给出正文。换一个模型，或把思考强度调低一点再试。', null, _en),
        );
      }
      rethrow;
    }
    if (!_cancelled) {
      throw AiException(tr('接口没有返回文字（已自动重试一次非流式请求）', null, _en));
    }
    throw AiException(tr('已取消', null, _en));
  }

  /// 连通性测试：只请求一句话，返回耗时（毫秒）。
  /// 预算给得比「两个字」宽一点，思考型模型才不会把额度全花在推理上。
  Future<(int, String)> ping() async {
    final watch = Stopwatch()..start();
    final reply = await complete(
      system: '你是连通性测试助手。',
      user: '只回复两个字：收到',
      temperature: 0,
      maxTokens: 256,
    );
    watch.stop();
    return (watch.elapsedMilliseconds, reply);
  }

  /// 从 `content` 里取文字。标准实现是字符串，但也有网关返回分段数组。
  String? _textOf(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is String) {
          buffer.write(part);
        } else if (part is Map) {
          final text = part['text'] ?? part['content'] ?? part['value'];
          if (text is String) {
            buffer.write(text);
          } else if (text is Map && text['value'] is String) {
            buffer.write(text['value']);
          }
        }
      }
      return buffer.isEmpty ? null : buffer.toString();
    }
    return null;
  }

  String _errorOf(dynamic error) {
    if (error is String) return tr('接口返回错误：{error}', {'error': error}, _en);
    if (error is Map) {
      final message = error['message'] ?? error['msg'];
      if (message is String && message.trim().isNotEmpty) {
        return tr('接口返回错误：{error}', {'error': message.trim()}, _en);
      }
    }
    return tr('接口返回错误：{error}', {'error': '$error'}, _en);
  }

  String _contentOf(String body) {
    dynamic data;
    try {
      data = jsonDecode(body);
    } catch (e) {
      throw AiException(tr('返回内容无法解析：{error}', {'error': e}, _en));
    }
    if (data is Map && data['error'] != null) {
      throw AiException(_errorOf(data['error']));
    }
    try {
      final choices = (data as Map)['choices'];
      if (choices is List && choices.isNotEmpty) {
        final choice = choices.first;
        if (choice is Map) {
          final message = choice['message'];
          final text = message is Map
              ? _textOf(message['content'])
              : _textOf(choice['text']);
          if (text != null && text.trim().isNotEmpty) return text.trim();
        }
      }
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException(tr('返回内容无法解析：{error}', {'error': e}, _en));
    }
    throw AiException(tr('接口没有返回文字', null, _en));
  }

  /// 只留合法 UTF-16：孤立的代理项会让有些 JSON 解析器直接拒收整段请求。
  static String _safeText(String text) {
    if (!text.contains('\uFFFC') && !_hasLoneSurrogate(text)) return text;
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0xFFFC) continue;
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : 0;
        if (next >= 0xDC00 && next <= 0xDFFF) {
          buffer.writeCharCode(unit);
          buffer.writeCharCode(next);
          i++;
        } else {
          buffer.write('\uFFFD');
        }
      } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
        buffer.write('\uFFFD');
      } else {
        buffer.writeCharCode(unit);
      }
    }
    return buffer.toString();
  }

  static bool _hasLoneSurrogate(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit >= 0xD800 && unit <= 0xDBFF) {
        final next = i + 1 < text.length ? text.codeUnitAt(i + 1) : 0;
        if (next >= 0xDC00 && next <= 0xDFFF) {
          i++;
          continue;
        }
        return true;
      }
      if (unit >= 0xDC00 && unit <= 0xDFFF) return true;
    }
    return false;
  }

  String _brief(String body) =>
      body.length > 220 ? '${body.substring(0, 220)}…' : body;
}
