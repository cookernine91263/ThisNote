import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';

const String tableKey = 'table';

const Map<String, String> _en = <String, String>{
  '表格': 'Table',
  '编辑表格': 'Edit table',
  '首行是表头': 'First row is a header',
  '取消': 'Cancel',
  '保存': 'Save',
  '插入表格': 'Insert table',
  '删除表格': 'Delete table',
  '添加行': 'Add row',
  '添加列': 'Add column',
  '删除末行': 'Remove last row',
  '删除末列': 'Remove last column',
  '行': 'rows',
  '列': 'columns',
};

String _t(String zh, [Map<String, Object?>? args]) => tr(zh, args, _en);

class TableData {
  TableData({required this.rows, this.header = true});

  final List<List<String>> rows;
  final bool header;

  static TableData blank() => TableData(
    rows: [
      ['', '', ''],
      ['', '', ''],
      ['', '', ''],
    ],
  );

  Map<String, dynamic> toJson() => {'rows': rows, 'header': header};

  static TableData? fromRaw(Object? raw) {
    if (raw == null) return null;
    if (raw is Map) return _fromMap(raw.cast<String, dynamic>());
    try {
      final decoded = jsonDecode(raw.toString());
      if (decoded is Map) return _fromMap(decoded.cast<String, dynamic>());
    } catch (_) {}
    return null;
  }

  static TableData? _fromMap(Map<String, dynamic> json) {
    final rawRows = json['rows'];
    if (rawRows is! List) return null;
    final rows = <List<String>>[];
    for (final row in rawRows) {
      if (row is List) {
        rows.add(row.map((cell) => cell?.toString() ?? '').toList());
      }
    }
    if (rows.isEmpty) rows.add(['']);
    final width = rows.fold<int>(
      1,
      (w, row) => row.length > w ? row.length : w,
    );
    for (var i = 0; i < rows.length; i++) {
      while (rows[i].length < width) {
        rows[i].add('');
      }
    }
    return TableData(rows: rows, header: json['header'] == true);
  }

  String get plainText => rows.map((row) => row.join('\t')).join('\n');
}

TableData? tableOf(Embeddable embed) {
  if (embed.type != tableKey) return null;
  return TableData.fromRaw(embed.data);
}

BlockEmbed tableEmbed(TableData data) =>
    BlockEmbed(tableKey, jsonEncode(data.toJson()));

class TableEmbedBuilder extends EmbedBuilder {
  const TableEmbedBuilder();

  @override
  String get key => tableKey;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) => tableOf(node.value)?.plainText ?? '';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final data = tableOf(embedContext.node.value);
    if (data == null) return const SizedBox.shrink();
    return _TableCard(
      data: data,
      controller: embedContext.controller,
      offset: embedContext.node.documentOffset,
    );
  }
}

Future<void> insertTable(
  BuildContext context,
  QuillController controller,
) async {
  final selection = controller.selection;
  if (!selection.isValid) return;
  final data = await showTableEditor(context);
  if (data == null) return;
  final offset = selection.start;
  controller.replaceText(
    offset,
    selection.end - offset,
    tableEmbed(data),
    TextSelection.collapsed(offset: offset + 1),
  );
}

class _TableCard extends StatelessWidget {
  const _TableCard({
    required this.data,
    required this.controller,
    required this.offset,
  });

  final TableData data;
  final QuillController controller;
  final int offset;

  Future<void> _edit(BuildContext context) async {
    final next = await showTableEditor(context, initial: data);
    if (next == null) return;
    controller.replaceText(
      offset,
      1,
      tableEmbed(next),
      TextSelection.collapsed(offset: offset + 1),
    );
  }

