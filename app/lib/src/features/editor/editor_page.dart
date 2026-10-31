import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/icons.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../export_sheet.dart';
import '../tag_editor.dart';
import '../../services/exporter.dart';
import 'editor_toolbar.dart';
import 'find_bar.dart';
import 'huazi.dart';
import 'image_embed.dart';
import 'outline_panel.dart';
import 'quill_theme.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '返回': 'Back',
  '{n} 字': '{n} words',
  '正在写…': 'Writing…',
  '正在保存': 'Saving',
  '保存失败': 'Save failed',
  '已保存': 'Saved',
  '已保存 {time}': 'Saved {time}',
  '查找 · Ctrl F': 'Find · Ctrl F',
  '目录': 'Outline',
  '导出 · 图片 / PDF / Word': 'Export · Image / PDF / Word',
  '历史版本': 'Version history',
  '专注模式 · Ctrl Shift F': 'Focus mode · Ctrl Shift F',
  '更多': 'More',
  '已移到回收站': 'Moved to Trash',
  '撤销': 'Undo',
  '这段文字已经很整齐了': 'This text is already tidy',
  '已整理 {count} 段排版，Ctrl Z 可撤销':
      'Tidied {count} paragraphs — press Ctrl Z to undo',
  '已复制为 Markdown': 'Copied as Markdown',
  '已复制为纯文本': 'Copied as plain text',
  '取消置顶': 'Unpin',
  '置顶': 'Pin',
  '取消收藏': 'Remove favorite',
  '收藏': 'Favorite',
  '导出…': 'Export…',
  '整理排版': 'Tidy typography',
  '复制为 Markdown': 'Copy as Markdown',
  '复制为纯文本': 'Copy as plain text',
  '移到回收站': 'Move to Trash',
  '退出专注模式': 'Exit focus mode',
  '此记 · 专注模式': 'ThisNote · Focus mode',
  '从这里开始写…': 'Start writing here…',
  '无题': 'Untitled',
  '标签': 'Tag',
  '切换类型': 'Change type',
  '心情': 'Mood',
  '天气': 'Weather',
  '不记录': 'None',
  '已选 {selected} 字 · 共 {words} 字':
      '{selected} words selected · {words} total',
  '保存失败：{detail}': 'Save failed: {detail}',
  '文件没有写进去，可能是磁盘空间或权限的问题。':
      'The file could not be written — check disk space or permissions.',
  '全文已复制，可以先粘到别处':
      'Everything copied — paste it somewhere safe for now',
  '纯文本': 'Plain text',
  '已另存为 {name}': 'Saved as {name}',
  '另存失败：{e}': 'Save as failed: {e}',
  '重试': 'Retry',
  '复制全文': 'Copy all',
  '另存为…': 'Save as…',
  '书写时每 5 分钟自动留存一次，最多保留 40 个版本。':
      'A version is kept every 5 minutes while you write, up to 40 versions.',
  '还没有历史版本。继续写一会儿，此记会替你留着。':
      'No versions yet. Keep writing — ThisNote will hold on to them.',
  ' · 最近': ' · latest',
  '回到这个版本？': 'Return to this version?',
  '当前内容会先存成一个新的历史版本，之后还能再回来。':
      'Your current text is saved as a new version first, so you can come back to it.',
  '回到这里': 'Go back here',
  '恢复': 'Restore',
  '按实际动笔时间累计，停顿超过一分钟不计入':
      'Counts actual writing time; pauses longer than a minute are skipped.',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class EditorPage extends StatelessWidget {
  const EditorPage({
    super.key,
    this.mobile = false,
    this.zen = false,
    this.onToggleZen,
    this.onBack,
  });

  final bool mobile;
  final bool zen;
  final VoidCallback? onToggleZen;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final session = state.session;
    if (session == null) return const SizedBox.shrink();
    final c = AppPalette.of(context);

    final body = Column(
      children: [
        if (!zen)
          _EditorTopBar(
            mobile: mobile,
            onBack: onBack,
            onToggleZen: onToggleZen,
          ),
        if (!zen && state.saveStatus == SaveStatus.error)
          _SaveErrorBanner(state: state, session: session, mobile: mobile),
        if (!zen && !mobile)
          EditorToolbar(controller: session.controller, session: session),
        // 查找条占一行，不浮在纸面上盖住标题和日期。
        AnimatedBuilder(
          animation: session,
          builder: (context, _) {
            if (zen || !session.findOpen) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                mobile ? 8 : 24,
                8,
                mobile ? 8 : 24,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: FindBar(session: session, mobile: mobile),
              ),
            );
          },
        ),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _EditorCanvas(
                        mobile: mobile,
                        zen: zen,
                        onToggleZen: onToggleZen,
                      ),
                    ),
                    if (!zen && mobile)
                      Positioned(
                        top: 10,
                        left: 8,
                        child: AnimatedBuilder(
                          animation: session,
                          builder: (context, _) => session.outlineOpen
                              ? OutlinePanel(session: session)
                              : const SizedBox.shrink(),
                        ),
                      ),
                  ],
                ),
              ),
              if (!zen)
                AnimatedBuilder(
                  animation: session,
                  builder: (context, _) {
                    final open = session.outlineOpen && !mobile;
                    return ClipRect(
                      child: AnimatedContainer(
                        duration: Motion.base,
                        curve: Motion.enter,
                        width: open ? 220 : 0,
                        child: open
                            ? OutlinePanel(session: session, docked: true)
                            : const SizedBox.shrink(),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        if (!zen && mobile)
          EditorToolbar(
            controller: session.controller,
            session: session,
            mobile: true,
          ),
      ],
    );

    if (mobile) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) onBack?.call();
        },
        child: Scaffold(
          backgroundColor: c.paper,
          body: SafeArea(bottom: false, child: body),
        ),
      );
    }
    return ColoredBox(color: c.paper, child: body);
  }
}

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.mobile,
    this.onBack,
    this.onToggleZen,
  });

  final bool mobile;
  final VoidCallback? onBack;
  final VoidCallback? onToggleZen;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final session = state.session!;
    final note = session.note;

    return Container(
      height: mobile ? 50 : 52,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 8 : 18),
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(bottom: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          if (mobile)
            SoftIconButton(
              icon: LucideIcons.arrowLeft,
              tooltip: _t('返回'),
              onPressed: onBack,
            )
          else ...[
            Icon(kindIcon(note.kind), size: 14, color: c.inkMuted),
            const SizedBox(width: 7),
            Text(
              note.kind.label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 11,
                color: c.inkMuted,
              ),
            ),
            const SizedBox(width: 8),
            Dot(size: 2, color: c.lineStrong),
            const SizedBox(width: 8),
            Text(
              shortDate(note.createdAt),
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: c.inkMuted,
              ),
            ),
          ],
          const Spacer(),
          if (!mobile) ...[
            AnimatedBuilder(
              animation: session.controller,
              builder: (context, _) => Text(
                _t('{n} 字', {'n': session.words}),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10.5,
                  color: c.inkMuted,
                ),
              ),
            ),
            const SizedBox(width: 16),
          ],
          AnimatedBuilder(
            animation: session,
            builder: (context, _) {
              final status =
                  session.dirty ? SaveStatus.saving : state.saveStatus;
              final statusText = switch (status) {
                SaveStatus.saving => _t(session.dirty ? '正在写…' : '正在保存'),
                SaveStatus.error => _t('保存失败'),
                SaveStatus.saved => session.lastSaved == null
                    ? _t('已保存')
                    : _t('已保存 {time}', {
                        'time': timeLabel(session.lastSaved!),
                      }),
                SaveStatus.idle => _t('已保存'),
              };
              final statusColor = switch (status) {
                SaveStatus.saving => c.gold,
                SaveStatus.error => c.danger,
                _ => c.sage,
              };
              return AnimatedSwitcher(
                duration: Motion.fast,
                child: Row(
                  key: ValueKey(statusText),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StatusDot(
                      color: statusColor,
                      active: status == SaveStatus.saving,
                    ),
                    const SizedBox(width: 6),
                    if (!mobile)
                      Text(
                        statusText,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9.5,
                          color: c.inkMuted,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 6),
          AnimatedBuilder(
            animation: session,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SoftIconButton(
                  icon: LucideIcons.search,
                  tooltip: _t('查找 · Ctrl F'),
                  active: session.findOpen,
                  onPressed: () => session.openFind(),
                ),
                SoftIconButton(
                  icon: LucideIcons.listTree,
                  tooltip: _t('目录'),
                  active: session.outlineOpen,
                  onPressed: session.toggleOutline,
                ),
              ],
            ),
          ),
          SoftIconButton(
            icon: LucideIcons.share2,
            tooltip: _t('导出 · 图片 / PDF / Word'),
            onPressed: () => showExportSheet(context),
          ),
          SoftIconButton(
            icon: LucideIcons.history,
            tooltip: _t('历史版本'),
            onPressed: () => _showHistory(context, state, session),
          ),
          if (!mobile)
            SoftIconButton(
              icon: LucideIcons.focus,
              tooltip: _t('专注模式 · Ctrl Shift F'),
              onPressed: onToggleZen,
            ),
          _MoreMenu(mobile: mobile, onBack: onBack),
          SizedBox(width: mobile ? 4 : 8),
        ],
      ),
    );
  }

  void _showHistory(
      BuildContext context, AppState state, EditorSession session) {
    showDialog<void>(
      context: context,
      builder: (context) {
        final c = AppPalette.of(context);
        return Dialog(
          backgroundColor: c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: c.line),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        _t('历史版本'),
                        style: TextStyle(
                          fontFamily: 'WenKai',
                          fontSize: 22,
                          color: c.ink,
                        ),
                      ),
                      const Spacer(),
                      SoftIconButton(
                        icon: LucideIcons.x,
                        size: 28,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _t('书写时每 5 分钟自动留存一次，最多保留 40 个版本。'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Flexible(
                    child: FutureBuilder<List<Snapshot>>(
                      future: state.historyFor(session.note.id),
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(30),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final list = snap.data!;
                        if (list.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 34),
                            child: Text(
                              _t('还没有历史版本。继续写一会儿，此记会替你留着。'),
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 11,
                                height: 1.7,
                                color: c.inkMuted,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          shrinkWrap: true,
                          itemCount: list.length,
                          separatorBuilder: (_, _) => Divider(color: c.line),
                          itemBuilder: (context, i) {
                            final s = list[i];
                            final latest = i == 0;
                            return Row(
                              children: [
                                Icon(
                                  LucideIcons.clock3,
                                  size: 13,
                                  color: latest ? c.accent : c.inkMuted,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shortDate(s.savedAt),
                                        style: TextStyle(
                                          fontFamily: 'NotoSansSC',
                                          fontSize: 11.5,
                                          color: c.ink,
                                        ),
                                      ),
                                      Text(
                                        '${timeLabel(s.savedAt)} · '
                                        '${_t('{n} 字', {'n': s.words})}'
                                        '${latest ? _t(' · 最近') : ''}',
                                        style: TextStyle(
                                          fontFamily: 'NotoSansSC',
                                          fontSize: 9.5,
                                          color: c.inkMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                     final ok = await showConfirm(
                                       context,
                                       title: _t('回到这个版本？'),
                                       message: _t('当前内容会先存成一个新的历史版本，之后还能再回来。'),
                                       confirmLabel: _t('回到这里'),
                                     );                                    if (ok) {
                                      await state.restoreSnapshot(s);
                                      if (context.mounted) Navigator.of(context).pop();
                                    }
                                  },
                                  child: Text(
                                    _t('恢复'),
                                    style: TextStyle(
                                      fontFamily: 'NotoSansSC',
                                      fontSize: 11,
                                      color: c.accent,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.mobile, this.onBack});
  final bool mobile;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final note = state.current;
    return PopupMenuButton<String>(
      tooltip: _t('更多'),
      color: c.surface,
      position: PopupMenuPosition.under,
      icon: Icon(LucideIcons.ellipsis, size: 18, color: c.inkSoft),
      onSelected: (value) async {
        if (note == null) return;
        switch (value) {
          case 'pin':
            final matches = state.notes.where((n) => n.id == note.id);
            if (matches.isNotEmpty) await state.togglePin(matches.first);
            break;
          case 'fav':
            final matches = state.notes.where((n) => n.id == note.id);
            if (matches.isNotEmpty) await state.toggleFavorite(matches.first);
            break;
          case 'trash':
            // 不再先弹确认框：删除立刻发生，用撤销兜住误触。
            showToast(
              context,
              _t('已移到回收站'),
              actionLabel: _t('撤销'),
              onAction: () => state.restoreNote(note.id),
            );
            await state.trashNote(note.id);
            onBack?.call();
            break;
          case 'typography':
            final count = state.session?.normalizeTypography() ?? 0;
            if (context.mounted) {
              showToast(
                context,
                count == 0
                    ? _t('这段文字已经很整齐了')
                    : _t('已整理 {count} 段排版，Ctrl Z 可撤销', {
                        'count': count,
                      }),
                icon: count == 0 ? LucideIcons.check : LucideIcons.sparkles,
              );
            }
            break;
          case 'copyMd':            await state.saveNow();
            await Clipboard.setData(
              ClipboardData(text: NoteExporter(state.store).markdown(note)),
            );
            if (context.mounted) {
              showToast(context, _t('已复制为 Markdown'), icon: LucideIcons.check);
            }
            break;
          case 'copyText':
            await state.saveNow();
            await Clipboard.setData(ClipboardData(text: note.text));
            if (context.mounted) {
              showToast(context, _t('已复制为纯文本'), icon: LucideIcons.check);
            }
            break;
          case 'export':
            await showExportSheet(context);
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'pin',
          child: Text(note?.pinned == true ? _t('取消置顶') : _t('置顶')),
        ),
        PopupMenuItem(
          value: 'fav',
          child: Text(note?.favorite == true ? _t('取消收藏') : _t('收藏')),
        ),
        PopupMenuItem(value: 'export', child: Text(_t('导出…'))),
        PopupMenuItem(value: 'typography', child: Text(_t('整理排版'))),
        PopupMenuItem(value: 'copyMd', child: Text(_t('复制为 Markdown'))),
        PopupMenuItem(value: 'copyText', child: Text(_t('复制为纯文本'))),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'trash',
          child: Text(
            _t('移到回收站'),
            style: const TextStyle(color: Color(0xFFB0473A)),
          ),
        ),
      ],
    );
  }
}

class _EditorCanvas extends StatelessWidget {
  const _EditorCanvas({
    required this.mobile,
    required this.zen,
    this.onToggleZen,
  });

  final bool mobile;
  final bool zen;
  final VoidCallback? onToggleZen;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final session = state.session!;
    final width = state.settings.editorWidth.clamp(560.0, 980.0);

    return Stack(
      children: [
        Positioned.fill(
          child: PaperGrain(color: c.ink, opacity: c.grain * 0.65),
        ),
        Positioned.fill(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width + (mobile ? 0 : 110)),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  mobile ? 0 : 26,
                  mobile ? 0 : 18,
                  mobile ? 0 : 26,
                  mobile ? 0 : 18,
                ),
                child: Container(
                  decoration: mobile
                      ? null
                      : BoxDecoration(
                          color: c.surface,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: c.line),
                          boxShadow: [
                            BoxShadow(
                              color: c.shadow.withValues(alpha: c.isDark ? 0.28 : 0.07),
                              blurRadius: 36,
                              offset: const Offset(0, 14),
                            ),
                          ],
                        ),
                  // 手机上不铺卡片纸（没有 decoration），此时不能再要求裁剪：
                  // Container 的断言是「有 decoration 才能 clip」，安卓 release
                  // 里会退化成一块灰色错误块。
                  clipBehavior: mobile ? Clip.none : Clip.antiAlias,
                  child: Column(
                    children: [
                      _TitleBlock(
                        mobile: mobile,
                        horizontalPadding: mobile ? 22 : 56,
                        session: session,
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: AnimatedBuilder(
                                animation: session,
                                builder: (context, _) => QuillEditor.basic(
                                key: ValueKey(
                                  '${session.note.id}-${session.renderEpoch}',
                                ),
                                controller: session.controller,
                                focusNode: session.editorFocus,
                                scrollController: session.scrollController,
                                config: QuillEditorConfig(
                                  placeholder: _t('从这里开始写…'),
                                  padding: EdgeInsets.fromLTRB(
                                    mobile ? 22 : 56,
                                    2,
                                    mobile ? 22 : 56,
                                    96,
                                  ),
                                  scrollable: true,
                                  expands: true,
                                  autoFocus: false,
                                  customStyles: buildQuillStyles(
                                    c,
                                    scale: state.settings.editorScale,
                                    lineHeight: state.settings.lineHeight,
                                    paragraphGap: state.settings.paragraphGap,
                                    letterSpacing:
                                        state.settings.letterSpacing,
                                  ),
                                  customStyleBuilder: (attribute) =>
                                      quillCustomStyle(attribute, dark: c.isDark),
                                  embedBuilders: [
                                    NoteImageEmbedBuilder(state.store),
                                    const DividerEmbedBuilder(),
                                  ],
                                  textSelectionThemeData: TextSelectionThemeData(
                                    cursorColor: c.accent,
                                    selectionColor: c.accent.withValues(
                                      alpha: c.isDark ? 0.34 : 0.20,
                                    ),
                                    selectionHandleColor: c.accent,
                                  ),
                                  onLaunchUrl: (url) async {
                                    final uri = Uri.tryParse(url);
                                    if (uri != null) {
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    }
                                  },
                                  scrollBottomInset: 70,
                                  showCursor: true,
                                ),
                              ),
                              ),
                            ),
                            Positioned(
                              right: mobile ? 16 : 22,
                              bottom: 10,
                              child: IgnorePointer(
                                child: _EditorFooter(session: session, mobile: mobile),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (zen)
          Positioned(
            top: 16,
            right: 20,
            child: Row(
              children: [
                SoftIconButton(
                  icon: LucideIcons.minimize2,
                  tooltip: _t('退出专注模式'),
                  onPressed: onToggleZen,
                ),
              ],
            ),
          ),
        if (zen)
          Positioned(
            left: 20,
            bottom: 16,
            child: Row(
              children: [
                Icon(LucideIcons.feather, size: 12, color: c.inkMuted),
                const SizedBox(width: 6),
                Text(
                  _t('此记 · 专注模式'),
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 10.5,
                    letterSpacing: 1,
                    color: c.inkMuted,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.mobile,
    required this.horizontalPadding,
    required this.session,
  });

  final bool mobile;
  final double horizontalPadding;
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final note = session.note;
    final mood = MoodX.fromScore(note.mood);
    final weather = WeatherX.fromKey(note.weather);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        mobile ? 20 : 34,
        horizontalPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _KindMenu(session: session),
              const SizedBox(width: 8),
              // 日期在窄屏上可能很长（年月日 + 星期），让它自己收缩，
              // 别把心情/天气两个按钮挤出屏幕。
              Expanded(
                child: Text(
                  dateLabel(note.createdAt),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 10,
                    color: c.inkMuted,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
              _MoodMenu(session: session, mood: mood),
              const SizedBox(width: 4),
              _WeatherMenu(session: session, weather: weather),
            ],
          ),
          SizedBox(height: mobile ? 10 : 14),
          TextField(
            controller: session.titleController,
            focusNode: session.titleFocus,
            maxLines: null,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => session.editorFocus.requestFocus(),
            cursorColor: c.accent,
            style: TextStyle(
              fontFamily: 'WenKai',
              fontSize: mobile ? 29 : 36,
              height: 1.35,
              letterSpacing: 1.2,
              color: c.ink,
            ),
            decoration: InputDecoration(
              hintText: _t('无题'),
              hintStyle: TextStyle(
                fontFamily: 'WenKai',
                fontSize: mobile ? 29 : 36,
                color: c.inkMuted.withValues(alpha: 0.55),
                letterSpacing: 1.2,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
          SizedBox(height: mobile ? 8 : 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tag in note.tags)
                      TagChip(
                        label: tag,
                        onDelete: () {
                          session.setTags(
                            note.tags.where((t) => t != tag).toList(),
                          );
                        },
                      ),
                    GestureDetector(
                      onTap: () => _editTags(context, session),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(color: c.line),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(LucideIcons.plus, size: 10, color: c.inkMuted),
                            const SizedBox(width: 3),
                            Text(
                              _t('标签'),
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 10,
                                color: c.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AnimatedBuilder(
                animation: session,
                builder: (context, _) => Tooltip(
                  message: _t('按实际动笔时间累计，停顿超过一分钟不计入'),
                  child: Text(
                    writingTimeLabel(session.writingSeconds, session.words),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      color: c.inkMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: mobile ? 14 : 20),
          Stack(
            children: [
              Container(height: 1, color: c.line),
              Container(width: 42, height: 1, color: c.accent),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editTags(BuildContext context, EditorSession session) async {
    final state = context.read<AppState>();
    final tags = await showTagEditor(context, state, session.note.tags);
    if (tags != null) await session.setTags(tags);
  }
}

class _KindMenu extends StatelessWidget {
  const _KindMenu({required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopupMenuButton<NoteKind>(
      tooltip: _t('切换类型'),
      color: c.surface,
      position: PopupMenuPosition.under,
      onSelected: session.setKind,
      itemBuilder: (context) => [
        for (final k in NoteKind.values)
          PopupMenuItem(
            value: k,
            child: Row(
              children: [
                Icon(kindIcon(k), size: 14, color: c.inkMuted),
                const SizedBox(width: 8),
                Text(k.label),
              ],
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: c.accentSoft,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(kindIcon(session.note.kind), size: 10, color: c.accent),
            const SizedBox(width: 4),
            Text(
              session.note.kind.label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
                color: c.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoodMenu extends StatelessWidget {
  const _MoodMenu({required this.session, required this.mood});
  final EditorSession session;
  final Mood? mood;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopupMenuButton<int>(
      tooltip: _t('心情'),
      color: c.surface,
      position: PopupMenuPosition.under,
      onSelected: (v) => session.setMood(v == 0 ? null : v),
      itemBuilder: (context) => [
        PopupMenuItem(value: 0, child: Text(_t('不记录'))),
        for (final m in Mood.values)
          PopupMenuItem(
            value: m.score,
            child: Row(
              children: [
                Icon(moodIcon(m), size: 14, color: m.color),
                const SizedBox(width: 8),
                Text(m.label),
              ],
            ),
          ),
      ],
      child: _MetaPill(
        icon: mood == null ? LucideIcons.smile : moodIcon(mood!),
        label: mood?.label ?? _t('心情'),
        color: mood?.color,
      ),
    );
  }
}

class _WeatherMenu extends StatelessWidget {
  const _WeatherMenu({required this.session, required this.weather});
  final EditorSession session;
  final Weather? weather;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: _t('天气'),
      color: c.surface,
      position: PopupMenuPosition.under,
      onSelected: (v) => session.setWeather(v.isEmpty ? null : v),
      itemBuilder: (context) => [
        PopupMenuItem(value: '', child: Text(_t('不记录'))),
        for (final w in Weather.values)
          PopupMenuItem(
            value: w.key,
            child: Row(
              children: [
                Icon(weatherIcon(w.key), size: 14, color: c.inkMuted),
                const SizedBox(width: 8),
                Text(w.label),
              ],
            ),
          ),
      ],
      child: _MetaPill(
        icon: weather == null ? LucideIcons.cloudSun : weatherIcon(weather!.key)!,
        label: weather?.label ?? _t('天气'),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color ?? c.inkMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9.5,
              color: color ?? c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorFooter extends StatelessWidget {
  const _EditorFooter({required this.session, required this.mobile});
  final EditorSession session;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return AnimatedBuilder(
      animation: session.controller,
      builder: (context, _) {
        final selected = session.selectedWords;
        final label = selected > 0
            ? _t('已选 {selected} 字 · 共 {words} 字', {
                'selected': selected,
                'words': session.words,
              })
            : _t('{n} 字', {'n': session.words});
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mobile) ...[
              Icon(LucideIcons.feather, size: 10, color: c.inkMuted.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
                color: c.inkMuted.withValues(alpha: 0.8),
                letterSpacing: 0.2,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 保存失败不是一行红字就够：给出重试、把全文复制走、另存为三个出口，
/// 让用户至少不至于把刚写的东西弄丢。
class _SaveErrorBanner extends StatelessWidget {
  const _SaveErrorBanner({
    required this.state,
    required this.session,
    required this.mobile,
  });

  final AppState state;
  final EditorSession session;
  final bool mobile;

  String get _detail {
    final raw =
        (state.lastSaveError ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.isEmpty) return _t('文件没有写进去，可能是磁盘空间或权限的问题。');
    return raw.length > 110 ? '${raw.substring(0, 110)}…' : raw;
  }

  String get _payload {
    final title = session.note.title.trim();
    final body = session.plainText;
    return title.isEmpty ? body : '$title\n\n$body';
  }

  Future<void> _copyAll(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: _payload));
    if (context.mounted) {
      showToast(context, _t('全文已复制，可以先粘到别处'), icon: LucideIcons.check);
    }
  }

  Future<void> _saveAs(BuildContext context) async {
    final rawTitle = session.note.title.trim();
    final safe = (rawTitle.isEmpty ? _t('无题') : rawTitle)
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final location = await getSaveLocation(
      suggestedName: '$safe.txt',
      acceptedTypeGroups: [
        XTypeGroup(label: _t('纯文本'), extensions: const ['txt']),
      ],
    );
    if (location == null) return;
    try {
      await File(location.path).writeAsString(_payload, flush: true);
      if (context.mounted) {
        showToast(
          context,
          _t('已另存为 {name}', {'name': p.basename(location.path)}),
        );
      }
    } catch (e) {
      if (context.mounted) showToast(context, _t('另存失败：{e}', {'e': e}));
    }
  }

  Widget _button(
    BuildContext context,
    String label,
    VoidCallback onPressed,
  ) {
    final c = AppPalette.of(context);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: c.danger,
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: const TextStyle(fontFamily: 'NotoSansSC', fontSize: 11),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 12 : 18, 5, mobile ? 8 : 14, 5),
      decoration: BoxDecoration(
        color: c.danger.withValues(alpha: 0.07),
        border: Border(
          bottom: BorderSide(color: c.danger.withValues(alpha: 0.25)),
        ),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.alertCircle, size: 14, color: c.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _t('保存失败：{detail}', {'detail': _detail}),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                height: 1.5,
                color: c.danger,
              ),
            ),
          ),
          const SizedBox(width: 4),
          _button(context, _t('重试'), () => state.saveNow()),
          _button(context, _t('复制全文'), () => _copyAll(context)),
          if (!mobile) _button(context, _t('另存为…'), () => _saveAs(context)),
        ],
      ),
    );
  }
}
