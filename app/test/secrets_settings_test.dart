import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:this_note/src/data/models.dart';
import 'package:this_note/src/data/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings.json 可以在不写密钥的情况下保存', () async {
    final temp = Directory.systemTemp.createTempSync('thisnote-secrets-');
    addTearDown(() {
      try {
        temp.deleteSync(recursive: true);
      } catch (_) {}
    });
    final store = NoteStore(rootOverride: temp.path);
    await store.init();
    final settings = AppSettings()
      ..aiSettings.apiKey = 'sk-secret'
      ..webdavSettings.password = 'dav-secret';

    await store.saveSettings(settings, includeSecrets: false);
    final raw = await File(p.join(temp.path, 'settings.json')).readAsString();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    expect((json['ai'] as Map)['apiKey'], isEmpty);
    expect((json['webdav'] as Map)['password'], isEmpty);
    expect(raw.contains('sk-secret'), isFalse);
    expect(raw.contains('dav-secret'), isFalse);

    final withSecrets = settings.toJson();
    expect((withSecrets['ai'] as Map)['apiKey'], 'sk-secret');
    expect((withSecrets['webdav'] as Map)['password'], 'dav-secret');
  });
}