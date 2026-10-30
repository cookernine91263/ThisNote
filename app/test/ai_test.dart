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
        ..write(jsonEncode({
          'choices': [
            {'message': {'content': '润色后的文字'}}
          ]
        }));
      await request.response.close();
    });

    final settings = AiSettings(
      enabled: true,
      baseUrl: 'http://127.0.0.1:${server.port}/v1',
      apiKey: 'test-key',
      model: 'test-model',
    );
    final result = await AiService(settings).complete(
      system: 'system',
      user: 'user',
    );
    expect(result, '润色后的文字');
    expect(path, '/v1/chat/completions');
    expect(auth, 'Bearer test-key');
    await server.close(force: true);
  });
}
