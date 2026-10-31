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

  Map<String, dynamic> _body({
    required String system,
    required String user,
    required bool stream,
    required double temperature,
    required int maxTokens,
  }) =>
      {
        'model': settings.model.trim().isEmpty
            ? 'deepseek-chat'
            : settings.model.trim(),
        'messages': [
          {'role': 'system', 'content': _system(system)},
          {'role': 'user', 'content': user},
        ],
        'temperature': temperature,
        'max_tokens': maxTokens,
        'stream': stream,
      };

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${settings.apiKey.trim()}',
      };

  /// 非流式调用，保留给不支持 SSE 的网关或测试。
  Future<String> complete({
    required String system,
    required String user,
    double temperature = 0.7,
    int maxTokens = 1400,
  }) async {
    final uri = _uri();
    late http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: _headers,
            body: jsonEncode(
              _body(
                system: system,
                user: user,
                stream: false,
                temperature: temperature,
                maxTokens: maxTokens,
              ),
            ),
          )
          .timeout(const Duration(seconds: 75));
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
    double temperature = 0.7,
    int maxTokens = 1400,
  }) async {
    final uri = _uri();
    _cancelled = false;
    final client = http.Client();
    _client = client;
    try {
      final request = http.Request('POST', uri)
        ..headers.addAll({
          ..._headers,
          'Accept': 'text/event-stream',
        })
        ..body = jsonEncode(
          _body(
            system: system,
            user: user,
            stream: true,
            temperature: temperature,
            maxTokens: maxTokens,
          ),
        );
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60));
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
      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_cancelled) break;
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final payload = trimmed.substring(5).trim();
        if (payload.isEmpty || payload == '[DONE]') continue;
        try {
          final data = jsonDecode(payload);
          final choices = data['choices'];
          if (choices is List && choices.isNotEmpty) {
            final delta = choices.first['delta'];
            final content = delta is Map ? delta['content'] : null;
            if (content is String && content.isNotEmpty) {
              buffer.write(content);
              onDelta(buffer.toString());
            }
          }
        } catch (_) {
          // 心跳或半截 JSON，跳过就好
        }
      }
      if (_cancelled) throw AiException(tr('已取消', null, _en));
      final text = buffer.toString().trim();
      if (text.isEmpty) throw AiException(tr('接口没有返回文字', null, _en));
      return text;
    } on TimeoutException {
      throw AiException(tr('请求超时，请检查网络或接口地址', null, _en));
    } on http.ClientException catch (e) {
      if (_cancelled) throw AiException(tr('已取消', null, _en));
      throw AiException(tr('无法连接接口：{error}', {'error': e}, _en));
    } finally {
      _client = null;
      client.close();
    }
  }

  String _contentOf(String body) {
    try {
      final data = jsonDecode(body);
      final content = data['choices'][0]['message']['content'];
      if (content is! String || content.trim().isEmpty) {
        throw AiException(tr('接口没有返回文字', null, _en));
      }
      return content.trim();
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException(tr('返回内容无法解析：{error}', {'error': e}, _en));
    }
  }

  String _brief(String body) =>
      body.length > 220 ? '${body.substring(0, 220)}…' : body;
}
