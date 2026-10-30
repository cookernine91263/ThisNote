import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/webdav_service.dart';

import '../core/format.dart';
import '../core/motion.dart';
import '../core/motion_choice.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import 'editor/color_picker.dart';
import 'editor/huazi.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final state = context.watch<AppState>();
    final s = state.settings;
    return SafeArea(
      bottom: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width < 900 ? 16 : 34,
          MediaQuery.sizeOf(context).width < 900 ? 12 : 30,
          MediaQuery.sizeOf(context).width < 900 ? 16 : 30,
          40,
        ),
        child: Center(
          child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置',
                style: TextStyle(
                  fontFamily: 'WenKai',
                  fontSize: 30,
                  letterSpacing: 2,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '把纸、灯和门，调成你喜欢的样子',
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 20),
              _Card(
                icon: LucideIcons.sunMoon,
                title: '外观',
                subtitle: '低饱和的纸色，白天黑夜都不刺眼',
                children: [
                  _RowLabel(label: '主题'),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (final entry in const [
                        (ThemeMode.system, LucideIcons.monitor, '跟随系统'),
                        (ThemeMode.light, LucideIcons.sun, '纸白'),
                        (ThemeMode.dark, LucideIcons.moon, '墨夜'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Choice(
                            selected: s.themeMode == entry.$1,
                            icon: entry.$2,
                            label: entry.$3,
                            onTap: () => state.setThemeMode(entry.$1),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _RowLabel(label: '强调色'),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (final entry in const [
                        ('vermilion', '朱砂', Color(0xFFA84637)),
                        ('ink', '黛青', Color(0xFF44515F)),
                        ('sage', '松烟', Color(0xFF5E7359)),
                        ('gold', '秋香', Color(0xFF9C7A43)),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: GestureDetector(
                            onTap: () => state.setAccent(entry.$1),
                            child: Column(
                              children: [
                                AnimatedContainer(
                                  duration: Motion.fast,
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: entry.$3,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: s.accent == entry.$1
                                          ? c.ink
                                          : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  entry.$2,
                                  style: TextStyle(
                                    fontFamily: 'NotoSansSC',
                                    fontSize: 8.5,
                                    color: s.accent == entry.$1
                                        ? c.ink
                                        : c.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () async {
                            final hex = await showNoteColorPicker(
                              context,
                              background: false,
                            );
                            if (hex != null && hex != 'clear') {
                              await state.setAccent(hex);
                            }
                          },
                          child: Column(
                            children: [
                              AnimatedContainer(
                                duration: Motion.fast,
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: s.accent.startsWith('#')
                                      ? parseHex(s.accent)
                                      : null,
                                  gradient: s.accent.startsWith('#')
                                      ? null
                                      : const SweepGradient(
                                          colors: [
                                            Color(0xFFA84637),
                                            Color(0xFF9C7A43),
                                            Color(0xFF5E7359),
                                            Color(0xFF44515F),
                                            Color(0xFF7A5A6B),
                                            Color(0xFFA84637),
                                          ],
                                        ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: s.accent.startsWith('#')
                                        ? c.ink
                                        : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  LucideIcons.pipette,
                                  size: 12,
                                  color: s.accent.startsWith('#')
                                      ? c.paper
                                      : Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '自选',
                                style: TextStyle(
                                  fontFamily: 'NotoSansSC',
                                  fontSize: 8.5,
                                  color: s.accent.startsWith('#')
                                      ? c.ink
                                      : c.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _SettingSwitch(
                    label: '纸张颗粒',
                    description: '在背景上铺一层极淡的纸纹',
                    value: s.paperTexture,
                    onChanged: (v) => state.updateSettings((x) => x.paperTexture = v),
                  ),
                  const SizedBox(height: 12),
                  Container(height: 0.8, color: c.line),
                  const SizedBox(height: 12),
                  _RowLabel(label: '页面切换'),
                  const SizedBox(height: 4),
                  Text(
                    '两种手感，随时可换。',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: MotionChoice(
                          value: 'slide',
                          compact: true,
                          selected: s.motionStyle == 'slide',
                          onTap: () => state.setMotionStyle('slide'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MotionChoice(
                          value: 'morph',
                          compact: true,
                          selected: s.motionStyle == 'morph',
                          onTap: () => state.setMotionStyle('morph'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.type,
                title: '编辑器',
                subtitle: '字号、行距与页宽，只影响书写时的纸',
                children: [
                  _SliderSetting(
                    label: '正文字号',
                    value: s.editorScale,
                    min: 0.85,
                    max: 1.3,
                    display: '${(17 * s.editorScale).round()} px',
                    onChanged: (v) => state.updateSettings((x) => x.editorScale = v),
                  ),
                  _SliderSetting(
                    label: '行距',
                    value: s.lineHeight,
                    min: 1.5,
                    max: 2.3,
                    display: s.lineHeight.toStringAsFixed(2),
                    onChanged: (v) => state.updateSettings((x) => x.lineHeight = v),
                  ),
                  _SliderSetting(
                    label: '页宽',
                    value: s.editorWidth,
                    min: 600,
                    max: 920,
                    display: '${s.editorWidth.round()} px',
                    onChanged: (v) => state.updateSettings((x) => x.editorWidth = v),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    decoration: BoxDecoration(
                      color: c.paper,
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '纸上的样子',
                          style: TextStyle(
                            fontFamily: 'WenKai',
                            fontSize: 21,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '落笔即心安',
                          style: huaziTextStyle('huazi:zhu:m', dark: c.isDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '正文会以 ${(17 * s.editorScale).round()} 号字、${s.lineHeight.toStringAsFixed(2)} 倍行距排布。中文、English 与 日本語 都可以在同一页里安静地待着。',
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 12.5 * s.editorScale,
                            height: s.lineHeight,
                            color: c.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.target,
                title: '写作目标',
                subtitle: '不是 KPI，只是给今天一个轻轻的落点',
                children: [
                  _SliderSetting(
                    label: '每日目标',
                    value: s.dailyGoal.toDouble(),
                    min: 100,
                    max: 3000,
                    divisions: 29,
                    display: '${s.dailyGoal} 字',
                    onChanged: (v) => state.setDailyGoal(v.round()),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '今天已写 ${state.todayWords} 字',
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 10.5,
                          color: c.inkMuted,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: (state.todayWords / s.dailyGoal).clamp(0, 1),
                            backgroundColor: c.surfaceAlt,
                            valueColor: AlwaysStoppedAnimation(c.accent),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.lock,
                title: '隐私与锁',
                subtitle: '密码只保存在本机，不上传、不找回',
                children: [
                  _SettingSwitch(
                    label: '启动密码锁',
                    description: '4 位数字密码。忘记后无法找回，请谨慎开启。',
                    value: s.lockEnabled,
                    onChanged: (v) async {
                      if (v) {
                        final pin = await _askPin(context, title: '设置 4 位密码');
                        if (pin != null) {
                          await state.enableLock(pin);
                          if (context.mounted) {
                            showToast(context, '密码已设置，下次启动时生效');
                          }
                        }
                      } else {
                        final pin = await _askPin(context, title: '输入当前密码');
                        if (pin != null) {
                          if (state.verifyPin(pin)) {
                            await state.disableLock(pin);
                            if (context.mounted) {
                              showToast(context, '密码锁已关闭');
                            }
                          } else if (context.mounted) {
                            showToast(context, '密码不正确');
                          }
                        }
                      }
                    },
                  ),
                  if (s.lockEnabled)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: state.lock,
                        icon: const Icon(LucideIcons.lock, size: 13),
                        label: const Text('立即锁定'),
                        style: TextButton.styleFrom(
                          foregroundColor: c.accent,
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.database,
                title: '数据',
                subtitle: '本地优先：所有文字都在你的设备上',
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.paper,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: c.line),
                    ),
                    child: SelectableText(
                      state.store.dataPath,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 10,
                        color: c.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SoftButton(
                        icon: LucideIcons.archive,
                        label: '立即备份',
                        dense: true,
                        onPressed: () => _backup(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.fileUp,
                        label: '从备份恢复',
                        dense: true,
                        onPressed: () => _restore(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.folder,
                        label: '数据文件夹',
                        dense: true,
                        onPressed: () => _openFolder(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.trash2,
                        label: '清空回收站',
                        dense: true,
                        onPressed: () async {
                          if (await showConfirm(context,
                              title: '清空回收站？',
                              message: '回收站里的文字将被永久删除。',
                              danger: true,
                              confirmLabel: '清空')) {
                            await state.emptyTrash();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '备份是一个 zip，包含正文、图片与历史版本；恢复会覆盖当前数据，并先自动备份一次。',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      height: 1.6,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
              if (Platform.isWindows || Platform.isAndroid) ...[
                const SizedBox(height: 12),
                _AiCard(state: state),
                const SizedBox(height: 12),
                _SyncCard(state: state),
              ],
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.feather,
                title: '关于此记',
                subtitle: '一个安静的本地写作空间',
                children: [
                  Text(
                    '此记 · ThisNote 1.0.0',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '内置字体：思源黑体 / 思源宋体 / 霞鹜文楷 /\n'
                    '马善政毛笔 / 站酷小薇，均为 SIL Open Font License。\n'
                    '中、英、日与假名可在同一页里混排。',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5,
                      height: 1.8,
                      color: c.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SoftButton(
                        icon: LucideIcons.globe,
                        label: 'Noto Sans SC',
                        dense: true,
                        onPressed: () => launchUrl(
                          Uri.parse('https://fonts.google.com/noto/specimen/Noto+Sans+SC'),
                        ),
                      ),
                      SoftButton(
                        icon: LucideIcons.globe,
                        label: 'LXGW WenKai',
                        dense: true,
                        onPressed: () => launchUrl(
                          Uri.parse('https://github.com/lxgw/LxgwWenKai'),
                        ),
                      ),
                      SoftButton(
                        icon: LucideIcons.keyboard,
                        label: '快捷键',
                        dense: true,
                        onPressed: () => _showShortcuts(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '完全本地 · 无账号 · 无广告 · 无追踪',
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9,
                      letterSpacing: 1,
                      color: c.inkMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  '写下去，就已经很好了。',
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 11,
                    letterSpacing: 1,
                    color: c.inkMuted.withValues(alpha: 0.8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Future<void> _backup(BuildContext context, AppState state) async {
    final path = await state.store.createBackup();
    if (!context.mounted) return;
    if (Platform.isAndroid) {
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path)],
          text: '此记 · 数据备份',
          subject: '此记备份',
        ),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      if (context.mounted) {
        showToast(context, '备份已生成，路径已复制到剪贴板');
      }
    }
  }

  Future<void> _restore(BuildContext context, AppState state) async {
    final file = await openFile(
      acceptedTypeGroups: const [XTypeGroup(label: '此记备份', extensions: ['zip'])],
    );
    if (file == null || !context.mounted) return;
    final ok = await showConfirm(
      context,
      title: '恢复这份备份？',
      message: '当前数据会被覆盖。恢复前会自动再做一次备份。',
      confirmLabel: '恢复',
      danger: true,
    );
    if (!ok) return;
    await state.store.restoreBackup(file.path);
    await state.reload();
    if (context.mounted) showToast(context, '备份已恢复');
  }

  Future<void> _openFolder(BuildContext context, AppState state) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [state.store.dataPath]);
    } else {
      await Clipboard.setData(ClipboardData(text: state.store.dataPath));
      if (context.mounted) showToast(context, '数据路径已复制到剪贴板');
    }
  }

  Future<String?> _askPin(BuildContext context, {required String title}) async {
    final c = AppPalette.of(context);
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          title,
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: c.ink,
          ),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: TextStyle(
            fontFamily: 'NotoSansSC',
            fontSize: 22,
            letterSpacing: 10,
            color: c.ink,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••',
            hintStyle: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 18,
              letterSpacing: 8,
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
          onSubmitted: (v) {
            if (v.length == 4) Navigator.of(context).pop(v);
          },
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
            onPressed: () {
              if (ctrl.text.length == 4) Navigator.of(context).pop(ctrl.text);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _showShortcuts(BuildContext context) {
    final c = AppPalette.of(context);
    const shortcuts = [
      ('Ctrl / ⌘ + K', '命令面板'),
      ('Ctrl / ⌘ + N', '新建笔记'),
      ('Ctrl / ⌘ + S', '立即保存'),
      ('Ctrl / ⌘ + B', '加粗'),
      ('Ctrl / ⌘ + I', '倾斜'),
      ('Ctrl / ⌘ + U', '下划线'),
      ('Ctrl / ⌘ + Shift + F', '专注模式'),
      ('Ctrl / ⌘ + ,', '设置'),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: c.surface,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '快捷键',
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 22,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 14),
                for (final s in shortcuts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.$2,
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 11.5,
                              color: c.inkSoft,
                            ),
                          ),
                        ),
                        Kbd(s.$1),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return PaperSurface(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: c.accent),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 9.5,
                    color: c.inkMuted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Text(
      label,
      style: TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 10.5,
        color: c.inkMuted,
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? c.ink : c.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13, color: selected ? c.paper : c.inkMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 11,
                color: selected ? c.paper : c.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10.5,
                color: c.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: c.accent,
                inactiveTrackColor: c.line,
                thumbColor: c.accent,
                overlayColor: c.accentSoft,
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 9.5,
                color: c.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  const _SettingSwitch({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 11.5,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 9.5,
                  height: 1.5,
                  color: c.inkMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: c.onAccent,
          activeTrackColor: c.accent,
          inactiveTrackColor: c.surfaceAlt,
          inactiveThumbColor: c.inkMuted,
        ),
      ],
    );
  }
}

class _AiCard extends StatefulWidget {
  const _AiCard({required this.state});
  final AppState state;

  @override
  State<_AiCard> createState() => _AiCardState();
}

class _AiCardState extends State<_AiCard> {
  late final TextEditingController _url =
      TextEditingController(text: widget.state.settings.aiSettings.baseUrl);
  late final TextEditingController _model =
      TextEditingController(text: widget.state.settings.aiSettings.model);
  late final TextEditingController _key =
      TextEditingController(text: widget.state.settings.aiSettings.apiKey);

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final ai = widget.state.settings.aiSettings;
    return _Card(
      icon: LucideIcons.sparkles,
      title: 'AI 助手',
      subtitle: '可选 · 使用你自己的 API Key',
      children: [
        _SettingSwitch(
          label: '启用 AI 功能',
          description: '支持 OpenAI 兼容接口；只在点击润色/续写时发送选中的文字。',
          value: ai.enabled,
          onChanged: (v) => widget.state.updateSettings((s) => s.aiSettings.enabled = v),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _url,
          label: '接口地址',
          hint: 'https://api.deepseek.com/v1',
          onChanged: (v) => widget.state.updateSettings((s) => s.aiSettings.baseUrl = v),
        ),
        _Field(
          controller: _model,
          label: '模型',
          hint: 'deepseek-chat',
          onChanged: (v) => widget.state.updateSettings((s) => s.aiSettings.model = v),
        ),
        _Field(
          controller: _key,
          label: 'API Key',
          hint: 'sk-…',
          obscure: true,
          onChanged: (v) => widget.state.updateSettings((s) => s.aiSettings.apiKey = v),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Key 仅保存在本机设置文件中。',
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9,
              color: c.inkMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _SyncCard extends StatefulWidget {
  const _SyncCard({required this.state});
  final AppState state;

  @override
  State<_SyncCard> createState() => _SyncCardState();
}

class _SyncCardState extends State<_SyncCard> {
  late final TextEditingController _url =
      TextEditingController(text: widget.state.settings.webdavSettings.url);
  late final TextEditingController _user =
      TextEditingController(text: widget.state.settings.webdavSettings.username);
  late final TextEditingController _pass =
      TextEditingController(text: widget.state.settings.webdavSettings.password);
  late final TextEditingController _folder =
      TextEditingController(text: widget.state.settings.webdavSettings.folder);

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    _folder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final w = widget.state.settings.webdavSettings;
    return _Card(
      icon: LucideIcons.cloudUpload,
      title: 'WebDAV 同步',
      subtitle: '可选 · 自己的服务器或坚果云',
      children: [
        _SettingSwitch(
          label: '启用 WebDAV',
          description: '本地优先，手动同步；不会上传到任何第三方服务。',
          value: w.enabled,
          onChanged: (v) => widget.state.updateSettings((s) => s.webdavSettings.enabled = v),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _url,
          label: '服务器地址',
          hint: 'https://dav.example.com/remote.php/dav/files/name',
          onChanged: (v) => widget.state.updateSettings((s) => s.webdavSettings.url = v),
        ),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _user,
                label: '用户名',
                hint: '',
                onChanged: (v) =>
                    widget.state.updateSettings((s) => s.webdavSettings.username = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                controller: _pass,
                label: '密码',
                hint: '',
                obscure: true,
                onChanged: (v) =>
                    widget.state.updateSettings((s) => s.webdavSettings.password = v),
              ),
            ),
          ],
        ),
        _Field(
          controller: _folder,
          label: '远端文件夹',
          hint: '/ThisNote',
          onChanged: (v) => widget.state.updateSettings((s) => s.webdavSettings.folder = v),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '同步会在设置中手动触发，采用较新覆盖较旧；同名冲突会保留副本。',
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9,
              height: 1.6,
              color: c.inkMuted,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SoftButton(
              icon: LucideIcons.refreshCw,
              label: '测试连接',
              dense: true,
              onPressed: () => _test(context, c),
            ),
            SoftButton(
              icon: LucideIcons.cloudUpload,
              label: '上传备份',
              dense: true,
              onPressed: () => _upload(context),
            ),
            SoftButton(
              icon: LucideIcons.cloud,
              label: '恢复最新',
              dense: true,
              onPressed: () => _download(context),
            ),
          ],
        ),
      ],
    );
  }

  bool _ready(BuildContext context) {
    final w = widget.state.settings.webdavSettings;
    if (!w.configured) {
      showToast(context, '请先填写 WebDAV 地址与用户名，并启用同步');
      return false;
    }
    return true;
  }

  Future<void> _test(BuildContext context, AppPalette c) async {
    if (!_ready(context)) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _Busy(),
    );
    try {
      final service = WebDavService(widget.state.settings.webdavSettings);
      await service.ensureFolder();
      final list = await service.listBackups();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        showToast(context, '连接成功，远端有 ${list.length} 份备份');
      }
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, '$e');
    }
  }

  Future<void> _upload(BuildContext context) async {
    if (!_ready(context)) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _Busy(),
    );
    try {
      final file = File(await widget.state.store.createBackup());
      final service = WebDavService(widget.state.settings.webdavSettings);
      await service.upload(file, name: p.basename(file.path));
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, '备份已上传到 WebDAV');
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, '$e');
    }
  }

  Future<void> _download(BuildContext context) async {
    if (!_ready(context)) return;
    final service = WebDavService(widget.state.settings.webdavSettings);
    List<RemoteBackup> list;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _Busy(),
    );
    try {
      list = await service.listBackups();
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, '$e');
      return;
    }
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (list.isEmpty) {
      if (context.mounted) showToast(context, '远端还没有备份');
      return;
    }
    if (!context.mounted) return;
    final target = list.first;
    final ok = await showConfirm(
      context,
      title: '恢复远端备份？',
      message:
          '将恢复 ${target.name}（${target.time.year}-${target.time.month}-${target.time.day}）。当前数据会先自动备份。',
      confirmLabel: '恢复',
      danger: true,
    );
    if (!ok || !context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _Busy(),
    );
    try {
      final bytes = await service.download(target);
      final file = File(p.join(widget.state.store.root.path, 'webdav-restore.zip'));
      await file.writeAsBytes(bytes, flush: true);
      await widget.state.store.restoreBackup(file.path);
      await widget.state.reload();
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, '已从 WebDAV 恢复');
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, '恢复失败：$e');
    }
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: c.accent),
            ),
            const SizedBox(width: 14),
            Text(
              '正在同步…',
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    this.obscure = false,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 10,
                color: c.inkMuted,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: obscure,
              onChanged: onChanged,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 11.5,
                color: c.ink,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 11,
                  color: c.inkMuted.withValues(alpha: 0.7),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                filled: true,
                fillColor: c.paper,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: c.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: c.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide(color: c.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
