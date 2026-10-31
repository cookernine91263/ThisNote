import 'dart:io';

import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../state/app_state.dart';

const _en = <String, String>{
  '没有可用的文件': 'No usable files',
  '已接收 {parts}': 'Received {parts}',
};

/// 接收 Windows 窗口拖进来的文件。
///
/// 原生侧在 runner 里把 WM_DROPFILES 的路径通过 `this_note/drop` 通道发过来；
/// 图片会作为图片插入当前笔记，Markdown / 文本会导入成新笔记。
class FileDropTarget {
  static const MethodChannel channel = MethodChannel('this_note/drop');

  static Future<void> install({
    required AppState state,
    required void Function(String message) onMessage,
  }) async {
    if (!Platform.isWindows) return;
    channel.setMethodCallHandler((call) async {
      if (call.method != 'drop') return null;
      final arguments = call.arguments;
      if (arguments is! List) return null;
      final paths = arguments.whereType<String>().toList(growable: false);
      if (paths.isEmpty) return null;
      final result = await state.acceptDroppedFiles(paths);
      final parts = <String>[
        if (result.images > 0) I18n.count(result.images, '张图片', 'image'),
        if (result.imported > 0) I18n.count(result.imported, '篇笔记', 'note'),
      ];
      onMessage(
        parts.isEmpty
            ? tr('没有可用的文件', null, _en)
            : tr('已接收 {parts}', {
                'parts': parts.join(I18n.isEn ? ', ' : '、'),
              }, _en),
      );
      return null;
    });
  }

  static void uninstall() {
    channel.setMethodCallHandler(null);
  }
}
