import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/app_state.dart';
import 'code_block.dart';
import 'image_embed.dart';

/// 文案以中文为源，英文放在 [_en] 里。
const Map<String, String> _en = <String, String>{
  '此记 · 图片': 'ThisNote · Image',
  'PNG 图片': 'PNG image',
  '图片已保存': 'Image saved',
  '导出图片失败：{e}': 'Could not export the image: {e}',
  '把这一页变成图片': 'Turn this page into an image',
  '不截屏，重新排一张可以收藏的纸': 'No screenshot — a keepsake page, freshly typeset',
  '纸色': 'Paper',
  '日期': 'Date',
  '标签': 'Tags',
  '长图会按内容自动延展': 'The long image grows with the content',
  '正在生成…': 'Generating…',
  '保存 PNG': 'Save PNG',
  '图片张数': 'Pages',
  '共 {n} 张': '{n} images',
  '自动分页': 'Auto',
  '第 {n} 张从这开始': 'Image {n} starts here',
  '长图在社交平台会被压糊，分成几张更清楚。':
      'Long images get blurred by social apps — a few pages stay sharp.',
  '整张长图会被社交平台压缩，建议分成 3–6 张。':
      'Social apps compress one long image; 3–6 pages usually look better.',
  '点断点两侧的小箭头，调整这一张到哪里结束。':
      'Tap the arrows beside a break to choose where that page ends.',
  '保存 {n} 张 PNG': 'Save {n} PNGs',
  '已保存 {n} 张图片': 'Saved {n} images',
  '已保存图片到 {name}': 'Saved the image to {name}',
  '选择保存图片的文件夹': 'Choose a folder for the images',
  '这一页还没有字。': 'This page has no words yet.',
  '{words} 字': '{words} words',
  '［图片］': '[Image]',
  '此记-{stamp}': 'ThisNote-{stamp}',
  '无题': 'Untitled',
  '此记': 'ThisNote',
  '此记 · ThisNote': 'ThisNote',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

enum NoteImageTheme { paper, ink, rose, sage }

class _Paper {
  const _Paper({
    required this.bg,
    required this.surface,
    required this.surfaceAlt,
    required this.ink,
    required this.soft,
    required this.accent,
    required this.line,
    required this.blue,
    required this.sage,
    required this.gold,
  });

  final Color bg;
  final Color surface;
  final Color surfaceAlt;
  final Color ink;
  final Color soft;
  final Color accent;
  final Color line;
  final Color blue;
  final Color sage;
  final Color gold;

  static _Paper of(NoteImageTheme theme) => switch (theme) {
    NoteImageTheme.paper => const _Paper(
      bg: Color(0xFFF4EDDF),
      surface: Color(0xFFFFFBF3),
      surfaceAlt: Color(0xFFEDE5D6),
      ink: Color(0xFF211E19),
      soft: Color(0xFF6F675B),
      accent: Color(0xFFA84637),
      line: Color(0xFFDFD2BC),
      blue: Color(0xFF56697D),
      sage: Color(0xFF6F806C),
      gold: Color(0xFFA8824B),
    ),
    NoteImageTheme.ink => const _Paper(
      bg: Color(0xFF171411),
      surface: Color(0xFF1E1A16),
      surfaceAlt: Color(0xFF24211C),
      ink: Color(0xFFEDE5D6),
      soft: Color(0xFFA59C8C),
      accent: Color(0xFFD38172),
      line: Color(0xFF3A342B),
      blue: Color(0xFF8AA0B8),
      sage: Color(0xFF93A38E),
      gold: Color(0xFFC9A46C),
    ),
    NoteImageTheme.rose => const _Paper(
      bg: Color(0xFFF1E3DD),
      surface: Color(0xFFFBF2ED),
      surfaceAlt: Color(0xFFEAD9D2),
      ink: Color(0xFF392326),
      soft: Color(0xFF7F6363),
      accent: Color(0xFF9A4F50),
      line: Color(0xFFE1CBC4),
      blue: Color(0xFF5E6E82),
      sage: Color(0xFF6E8069),
      gold: Color(0xFFA87B4A),
    ),
    NoteImageTheme.sage => const _Paper(
      bg: Color(0xFFE8EDE3),
      surface: Color(0xFFF5F8F1),
      surfaceAlt: Color(0xFFDDE5D7),
      ink: Color(0xFF263229),
      soft: Color(0xFF667263),
      accent: Color(0xFF5F7464),
      line: Color(0xFFCED9C8),
      blue: Color(0xFF566B7E),
      sage: Color(0xFF5F7464),
      gold: Color(0xFF9C7A43),
    ),
  };
}

Future<void> showPngExport(BuildContext context) async {
  final state = context.read<AppState>();
  final note = state.current;
  if (note == null) return;
  await state.saveNow();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    builder: (_) => _PngDialog(note: note, store: state.store),
  );
}

class _PngDialog extends StatefulWidget {
  const _PngDialog({required this.note, required this.store});
  final Note note;
  final NoteStore store;

