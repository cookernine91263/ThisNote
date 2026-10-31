import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:url_launcher/url_launcher.dart';

import '../services/library_export.dart';
import '../services/webdav_service.dart';

import '../core/format.dart';
import '../core/i18n.dart';
import '../core/motion.dart';
import '../core/theme.dart';
import '../core/theme_reveal.dart';
import '../core/ui.dart';
import '../state/app_state.dart';
import 'editor/color_picker.dart';
import 'editor/huazi.dart';
import 'onboarding.dart';

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
                _t('设置'),
                style: TextStyle(
                  fontFamily: 'WenKai',
                  fontSize: 30,
                  letterSpacing: 2,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _t('把纸、灯和门，调成你喜欢的样子'),
                style: TextStyle(
                  fontFamily: 'NotoSansSC',
                  fontSize: 10.5,
                  color: c.inkMuted,
                ),
              ),
              const SizedBox(height: 20),
              _Card(
                icon: LucideIcons.languages,
                title: _t('语言'),
                subtitle: _t('界面语言 · 可随时切换'),
                children: [
                  Row(
                    children: [
                      LanguageToggle(
                        value: s.language,
                        onChanged: (code) => state.setLanguage(code),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _t('切换后整个界面立即换成所选语言，笔记内容不会被改动。'),
                          style: TextStyle(
                            fontFamily: 'NotoSansSC',
                            fontSize: 9.5,
                            height: 1.6,
                            color: c.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.sunMoon,
                title: _t('外观'),
                subtitle: _t('低饱和的纸色，白天黑夜都不刺眼'),
                children: [
                  _RowLabel(label: _t('主题')),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (final entry in [
                        (ThemeMode.system, LucideIcons.monitor, _t('跟随系统')),
                        (ThemeMode.light, LucideIcons.sun, _t('纸白')),
                        (ThemeMode.dark, LucideIcons.moon, _t('墨夜')),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Choice(
                            selected: s.themeMode == entry.$1,
                            icon: entry.$2,
                            label: entry.$3,
                            onTap: () {},
                            onTapPosition: (origin) {
                              // 点的就是当前主题：不播那段看不见的扩散，
                              // 也不让遮罩平白挡掉半秒多的输入。
                              if (s.themeMode == entry.$1) return;
                              ThemeReveal.reveal(
                                context: context,
                                globalOrigin: origin,
                                apply: () => state.setThemeMode(entry.$1),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _RowLabel(label: _t('强调色')),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      for (final entry in [
                        ('vermilion', _t('朱砂'), const Color(0xFFA84637)),
                        ('ink', _t('黛青'), const Color(0xFF44515F)),
                        ('sage', _t('松烟'), const Color(0xFF5E7359)),
                        ('gold', _t('秋香'), const Color(0xFF9C7A43)),
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
                                _t('自选'),
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
                  _SliderSetting(
                    label: _t('界面字号'),
                    value: s.uiScale,
                    min: 0.9,
                    max: 1.15,
                    display: '${(s.uiScale * 100).round()}%',
                    suffix: '%',
                    decimals: 0,
                    snap: 0.01,
                    transform: (v) => v * 100,
                    inverse: (v) => v / 100,
                    onChanged: (v) => state.updateSettings((x) => x.uiScale = v),
                  ),
                  const SizedBox(height: 10),
                  _SettingSwitch(
                    label: _t('纸张颗粒'),
                    description: _t('在背景上铺一层极淡的纸纹'),
                    value: s.paperTexture,
                    onChanged: (v) => state.updateSettings((x) => x.paperTexture = v),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                icon: LucideIcons.type,
                title: _t('编辑器'),
                subtitle: _t('字号、行距与页宽，只影响书写时的纸'),
                children: [
                  _SliderSetting(
                    label: _t('正文字号'),
                    value: s.editorScale,
                    min: 0.85,
                    max: 1.3,
                    display: '${(17 * s.editorScale).round()} px',
                    suffix: 'px',
                    decimals: 0,
                    transform: (v) => 17 * v,
                    inverse: (v) => v / 17,
                    onChanged: (v) => state.updateSettings((x) => x.editorScale = v),
                  ),
                  _SliderSetting(
                    label: _t('行距'),
                    value: s.lineHeight,
                    min: 1.5,
                    max: 2.3,
                    display: s.lineHeight.toStringAsFixed(2),
                    decimals: 2,
                    snap: 0.05,
                    onChanged: (v) => state.updateSettings((x) => x.lineHeight = v),
                  ),
                  _SliderSetting(
                    label: _t('段间距'),
                    value: s.paragraphGap,
                    min: 0,
                    max: 24,
                    display: '${s.paragraphGap.round()} px',
                    suffix: 'px',
                    decimals: 0,
                    snap: 1,
                    onChanged: (v) =>
                        state.updateSettings((x) => x.paragraphGap = v),
                  ),
                  _SliderSetting(
                    label: _t('字间距'),
                    value: s.letterSpacing,
                    min: 0,
                    max: 1.2,
                    display: s.letterSpacing.toStringAsFixed(2),
                    decimals: 2,
                    snap: 0.05,
                    onChanged: (v) =>
                        state.updateSettings((x) => x.letterSpacing = v),
                  ),
                  _SliderSetting(
                    label: _t('页宽'),
                    value: s.editorWidth,
                    min: 600,
                    max: 920,
                    display: '${s.editorWidth.round()} px',
                    suffix: 'px',
                    decimals: 0,
                    snap: 10,
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
                          _t('纸上的样子'),
                          style: TextStyle(
                            fontFamily: 'WenKai',
                            fontSize: 21,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _t('落笔即心安'),
                          style: huaziTextStyle('huazi:zhu:m', dark: c.isDark),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _t(
                            '正文会以 {n} 号字、{h} 倍行距排布。中文、English 与 日本語 都可以在同一页里安静地待着。',
                            {
                              'n': (17 * s.editorScale).round(),
                              'h': s.lineHeight.toStringAsFixed(2),
                            },
                          ),
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
                title: _t('写作目标'),
                subtitle: _t('不是 KPI，只是给今天一个轻轻的落点'),
                children: [
                  _SliderSetting(
                    label: _t('每日目标'),
                    value: s.dailyGoal.toDouble(),
                    min: 100,
                    max: 3000,
                    divisions: 29,
                    display: _t('{n} 字', {'n': s.dailyGoal}),
                    suffix: _t('字'),
                    decimals: 0,
                    snap: 50,
                    onChanged: (v) => state.setDailyGoal(v.round()),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        _t('今天已写 {n} 字', {'n': state.todayWords}),
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
                title: _t('隐私与锁'),
                subtitle: _t('密码只保存在本机，不上传、不找回'),
                children: [
                  _SettingSwitch(
                    label: _t('启动密码锁'),
                    description: _t('4 位数字密码。忘记后无法找回，请谨慎开启。'),
                    value: s.lockEnabled,
                    onChanged: (v) async {
                      if (v) {
                        final pin = await _askPin(context, title: _t('设置 4 位密码'));
                        if (pin != null) {
                          await state.enableLock(pin);
                          if (context.mounted) {
                            showToast(context, _t('密码已设置，下次启动时生效'));
                          }
                        }
                      } else {
                        final pin = await _askPin(context, title: _t('输入当前密码'));
                        if (pin != null) {
                          if (state.verifyPin(pin)) {
                            await state.disableLock(pin);
                            if (context.mounted) {
                              showToast(context, _t('密码锁已关闭'));
                            }
                          } else if (context.mounted) {
                            showToast(context, _t('密码不正确'));
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
                        label: Text(_t('立即锁定')),
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
                title: _t('数据'),
                subtitle: _t('本地优先：所有文字都在你的设备上'),
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
                        label: _t('立即备份'),
                        dense: true,
                        onPressed: () => _backup(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.fileUp,
                        label: _t('从备份恢复'),
                        dense: true,
                        onPressed: () => _restore(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.fileDown,
                        label: _t('导入 Markdown'),
                        dense: true,
                        onPressed: () => _importMarkdown(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.folderOutput,
                        label: _t('导出全部 Markdown'),
                        dense: true,
                        onPressed: () => _exportMarkdown(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.folder,
                        label: _t('数据文件夹'),
                        dense: true,
                        onPressed: () => _openFolder(context, state),
                      ),
                      SoftButton(
                        icon: LucideIcons.trash2,
                        label: _t('清空回收站'),
                        dense: true,
                        onPressed: () async {
                          if (await showConfirm(context,
                              title: _t('清空回收站？'),
                              message: _t('回收站里的文字将被永久删除。'),
                              danger: true,
                              confirmLabel: _t('清空'))) {
                            await state.emptyTrash();
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('备份是一个 zip，包含正文、图片与历史版本；恢复会覆盖当前数据，并先自动备份一次。'),
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
                title: _t('关于此记'),
                subtitle: _t('一个安静的本地写作空间'),
                children: [
                  Text(
                    _t('此记 · ThisNote 1.1.1'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 12,
                      color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _t(
                      '内置字体：思源黑体 / 思源宋体 / 霞鹜文楷 /\n'
                      '马善政毛笔 / 站酷小薇，均为 SIL Open Font License。\n'
                      '中、英、日与假名可在同一页里混排。',
                    ),
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
                        label: _t('快捷键'),
                        dense: true,
                        onPressed: () => _showShortcuts(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t('完全本地 · 无账号 · 无广告 · 无追踪'),
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
                  _t('写下去，就已经很好了。'),
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
          text: _t('此记 · 数据备份'),
          subject: _t('此记备份'),
        ),
      );
    } else {
      await Clipboard.setData(ClipboardData(text: path));
      if (context.mounted) {
        showToast(context, _t('备份已生成，路径已复制到剪贴板'));
      }
    }
  }

  Future<void> _restore(BuildContext context, AppState state) async {
    final file = await openFile(
      acceptedTypeGroups: [XTypeGroup(label: _t('此记备份'), extensions: const ['zip'])],
    );
    if (file == null || !context.mounted) return;
    final ok = await showConfirm(
      context,
      title: _t('恢复这份备份？'),
      message: _t('当前数据会被覆盖。恢复前会自动再做一次备份。'),
      confirmLabel: _t('恢复'),
      danger: true,
    );
    if (!ok) return;
    await state.store.restoreBackup(file.path);
    await state.reload();
    if (context.mounted) showToast(context, _t('备份已恢复'));
  }

  Future<void> _importMarkdown(BuildContext context, AppState state) async {
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: _t('Markdown / 文本'),
          extensions: const ['md', 'markdown', 'txt'],
        ),
      ],
    );
    if (files.isEmpty) return;

    var count = 0;
    String? firstError;
    for (final file in files) {
      try {
        final content = utf8.decode(
          await file.readAsBytes(),
          allowMalformed: true,
        );
        await state.importMarkdown(content: content, filename: file.name);
        count++;
      } catch (e) {
        firstError ??= _t('{name}：{e}', {'name': file.name, 'e': e});
      }
    }
    if (!context.mounted) return;
    if (count > 0) {
      showToast(
        context,
        _t('导入了 {n} 篇，去「全部」里看看', {'n': count}),
        icon: LucideIcons.check,
      );
    } else {
      showToast(
        context,
        firstError ?? _t('没有可导入的内容'),
        icon: LucideIcons.alertCircle,
      );
    }
  }

  Future<void> _exportMarkdown(BuildContext context, AppState state) async {
    final dir = await getDirectoryPath(confirmButtonText: _t('导出到这里'));
    if (dir == null) return;
    try {
      final count = await exportLibraryMarkdown(
        state.store,
        state.activeNotes,
        dir,
      );
      if (context.mounted) {
        showToast(
          context,
          _t('已导出 {n} 篇到 {path}', {'n': count, 'path': dir}),
          icon: LucideIcons.check,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showToast(context, _t('导出失败：{e}', {'e': e}), icon: LucideIcons.alertCircle);
      }
    }
  }

  Future<void> _openFolder(BuildContext context, AppState state) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [state.store.dataPath]);
    } else {
      await Clipboard.setData(ClipboardData(text: state.store.dataPath));
      if (context.mounted) showToast(context, _t('数据路径已复制到剪贴板'));
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
            child: Text(_t('取消'), style: TextStyle(color: c.inkMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.ink,
              foregroundColor: c.paper,
            ),
            onPressed: () {
              if (ctrl.text.length == 4) Navigator.of(context).pop(ctrl.text);
            },
            child: Text(_t('确定')),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  void _showShortcuts(BuildContext context) {
    final c = AppPalette.of(context);
    final modifier = I18n.isEn ? 'Ctrl / Cmd' : 'Ctrl / ⌘';
    final shortcuts = [
      ('$modifier + K', _t('命令面板')),
      ('$modifier + N', _t('新建笔记')),
      ('$modifier + S', _t('立即保存')),
      ('$modifier + F', _t('查找')),
      ('$modifier + H', _t('查找替换')),
      ('$modifier + B', _t('加粗')),
      ('$modifier + I', _t('倾斜')),
      ('$modifier + U', _t('下划线')),
      ('$modifier + Shift + V', _t('粘贴为纯文本')),
      ('$modifier + Shift + F', _t('专注模式')),
      ('$modifier + ,', _t('设置')),
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
                  _t('快捷键'),
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
    this.onTapPosition,
  });
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onTapPosition;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTapUp: onTapPosition == null
          ? null
          : (details) => onTapPosition!(details.globalPosition),
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
    this.suffix = '',
    this.decimals = 0,
    this.snap,
    this.transform,
    this.inverse,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String display;
  final String suffix;
  final int decimals;
  final double? snap;
  final double Function(double)? transform;
  final double Function(double)? inverse;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            // 英文滑杆标签更长，留出更宽的一列，避免折行把滑杆挤歪。
            width: I18n.isEn ? 100 : 70,
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
          _NumberField(
            value: value,
            min: min,
            max: max,
            suffix: suffix,
            decimals: decimals,
            snap: snap,
            transform: transform,
            inverse: inverse,
            onSubmitted: (v) => onChanged(v),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatefulWidget {
  const _NumberField({
    required this.value,
    required this.min,
    required this.max,
    required this.suffix,
    required this.decimals,
    required this.onSubmitted,
    this.snap,
    this.transform,
    this.inverse,
  });

  final double value;
  final double min;
  final double max;
  final String suffix;
  final int decimals;
  final double? snap;
  final double Function(double)? transform;
  final double Function(double)? inverse;
  final ValueChanged<double> onSubmitted;

  @override
  State<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<_NumberField> {
  late final TextEditingController _controller =
      TextEditingController(text: _format(widget.value));
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && widget.value != oldWidget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _format(double value) {
    final shown = widget.transform?.call(value) ?? value;
    return shown.toStringAsFixed(widget.decimals);
  }

  void _commit() {
    var parsed = double.tryParse(_controller.text.trim());
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }
    if (widget.snap != null && widget.snap! > 0) {
      parsed = (parsed / widget.snap!).round() * widget.snap!;
    }
    var internal = widget.inverse?.call(parsed) ?? parsed;
    internal = internal.clamp(widget.min, widget.max).toDouble();
    widget.onSubmitted(internal);
    _controller.text = _format(internal);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            keyboardType: TextInputType.numberWithOptions(
              decimal: widget.decimals > 0,
            ),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 10,
              color: c.ink,
            ),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 5),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.line),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: c.accent),
              ),
            ),
            onSubmitted: (_) => _commit(),
            onTapOutside: (_) => _focus.unfocus(),
          ),
        ),
        if (widget.suffix.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Text(
              widget.suffix,
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
      title: _t('AI 助手'),
      subtitle: _t('可选 · 使用你自己的 API Key'),
      children: [
        _SettingSwitch(
          label: _t('启用 AI 功能'),
          description: _t('支持 OpenAI 兼容接口；只在点击润色/续写时发送选中的文字。'),
          value: ai.enabled,
          onChanged: (v) => widget.state.updateSettings((s) => s.aiSettings.enabled = v),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _url,
          label: _t('接口地址'),
          hint: 'https://api.deepseek.com/v1',
          onChanged: (v) => widget.state.updateSettings((s) => s.aiSettings.baseUrl = v),
        ),
        _Field(
          controller: _model,
          label: _t('模型'),
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
            _t('Key 仅保存在本机设置文件中。'),
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
      title: _t('WebDAV 同步'),
      subtitle: _t('可选 · 自己的服务器或坚果云'),
      children: [
        _SettingSwitch(
          label: _t('启用 WebDAV'),
          description: _t('本地优先，手动同步；不会上传到任何第三方服务。'),
          value: w.enabled,
          onChanged: (v) => widget.state.updateSettings((s) => s.webdavSettings.enabled = v),
        ),
        const SizedBox(height: 12),
        _Field(
          controller: _url,
          label: _t('服务器地址'),
          hint: 'https://dav.example.com/remote.php/dav/files/name',
          onChanged: (v) => widget.state.updateSettings((s) => s.webdavSettings.url = v),
        ),
        Row(
          children: [
            Expanded(
              child: _Field(
                controller: _user,
                label: _t('用户名'),
                hint: '',
                onChanged: (v) =>
                    widget.state.updateSettings((s) => s.webdavSettings.username = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                controller: _pass,
                label: _t('密码'),
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
          label: _t('远端文件夹'),
          hint: '/ThisNote',
          onChanged: (v) => widget.state.updateSettings((s) => s.webdavSettings.folder = v),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _t('同步会在设置中手动触发，采用较新覆盖较旧；同名冲突会保留副本。'),
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
              label: _t('测试连接'),
              dense: true,
              onPressed: () => _test(context, c),
            ),
            SoftButton(
              icon: LucideIcons.cloudUpload,
              label: _t('上传备份'),
              dense: true,
              onPressed: () => _upload(context),
            ),
            SoftButton(
              icon: LucideIcons.cloud,
              label: _t('恢复最新'),
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
      showToast(context, _t('请先填写 WebDAV 地址与用户名，并启用同步'));
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
        showToast(context, _t('连接成功，远端有 {n} 份备份', {'n': list.length}));
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
      if (context.mounted) showToast(context, _t('备份已上传到 WebDAV'));
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
      if (context.mounted) showToast(context, _t('远端还没有备份'));
      return;
    }
    if (!context.mounted) return;
    final target = list.first;
    final ok = await showConfirm(
      context,
      title: _t('恢复远端备份？'),
      message: _t(
        '将恢复 {name}（{y}-{m}-{d}）。当前数据会先自动备份。',
        {
          'name': target.name,
          'y': target.time.year,
          'm': target.time.month,
          'd': target.time.day,
        },
      ),
      confirmLabel: _t('恢复'),
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
      if (context.mounted) showToast(context, _t('已从 WebDAV 恢复'));
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) showToast(context, _t('恢复失败：{e}', {'e': e}));
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
              _t('正在同步…'),
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

/// 设置页的英文表：键就是界面里的中文原文，改文案时不会漏掉英文。
const Map<String, String> _en = <String, String>{
  '设置': 'Settings',
  '把纸、灯和门，调成你喜欢的样子':
      'Tune the paper, the light, and the door to your liking',
  '语言': 'Language',
  '界面语言 · 可随时切换': 'Interface language · switch anytime',
  '切换后整个界面立即换成所选语言，笔记内容不会被改动。':
      'The whole interface switches instantly; your notes stay untouched.',
  '外观': 'Appearance',
  '低饱和的纸色，白天黑夜都不刺眼':
      'Low-saturation paper tones, easy on the eyes day and night',
  '主题': 'Theme',
  '跟随系统': 'System',
  '纸白': 'Paper',
  '墨夜': 'Ink Night',
  '强调色': 'Accent',
  '朱砂': 'Vermilion',
  '黛青': 'Slate',
  '松烟': 'Pine',
  '秋香': 'Amber',
  '自选': 'Custom',
  '界面字号': 'UI scale',
  '纸张颗粒': 'Paper grain',
  '在背景上铺一层极淡的纸纹': 'A faint paper texture over the background',
  '编辑器': 'Editor',
  '字号、行距与页宽，只影响书写时的纸':
      'Size, spacing and width — they only touch the paper you write on',
  '正文字号': 'Body size',
  '行距': 'Line height',
  '段间距': 'Paragraph spacing',
  '字间距': 'Letter spacing',
  '页宽': 'Page width',
  '纸上的样子': 'On the paper',
  '落笔即心安': 'Write, and the heart settles.',
  '正文会以 {n} 号字、{h} 倍行距排布。中文、English 与 日本語 都可以在同一页里安静地待着。':
      'Body text sets at {n} pt with {h}× line height. Chinese, English and Japanese all rest quietly on one page.',
  '写作目标': 'Writing goal',
  '不是 KPI，只是给今天一个轻轻的落点':
      'Not a KPI — just a gentle landing spot for today',
  '每日目标': 'Daily goal',
  '{n} 字': '{n} words',
  '字': 'words',
  '今天已写 {n} 字': '{n} words written today',
  '隐私与锁': 'Privacy & lock',
  '密码只保存在本机，不上传、不找回':
      'The passcode stays on this device — never uploaded, never recoverable',
  '启动密码锁': 'Lock on launch',
  '4 位数字密码。忘记后无法找回，请谨慎开启。':
      'A 4-digit passcode. It cannot be recovered if forgotten — enable with care.',
  '设置 4 位密码': 'Set a 4-digit passcode',
  '密码已设置，下次启动时生效': 'Passcode set. It applies on next launch.',
  '输入当前密码': 'Enter current passcode',
  '密码锁已关闭': 'Passcode lock is off',
  '密码不正确': 'Incorrect passcode',
  '立即锁定': 'Lock now',
  '数据': 'Data',
  '本地优先：所有文字都在你的设备上':
      'Local-first: every word lives on your device',
  '立即备份': 'Back up now',
  '从备份恢复': 'Restore from backup',
  '导入 Markdown': 'Import Markdown',
  '导出全部 Markdown': 'Export all Markdown',
  '数据文件夹': 'Data folder',
  '清空回收站': 'Empty trash',
  '清空回收站？': 'Empty trash?',
  '回收站里的文字将被永久删除。':
      'Everything in the trash will be permanently deleted.',
  '清空': 'Empty',
  '备份是一个 zip，包含正文、图片与历史版本；恢复会覆盖当前数据，并先自动备份一次。':
      'A backup is a zip of text, images and version history. Restoring overwrites current data, so a fresh backup is made first.',
  '关于此记': 'About ThisNote',
  '一个安静的本地写作空间': 'A quiet local writing space',
  '此记 · ThisNote 1.1.1': 'ThisNote 1.1.1',
  '内置字体：思源黑体 / 思源宋体 / 霞鹜文楷 /\n'
          '马善政毛笔 / 站酷小薇，均为 SIL Open Font License。\n'
          '中、英、日与假名可在同一页里混排。':
      'Bundled fonts: Source Han Sans / Source Han Serif / LXGW WenKai /\n'
      'Ma Shan Zheng / ZCOOL XiaoWei, all under the SIL Open Font License.\n'
      'Chinese, English and Japanese mix freely on one page.',
  '快捷键': 'Keyboard shortcuts',
  '完全本地 · 无账号 · 无广告 · 无追踪':
      'Fully local · No account · No ads · No tracking',
  '写下去，就已经很好了。': 'Just keep writing — that is already enough.',
  '此记 · 数据备份': 'ThisNote · Data backup',
  '此记备份': 'ThisNote backup',
  '备份已生成，路径已复制到剪贴板': 'Backup created — path copied to clipboard',
  '恢复这份备份？': 'Restore this backup?',
  '当前数据会被覆盖。恢复前会自动再做一次备份。':
      'Current data will be overwritten. A fresh backup is made first.',
  '恢复': 'Restore',
  '备份已恢复': 'Backup restored',
  'Markdown / 文本': 'Markdown / Text',
  '导入了 {n} 篇，去「全部」里看看': 'Imported {n} notes — look under All',
  '没有可导入的内容': 'Nothing to import',
  '{name}：{e}': '{name}: {e}',
  '导出到这里': 'Export here',
  '已导出 {n} 篇到 {path}': 'Exported {n} notes to {path}',
  '导出失败：{e}': 'Export failed: {e}',
  '数据路径已复制到剪贴板': 'Data path copied to clipboard',
  '取消': 'Cancel',
  '确定': 'OK',
  '命令面板': 'Command palette',
  '新建笔记': 'New note',
  '立即保存': 'Save now',
  '查找': 'Find',
  '查找替换': 'Find & replace',
  '加粗': 'Bold',
  '倾斜': 'Italic',
  '下划线': 'Underline',
  '粘贴为纯文本': 'Paste as plain text',
  '专注模式': 'Focus mode',
  'AI 助手': 'AI assistant',
  '可选 · 使用你自己的 API Key': 'Optional · Use your own API key',
  '启用 AI 功能': 'Enable AI features',
  '支持 OpenAI 兼容接口；只在点击润色/续写时发送选中的文字。':
      'Works with OpenAI-compatible APIs; only the text you select is sent, when you tap Polish or Continue.',
  '接口地址': 'Endpoint',
  '模型': 'Model',
  'Key 仅保存在本机设置文件中。':
      'The key is stored only in the local settings file.',
  'WebDAV 同步': 'WebDAV sync',
  '可选 · 自己的服务器或坚果云': 'Optional · Your own server or Nutstore',
  '启用 WebDAV': 'Enable WebDAV',
  '本地优先，手动同步；不会上传到任何第三方服务。':
      'Local-first and manual; nothing goes to a third-party service.',
  '服务器地址': 'Server URL',
  '用户名': 'Username',
  '密码': 'Password',
  '远端文件夹': 'Remote folder',
  '同步会在设置中手动触发，采用较新覆盖较旧；同名冲突会保留副本。':
      'Sync runs manually from here; newer files win and clashing names keep a copy.',
  '测试连接': 'Test connection',
  '上传备份': 'Upload backup',
  '恢复最新': 'Restore latest',
  '请先填写 WebDAV 地址与用户名，并启用同步':
      'Fill in the WebDAV URL and username, and enable sync first.',
  '连接成功，远端有 {n} 份备份': 'Connected — {n} backups on the server',
  '备份已上传到 WebDAV': 'Backup uploaded to WebDAV',
  '远端还没有备份': 'No backups on the server yet',
  '恢复远端备份？': 'Restore the remote backup?',
  '将恢复 {name}（{y}-{m}-{d}）。当前数据会先自动备份。':
      'Will restore {name} ({y}-{m}-{d}). Current data is backed up first.',
  '已从 WebDAV 恢复': 'Restored from WebDAV',
  '恢复失败：{e}': 'Restore failed: {e}',
  '正在同步…': 'Syncing…',
};

/// 本页的翻译入口：中文原文写在调用处，英文由 [_en] 提供。
String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);
