// K-MAPS: 属性テーブルウィジェット（リファクタリング版）
// PlutoGridを使用した属性テーブル表示・編集

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../providers/selection_providers.dart';
import '../../utils/app_logger.dart';
import 'attribute_table_controller.dart';
import 'attribute_table_toolbar.dart';
import 'attribute_table_dialogs.dart';
import 'attribute_form_view.dart';

/// 動的属性テーブルウィジェット（リファクタリング版）
class AttributeTableWidget extends ConsumerStatefulWidget {
  final LayerNode layer;
  final Function(FeatureNode feature)? onFeatureSelected;
  final Function()? onAddFeature;

  const AttributeTableWidget({
    super.key,
    required this.layer,
    this.onFeatureSelected,
    this.onAddFeature,
  });

  @override
  ConsumerState<AttributeTableWidget> createState() =>
      _AttributeTableWidgetState();
}

enum _ViewMode { table, form }

class _AttributeTableWidgetState extends ConsumerState<AttributeTableWidget> {
  late AttributeTableController _controller;
  Key _plutoGridKey = UniqueKey();
  Map<String, dynamic>? _columnStats;
  String? _statsColumnName;
  _ViewMode _viewMode = _ViewMode.table;

  @override
  void initState() {
    super.initState();
    _controller = AttributeTableController(widget.layer, ref);
    _controller.addListener(_onControllerChanged);
    _controller.initialize();
  }

