// K-MAPS: 属性テーブルウィジェット（リファクタリング版）
// PlutoGridを使用した属性テーブル表示・編集

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../utils/app_logger.dart';
import 'attribute_table_controller.dart';
import 'attribute_table_toolbar.dart';
import 'attribute_table_dialogs.dart';

/// 動的属性テーブルウィジェット（リファクタリング版）
class AttributeTableWidget extends ConsumerStatefulWidget {
  final LayerNode layer;
  final Function(FeatureNode feature)? onFeatureSelected;
  final Function(FeatureNode feature)? onFeatureDeleted;
  final Function()? onAddFeature;

  const AttributeTableWidget({
    super.key,
    required this.layer,
    this.onFeatureSelected,
    this.onFeatureDeleted,
    this.onAddFeature,
  });

  @override
  ConsumerState<AttributeTableWidget> createState() => _AttributeTableWidgetState();
}

class _AttributeTableWidgetState extends ConsumerState<AttributeTableWidget> {
  late AttributeTableController _controller;
  Key _plutoGridKey = UniqueKey();

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
    if (_controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
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
          onAddColumn: () => showAddColumnDialog(
            context,
            widget.layer,
            _rebuildGrid,
          ),
          onDuplicateFiltered: (filterSql) => showDuplicateFilteredDialog(
            context,
            widget.layer,
            filterSql,
            _rebuildGrid,
          ),
        ),

        // PlutoGrid
        Expanded(
          child: PlutoGrid(
            key: _plutoGridKey,
            columns: List.of(_controller.columns),
            rows: List.of(_controller.rows),
            mode: PlutoGridMode.normal,
            onLoaded: _onGridLoaded,
            onChanged: _onGridChanged,
            configuration: _buildGridConfiguration(),
          ),
        ),
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
        
        if (currentRowIdx < _controller.features.length) {
          widget.onFeatureSelected?.call(_controller.features[currentRowIdx]);
        }
      }
    });
  }

  void _onGridChanged(PlutoGridOnChangedEvent event) async {
    final rowIndex = event.rowIdx;
    final field = event.column.field;
    final newValue = event.value;

    if (rowIndex < _controller.features.length) {
      final feature = _controller.features[rowIndex];
      await _controller.saveAttributeChange(feature, field, newValue);
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