  void _delete() {
    controller.replaceText(
      offset,
      1,
      '',
      TextSelection.collapsed(offset: offset),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 4),
              child: Row(
                children: [
                  Icon(LucideIcons.table, size: 13, color: c.inkMuted),
                  const SizedBox(width: 6),
                  Text(
                    _t('表格'),
                    style: TextStyle(
                      fontFamily: 'NotoSansSC',
                      fontSize: 10,
                      color: c.inkMuted,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  SoftIconButton(
                    icon: LucideIcons.penLine,
                    tooltip: _t('编辑表格'),
                    size: 26,
                    iconSize: 13,
                    onPressed: () => _edit(context),
                  ),
                  SoftIconButton(
                    icon: LucideIcons.trash2,
                    tooltip: _t('删除表格'),
                    size: 26,
                    iconSize: 13,
                    onPressed: _delete,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Table(
                border: TableBorder.all(color: c.line, width: 0.7),
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                children: [
                  for (var row = 0; row < data.rows.length; row++)
                    TableRow(
                      decoration: data.header && row == 0
                          ? BoxDecoration(color: c.surfaceAlt)
                          : null,
                      children: [
                        for (final cell in data.rows[row])
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 6,
                            ),
                            child: Text(
                              cell,
                              style: TextStyle(
                                fontFamily: 'NotoSansSC',
                                fontSize: 11,
                                height: 1.5,
                                fontWeight: data.header && row == 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: c.ink,
                              ),
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
    );
  }
}

Future<TableData?> showTableEditor(BuildContext context, {TableData? initial}) {
  return showDialog<TableData>(
    context: context,
    builder: (_) => _TableEditor(initial: initial ?? TableData.blank()),
  );
}

class _TableEditor extends StatefulWidget {
  const _TableEditor({required this.initial});

  final TableData initial;

  @override
  State<_TableEditor> createState() => _TableEditorState();
}

class _TableEditorState extends State<_TableEditor> {
  /// 每个单元格一个控制器，行列增删时同步创建 / 释放。
  late final List<List<TextEditingController>> _cells;
  final ScrollController _rowsScroll = ScrollController();
  final ScrollController _colsScroll = ScrollController();
  late bool _header = widget.initial.header;

  static const double _minCellWidth = 108;
  static const double _cellHeight = 36;

  int get _rows => _cells.length;
  int get _cols => _cells.isEmpty ? 0 : _cells.first.length;

  @override
  void initState() {
    super.initState();
    // initial 里的行可能长短不一，先补成矩形，保证每个格子都有输入框。
    final source = widget.initial.rows;
    final rows = source.isEmpty ? 1 : source.length;
    var cols = 1;
    for (final row in source) {
      if (row.length > cols) cols = row.length;
    }
    _cells = List.generate(
      rows,
      (r) => List.generate(
        cols,
        (col) => TextEditingController(
          text: r < source.length && col < source[r].length
              ? source[r][col]
              : '',
        ),
      ),
    );
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final cell in row) {
        cell.dispose();
      }
    }
    _rowsScroll.dispose();
    _colsScroll.dispose();
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _cells.add(List.generate(_cols, (_) => TextEditingController()));
    });
  }

  void _addColumn() {
    setState(() {
      for (final row in _cells) {
        row.add(TextEditingController());
      }
    });
  }

  void _removeRow() {
    if (_rows <= 1) return;
    setState(() {
      for (final cell in _cells.removeLast()) {
        cell.dispose();
      }
    });
  }

  void _removeColumn() {
    if (_cols <= 1) return;
    setState(() {
      for (final row in _cells) {
        row.removeLast().dispose();
      }
    });
  }

  /// 单行输入框里不该出现换行；其余字符（含空格）原样保留。
  static String _clean(String text) => text.replaceAll(RegExp(r'[\r\n]+'), ' ');

  TableData _collect() {
    final rows = <List<String>>[
      for (final row in _cells) [for (final cell in row) _clean(cell.text)],
    ];
    if (rows.isEmpty) rows.add(<String>['']);
    if (rows.first.isEmpty) {
      for (final row in rows) {
        row.add('');
      }
    }
    return TableData(rows: rows, header: _header);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppPalette.of(context);
    final media = MediaQuery.of(context);
    // 宽高都跟着窗口收，窄窗口里也不会把对话框撑破。
    final width = math.min(640.0, math.max(280.0, media.size.width - 120));
    final height = math.min(460.0, math.max(180.0, media.size.height - 240));
    return AlertDialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.line),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
      actionsPadding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
      title: Row(
        children: [
          Icon(LucideIcons.table, size: 17, color: c.accent),
          const SizedBox(width: 8),
          Text(
            _t('编辑表格'),
            style: TextStyle(fontFamily: 'WenKai', fontSize: 21, color: c.ink),
          ),
        ],
      ),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 按钮用 Wrap：窗口再窄也只换行，不会横向溢出。
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SoftButton(
                  key: const ValueKey('table-add-row'),
                  dense: true,
                  icon: LucideIcons.plus,
                  label: _t('添加行'),
                  onPressed: _addRow,
                ),
                SoftButton(
                  key: const ValueKey('table-add-column'),
                  dense: true,
                  icon: LucideIcons.columns2,
                  label: _t('添加列'),
                  onPressed: _addColumn,
                ),
                SoftButton(
                  key: const ValueKey('table-remove-row'),
                  dense: true,
                  icon: LucideIcons.minus,
                  label: _t('删除末行'),
                  onPressed: _rows > 1 ? _removeRow : null,
                ),
                SoftButton(
                  key: const ValueKey('table-remove-column'),
                  dense: true,
                  icon: LucideIcons.trash2,
                  label: _t('删除末列'),
                  onPressed: _cols > 1 ? _removeColumn : null,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 有界高度只给这一块：里面的单元格网格可以双向滚动。
            Expanded(child: _grid(c)),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      key: const ValueKey('table-header-toggle'),
                      onTap: () => setState(() => _header = !_header),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 5,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _header
                                  ? LucideIcons.checkSquare
                                  : LucideIcons.square,
                              size: 15,
                              color: _header ? c.accent : c.inkMuted,
                            ),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                _t('首行是表头'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'NotoSansSC',
                                  fontSize: 11.5,
                                  color: c.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_rows ${_t('行')} × $_cols ${_t('列')}',
                  style: TextStyle(
                    fontFamily: 'NotoSansSC',
                    fontSize: 11,
                    color: c.inkMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            _t('取消'),
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 12,
              color: c.inkMuted,
            ),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_collect()),
          child: Text(
            _t('保存'),
            style: TextStyle(
              fontFamily: 'NotoSansSC',
              fontSize: 12,
              color: c.accent,
            ),
          ),
        ),
      ],
    );
  }

