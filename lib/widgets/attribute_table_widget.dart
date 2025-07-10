// K-MAPS: 属性テーブル表示・編集ウィジェット
// PlutoGridを使用したフィーチャ属性の表示・編集機能
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../models/layer_tree_node.dart';
import '../utils/wkb_utils.dart';

/// 属性テーブル表示・編集ウィジェット
class AttributeTableWidget extends StatefulWidget {
  final LayerTreeNode layer;
  final List<Map<String, dynamic>> features;
  final Function(Map<String, dynamic> feature)? onFeatureSelected;
  final Function(Map<String, dynamic> feature, String field, dynamic value)?
  onAttributeChanged;
  final Function(Map<String, dynamic> feature)? onFeatureDeleted;
  final Function()? onAddFeature;

  const AttributeTableWidget({
    Key? key,
    required this.layer,
    required this.features,
    this.onFeatureSelected,
    this.onAttributeChanged,
    this.onFeatureDeleted,
    this.onAddFeature,
  }) : super(key: key);

  @override
  State<AttributeTableWidget> createState() => _AttributeTableWidgetState();
}

class _AttributeTableWidgetState extends State<AttributeTableWidget> {
  late PlutoGridStateManager stateManager;
  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];

  // 選択されたフィーチャのID
  Set<int> selectedFeatureIds = {};

  @override
  void initState() {
    super.initState();
    _initializeTableData();
  }

  @override
  void didUpdateWidget(AttributeTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.features != widget.features) {
      _initializeTableData();
      // PlutoGridが既に初期化されている場合、データを更新
      if (stateManager != null) {
        stateManager.removeAllRows();
        stateManager.appendRows(rows);
      }
    }
  }

  /// テーブルデータを初期化
  void _initializeTableData() {
    columns = _createColumns();
    rows = _createRows();
  }

  /// カラム定義を作成
  List<PlutoColumn> _createColumns() {
    if (widget.features.isEmpty) {
      return [
        PlutoColumn(
          title: 'No Data',
          field: 'no_data',
          type: PlutoColumnType.text(),
          enableEditingMode: false,
        ),
      ];
    }

    final List<PlutoColumn> tableColumns = [];
    final Set<String> fieldNames = {};

    // 基本カラム（ID、ジオメトリタイプ）
    tableColumns.add(
      PlutoColumn(
        title: 'ID',
        field: 'id',
        type: PlutoColumnType.number(),
        enableEditingMode: false,
        width: 80,
      ),
    );

    tableColumns.add(
      PlutoColumn(
        title: 'Type',
        field: 'geometry_type',
        type: PlutoColumnType.text(),
        enableEditingMode: false,
        width: 100,
      ),
    );

    // 全フィーチャの属性フィールドを収集
    for (final feature in widget.features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      fieldNames.addAll(metadata.keys);
    }

    // 属性フィールドのカラムを作成
    for (final fieldName in fieldNames) {
      final columnType = _determineColumnType(fieldName);

      tableColumns.add(
        PlutoColumn(
          title: fieldName,
          field: fieldName,
          type: columnType,
          enableEditingMode: true,
          width: 150,
        ),
      );
    }

    return tableColumns;
  }

  /// フィールドタイプからPlutoColumnTypeを決定
  PlutoColumnType _determineColumnType(String fieldName) {
    // フィールド名や値からタイプを推定
    final lowerName = fieldName.toLowerCase();

    if (lowerName.contains('date') || lowerName.contains('time')) {
      return PlutoColumnType.date();
    } else if (lowerName.contains('number') ||
        lowerName.contains('count') ||
        lowerName.contains('id') ||
        lowerName.contains('size')) {
      return PlutoColumnType.number();
    } else {
      return PlutoColumnType.text();
    }
  }

  /// 行データを作成
  List<PlutoRow> _createRows() {
    if (widget.features.isEmpty) {
      return [
        PlutoRow(cells: {'no_data': PlutoCell(value: 'No features available')}),
      ];
    }

    final List<PlutoRow> tableRows = [];

    for (final feature in widget.features) {
      final Map<String, PlutoCell> cells = {};

      // ID
      cells['id'] = PlutoCell(value: feature['id'] ?? 0);

      // ジオメトリタイプ
      final geometry = feature['geometry'] as Map<String, dynamic>?;
      final geometryType = geometry?['type'] ?? 'Unknown';
      cells['geometry_type'] = PlutoCell(value: geometryType);

      // 属性データ
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      for (final entry in metadata.entries) {
        cells[entry.key] = PlutoCell(value: entry.value ?? '');
      }

      // 空のフィールドを埋める
      for (final column in columns) {
        if (!cells.containsKey(column.field)) {
          cells[column.field] = PlutoCell(value: '');
        }
      }

      tableRows.add(PlutoRow(cells: cells));
    }

    return tableRows;
  }

  /// 選択されたフィーチャを取得
  List<Map<String, dynamic>> _getSelectedFeatures() {
    final selectedRows = stateManager.checkedRows;
    final selectedFeatures = <Map<String, dynamic>>[];

    for (final row in selectedRows) {
      final featureId = row.cells['id']?.value;
      if (featureId != null) {
        final feature = widget.features.firstWhere(
          (f) => f['id'] == featureId,
          orElse: () => <String, dynamic>{},
        );
        if (feature.isNotEmpty) {
          selectedFeatures.add(feature);
        }
      }
    }

    return selectedFeatures;
  }

  /// 選択されたフィーチャを削除
  void _deleteSelectedFeatures() {
    final selectedFeatures = _getSelectedFeatures();
    if (selectedFeatures.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('削除するフィーチャを選択してください')));
      return;
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('フィーチャ削除'),
            content: Text('選択された${selectedFeatures.length}個のフィーチャを削除しますか？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  for (final feature in selectedFeatures) {
                    widget.onFeatureDeleted?.call(feature);
                  }
                },
                child: const Text('削除'),
              ),
            ],
          ),
    );
  }

  /// 新しいフィーチャを追加
  void _addNewFeature() {
    widget.onAddFeature?.call();
  }

  /// CSVエクスポート
  void _exportToCsv() {
    // TODO: CSV エクスポート機能の実装
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('CSV Export feature coming soon')),
    );
  }

  /// 属性フィルター設定
  void _showAttributeFilter() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('属性フィルター'),
            content: const Text('属性フィルター機能は開発中です。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  /// 属性値をデータベースに保存
  Future<void> _saveAttributeChange(
    Map<String, dynamic> feature,
    String field,
    dynamic value,
  ) async {
    try {
      print('[AttributeTable] 属性変更保存開始: field=$field, value=$value');

      // レイヤーノードを取得
      final layerNode = widget.layer as LayerNode;
      final geoPackageFile = layerNode.geoPackageFile;
      final layerName = layerNode.layerName;
      final featureId = feature['id'] as int;

      // 基本フィールドの処理
      if (field == 'id' || field == 'geometry_type') {
        // ID とジオメトリタイプは編集不可
        return;
      }

      // 属性値をデータベースに保存
      await geoPackageFile.updateFeatureAttribute(
        layerName,
        featureId,
        field,
        value,
      );

      // ローカルのフィーチャデータも更新
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      metadata[field] = value;
      feature['metadata'] = metadata;

      print('[AttributeTable] 属性変更保存成功: $field = $value');

      // 成功メッセージ
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('属性が保存されました: $field = $value'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('[AttributeTable] 属性変更保存エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('属性の保存に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.layer.name} - 属性テーブル'),
        backgroundColor: Colors.blue[100],
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addNewFeature,
            tooltip: '新しいフィーチャを追加',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteSelectedFeatures,
            tooltip: '選択したフィーチャを削除',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showAttributeFilter,
            tooltip: '属性フィルター',
          ),
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _exportToCsv,
            tooltip: 'CSV エクスポート',
          ),
        ],
      ),
      body: Column(
        children: [
          // 情報バー
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.grey[100],
            child: Row(
              children: [
                Text(
                  '総フィーチャ数: ${widget.features.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 20),
                Text(
                  '選択数: ${selectedFeatureIds.length}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // PlutoGrid
          Expanded(
            child: PlutoGrid(
              columns: columns,
              rows: rows,
              onLoaded: (PlutoGridOnLoadedEvent event) {
                stateManager = event.stateManager;

                // 列フィルターを有効化
                stateManager.setShowColumnFilter(true);

                // 行選択を有効化
                stateManager.setSelectingMode(PlutoGridSelectingMode.row);
              },
              onChanged: (PlutoGridOnChangedEvent event) {
                // セルの値が変更された時の処理
                final rowIndex = event.rowIdx;
                final field = event.column.field;
                final newValue = event.value;

                // ID フィールドから対応するフィーチャを特定
                final featureId =
                    stateManager.rows[rowIndex].cells['id']?.value;
                if (featureId != null) {
                  final feature = widget.features.firstWhere(
                    (f) => f['id'] == featureId,
                    orElse: () => <String, dynamic>{},
                  );

                  if (feature.isNotEmpty) {
                    // データベースに保存
                    _saveAttributeChange(feature, field, newValue);

                    // 旧コールバックも呼び出し（互換性のため）
                    if (widget.onAttributeChanged != null) {
                      widget.onAttributeChanged!(feature, field, newValue);
                    }
                  }
                }
              },
              onSelected: (PlutoGridOnSelectedEvent event) {
                // 行が選択された時の処理
                final selectedRow = event.row;
                if (selectedRow != null) {
                  final featureId = selectedRow.cells['id']?.value;
                  if (featureId != null) {
                    final feature = widget.features.firstWhere(
                      (f) => f['id'] == featureId,
                      orElse: () => <String, dynamic>{},
                    );

                    if (feature.isNotEmpty &&
                        widget.onFeatureSelected != null) {
                      widget.onFeatureSelected!(feature);
                    }
                  }
                }
              },
              configuration: PlutoGridConfiguration(
                style: PlutoGridStyleConfig(
                  // 基本スタイル設定のみ使用
                  gridBorderColor: Colors.grey[300]!,
                  gridBorderRadius: BorderRadius.circular(8),
                  columnTextStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                  rowColor: Colors.white,
                  activatedColor: Colors.blue[100]!,
                  activatedBorderColor: Colors.blue[300]!,
                  cellTextStyle: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  checkedColor: Colors.blue[200]!,
                ),
                columnSize: const PlutoGridColumnSizeConfig(
                  autoSizeMode: PlutoAutoSizeMode.scale,
                  resizeMode: PlutoResizeMode.pushAndPull,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 属性テーブルを表示するためのダイアログ
class AttributeTableDialog extends StatelessWidget {
  final LayerTreeNode layer;
  final List<Map<String, dynamic>> features;
  final Function(Map<String, dynamic> feature)? onFeatureSelected;
  final Function(Map<String, dynamic> feature, String field, dynamic value)?
  onAttributeChanged;
  final Function(Map<String, dynamic> feature)? onFeatureDeleted;
  final Function()? onAddFeature;

  const AttributeTableDialog({
    Key? key,
    required this.layer,
    required this.features,
    this.onFeatureSelected,
    this.onAttributeChanged,
    this.onFeatureDeleted,
    this.onAddFeature,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: AttributeTableWidget(
          layer: layer,
          features: features,
          onFeatureSelected: onFeatureSelected,
          onAttributeChanged: onAttributeChanged,
          onFeatureDeleted: onFeatureDeleted,
          onAddFeature: onAddFeature,
        ),
      ),
    );
  }
}
