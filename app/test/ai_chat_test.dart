import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';
import 'package:this_note/src/state/ai_chat.dart';

void main() {
  late HttpServer server;
  final bodies = <Map<String, dynamic>>[];

  setUp(() async {
    bodies.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final raw = await utf8.decoder.bind(request).join();
      bodies.add(jsonDecode(raw) as Map<String, dynamic>);
      request.response.headers.contentType =
          ContentType('text', 'event-stream', charset: 'utf-8');
      request.response.write(
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n',
      );
      request.response.write(
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n',
      );
      request.response.write('data: [DONE]\n\n');
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  AiSettings settingsFor() => AiSettings(
        enabled: true,
        baseUrl: 'http://127.0.0.1:${server.port}/v1',
        apiKey: 'test-key',
        model: 'test-model',
        thinking: 'fast',
      );

  test('AI conversation persists and sends multi-turn history', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-ai-chat-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();

    final first = AiChatController(
      store: store,
      noteId: 'note-1',
      settings: settingsFor(),
    );
    await first.load();
    expect(first.messages, isEmpty);

    await first.send(prompt: '第一句', system: '你是一位编辑。');
    expect(first.messages.length, 2);
    expect(first.messages.last.role, AiRole.assistant);
    expect(first.messages.last.text, '你好');

    final persisted = await store.loadConversation('note-1');
    expect(persisted, isNotNull);
    expect(persisted!.messages.length, 2);

    final backupPath = await store.createBackup();
    final archive =
        ZipDecoder().decodeBytes(await File(backupPath).readAsBytes());
    expect(archive.findFile('conversations/note-1.json'), isNotNull);

    await first.send(prompt: '第二句');
    expect(bodies.length, 2);
    final messages = (bodies[1]['messages'] as List).cast<Map>();
    expect(messages.length, 4);
    expect(messages[0]['role'], 'system');
    expect(messages[1]['role'], 'user');
    expect(messages[2]['role'], 'assistant');
    expect(messages[3]['role'], 'user');

    first.dispose();
    final second = AiChatController(
      store: store,
      noteId: 'note-1',
      settings: settingsFor(),
    );
    await second.load();
    expect(second.messages.length, 4);
    expect(second.messages.first.text, '第一句');
    second.dispose();

    final reloaded = AiChatController(
      store: store,
      noteId: 'note-1',
      settings: settingsFor(),
    );
    await reloaded.load();
    await reloaded.clear();
    expect(reloaded.messages, isEmpty);
    expect(await store.loadConversation('note-1'), isNull);
    reloaded.dispose();
  });
}
