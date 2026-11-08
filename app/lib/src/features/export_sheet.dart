import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../data/models.dart';
import '../state/app_state.dart';
import '../services/exporter.dart';
import '../services/library_export.dart';
import 'editor/note_image.dart';

/// 文案以中文为源，英文放在 [_en] 里。
/// 导出格式的名称与说明由 [ExportFormat] 自己翻译，这里不再重复。
const Map<String, String> _en = <String, String>{
  '此记导出': 'ThisNote export',
  '此记 · {format}': 'ThisNote · {format}',
  '已导出 {format}': 'Exported {format}',
  '导出失败：{e}': 'Export failed: {e}',
  '此记-{day}': 'ThisNote-{day}',
  '导出这篇文字': 'Export this piece',
  '选择一种离开纸面的方式。原稿仍会留在「此记」里。':
      'Choose how it leaves the page. The original stays in ThisNote.',
  '正在排版…': 'Laying out…',
  '已打开 PDF，可在阅读器里打印':
      'PDF opened — print it from your reader',
  '这个文件夹里还没有文字': 'This folder has no text yet',
  '正在打包…': 'Packing…',
  'ZIP 压缩包': 'ZIP archive',
  '已导出「{name}」的 {n} 篇文字': 'Exported {n} notes from “{name}”',
  '此记 · {name}': 'ThisNote · {name}',
  '导出整个文件夹': 'Export the whole folder',
  '打包成 ZIP，解压后保留文件夹结构。':
      'Pack a ZIP that keeps the folder structure when extracted.',
  '没有可导出的内容': 'Nothing to export',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

Future<void> showExportSheet(BuildContext context) async {
  final state = context.read<AppState>();
  final note = state.current;
  if (note == null) return;
  final format = await showDialog<ExportFormat>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.22),
    builder: (context) => const _ExportDialog(),
  );
  if (format == null || !context.mounted) return;
  if (format == ExportFormat.png) {
    await showPngExport(context);
    return;
  }
  final accent = AppPalette.of(context).accent;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (context) => const _BusyDialog(),
  );
  try {
    await state.saveNow();
    final exporter = NoteExporter(state.store);
    Uint8List bytes;
    var printAfter = false;
    switch (format) {
      case ExportFormat.docx:
        bytes = await exporter.docx(note);
        break;
      case ExportFormat.pdf:
        bytes = await exporter.pdf(note, accent: accent);
        break;
      case ExportFormat.epub:
        bytes = await exporter.epub(note);
        break;
      case ExportFormat.printPdf:
        bytes = await exporter.pdf(note, accent: accent);
        printAfter = true;
        break;
      case ExportFormat.png:
        return;
      case ExportFormat.html:
        bytes = Uint8List.fromList(utf8.encode(await exporter.html(note)));
        break;
      case ExportFormat.markdown:
        bytes = Uint8List.fromList(utf8.encode(exporter.markdown(note)));
        break;
      case ExportFormat.txt:
        bytes = Uint8List.fromList(utf8.encode(exporter.txt(note)));
        break;
    }
    if (printAfter && !Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(
        dir.path,
        '${_safeName(note.title)}.pdf',
      ));
      await file.writeAsBytes(bytes, flush: true);
      await Process.start(
        'cmd',
        ['/c', 'start', '', file.path],
        runInShell: true,
      );
      if (context.mounted) {
        showToast(
          context,
          _t('已打开 PDF，可在阅读器里打印'),
        );
      }
      return;
    }
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final file = File(p.join(
        dir.path,
        '${_safeName(note.title)}.${format.extension}',
      ));
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          subject: note.title.isEmpty ? _t('此记导出') : note.title,
          text: _t('此记 · {format}', {'format': format.label}),
        ),
      );
    } else {
      final location = await getSaveLocation(
        suggestedName: '${_safeName(note.title)}.${format.extension}',
        acceptedTypeGroups: [
          XTypeGroup(
            label: format.label,
            extensions: [format.extension],
          ),
        ],
      );
      if (location != null) {
        await File(location.path).writeAsBytes(bytes, flush: true);
        if (context.mounted) {
          showToast(context, _t('已导出 {format}', {'format': format.label}));
        }
      }
    }
  } catch (e) {
    if (context.mounted) {
      showToast(context, _t('导出失败：{e}', {'e': e}));
    }
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

String _safeName(String title) {
  final t = title.trim();
  final base = t.isEmpty
      ? _t('此记-{day}', {'day': dayKey(DateTime.now())})
      : t;
  return base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').substring(
        0,
        base.length > 60 ? 60 : base.length,
      );
}

