import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/services/ai_service.dart';

void main() {
  test('AI service calls an OpenAI-compatible endpoint', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? path;
    String? auth;
    server.listen((request) async {
      path = request.uri.path;
      auth = request.headers.value('authorization');
      await utf8.decoder.bind(request).join();
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '润色后的文字'},
              },
            ],
          }),
        );
      await request.response.close();
    });

    final settings = AiSettings(
      enabled: true,
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'test-key',
      model: 'test-model',
    );
    final result = await AiService(settings)
        .complete(system: 'system', user: 'user');
    expect(result, '润色后的文字');
    expect(path, '/v1/chat/completions');
    expect(auth, 'Bearer test-key');
    await server.close(force: true);
  });

  test('流式接口逐段回调并拼出全文', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    String? body;
    server.listen((request) async {
      body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });

    final service = AiService(
      AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
        model: 'm',
      ),
    );
    final chunks = <String>[];
    final text = await service.completeStream(
      system: 's',
      user: 'u',
      onDelta: chunks.add,
    );
    expect(text, '你好');
    expect(chunks.first, '你');
    expect(chunks.last, '你好');
    expect(body, contains('"stream":true'));
    await server.close(force: true);
  });

  test('网关忽略 stream 参数时退回整段 JSON', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {'content': '整段返回'},
            },
          ],
        }),
      );
      await request.response.close();
    });

    final service = AiService(
      AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
        model: 'm',
      ),
    );
    final text = await service.completeStream(
      system: 's',
      user: 'u',
      onDelta: (_) {},
    );
    expect(text, '整段返回');
    await server.close(force: true);
  });

  test('流式请求可以被中途取消', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      try {
        for (var i = 0; i < 30; i++) {
          request.response.write(
            'data: {"choices":[{"delta":{"content":"…"}}]}\n\n',
          );
          await request.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      } catch (_) {
        // 客户端关闭会打断写入
      }
      await request.response.close();
    });

    final service = AiService(
      AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
        model: 'm',
      ),
    );
    final future = service.completeStream(
      system: 's',
      user: 'u',
      onDelta: (_) {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    service.cancel();
    await expectLater(future, throwsA(isA<AiException>()));
    expect(service.cancelled, isTrue);
    await server.close(force: true);
  });

  test('流式只给思考内容时，自动改用非流式再要一次正文', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    server.listen((request) async {
      calls++;
      final body = await utf8.decoder.bind(request).join();
      if (body.contains('"stream":true')) {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
          charset: 'utf-8',
        );
        request.response.write(
          'data: {"choices":[{"delta":{"reasoning_content":"先想一下"}}]}\n\n',
        );
        request.response.write(
          'data: {"choices":[{"delta":{},"finish_reason":"length"}]}\n\n',
        );
        request.response.write('data: [DONE]\n\n');
      } else {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '重试后的正文'},
              },
            ],
          }),
        );
      }
      await request.response.close();
    });

    final service = AiService(
      AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
        model: 'm',
      ),
    );
    final chunks = <String>[];
    final text = await service.completeStream(
      system: 's',
      user: 'u',
      onDelta: chunks.add,
    );
    expect(text, '重试后的正文');
    expect(chunks.last, '重试后的正文');
    expect(calls, 2);
    await server.close(force: true);
  });

  test('流里夹着错误时会把它显示出来，而不是说没有文字', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType(
        'text',
        'event-stream',
        charset: 'utf-8',
      );
      request.response.write('data: {"error":{"message":"模型不存在"}}\n\n');
      await request.response.close();
    });

    final service = AiService(
      AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
        model: 'm',
      ),
    );
    await expectLater(
      service.completeStream(system: 's', user: 'u', onDelta: (_) {}),
      throwsA(
        isA<AiException>().having(
          (e) => e.message,
          'message',
          contains('模型不存在'),
        ),
      ),
    );
    await server.close(force: true);
  });

  test('分段 content 数组也能拼出正文', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': '润色'},
                  {'type': 'text', 'text': '之后'},
                ],
              },
            },
          ],
        }),
      );
      await request.response.close();
    });

    final service = AiService(
      AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'k',
        model: 'm',
      ),
    );
    expect(await service.complete(system: 's', user: 'u'), '润色之后');
    await server.close(force: true);
  });

  test('思考强度决定输出预算，并会随设置保存', () {
    final ai = AiSettings();
    expect(ai.thinkingLevel, AiThinking.balanced);
    ai.thinking = 'deep';
    final restored = AiSettings.fromJson(
      jsonDecode(jsonEncode(ai.toJson())) as Map<String, dynamic>,
    );
    expect(restored.thinking, 'deep');
    expect(restored.thinkingLevel.maxTokens, AiThinking.deep.maxTokens);
    expect(AiThinking.fast.maxTokens, lessThan(AiThinking.deep.maxTokens));
  });
}
