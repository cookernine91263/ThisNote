import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../core/i18n.dart';
import '../data/models.dart';

/// WebDAV 的错误提示。协议、路径与文件名格式一律不动。
const _en = <String, String>{
  '还没有填写 WebDAV 地址': 'No WebDAV address yet',
  'WebDAV 地址格式不正确': 'The WebDAV address is not valid',
  '创建目录失败：{code}': 'Could not create the folder: {code}',
  '无法连接 WebDAV：{error}': 'Could not reach WebDAV: {error}',
  '上传失败：{error}': 'Upload failed: {error}',
  '列出备份失败：{error}': 'Could not list backups: {error}',
  '备份列表无法解析：{error}': 'Could not parse the backup list: {error}',
  '下载失败：{error}': 'Download failed: {error}',
};

class WebDavException implements Exception {
  WebDavException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WebDavService {
  WebDavService(this.settings);
  final WebDavSettings settings;

  Uri get _base {
    final raw = settings.url.trim();
    if (raw.isEmpty) {
      throw WebDavException(tr('还没有填写 WebDAV 地址', null, _en));
    }
    final uri = Uri.tryParse(raw.endsWith('/') ? raw : '$raw/');
    if (uri == null || !uri.hasScheme) {
      throw WebDavException(tr('WebDAV 地址格式不正确', null, _en));
    }
    return uri;
  }

  String get _folder =>
      settings.folder.trim().replaceAll(RegExp(r'^/+|/+$'), '');

  Uri _uriFor(String name) {
    final base = _base;
    final basePath = base.path.endsWith('/') ? base.path : '${base.path}/';
    final folder = _folder.isEmpty ? '' : '$_folder/';
    return base.replace(path: '$basePath$folder$name', query: null, fragment: null);
  }

  Map<String, String> get _headers {
    final headers = <String, String>{};
    if (settings.username.trim().isNotEmpty) {
      headers['Authorization'] = 'Basic ${base64Encode(utf8.encode('${settings.username}:${settings.password}'))}';
    }
    return headers;
  }

  Future<void> ensureFolder() async {
    if (_folder.isEmpty) return;
    try {
      final request = http.Request('MKCOL', _uriFor(''))..headers.addAll(_headers);
      final response = await request.send().timeout(const Duration(seconds: 15));
      await response.stream.drain<void>();
      if (![200, 201, 204, 301, 405].contains(response.statusCode)) {
        throw WebDavException(
          tr('创建目录失败：{code}', {'code': response.statusCode}, _en),
        );
      }
    } catch (e) {
      if (e is WebDavException) rethrow;
      throw WebDavException(tr('无法连接 WebDAV：{error}', {'error': e}, _en));
    }
  }

  Future<String> upload(File file, {String? name}) async {
    await ensureFolder();
    final filename = name ?? p.basename(file.path);
    final uri = _uriFor(filename);
    final bytes = await file.readAsBytes();
    late http.Response response;
    try {
      response = await http
          .put(
            uri,
            headers: {
              ..._headers,
              'Content-Type': 'application/zip',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
    } catch (e) {
      throw WebDavException(tr('上传失败：{error}', {'error': e}, _en));
    }
    if (![200, 201, 204].contains(response.statusCode)) {
      throw WebDavException(
        tr('上传失败：{error}', {'error': response.statusCode}, _en),
      );
    }
    return uri.toString();
  }

  Future<List<RemoteBackup>> listBackups() async {
    await ensureFolder();
    final uri = _uriFor('');
    late http.Response response;
    try {
      final request = http.Request('PROPFIND', uri)
        ..headers.addAll({
          ..._headers,
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        })
        ..body = '<?xml version="1.0" encoding="utf-8"?>'
            '<d:propfind xmlns:d="DAV:"><d:prop><d:displayname/>'
            '<d:getcontentlength/><d:getlastmodified/></d:prop></d:propfind>';
      final streamed = await request.send().timeout(const Duration(seconds: 20));
      response = await http.Response.fromStream(streamed);
    } catch (e) {
      throw WebDavException(tr('列出备份失败：{error}', {'error': e}, _en));
    }
    if (response.statusCode != 207 && response.statusCode != 200) {
      throw WebDavException(
        tr('列出备份失败：{error}', {'error': response.statusCode}, _en),
      );
    }
    final result = <RemoteBackup>[];
    try {
      final doc = XmlDocument.parse(utf8.decode(response.bodyBytes));
      for (final node in doc.findAllElements('response')) {
        final hrefs = node.findElements('href');
        if (hrefs.isEmpty) continue;
        final href = hrefs.first.innerText;
        final name = Uri.decodeComponent(href.split('/').last);
        if (!name.startsWith('ThisNote-backup-') || !name.endsWith('.zip')) {
          continue;
        }
        final sizes = node.findElements('getcontentlength');
        result.add(RemoteBackup(
          name: name,
          href: _base.resolve(href).toString(),
          size: sizes.isEmpty ? 0 : int.tryParse(sizes.first.innerText) ?? 0,
        ));
      }
    } catch (e) {
      throw WebDavException(
        tr('备份列表无法解析：{error}', {'error': e}, _en),
      );
    }
    result.sort((a, b) => b.name.compareTo(a.name));
    return result;
  }

  Future<List<int>> download(RemoteBackup backup) async {
    try {
      final response = await http
          .get(Uri.parse(backup.href), headers: _headers)
          .timeout(const Duration(seconds: 90));
      if (response.statusCode != 200) {
        throw WebDavException(
          tr('下载失败：{error}', {'error': response.statusCode}, _en),
        );
      }
      return response.bodyBytes;
    } catch (e) {
      if (e is WebDavException) rethrow;
      throw WebDavException(tr('下载失败：{error}', {'error': e}, _en));
    }
  }
}

class RemoteBackup {
  RemoteBackup({required this.name, required this.href, required this.size});
  final String name;
  final String href;
  final int size;

  DateTime get time {
    final digits = RegExp(r'(\d{10,})').firstMatch(name)?.group(1);
    final ms = int.tryParse(digits ?? '');
    if (ms == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
}