  @override
  State<_PngDialog> createState() => _PngDialogState();
}

class _PngDialogState extends State<_PngDialog> {
  final _boundary = GlobalKey();
  final _lineKeys = NoteImageLineKeys();
  NoteImageTheme _theme = NoteImageTheme.paper;
  bool _showMeta = true;
  bool _showTags = true;
  bool _saving = false;

  /// 预览里量出来的段落位置与整张卡片的高度（逻辑像素）。
  List<double> _lineTops = const [];
  double _cardHeight = 0;
  double _cardWidth = 520;

  /// 分页：[_cuts] 里的每个位置都是「下一张从这条横线开始」。
  int _pages = 1;
  bool _autoPages = true;
  List<double> _cuts = const [];

  /// 正文里引用到的图片，一次读进来；图片本身也要进 PNG。
  Map<String, Uint8List> _images = const {};
  late final Future<void> _imagesReady;

  @override
  void initState() {
    super.initState();
    _imagesReady = _loadImages();
    _scheduleMeasure();
  }

  Future<void> _loadImages() async {
    final paths = <String>{};
    for (final op in widget.note.delta) {
      if (op is! Map) continue;
      final insert = op['insert'];
      if (insert is! Map) continue;
      final path = insert['image'];
      if (path is String && path.isNotEmpty) paths.add(path);
    }
    if (paths.isEmpty) return;
    final loaded = <String, Uint8List>{};
    for (final path in paths) {
      final bytes = await widget.store.readAsset(path);
      if (bytes != null) loaded[path] = bytes;
    }
    if (!mounted) return;
    // 先解码，免得 toImage 时图片还没画上去。
    for (final bytes in loaded.values) {
      try {
        await precacheImage(MemoryImage(bytes), context);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _images = loaded);
    _scheduleMeasure();
  }

  int get _pageCount => _cardHeight > 0 ? _pageBounds(_cardHeight).length : 1;

  /// 再加一张是否真的切得出来（段数不够时按钮不该亮着）。
  bool get _canAddPage {
    if (_pageCount >= math.min(_lineTops.length, 20)) return false;
    final cuts = _autoCuts(_pageCount + 1, _lineTops, _cardHeight);
    return cuts.length >= _pageCount;
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  /// 量出每一段在卡片里的纵向位置。分页只在段与段之间切，
  /// 不会把一行字劈成两半。
  void _measure() {
    if (!mounted) return;
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderBox || !boundary.hasSize) return;
    final tops = <double>[];
    for (var i = 0; i < _lineKeys.count; i++) {
      final box = _lineKeys.at(i).currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      tops.add(box.localToGlobal(Offset.zero, ancestor: boundary).dy);
    }
    final height = boundary.size.height;
    final width = boundary.size.width;
    var same =
        tops.length == _lineTops.length &&
        height == _cardHeight &&
        width == _cardWidth;
    if (same) {
      for (var i = 0; i < tops.length; i++) {
        if (tops[i] != _lineTops[i]) {
          same = false;
          break;
        }
      }
    }
    if (same) return;

    final maxPages = math.max(1, math.min(tops.length, 20));
    final auto = _autoPageCount(width, height, maxPages);
    var pages = _autoPages ? auto : _pages.clamp(1, maxPages);
    var cuts = _autoCuts(pages, tops, height);
    if (!_autoPages && cuts.length != pages - 1) {
      // 宽度变了（窗口缩放）以后手调的分页可能不再成立，退回自动。
      pages = auto;
      cuts = _autoCuts(pages, tops, height);
    }
    if (cuts.length + 1 < pages) pages = cuts.length + 1;
    setState(() {
      _lineTops = tops;
      _cardHeight = height;
      _cardWidth = width;
      _pages = pages;
      _autoPages = _autoPages && pages == auto;
      _cuts = cuts;
    });
  }

  int _autoPageCount(double width, double height, int maxPages) {
    if (height <= 0) return 1;
    // 接近 3:4 的竖版，朋友圈和小红书都不会把它压成一条。
    final ideal = math.max(320.0, width * 1.36);
    return (height / ideal).ceil().clamp(1, maxPages);
  }

  /// 自动分页：每个断点尽量靠近等分线，但一定落在段首，
  /// 并且保证首尾两页都有足够的内容。
  List<double> _autoCuts(int pages, List<double> tops, double height) {
    if (pages <= 1 || tops.length < 3 || height <= 0) return const [];
    final candidates = tops.sublist(1);
    final gap = math.max(60.0, math.min(180.0, height / (pages * 2)));
    final cuts = <double>[];
    var previous = tops.first;
    for (var i = 1; i < pages; i++) {
      final target = height * i / pages;
      double? best;
      for (final y in candidates) {
        if (y - previous < gap) continue;
        if (height - y < gap * 0.5) continue;
        if (best == null || (y - target).abs() < (best - target).abs()) {
          best = y;
        }
      }
      if (best == null) break;
      cuts.add(best);
      previous = best;
    }
    return cuts;
  }

  void _setPages(int next) {
    final maxPages = math.max(1, math.min(_lineTops.length, 20));
    final pages = next.clamp(1, maxPages);
    final cuts = _autoCuts(pages, _lineTops, _cardHeight);
    setState(() {
      _autoPages = false;
      _pages = cuts.length + 1;
      _cuts = cuts;
    });
  }

  void _autoAgain() {
    final maxPages = math.max(1, math.min(_lineTops.length, 20));
    final pages = _autoPageCount(_cardWidth, _cardHeight, maxPages);
    final cuts = _autoCuts(pages, _lineTops, _cardHeight);
    setState(() {
      _autoPages = true;
      _pages = cuts.length + 1;
      _cuts = cuts;
    });
  }

  /// 把某个断点往前/往后挪一段。
  void _nudgeCut(int index, int direction) {
    if (index < 0 || index >= _cuts.length || _lineTops.length < 3) return;
    final current = _cuts[index];
    final lower = index == 0 ? _lineTops.first + 12 : _cuts[index - 1] + 40;
    final upper = index == _cuts.length - 1
        ? _cardHeight - 80
        : _cuts[index + 1] - 40;
    var at = _lineTops.indexOf(current);
    if (at < 0) {
      at = 0;
      for (var i = 0; i < _lineTops.length; i++) {
        if ((_lineTops[i] - current).abs() < (_lineTops[at] - current).abs()) {
          at = i;
        }
      }
    }
    for (
      var i = at + direction;
      i > 0 && i < _lineTops.length;
      i += direction
    ) {
      final y = _lineTops[i];
      if (y <= lower || y >= upper) continue;
      setState(() {
        _autoPages = false;
        _cuts = List<double>.of(_cuts)..[index] = y;
      });
      return;
    }
  }

  List<(double, double)> _pageBounds(double height) {
    final cuts = _cuts.where((y) => y > 4 && y < height - 4).toList()..sort();
    final bounds = <(double, double)>[];
    var top = 0.0;
    for (final cut in cuts) {
      bounds.add((top, cut));
      top = cut;
    }
    bounds.add((top, height));
    return bounds;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _imagesReady;
      await WidgetsBinding.instance.endOfFrame;
      final object = _boundary.currentContext?.findRenderObject();
      if (object is! RenderRepaintBoundary) return;
      final size = object.size;
      // 超长图会撞上引擎的纹理上限；按高度反过来限制像素比。
      final ratio = math.min(3.0, math.max(1.0, 16000 / size.height));
      final image = await object.toImage(pixelRatio: ratio);
      final scale = image.width / size.width;
      final bounds = _pageBounds(size.height);
      final base = _safeName(widget.note.title);
      final files = <(String, Uint8List)>[];
      for (var i = 0; i < bounds.length; i++) {
        final src = Rect.fromLTRB(
          0,
          bounds[i].$1 * scale,
          image.width.toDouble(),
          bounds[i].$2 * scale,
        );
        final page = await _crop(image, src);
        final data = await page.toByteData(format: ui.ImageByteFormat.png);
        page.dispose();
        if (data == null) continue;
        final suffix = bounds.length > 1
            ? '-${bounds.length >= 10 ? '${i + 1}'.padLeft(2, '0') : i + 1}'
            : '';
        files.add(('$base$suffix.png', data.buffer.asUint8List()));
      }
      image.dispose();
      if (files.isEmpty || !mounted) return;
      await _deliver(files);
    } catch (e) {
      if (mounted) {
        showToast(context, _t('导出图片失败：{e}', {'e': e}));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ui.Image> _crop(ui.Image source, Rect src) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      source,
      src,
      Rect.fromLTWH(0, 0, src.width, src.height),
      Paint()..filterQuality = FilterQuality.none,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(src.width.round(), src.height.round());
    picture.dispose();
    return image;
  }

  Future<void> _deliver(List<(String, Uint8List)> files) async {
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      final shared = <XFile>[];
      for (final file in files) {
        final out = File(p.join(dir.path, file.$1));
        await out.writeAsBytes(file.$2, flush: true);
        shared.add(XFile(out.path));
      }
      await SharePlus.instance.share(
        ShareParams(
          files: shared,
          subject: widget.note.title.isEmpty
              ? _t('此记 · 图片')
              : widget.note.title,
        ),
      );
      return;
    }

    if (files.length == 1) {
      final location = await getSaveLocation(
        suggestedName: files.first.$1,
        acceptedTypeGroups: [
          XTypeGroup(label: _t('PNG 图片'), extensions: const ['png']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsBytes(files.first.$2, flush: true);
      if (mounted) {
        showToast(
          context,
          _t('已保存图片到 {name}', {'name': p.basename(location.path)}),
        );
      }
      return;
    }

    final dir = await getDirectoryPath(confirmButtonText: _t('保存到这里'));
    if (dir == null) return;
    for (final file in files) {
      await File(p.join(dir, file.$1)).writeAsBytes(file.$2, flush: true);
    }
    if (mounted) {
      showToast(
        context,
        _t('已保存 {n} 张图片', {'n': files.length}),
        icon: LucideIcons.check,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    _scheduleMeasure();
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: size.height - 46),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.line),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 50,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 12, 10),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('把这一页变成图片'),
                            style: TextStyle(
                              fontFamily: 'WenKai',
                              fontSize: 23,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _t('不截屏，重新排一张可以收藏的纸'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      SoftIconButton(
                        icon: LucideIcons.x,
                        size: 30,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // 减去滚动区左右各 22 的内边距，窄屏上也不会横向溢出。
                      final width = (constraints.maxWidth - 44).clamp(
                        240.0,
                        520.0,
                      );
                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
                        child: Center(
                          child: SizedBox(
                            width: width,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                RepaintBoundary(
                                  key: _boundary,
                                  child: NoteImageCard(
                                    note: widget.note,
                                    theme: _theme,
                                    width: width,
                                    showMeta: _showMeta,
                                    showTags: _showTags,
                                    lineKeys: _lineKeys,
                                    images: _images,
                                  ),
                                ),
                                for (var i = 0; i < _cuts.length; i++)
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    top: _cuts[i] - 14,
                                    child: _CutMarker(
                                      label: _t('第 {n} 张从这开始', {'n': i + 2}),
                                      onUp: () => _nudgeCut(i, -1),
                                      onDown: () => _nudgeCut(i, 1),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
                  decoration: BoxDecoration(
                    border: Border(top: BorderSide(color: c.line)),
                  ),
                  child: Column(
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _t('纸色'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10,
                              color: c.inkMuted,
                            ),
                          ),
                          for (final theme in NoteImageTheme.values)
                            _ThemeDot(
                              theme: theme,
                              active: theme == _theme,
                              onTap: () => setState(() => _theme = theme),
                            ),
                          _ToggleText(
                            label: _t('日期'),
                            value: _showMeta,
                            onTap: () => setState(() => _showMeta = !_showMeta),
                          ),
                          _ToggleText(
                            label: _t('标签'),
                            value: _showTags,
                            onTap: () => setState(() => _showTags = !_showTags),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(
                            _t('图片张数'),
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 10,
                              color: c.inkMuted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          _StepButton(
                            icon: LucideIcons.minus,
                            onTap: _pageCount > 1
                                ? () => _setPages(_pageCount - 1)
                                : null,
                          ),
                          Container(
                            constraints: const BoxConstraints(minWidth: 64),
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              _t('共 {n} 张', {'n': _pageCount}),
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 11,
                                color: c.ink,
                              ),
                            ),
                          ),
                          _StepButton(
                            icon: LucideIcons.plus,
                            onTap: _canAddPage
                                ? () => _setPages(_pageCount + 1)
                                : null,
                          ),
                          const Spacer(),
                          if (!_autoPages)
                            SoftButton(
                              icon: LucideIcons.wand2,
                              label: _t('自动分页'),
                              dense: true,
                              onPressed: _autoAgain,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _pageCount > 1
                                  ? _t('点断点两侧的小箭头，调整这一张到哪里结束。')
                                  : _t('整张长图会被社交平台压缩，建议分成 3–6 张。'),
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 9,
                                height: 1.5,
                                color: c.inkMuted,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: c.ink,
                              foregroundColor: c.paper,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 11,
                              ),
                            ),
                            onPressed: _saving ? null : _save,
                            icon: _saving
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(LucideIcons.download, size: 15),
                            label: Text(
                              _saving
                                  ? _t('正在生成…')
                                  : _pageCount > 1
                                  ? _t('保存 {n} 张 PNG', {'n': _pageCount})
                                  : _t('保存 PNG'),
                            ),
                          ),
                        ],
                      ),
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

/// 分页断点：一条横线，右侧两个小箭头把断点挪到前一段或后一段。
class _CutMarker extends StatelessWidget {
  const _CutMarker({
    required this.label,
    required this.onUp,
    required this.onDown,
  });

  final String label;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1.2,
              color: c.accent.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(width: 6),
          _ArrowButton(icon: LucideIcons.chevronUp, onTap: onUp),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.accent.withValues(alpha: 0.45)),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'NotoSansSC',
                fontSize: 8.5,
                color: c.accent,
              ),
            ),
          ),
          _ArrowButton(icon: LucideIcons.chevronDown, onTap: onDown),
        ],
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return HoverBuilder(
      builder: (context, hovered, t) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? c.accentSoft : c.surface,
            shape: BoxShape.circle,
            border: Border.all(color: c.accent.withValues(alpha: 0.45)),
          ),
          child: Icon(icon, size: 13, color: c.accent),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.transparent : c.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: onTap == null ? c.line : c.lineStrong),
        ),
        child: Icon(
          icon,
          size: 12,
          color: onTap == null ? c.inkMuted.withValues(alpha: 0.5) : c.inkSoft,
        ),
      ),
    );
  }
}

