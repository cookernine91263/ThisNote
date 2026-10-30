import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/icons.dart';
import '../../core/motion.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../state/app_state.dart';
import '../export_sheet.dart';
import 'editor_toolbar.dart';
import 'huazi.dart';
import 'image_embed.dart';
import 'quill_theme.dart';

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
        if (!zen && !mobile)
          EditorToolbar(controller: session.controller, session: session),
        Expanded(
          child: _EditorCanvas(
            mobile: mobile,
            zen: zen,
            onToggleZen: onToggleZen,
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
              tooltip: '返回',
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
                '${session.words} 字',
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
                SaveStatus.saving => session.dirty ? '正在写…' : '正在保存',
                SaveStatus.error => '保存失败',
                SaveStatus.saved => session.lastSaved == null
                    ? '已保存'
                    : '已保存 ${timeLabel(session.lastSaved!)}',
                SaveStatus.idle => '已保存',
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
          SoftIconButton(
            icon: LucideIcons.history,
            tooltip: '历史版本',
            onPressed: () => _showHistory(context, state, session),
          ),
          if (!mobile)
            SoftIconButton(
              icon: LucideIcons.focus,
              tooltip: '专注模式 · Ctrl Shift F',
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
                        '历史版本',
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
                    '书写时每 5 分钟自动留存一次，最多保留 40 个版本。',
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
                              '还没有历史版本。继续写一会儿，此记会替你留着。',
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
                          separatorBuilder: (_, __) => Divider(color: c.line),
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
                                        '${timeLabel(s.savedAt)} · ${s.words} 字'
                                        '${latest ? " · 最近" : ""}',
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
                                      title: '恢复这个版本？',
                                      message: '当前内容会被替换，但会先自动保存一次。',
                                      confirmLabel: '恢复',
                                    );
                                    if (ok) {
                                      await state.restoreSnapshot(s);
                                      if (context.mounted) Navigator.of(context).pop();
                                    }
                                  },
                                  child: Text(
                                    '恢复',
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
      tooltip: '更多',
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
            final ok = await showConfirm(
              context,
              title: '移到回收站？',
              message: '这篇文字会先放进回收站，之后仍可恢复。',
              confirmLabel: '移到回收站',
              danger: true,
            );
            if (ok) {
              await state.trashNote(note.id);
              onBack?.call();
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
          child: Text(note?.pinned == true ? '取消置顶' : '置顶'),
        ),
        PopupMenuItem(
          value: 'fav',
          child: Text(note?.favorite == true ? '取消收藏' : '收藏'),
        ),
        const PopupMenuItem(value: 'export', child: Text('导出…')),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'trash',
          child: Text('移到回收站', style: TextStyle(color: Color(0xFFB0473A))),
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
                  clipBehavior: Clip.antiAlias,
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
                                  placeholder: '从这里开始写…',
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
                                  ),
                                  customStyleBuilder: (attribute) =>
                                      quillCustomStyle(attribute, dark: c.isDark),
                                  embedBuilders: [
                                    NoteImageEmbedBuilder(state.store),
                                    const DividerEmbedBuilder(),
                                  ],
                                  textSelectionThemeData: TextSelectionThemeData(
                                    cursorColor: c.accent,
                                    selectionColor: c.selection,
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
                  tooltip: '退出专注模式',
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
                  '此记 · 专注模式',
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
              Text(
                dateLabel(note.createdAt),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
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
              hintText: '无题',
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
                              '标签',
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
              Text(
                readingTime(session.words),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9.5,
                  color: c.inkMuted,
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
    final c = AppPalette.of(context);
    final ctrl = TextEditingController(text: session.note.tags.join(' '));
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          '标签',
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 13,
                  color: c.ink,
                ),
                decoration: InputDecoration(
                  hintText: '用空格或逗号分隔，如：日常 读书',
                  hintStyle: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 12,
                    color: c.inkMuted,
                  ),
                  filled: true,
                  fillColor: c.paper,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.accent),
                  ),
                ),
                onSubmitted: (v) => Navigator.of(context).pop(v),
              ),
              const SizedBox(height: 8),
              Text(
                '标签会显示在列表里，也可以用来筛选。',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('取消', style: TextStyle(color: c.inkMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.ink,
              foregroundColor: c.paper,
            ),
            onPressed: () => Navigator.of(context).pop(ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (result != null) {
      final tags = result
          .split(RegExp(r'[\s,，、#]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      await session.setTags(tags);
    }
    ctrl.dispose();
  }
}

class _KindMenu extends StatelessWidget {
  const _KindMenu({required this.session});
  final EditorSession session;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PopupMenuButton<NoteKind>(
      tooltip: '切换类型',
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
      tooltip: '心情',
      color: c.surface,
      position: PopupMenuPosition.under,
      onSelected: (v) => session.setMood(v == 0 ? null : v),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 0, child: Text('不记录')),
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
        label: mood?.label ?? '心情',
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
      tooltip: '天气',
      color: c.surface,
      position: PopupMenuPosition.under,
      onSelected: (v) => session.setWeather(v.isEmpty ? null : v),
      itemBuilder: (context) => [
        const PopupMenuItem(value: '', child: Text('不记录')),
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
        label: weather?.label ?? '天气',
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mobile) ...[
              Icon(LucideIcons.feather, size: 10, color: c.inkMuted.withValues(alpha: 0.6)),
              const SizedBox(width: 5),
            ],
            Text(
              '${session.words} 字',
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
