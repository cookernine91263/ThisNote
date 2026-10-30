import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/models.dart';

class AiException implements Exception {
  AiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiService {
  AiService(this.settings);
  final AiSettings settings;

  Future<String> complete({
    required String system,
    required String user,
    double temperature = 0.7,
    int maxTokens = 1400,
  }) async {
    if (!settings.configured) {
      throw AiException('还没有配置 API Key');
    }
    final base = settings.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (base.isEmpty) throw AiException('接口地址为空');
    final uri = Uri.tryParse(
      base.endsWith('/chat/completions') ? base : '$base/chat/completions',
    );
    if (uri == null) throw AiException('接口地址格式不正确');
    late http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${settings.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': settings.model.trim().isEmpty
                  ? 'deepseek-chat'
                  : settings.model.trim(),
              'messages': [
                {'role': 'system', 'content': system},
                {'role': 'user', 'content': user},
              ],
              'temperature': temperature,
              'max_tokens': maxTokens,
              'stream': false,
            }),
          )
          .timeout(const Duration(seconds: 75));
    } on TimeoutException {
      throw AiException('请求超时，请检查网络或接口地址');
    } catch (e) {
      throw AiException('无法连接接口：$e');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = utf8.decode(response.bodyBytes, allowMalformed: true);
      final brief = body.length > 220 ? '${body.substring(0, 220)}…' : body;
      throw AiException('接口返回 ${response.statusCode}：$brief');
    }
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final content = data['choices'][0]['message']['content'];
      if (content is! String || content.trim().isEmpty) {
        throw AiException('接口没有返回文字');
      }
      return content.trim();
    } catch (e) {
      if (e is AiException) rethrow;
      throw AiException('返回内容无法解析：$e');
    }
  }
}
