// K-MAPS: 属性テーブルツールバー
// 座標系選択、各種操作ボタンを提供

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/coordinate/index.dart';
import '../../utils/app_logger.dart';
import 'attribute_table_controller.dart';

/// 属性テーブルツールバー
class AttributeTableToolbar extends StatefulWidget {
  final AttributeTableController controller;
  final VoidCallback? onRefresh;
  final VoidCallback? onCopyTable;
  final VoidCallback? onAddFeature;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onSave;
  final VoidCallback? onAddColumn;
  final VoidCallback? onFieldCalculator;
  final void Function(String columnName, String action)? onColumnAction;
  final VoidCallback? onToggleView;
  final bool isFormView;
  final Future<void> Function(String expression)? onDuplicateFiltered;

  const AttributeTableToolbar({
    super.key,
    required this.controller,
    this.onRefresh,
    this.onCopyTable,
    this.onAddFeature,
    this.onDeleteSelected,
    this.onSave,
    this.onAddColumn,
    this.onFieldCalculator,
    this.onColumnAction,
    this.onToggleView,
    this.isFormView = false,
    this.onDuplicateFiltered,
  });

  @override
  State<AttributeTableToolbar> createState() => _AttributeTableToolbarState();
}

class _AttributeTableToolbarState extends State<AttributeTableToolbar> {
  final _filterController = TextEditingController();
  bool _isFilterApplied = false;

  // 検索・置換
  bool _showSearchReplace = false;
  final _searchController = TextEditingController();
  final _replaceController = TextEditingController();
  String? _selectedReplaceColumn;
  int _searchResultCount = 0;