  @override
  void didUpdateWidget(AttributeTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer != widget.layer) {
      _controller.removeListener(_onControllerChanged);
      _controller.dispose();
      _controller = AttributeTableController(widget.layer, ref);
      _controller.addListener(_onControllerChanged);
      _controller.initialize();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _rebuildGrid() {
    setState(() {
      _plutoGridKey = UniqueKey();
    });
    _controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    // 地図からの選択変更を監視してテーブル側に反映
    ref.listen<List<dynamic>>(selectedFeaturesProvider, (prev, next) {
      if (next.length == 1 && next.first is FeatureNode) {
        _controller.highlightFeatureOnCurrentPage(next.first as FeatureNode);
      }
    });

    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.lastError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              _controller.lastError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                _controller.clearError();
                _rebuildGrid();
              },
              child: const Text('再試行'),
            ),
          ],
        ),
      );
    }

    if (_controller.columns.isEmpty) {
      return const Center(child: Text('カラム定義がありません'));
    }

    return Column(
      children: [
        // ツールバー
        AttributeTableToolbar(
          controller: _controller,
          onRefresh: _rebuildGrid,
          onCopyTable: () => copyTableToClipboard(context, _controller),
          onAddFeature: widget.onAddFeature,
          onDeleteSelected: _handleDeleteSelected,
          onSave: _handleSave,
          onAddColumn:
              () => showAddColumnDialog(context, widget.layer, _rebuildGrid),
          onFieldCalculator:
              () => showFieldCalculatorDialog(
                context,
                widget.layer,
                _controller.columnNames,
                _rebuildGrid,
              ),
          onColumnAction: (columnName, action) {
            if (action == 'rename') {
              showRenameColumnDialog(
                context,
                widget.layer,
                columnName,
                _rebuildGrid,
              );
            } else if (action == 'delete') {
              showDeleteColumnDialog(
                context,
                widget.layer,
                columnName,
                _rebuildGrid,
              );
            }
          },
          onToggleView: () {
            setState(() {
              _viewMode =
                  _viewMode == _ViewMode.table
                      ? _ViewMode.form
                      : _ViewMode.table;
            });
          },
          isFormView: _viewMode == _ViewMode.form,
          onDuplicateFiltered:
              (filterSql) => showDuplicateFilteredDialog(
                context,
                widget.layer,
                filterSql,
                _rebuildGrid,
              ),
        ),

        // メインコンテンツ: テーブル or フォーム
        if (_viewMode == _ViewMode.form)
          Expanded(child: AttributeFormView(controller: _controller))
        else ...[
          Expanded(
            child: PlutoGrid(
              key: _plutoGridKey,
              columns: List.of(_controller.columns),
              rows: List.of(_controller.rows),
              mode: PlutoGridMode.normal,
              onLoaded: _onGridLoaded,
              onChanged: _onGridChanged,
              createFooter: (stateManager) {
                return PlutoLazyPagination(
                  initialPage: 1,
                  initialFetch: false,
                  fetchWithSorting: false,
                  fetchWithFiltering: false,
                  fetch: _controller.fetchPage,
                  stateManager: stateManager,
                );
              },
              configuration: _buildGridConfiguration(),
            ),
          ),

          // 統計サマリバー
          _buildStatisticsBar(),
        ],
      ],
    );
  }

  void _onGridLoaded(PlutoGridOnLoadedEvent event) {
    _controller.setStateManager(event.stateManager);
    event.stateManager.setSelectingMode(PlutoGridSelectingMode.cell);

    // セル選択時のフィーチャ選択処理
    event.stateManager.addListener(() {
      final currentRowIdx = event.stateManager.currentRowIdx;
      final currentCell = event.stateManager.currentCell;

      if (currentCell != null && currentRowIdx != null && currentRowIdx >= 0) {
        _controller.selectFeature(currentRowIdx);

        final absoluteIdx = _controller.currentPageOffset + currentRowIdx;
        if (absoluteIdx < _controller.features.length) {
          widget.onFeatureSelected?.call(_controller.features[absoluteIdx]);
        }
      }
    });
  }

  void _onGridChanged(PlutoGridOnChangedEvent event) async {
    final rowIndex = event.rowIdx;
    final field = event.column.field;
    final newValue = event.value;

    final absoluteIndex = _controller.currentPageOffset + rowIndex;
    if (absoluteIndex < _controller.features.length) {
      final feature = _controller.features[absoluteIndex];
      final error = await _controller.saveAttributeChange(
        feature,
        field,
        newValue,
      );
      if (error != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _handleDeleteSelected() async {
    await _controller.deleteSelectedFeatures();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('フィーチャを削除しました'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleSave() async {
    try {
      await widget.layer.geoPackageFile.flushChanges();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存完了'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[AttributeTableWidget] 保存エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存エラー: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildStatisticsBar() {
    final editableColumns =
        _controller.columnNames.where((c) => !c.startsWith('_')).toList();

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 20,
            child: DropdownButtonFormField<String>(
              initialValue: _statsColumnName,
              isDense: true,
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 4),
                border: InputBorder.none,
                isDense: true,
              ),
              style: const TextStyle(fontSize: 10, color: Colors.black87),
              hint: const Text('統計カラム', style: TextStyle(fontSize: 10)),
              items:
                  editableColumns
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          child: Text(c, style: const TextStyle(fontSize: 10)),
                        ),
                      )
                      .toList(),
              onChanged: (v) async {
                if (v != null) {
                  final stats = await _controller.getColumnStatistics(v);
                  setState(() {
                    _statsColumnName = v;
                    _columnStats = stats;
                  });
                }
              },
            ),
          ),
          if (_columnStats != null) ...[
            const SizedBox(width: 8),
            _buildStatChip('件数', '${_columnStats!['count']}'),
            _buildStatChip('ユニーク', '${_columnStats!['unique']}'),
            if (_columnStats!['sum'] != null)
              _buildStatChip('合計', _formatStat(_columnStats!['sum'])),
            if (_columnStats!['avg'] != null)
              _buildStatChip('平均', _formatStat(_columnStats!['avg'])),
            _buildStatChip('最小', '${_columnStats!['min'] ?? '-'}'),
            _buildStatChip('最大', '${_columnStats!['max'] ?? '-'}'),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Text(
        '$label: $value',
        style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
      ),
    );
  }

  String _formatStat(dynamic value) {
    if (value is double) return value.toStringAsFixed(2);
    return '$value';
  }

  PlutoGridConfiguration _buildGridConfiguration() {
    return PlutoGridConfiguration(
      columnSize: const PlutoGridColumnSizeConfig(
        autoSizeMode: PlutoAutoSizeMode.none,
        resizeMode: PlutoResizeMode.normal,
      ),
      style: PlutoGridStyleConfig(
        rowHeight: 20,
        columnHeight: 22,
        cellTextStyle: const TextStyle(fontSize: 10, height: 1.1),
        columnTextStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1.1,
        ),
        borderColor: Colors.grey.shade300,
        activatedBorderColor: Colors.blue.shade300,
        evenRowColor: Colors.grey.shade50,
        oddRowColor: Colors.white,
      ),
      scrollbar: const PlutoGridScrollbarConfig(
        scrollbarThickness: 8,
        scrollbarThicknessWhileDragging: 10,
      ),
      shortcut: const PlutoGridShortcut(actions: {}),
      enterKeyAction: PlutoGridEnterKeyAction.none,
    );
  }
}
