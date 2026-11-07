import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 把 API Key / WebDAV 密码放进系统钥匙串；不可用时退回设置文件。
class SecretsStore {
  static const _storage = FlutterSecureStorage();
  bool _available = true;

  bool get available => _available;

  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      _available = false;
      return null;
    }
  }

  Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (_) {
      _available = false;
      return false;
    }
  }

  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      _available = false;
    }
  }
}