/// 给 [NoteImageCard] 的每一段一个稳定的 key，导出时用来量分页位置。
class NoteImageLineKeys {
  final List<GlobalKey> _keys = [];

  GlobalKey at(int index) {
    while (_keys.length <= index) {
      _keys.add(GlobalKey());
    }
    return _keys[index];
  }

  int get count => _keys.length;
}

class _ThemeDot extends StatelessWidget {
  const _ThemeDot({
    required this.theme,
    required this.active,
    required this.onTap,
  });
  final NoteImageTheme theme;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final paper = _Paper.of(theme);
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: paper.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: active ? c.ink : c.lineStrong.withValues(alpha: 0.55),
            width: active ? 2 : 1,
          ),
        ),
        child: Center(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: paper.accent,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

class _ToggleText extends StatelessWidget {
  const _ToggleText({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final bool value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            value ? LucideIcons.eye : LucideIcons.eyeOff,
            size: 12,
            color: value ? c.accent : c.inkMuted,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 9.5,
              color: value ? c.inkSoft : c.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class NoteImageCard extends StatelessWidget {
  const NoteImageCard({
    required this.note,
    required this.theme,
    required this.width,
    this.showMeta = true,
    this.showTags = true,
    this.lineKeys,
    this.images = const {},
    super.key,
  });

  final Note note;
  final NoteImageTheme theme;
  final double width;
  final bool showMeta;
  final bool showTags;

  /// 只给导出对话框用：给每一段挂一个 key，方便量分页断点。
  final NoteImageLineKeys? lineKeys;

  /// 文档里引用的图片，路径 → 字节。没有时退回「［图片］」。
  final Map<String, Uint8List> images;

  @override
  Widget build(BuildContext context) {
    final paper = _Paper.of(theme);
    final scale = (width / 520).clamp(0.6, 1.0);
    final title = note.title.trim().isEmpty ? _t('无题') : note.title.trim();
    final lines = _Lines(note.delta).parse();
    final date = dateLabel(note.createdAt);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: paper.bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: paper.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned(
            right: -width * 0.12,
            top: -width * 0.16,
            child: Container(
              width: width * 0.55,
              height: width * 0.55,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    paper.accent.withValues(alpha: 0.08),
                    paper.accent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(42 * scale),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 3 * scale,
                      height: 18 * scale,
                      color: paper.accent,
                    ),
                    const SizedBox(width: 9),
                    Text(
                      _t('此记'),
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 13 * scale,
                        letterSpacing: 2,
                        color: paper.accent,
                      ),
                    ),
                    const Spacer(),
                    if (showMeta)
                      Text(
                        date,
                        style: TextStyle(
                          fontFamily: 'NotoSansSC',
                          fontSize: 9 * scale,
                          color: paper.soft,
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 30 * scale),
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'WenKai',
                    fontSize: 37 * scale,
                    height: 1.28,
                    letterSpacing: 1,
                    color: paper.ink,
                  ),
                ),
                if (showMeta) ...[
                  SizedBox(height: 10 * scale),
                  Text(
                    _subtitle(),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9.5 * scale,
                      height: 1.6,
                      color: paper.soft,
                    ),
                  ),
                ],
                if (showTags && note.tags.isNotEmpty) ...[
                  SizedBox(height: 16 * scale),
                  Wrap(
                    spacing: 7 * scale,
                    runSpacing: 6 * scale,
                    children: [
                      for (final tag in note.tags)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * scale,
                            vertical: 3 * scale,
                          ),
                          decoration: BoxDecoration(
                            color: paper.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: paper.line),
                          ),
                          child: Text(
                            '# $tag',
                            style: TextStyle(
                              fontFamily: 'NotoSansSC',
                              fontSize: 8.5 * scale,
                              color: paper.soft,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                SizedBox(height: 22 * scale),
                Container(height: 0.8, color: paper.line),
                SizedBox(height: 18 * scale),
                if (lines.isEmpty)
                  Text(
                    _t('这一页还没有字。'),
                    style: TextStyle(
                      fontFamily: 'NotoSerifSC',
                      fontSize: 14 * scale,
                      color: paper.soft,
                    ),
                  )
                else
                  for (var i = 0; i < lines.length; i++)
                    _lineView(lines[i], paper, scale, lineKeys?.at(i)),
                SizedBox(height: 28 * scale),
                Row(
                  children: [
                    Text(
                      _t('{words} 字', {'words': note.words}),
                      style: TextStyle(
                        fontFamily: 'NotoSansSC',
                        fontSize: 9 * scale,
                        color: paper.soft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _t('此记 · ThisNote'),
                      style: TextStyle(
                        fontFamily: 'WenKai',
                        fontSize: 10 * scale,
                        letterSpacing: 1,
                        color: paper.soft,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    final parts = <String>[
      note.kind.label,
      if (note.weather != null) WeatherX.fromKey(note.weather)?.label ?? '',
      if (note.mood != null) MoodX.fromScore(note.mood)?.label ?? '',
    ].where((e) => e.isNotEmpty).toList();
    return parts.join(' · ');
  }

  Widget _lineView(_Line line, _Paper paper, double scale, [Key? key]) {
    return Padding(
      key: key,
      padding: EdgeInsets.only(
        left: (line.quote ? 13 : 0) * scale,
        bottom: (line.kind == _LineKind.text && line.header == null ? 10 : 14) *
            scale,
      ),
      child: switch (line.kind) {
        _LineKind.code => _codeView(line, paper, scale),
        _LineKind.divider => _dividerView(paper, scale),
        _LineKind.image => _imageView(line, paper, scale),
        _LineKind.text => _textView(line, paper, scale),
      },
    );
  }

  Widget _textView(_Line line, _Paper paper, double scale) {
    final header = int.tryParse(line.header ?? '');
    final base = _blockStyle(header, line.quote, paper, scale);
    final checked = line.list == 'checked';
    final prefix = _listPrefix(line);
    final spans = <InlineSpan>[
      if (prefix != null)
        TextSpan(
          text: prefix,
          style: base.copyWith(
            color: line.list == 'unchecked' ? paper.soft : paper.accent,
            fontWeight: FontWeight.w500,
          ),
        ),
      for (final run in line.runs)
        TextSpan(
          text: run.text,
          style: _inlineStyle(
            base,
            run.attrs,
            paper,
            scale,
            checked: checked,
          ),
        ),
    ];
    final text = Text.rich(
      TextSpan(children: spans),
      style: base,
      textAlign: switch (line.align) {
        'center' => TextAlign.center,
        'right' => TextAlign.right,
        'justify' => TextAlign.justify,
        _ => TextAlign.left,
      },
    );
    if (line.quote) {
      return Container(
        padding: EdgeInsets.fromLTRB(12 * scale, 8 * scale, 12 * scale, 8 * scale),
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            paper.accent.withValues(alpha: 0.10),
            paper.bg,
          ),
          borderRadius: BorderRadius.circular(3 * scale),
          border: Border(
            left: BorderSide(
              color: paper.accent.withValues(alpha: 0.55),
              width: 2 * scale,
            ),
          ),
        ),
        child: text,
      );
    }
    final indent = (line.list != null ? 16 : 0) + line.indent * 18;
    if (indent == 0) return text;
    return Padding(
      padding: EdgeInsets.only(left: indent * scale),
      child: text,
    );
  }

  TextStyle _blockStyle(
    int? header,
    bool quote,
    _Paper paper,
    double scale,
  ) {
    var family = 'NotoSansSC';
    var size = 14.5 * scale;
    var height = 1.9;
    var weight = FontWeight.w400;
    var spacing = 0.15;
    if (header != null) {
      family = header == 3 ? 'NotoSansSC' : 'WenKai';
      size = (header == 1 ? 30 : header == 2 ? 24 : 20) * scale;
      height = header == 3 ? 1.5 : 1.45;
      weight = FontWeight.w600;
      spacing = header == 3 ? 0.1 : 0.5;
    }
    return TextStyle(
      fontFamily: family,
      fontSize: size,
      height: height,
      fontWeight: weight,
      letterSpacing: spacing,
      color: quote ? paper.soft : paper.ink,
    );
  }

  TextStyle _inlineStyle(
    TextStyle base,
    Map<String, dynamic> attrs,
    _Paper paper,
    double scale, {
    bool checked = false,
  }) {
    if (attrs.isEmpty && !checked) return base;
    var style = base;
    final font = attrs['font']?.toString();
    if (font != null && font.isNotEmpty) {
      if (font.startsWith('huazi:')) {
        style = style.copyWith(fontFamily: 'WenKai');
      } else if (font == 'style:thin' || font == 'NotoSansSCLight') {
        style = style.copyWith(
          fontFamily: 'NotoSansSC',
          fontWeight: FontWeight.w300,
        );
      } else if (font == 'Serif') {
        style = style.copyWith(fontFamily: 'WenKai');
      } else {
        style = style.copyWith(fontFamily: font);
      }
    }
    final size = attrs['size']?.toString();
    if (size != null) {
      final target = switch (size) {
        'small' => 13.0,
        'large' => 22.0,
        'huge' => 30.0,
        _ => double.tryParse(size),
      };
      if (target != null) {
        // 编辑器正文是 17，按同一比例放大，保留正文与标题的相对关系。
        style = style.copyWith(fontSize: 14.5 * scale * (target / 17));
      }
    }
    if (attrs['bold'] == true) {
      style = style.copyWith(fontWeight: FontWeight.w700);
    }
    if (attrs['italic'] == true) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    var decoration = style.decoration ?? TextDecoration.none;
    if (attrs['underline'] == true) {
      decoration = decoration == TextDecoration.none
          ? TextDecoration.underline
          : TextDecoration.combine([decoration, TextDecoration.underline]);
    }
    if (attrs['strike'] == true || checked) {
      decoration = decoration == TextDecoration.none
          ? TextDecoration.lineThrough
          : TextDecoration.combine([decoration, TextDecoration.lineThrough]);
    }
    if (decoration != TextDecoration.none) {
      style = style.copyWith(
        decoration: decoration,
        decorationColor: checked ? paper.soft : style.color,
      );
    }
    if (attrs['code'] == true) {
      style = style.copyWith(
        fontFamily: 'SourceHanMono',
        fontFamilyFallback: const ['NotoSansSC', 'monospace'],
        fontSize: 12 * scale,
        height: 1.7,
        color: paper.accent,
        backgroundColor: paper.surfaceAlt,
        letterSpacing: 0,
      );
    }
    final color = attrs['color']?.toString();
    if (color != null && !checked) {
      final parsed = parseHex(color);
      if (parsed != null) style = style.copyWith(color: parsed);
    }
    final background = attrs['background']?.toString();
    if (background != null) {
      final parsed = parseHex(background);
      if (parsed != null) style = style.copyWith(backgroundColor: parsed);
    }
    if (attrs['link'] != null) {
      style = style.copyWith(
        color: paper.blue,
        decoration: TextDecoration.underline,
        decorationColor: paper.blue,
      );
    }
    return style;
  }

  String? _listPrefix(_Line line) => switch (line.list) {
    null => null,
    'ordered' => '${line.listNumber ?? 1}.  ',
    'checked' => '☑  ',
    'unchecked' => '☐  ',
    _ => '•  ',
  };

  Widget _codeView(_Line line, _Paper paper, double scale) {
    final base = TextStyle(
      fontFamily: 'SourceHanMono',
      fontFamilyFallback: const ['NotoSansSC', 'monospace'],
      fontSize: 12 * scale,
      height: 1.75,
      color: paper.soft,
    );
    final language = line.language ?? '';
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: 6 * scale),
      decoration: BoxDecoration(
        color: paper.surfaceAlt,
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: paper.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (language.isNotEmpty)
            Container(
              padding: EdgeInsets.fromLTRB(
                12 * scale,
                5 * scale,
                12 * scale,
                5 * scale,
              ),
              decoration: BoxDecoration(
                color: paper.surface,
                border: Border(bottom: BorderSide(color: paper.line)),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 7 * scale,
                    vertical: 2 * scale,
                  ),
                  decoration: BoxDecoration(
                    color: paper.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5 * scale),
                  ),
                  child: Text(
                    codeLanguageLabel(language),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 9 * scale,
                      fontWeight: FontWeight.w500,
                      color: paper.accent,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              12 * scale,
              9 * scale,
              12 * scale,
              11 * scale,
            ),
            child: Text.rich(
              TextSpan(
                children: codeHighlightSpans(
                  line.code ?? '',
                  language,
                  base: base,
                  theme: _codeTheme(paper),
                ),
                style: base,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Map<String, TextStyle> _codeTheme(_Paper paper) => {
    'keyword': TextStyle(color: paper.accent, fontWeight: FontWeight.w600),
    'built_in': TextStyle(color: paper.blue),
    'type': TextStyle(color: paper.blue),
    'literal': TextStyle(color: paper.gold),
    'number': TextStyle(color: paper.gold),
    'string': TextStyle(color: paper.sage),
    'comment': TextStyle(color: paper.soft, fontStyle: FontStyle.italic),
    'title': TextStyle(color: paper.ink, fontWeight: FontWeight.w600),
    'attr': TextStyle(color: paper.accent),
    'attribute': TextStyle(color: paper.blue),
    'variable': TextStyle(color: paper.soft),
    'meta': TextStyle(color: paper.soft),
    'symbol': TextStyle(color: paper.gold),
    'tag': TextStyle(color: paper.accent),
    'name': TextStyle(color: paper.accent),
    'selector-tag': TextStyle(color: paper.accent),
    'selector-class': TextStyle(color: paper.blue),
    'selector-id': TextStyle(color: paper.blue),
  };

  Widget _dividerView(_Paper paper, double scale) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12 * scale),
      child: Row(
        children: [
          Expanded(child: Container(height: 0.8, color: paper.line)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 9 * scale),
            child: Container(
              width: 4 * scale,
              height: 4 * scale,
              decoration: BoxDecoration(
                color: paper.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(child: Container(height: 0.8, color: paper.line)),
        ],
      ),
    );
  }

  Widget _imageView(_Line line, _Paper paper, double scale) {
    final bytes = images[line.imagePath];
    if (bytes == null) {
      return Text(
        _t('［图片］'),
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontSize: 10 * scale,
          color: paper.accent,
        ),
      );
    }
    final alignment = switch (line.imageAlign) {
      'center' => Alignment.center,
      'right' => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };
    final innerWidth = width - 84 * scale;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 10 * scale),
      child: Align(
        alignment: alignment,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6 * scale),
          child: Image.memory(
            bytes,
            width: innerWidth * line.imageWidth.clamp(0.2, 1.0),
            cacheWidth:
                (innerWidth * line.imageWidth.clamp(0.2, 1.0) * scale)
                    .round()
                    .clamp(64, 4096),
            fit: BoxFit.fitWidth,
          ),
        ),
      ),
    );
  }
}

enum _LineKind { text, code, divider, image }

class _Run {
  const _Run(this.text, this.attrs);
  final String text;
  final Map<String, dynamic> attrs;
}

class _Line {
  _Line({
    this.kind = _LineKind.text,
    this.runs = const [],
    this.header,
    this.quote = false,
    this.list,
    this.listNumber,
    this.align = 'left',
    this.indent = 0,
    this.code,
    this.language = '',
    this.imagePath,
    this.imageWidth = 1,
    this.imageAlign = 'left',
  });

  final _LineKind kind;
  final List<_Run> runs;
  final String? header;
  final bool quote;
  final String? list;
  final int? listNumber;
  final String align;
  final int indent;
  final String? code;
  final String? language;
  final String? imagePath;
  final double imageWidth;
  final String imageAlign;
}

class _Lines {
  _Lines(this.delta);
  final List<dynamic> delta;

  List<_Line> parse() {
    final lines = <_Line>[];
    var runs = <_Run>[];
    String? header;
    var quote = false;
    String? list;
    var align = 'left';
    var indent = 0;
    var legacyCode = false;
    var hadBreak = false;
    var ordered = 0;

    void flush() {
      final plain = runs.map((r) => r.text).join();
      if (legacyCode) {
        if (plain.trim().isNotEmpty) {
          lines.add(_Line(kind: _LineKind.code, code: plain));
        }
      } else if (runs.isNotEmpty ||
          header != null ||
          quote ||
          list != null ||
          hadBreak) {
        int? number;
        if (list == 'ordered') {
          ordered++;
          number = ordered;
        } else {
          ordered = 0;
        }
        lines.add(
          _Line(
            runs: List.of(runs),
            header: header,
            quote: quote,
            list: list,
            listNumber: number,
            align: align,
            indent: indent,
          ),
        );
      }
      runs = <_Run>[];
      header = null;
      quote = false;
      list = null;
      align = 'left';
      indent = 0;
      legacyCode = false;
      hadBreak = false;
    }

    void readBlock(Map<String, dynamic> attrs) {
      header = attrs['header']?.toString();
      quote = attrs['blockquote'] == true;
      list = attrs['list']?.toString();
      align = attrs['align']?.toString() ?? 'left';
      indent = int.tryParse(attrs['indent']?.toString() ?? '') ?? 0;
      legacyCode = attrs['code-block'] == true;
    }

    for (final op in delta) {
      if (op is! Map) continue;
      final insert = op['insert'];
      final attrs =
          (op['attributes'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      if (insert is String) {
        final parts = insert.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            runs.add(_Run(parts[i], attrs));
          }
          if (i < parts.length - 1) {
            readBlock(attrs);
            hadBreak = true;
            flush();
          }
        }
        continue;
      }
      if (insert is! Map) continue;
      final code = CodeBlockData.fromRaw(insert[codeBlockKey]);
      if (code != null) {
        flush();
        lines.add(
          _Line(
            kind: _LineKind.code,
            code: code.code,
            language: code.language,
          ),
        );
        continue;
      }
      final path = insert['image'];
      if (path is String && path.isNotEmpty) {
        flush();
        final width = double.tryParse(attrs[imageWidthKey]?.toString() ?? '');
        lines.add(
          _Line(
            kind: _LineKind.image,
            imagePath: path,
            imageWidth: (width ?? 1).clamp(0.2, 1.0),
            imageAlign: switch (attrs[imageAlignKey]?.toString()) {
              'center' => 'center',
              'right' => 'right',
              _ => 'left',
            },
          ),
        );
        continue;
      }
      if (insert['divider'] != null) {
        flush();
        lines.add(_Line(kind: _LineKind.divider));
      }
    }
    flush();

    // 旧版按行存储的代码块会拆成多行，这里接回去。
    final merged = <_Line>[];
    for (final line in lines) {
      if (line.kind == _LineKind.code &&
          merged.isNotEmpty &&
          merged.last.kind == _LineKind.code) {
        final previous = merged.removeLast();
        merged.add(
          _Line(
            kind: _LineKind.code,
            code: '${previous.code}\n${line.code}',
            language: (previous.language ?? '').isNotEmpty
                ? previous.language!
                : (line.language ?? ''),
          ),
        );
      } else {
        merged.add(line);
      }
    }
    return merged;
  }
}

String _safeName(String title) {
  final base = title.trim().isEmpty
      ? _t('此记-{stamp}', {'stamp': DateTime.now().millisecondsSinceEpoch})
      : title.trim();
  final clean = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  return clean.substring(0, clean.length > 50 ? 50 : clean.length);
}