  @override
  void dispose() {
    _filterController.dispose();
    _searchController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  Future<void> _applyFilter() async {
    final expression = _filterController.text.trim();
    if (expression.isEmpty) {
      _clearFilter();
      return;
    }
    final error = await widget.controller.applyFilter(expression);
    setState(() => _isFilterApplied = error == null);
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('フィルタエラー: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _clearFilter() async {
    _filterController.clear();
    await widget.controller.clearFilter();
    setState(() => _isFilterApplied = false);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 上段: レイヤー名 + ボタン群
          Row(
            children: [
              Text(
                ctrl.isFiltered
                    ? '${ctrl.layer.layerName} (${ctrl.filteredCount}/${ctrl.totalCount})'
                    : '${ctrl.layer.layerName} (${ctrl.totalCount})',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 9,
                  height: 1.0,
                  color: ctrl.isFiltered ? Colors.orange.shade800 : null,
                ),
              ),

              if (ctrl.isPointLayer) ...[
                const SizedBox(width: 8),
                _buildWgs84Checkbox(context),
                const SizedBox(width: 8),
                _buildEpsgSelector(context),
              ],

              const Spacer(),

              _buildIconButton(
                Icons.calculate,
                Colors.deepPurple,
                widget.onFieldCalculator,
                'フィールド計算機',
              ),
              _buildColumnMenuButton(context),
              _buildIconButton(
                Icons.add_box,
                Colors.blue,
                widget.onAddColumn,
                'カラム追加',
              ),
              _buildIconButton(Icons.refresh, null, widget.onRefresh, '更新'),
              _buildIconButton(
                Icons.find_replace,
                _showSearchReplace ? Colors.orange : null,
                () => setState(() => _showSearchReplace = !_showSearchReplace),
                '検索・置換',
              ),
              _buildIconButton(
                Icons.copy,
                null,
                widget.onCopyTable,
                'テーブルをコピー',
              ),
              if (widget.onAddFeature != null)
                _buildIconButton(
                  Icons.add,
                  null,
                  widget.onAddFeature,
                  'フィーチャ追加',
                ),
              _buildIconButton(
                Icons.delete,
                Colors.red,
                widget.onDeleteSelected,
                '選択フィーチャ削除',
              ),
              _buildIconButton(Icons.save, null, widget.onSave, '即座に保存'),
              _buildIconButton(
                widget.isFormView ? Icons.table_chart : Icons.article,
                widget.isFormView ? Colors.orange : null,
                widget.onToggleView,
                widget.isFormView ? 'テーブル表示' : 'フォーム表示',
              ),
            ],
          ),
          // 下段: フィルタバー
          _buildFilterBar(context),
          // 検索・置換バー
          if (_showSearchReplace) _buildSearchReplaceBar(context),
        ],
      ),
    );
  }

  Widget _buildFilterBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Icon(
              Icons.filter_alt,
              size: 14,
              color: _isFilterApplied ? Colors.orange : Colors.grey,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: _filterController,
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: '"name" = \'Tokyo\'  |  "pop" > 1000',
                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                  ),
                  suffixIcon:
                      _isFilterApplied
                          ? GestureDetector(
                            onTap: _clearFilter,
                            child: Icon(
                              Icons.clear,
                              size: 14,
                              color: Colors.orange.shade700,
                            ),
                          )
                          : null,
                ),
                onSubmitted: (_) => _applyFilter(),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 24,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.blue,
                ),
                onPressed: _applyFilter,
                child: const Text('適用', style: TextStyle(fontSize: 11)),
              ),
            ),
            if (_isFilterApplied && widget.onDuplicateFiltered != null) ...[
              const SizedBox(width: 2),
              SizedBox(
                height: 24,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: Colors.green.shade700,
                  ),
                  icon: const Icon(Icons.copy_all, size: 14),
                  label: const Text('複製', style: TextStyle(fontSize: 11)),
                  onPressed: () {
                    widget.onDuplicateFiltered?.call(
                      widget.controller.filterSql,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchReplaceBar(BuildContext context) {
    final ctrl = widget.controller;
    final editableColumns =
        ctrl.columnNames.where((c) => !c.startsWith('_')).toList();

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            Icon(Icons.search, size: 14, color: Colors.blue.shade700),
            const SizedBox(width: 4),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: '検索...',
                  hintStyle: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade400,
                  ),
                ),
                onSubmitted: (_) => _doSearch(),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _replaceController,
                style: const TextStyle(fontSize: 11),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  hintText: '置換...',
                  hintStyle: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade400,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 100,
              height: 24,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedReplaceColumn,
                isDense: true,
                isExpanded: true,
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontSize: 10, color: Colors.black87),
                hint: const Text('カラム', style: TextStyle(fontSize: 10)),
                items:
                    editableColumns
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => _selectedReplaceColumn = v),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              height: 22,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: _doSearch,
                child: const Text('検索', style: TextStyle(fontSize: 10)),
              ),
            ),
            SizedBox(
              height: 22,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: Colors.orange.shade800,
                ),
                onPressed: _doReplace,
                child: const Text('置換', style: TextStyle(fontSize: 10)),
              ),
            ),
            if (_searchResultCount > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '$_searchResultCount件',
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _doSearch() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) return;
    final results = await widget.controller.searchText(text);
    setState(() => _searchResultCount = results.length);
    if (mounted && results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('該当なし'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _doReplace() async {
    final search = _searchController.text.trim();
    final replace = _replaceController.text;
    final column = _selectedReplaceColumn;
    if (search.isEmpty || column == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('検索テキストと対象カラムを指定してください'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    try {
      final count = await widget.controller.replaceText(
        column,
        search,
        replace,
      );
      setState(() => _searchResultCount = 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count件を置換しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('置換エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildWgs84Checkbox(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: widget.controller.settings.showWgs84,
              onChanged: (value) {
                widget.controller.updateSettings(
                  widget.controller.settings.copyWith(showWgs84: value ?? true),
                );
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Text('WGS84', style: TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildEpsgSelector(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 22,
      child: _EpsgAutocomplete(
        initialValue: widget.controller.settings.additionalEpsg,
        onSelected: (epsg) {
          widget.controller.updateSettings(
            widget.controller.settings.copyWith(additionalEpsg: epsg),
          );
        },
        onCleared: () {
          widget.controller.updateSettings(
            widget.controller.settings.copyWith(clearAdditionalEpsg: true),
          );
        },
      ),
    );
  }

  Widget _buildColumnMenuButton(BuildContext context) {
    final ctrl = widget.controller;
    final editableColumns =
        ctrl.columnNames.where((c) => !c.startsWith('_')).toList();

    return SizedBox(
      width: 20,
      height: 20,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        iconSize: 12,
        icon: const Icon(Icons.view_column, size: 12),
        tooltip: 'カラム管理',
        itemBuilder: (ctx) {
          final items = <PopupMenuEntry<String>>[];

          if (ctrl.hiddenColumns.isNotEmpty) {
            items.add(
              const PopupMenuItem(
                value: '__show_all__',
                child: Text(
                  '全て表示',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            );
            items.add(const PopupMenuDivider());
          }

          for (final col in editableColumns) {
            final hidden = ctrl.hiddenColumns.contains(col);
            items.add(
              PopupMenuItem(
                value: 'toggle:$col',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hidden ? Icons.visibility_off : Icons.visibility,
                      size: 14,
                      color: hidden ? Colors.grey : Colors.blue,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(col, style: const TextStyle(fontSize: 12)),
                    ),
                    PopupMenuButton<String>(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      icon: const Icon(Icons.more_vert, size: 14),
                      itemBuilder:
                          (_) => [
                            PopupMenuItem(
                              value: 'rename:$col',
                              child: const Text(
                                '名前変更',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete:$col',
                              child: Text(
                                '削除',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                      onSelected: (val) {
                        Navigator.of(ctx).pop(val);
                      },
                    ),
                  ],
                ),
              ),
            );
          }
          return items;
        },
        onSelected: (value) {
          if (value == '__show_all__') {
            ctrl.showAllColumns();
          } else if (value.startsWith('toggle:')) {
            ctrl.toggleColumnVisibility(value.substring(7));
          } else if (value.startsWith('rename:') ||
              value.startsWith('delete:')) {
            final parts = value.split(':');
            widget.onColumnAction?.call(parts[1], parts[0]);
          }
        },
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    Color? color,
    VoidCallback? onPressed,
    String tooltip,
  ) {
    return SizedBox(
      width: 20,
      height: 20,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 12,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}

/// EPSG座標系オートコンプリート
class _EpsgAutocomplete extends StatefulWidget {
  final EpsgDefinition? initialValue;
  final ValueChanged<EpsgDefinition> onSelected;
  final VoidCallback onCleared;

  const _EpsgAutocomplete({
    this.initialValue,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  State<_EpsgAutocomplete> createState() => _EpsgAutocompleteState();
}

class _EpsgAutocompleteState extends State<_EpsgAutocomplete> {
  final _registry = EpsgRegistry.instance;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.displayString ?? '',
    );
  }

  @override
  void didUpdateWidget(_EpsgAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue?.displayString ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<EpsgDefinition>(
      initialValue: TextEditingValue(text: _controller.text),
      optionsBuilder: (TextEditingValue value) {
        return _registry.search(value.text);
      },
      displayStringForOption: (option) => option.displayString,
      onSelected: (selection) {
        _controller.text = selection.displayString;
        widget.onSelected(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 8, height: 1.0),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: 2,
            ),
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: 'EPSG (例: 6677, IX系)',
            hintStyle: const TextStyle(fontSize: 8),
            suffixIcon:
                widget.initialValue != null
                    ? GestureDetector(
                      onTap: () {
                        controller.clear();
                        widget.onCleared();
                      },
                      child: const Icon(Icons.clear, size: 12),
                    )
                    : null,
          ),
          onSubmitted: (value) {
            final code = value.split(' ').first.trim();
            if (code.isNotEmpty) {
              final epsg = _registry.getByCode(code);
              if (epsg != null) {
                widget.onSelected(epsg);
              }
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 380),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        option.displayString,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// テーブルをTSV形式でクリップボードにコピー
Future<void> copyTableToClipboard(
  BuildContext context,
  AttributeTableController controller,
) async {
  try {
    final buffer = StringBuffer();

    // ヘッダー行
    final headerNames =
        controller.columns.map((c) => _escapeTsvValue(c.title)).toList();
    buffer.writeln(headerNames.join('\t'));

    // データ行
    for (final row in controller.rows) {
      final rowValues = <String>[];
      for (final column in controller.columns) {
        final cell = row.cells[column.field];
        final value = cell?.value?.toString() ?? '';
        rowValues.add(_escapeTsvValue(value));
      }
      buffer.writeln(rowValues.join('\t'));
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${controller.rows.length}行をクリップボードにコピーしました'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    AppLogger.debug('[AttributeTableToolbar] クリップボードコピーエラー: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('コピーエラー: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

String _escapeTsvValue(String value) {
  if (value.contains('\n') || value.contains('\t') || value.contains('"')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