  /// 可见的单元格网格：每个格子都是一个带边框的小输入框，
  /// 空表格也能看出行列结构。
  Widget _grid(AppPalette c) {
    final cols = _cols;
    return Container(
      decoration: BoxDecoration(
        color: c.paper,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 列少时铺满宽度，列多时保持最小列宽并横向滚动。
          final cellWidth = math.max(
            _minCellWidth,
            (constraints.maxWidth - 2) / cols,
          );
          final totalWidth = cellWidth * cols;
          return Scrollbar(
            controller: _colsScroll,
            child: SingleChildScrollView(
              controller: _colsScroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: math.max(totalWidth, constraints.maxWidth),
                child: Scrollbar(
                  controller: _rowsScroll,
                  child: SingleChildScrollView(
                    controller: _rowsScroll,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var row = 0; row < _rows; row++)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (var col = 0; col < cols; col++)
                                _cell(c, row, col, cellWidth),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _cell(AppPalette c, int row, int col, double width) {
    final isHeader = _header && row == 0;
    return Container(
      width: width,
      height: _cellHeight,
      decoration: BoxDecoration(
        // 表头行稍深，并加粗字重。
        color: isHeader ? c.surfaceAlt : c.paper,
        border: Border(
          right: BorderSide(color: c.line, width: 0.8),
          bottom: BorderSide(color: c.line, width: 0.8),
        ),
      ),
      child: TextField(
        key: ValueKey('table-cell-$row-$col'),
        controller: _cells[row][col],
        maxLines: 1,
        autofocus: row == 0 && col == 0,
        cursorWidth: 1.2,
        style: TextStyle(
          fontFamily: 'NotoSansSC',
          fontFamilyFallback: AppTypography.fallback,
          fontSize: 12,
          height: 1.3,
          fontWeight: isHeader ? FontWeight.w600 : FontWeight.w400,
          color: c.ink,
        ),
        textAlignVertical: TextAlignVertical.center,
        // Tab 的默认焦点遍历即可在单元格之间移动。
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 9,
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          hintText: '',
        ),
      ),
    );
  }
}