/// 把一个文件夹（含子文件夹）的笔记打包成 zip，电脑端另存、手机端分享。
Future<void> showFolderExport(BuildContext context, Folder folder) async {
  final state = context.read<AppState>();
  final folderIds = state.folderTreeIds(folder.id);
  final metas = state.activeNotes
      .where((meta) => meta.folderId != null &&
          folderIds.contains(meta.folderId))
      .toList();
  if (metas.isEmpty) {
    showToast(context, _t('这个文件夹里还没有文字'));
    return;
  }

  final format = await showDialog<FolderExportFormat>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.22),
    builder: (_) => _FolderExportDialog(folder: folder),
  );
  if (format == null || !context.mounted) return;

  await state.saveNow();
  if (!context.mounted) return;

  final name = _safeName(folder.name);
  String? target;
  if (!Platform.isAndroid) {
    final location = await getSaveLocation(
      suggestedName: '$name.zip',
      acceptedTypeGroups: [
        XTypeGroup(
          label: _t('ZIP 压缩包'),
          extensions: const ['zip'],
        ),
      ],
    );
    if (location == null) return;
    target = location.path;
  }
  if (!context.mounted) return;

  if (format == FolderExportFormat.png) {
    final notes = <Note>[];
    for (final meta in metas) {
      final note = await state.store.loadNote(meta.id);
      if (note != null) notes.add(note);
    }
    if (!context.mounted) return;
    final pages = await renderNotesPng(
      context,
      notes: notes,
      store: state.store,
    );
    if (!context.mounted) return;
    if (pages.isEmpty) {
      showToast(context, _t('没有可导出的内容'));
      return;
    }
    try {
      final result = await buildFolderZip(
        store: state.store,
        folder: folder,
        folders: state.folders,
        notes: metas,
        format: format,
        pngPages: pages,
      );
      if (!context.mounted) return;
      await _deliverFolderZip(context, folder, name, target, result);
    } catch (e) {
      if (context.mounted) {
        showToast(context, _t('导出失败：{e}', {'e': e}));
      }
    }
    return;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.18),
    builder: (context) => _BusyDialog(message: _t('正在打包…')),
  );
  try {
    final result = await buildFolderZip(
      store: state.store,
      folder: folder,
      folders: state.folders,
      notes: metas,
      format: format,
    );
    if (!context.mounted) return;
    await _deliverFolderZip(context, folder, name, target, result);
  } catch (e) {
    if (context.mounted) {
      showToast(context, _t('导出失败：{e}', {'e': e}));
    }
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  }
}

Future<void> _deliverFolderZip(
  BuildContext context,
  Folder folder,
  String name,
  String? target,
  ({Uint8List bytes, int count}) result,
) async {
  if (result.count == 0) {
    if (context.mounted) showToast(context, _t('没有可导出的内容'));
    return;
  }
  if (Platform.isAndroid) {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '$name.zip'));
    await file.writeAsBytes(result.bytes, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: folder.name,
        text: _t('此记 · {name}', {'name': folder.name}),
      ),
    );
  } else {
    await File(target!).writeAsBytes(result.bytes, flush: true);
    if (context.mounted) {
      showToast(
        context,
        _t('已导出「{name}」的 {n} 篇文字', {
          'name': folder.name,
          'n': result.count,
        }),
        icon: LucideIcons.check,
      );
    }
  }
}

class _ExportDialog extends StatelessWidget {
  const _ExportDialog();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.sizeOf(context).height - 72,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _t('导出这篇文字'),
                    style: TextStyle(
                      fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                      fontSize: I18n.isEn ? 20 : 24,
                      fontWeight: I18n.isEn ? FontWeight.w600 : null,
                      letterSpacing: I18n.isEn ? 0.3 : 1,
                      color: c.ink,
                    ),
                  ),
                  const Spacer(),
                  SoftIconButton(
                    icon: LucideIcons.x,
                    size: 30,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                _t('选择一种离开纸面的方式。原稿仍会留在「此记」里。'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10.5,
                  height: I18n.isEn ? 1.5 : null,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              for (final format in ExportFormat.values)
                _FormatRow(format: format),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.format});
  final ExportFormat format;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final icon = switch (format) {
      ExportFormat.docx => LucideIcons.fileText,
      ExportFormat.pdf => LucideIcons.fileType,
      ExportFormat.epub => LucideIcons.bookOpen,
      ExportFormat.printPdf => LucideIcons.printer,
      ExportFormat.png => LucideIcons.image,
      ExportFormat.markdown => LucideIcons.fileCode,
      ExportFormat.html => LucideIcons.globe,
      ExportFormat.txt => LucideIcons.file,
    };
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(format),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
            decoration: BoxDecoration(
              color: hovered ? c.paper : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: hovered ? c.lineStrong : c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: c.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        format.label,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 12.5,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        format.description,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '.${format.extension}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronRight, size: 14, color: c.inkMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FolderExportDialog extends StatelessWidget {
  const _FolderExportDialog({required this.folder});
  final Folder folder;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: c.surface,
      insetPadding: const EdgeInsets.all(22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: c.line),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.sizeOf(context).height - 72,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _t('导出整个文件夹'),
                          style: TextStyle(
                            fontFamily: I18n.isEn ? 'NotoSansSC' : 'WenKai',
                            fontSize: I18n.isEn ? 20 : 24,
                            fontWeight:
                                I18n.isEn ? FontWeight.w600 : null,
                            letterSpacing: I18n.isEn ? 0.3 : 1,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 10.5,
                            color: c.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SoftIconButton(
                    icon: LucideIcons.x,
                    size: 30,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _t('打包成 ZIP，解压后保留文件夹结构。'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10.5,
                  height: I18n.isEn ? 1.5 : null,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 16),
              for (final format in FolderExportFormat.values)
                _FolderFormatRow(format: format),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderFormatRow extends StatelessWidget {
  const _FolderFormatRow({required this.format});
  final FolderExportFormat format;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final icon = switch (format) {
      FolderExportFormat.markdown => LucideIcons.fileCode,
      FolderExportFormat.txt => LucideIcons.file,
      FolderExportFormat.epub => LucideIcons.bookOpen,
      FolderExportFormat.png => LucideIcons.image,
    };
    return HoverBuilder(
      builder: (context, hovered, t) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(format),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: const EdgeInsets.only(bottom: 7),
            padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
            decoration: BoxDecoration(
              color: hovered ? c.paper : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: hovered ? c.lineStrong : c.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 15, color: c.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        format.label,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 12.5,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        format.description,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '.${format.extension}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 9,
                    color: c.inkMuted,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(LucideIcons.chevronRight, size: 14, color: c.inkMuted),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BusyDialog extends StatelessWidget {
  const _BusyDialog({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.accent,
              ),
            ),
            const SizedBox(width: 14),
            Text(
              message ?? _t('正在排版…'),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 12,
                color: c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
