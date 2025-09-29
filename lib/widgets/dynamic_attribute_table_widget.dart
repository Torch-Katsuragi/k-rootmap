// K-MAPS: 動的属性テーブル表示・編集ウィジェット
// LayerNodeから直接属性スキーマを取得して動的にテーブル構造を構築

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../utils/global_config.dart';

/// 動的属性テーブル表示・編集ウィジェット
/// LayerNodeのスキーマから動的にテーブル構造を構築
class DynamicAttributeTableWidget extends StatefulWidget {
  final LayerNode layer;
  final Function(FeatureNode feature)? onFeatureSelected;
  final Function(FeatureNode feature)? onFeatureDeleted;
  final Function()? onAddFeature;

  const DynamicAttributeTableWidget({
    Key? key,
    required this.layer,
    this.onFeatureSelected,
    this.onFeatureDeleted,
    this.onAddFeature,
  }) : super(key: key);

  @override
  State<DynamicAttributeTableWidget> createState() => _DynamicAttributeTableWidgetState();
}

class _DynamicAttributeTableWidgetState extends State<DynamicAttributeTableWidget> {
  PlutoGridStateManager? stateManager;
  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];
  List<String> columnNames = [];
  List<FeatureNode> features = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeTableData();
  }

  @override
  void didUpdateWidget(DynamicAttributeTableWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layer != widget.layer) {
      _initializeTableData();
    }
  }

  /// テーブルデータを初期化
  Future<void> _initializeTableData() async {
    if (!mounted) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      print('[DynamicAttributeTable] データ初期化開始: ${widget.layer.layerName}');

      // LayerNodeから属性カラム名を取得
      columnNames = await widget.layer.getAttributeColumnNames(getAll: true);
      print('[DynamicAttributeTable] カラム名取得: ${columnNames.length}個');

      // LayerNodeからFeatureNodeリストを取得
      features = widget.layer.features;
      print('[DynamicAttributeTable] フィーチャ取得: ${features.length}個');

      // カラムとデータを構築
      columns = _createColumns();
      rows = await _createRows();

      print('[DynamicAttributeTable] テーブル構築完了');
    } catch (e) {
      print('[DynamicAttributeTable] データ初期化エラー: $e');
      columnNames = [];
      features = [];
      columns = [];
      rows = [];
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// カラム定義を作成
  List<PlutoColumn> _createColumns() {
    if (columnNames.isEmpty) {
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

    // LayerNodeから取得したカラム名を基にカラムを作成
    for (final columnName in columnNames) {
      final columnType = _determineColumnType(columnName);
      final isEditable = _isColumnEditable(columnName);
      final columnWidth = _getColumnWidth(columnName);

      tableColumns.add(
        PlutoColumn(
          title: columnName,
          field: columnName,
          type: columnType,
          enableEditingMode: isEditable,
          width: columnWidth,
        ),
      );
    }

    return tableColumns;
  }

  /// 行データを作成
  Future<List<PlutoRow>> _createRows() async {
    if (features.isEmpty || columnNames.isEmpty) {
      return [
        PlutoRow(cells: {'no_data': PlutoCell(value: 'No features available')}),
      ];
    }

    final List<PlutoRow> tableRows = [];

    for (final feature in features) {
      final Map<String, PlutoCell> cells = {};

      // 各カラムの値をFeatureNodeから取得
      for (final columnName in columnNames) {
        try {
          final value = await feature.getAttributeValue(columnName);
          cells[columnName] = PlutoCell(value: value ?? '');
        } catch (e) {
          print('[DynamicAttributeTable] 属性値取得エラー ($columnName): $e');
          cells[columnName] = PlutoCell(value: '');
        }
      }

      tableRows.add(PlutoRow(cells: cells));
    }

    return tableRows;
  }

  /// カラムタイプを決定
  PlutoColumnType _determineColumnType(String columnName) {
    final lowerName = columnName.toLowerCase();

    if (lowerName == 'id' || lowerName == 'fid' || lowerName.contains('_id')) {
      return PlutoColumnType.number();
    } else if (lowerName.contains('date') || lowerName.contains('time')) {
      return PlutoColumnType.date();
    } else if (lowerName.contains('number') || 
               lowerName.contains('count') || 
               lowerName.contains('size') ||
               lowerName.contains('length') ||
               lowerName.contains('area')) {
      return PlutoColumnType.number();
    } else {
      return PlutoColumnType.text();
    }
  }

  /// カラムが編集可能かどうかを判定
  bool _isColumnEditable(String columnName) {
    final lowerName = columnName.toLowerCase();
    
    // システムカラムは編集不可
    if (lowerName == 'id' || 
        lowerName == 'fid' || 
        lowerName == 'geom' || 
        lowerName == 'geometry' ||
        lowerName.startsWith('_')) {
      return false;
    }
    
    return true;
  }

  /// カラム幅を取得
  double _getColumnWidth(String columnName) {
    final lowerName = columnName.toLowerCase();
    
    if (lowerName == 'id' || lowerName == 'fid') {
      return 40; // IDフィールド
    } else if (lowerName == 'name') {
      return 80; // 名前フィールド
    } else if (lowerName == 'description') {
      return 100; // 説明フィールド
    } else if (lowerName == 'geom' || lowerName == 'geometry') {
      return 70; // ジオメトリフィールド
    } else {
      return 60; // その他のフィールド
    }
  }

  /// 選択されたフィーチャを削除
  Future<void> _deleteSelectedFeatures() async {
    try {
      // GlobalConfigから選択されたフィーチャーを取得
      final selectedFeatures = GlobalConfig.instance.selectedFeatures
          .whereType<FeatureNode>()
          .toList();

      // 選択されたフィーチャーがない場合は処理を終了
      if (selectedFeatures.isEmpty) {
        print('[DynamicAttributeTable] 削除するフィーチャーが選択されていません');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('削除するフィーチャーが選択されていません'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        return;
      }

      print('[DynamicAttributeTable] 削除処理開始: ${selectedFeatures.length}個のフィーチャ');

      // 削除対象の行インデックスを収集
      final rowIndicesToRemove = <int>[];
      for (final feature in selectedFeatures) {
        final index = features.indexOf(feature);
        if (index >= 0) {
          rowIndicesToRemove.add(index);
        }
      }

      // 各フィーチャーに対してdispose()を実行（データベース削除）
      for (final feature in selectedFeatures) {
        print('[DynamicAttributeTable] フィーチャ削除中: ${feature.name} (ID: ${feature.rowId})');
        
        // レイヤーノードから削除
        widget.layer.removeFeature(feature);
        
        // dispose()を実行してDBからも削除
        await feature.dispose();
        
        print('[DynamicAttributeTable] フィーチャ削除完了: ${feature.name}');
      }

      // PlutoGridから該当する行を削除（後ろからインデックス順で削除）
      if (stateManager != null && rowIndicesToRemove.isNotEmpty) {
        rowIndicesToRemove.sort((a, b) => b.compareTo(a)); // 後ろから削除
        final rowsToRemove = <PlutoRow>[];
        for (final index in rowIndicesToRemove) {
          if (index < rows.length) {
            rowsToRemove.add(rows[index]);
          }
        }
        
        print('[DynamicAttributeTable] PlutoGrid行削除: ${rowsToRemove.length}行');
        
        // rowsリストからも削除（後ろから削除）
        rowIndicesToRemove.sort((a, b) => b.compareTo(a));
        for (final index in rowIndicesToRemove) {
          if (index < rows.length) {
            rows.removeAt(index);
          }
        }
        
        // StateManagerから行削除
        stateManager!.removeRows(rowsToRemove);
      }

      // ローカルのfeaturesリストからも削除
      for (final feature in selectedFeatures) {
        features.remove(feature);
      }

      // GlobalConfigのselectedFeaturesをクリア
      GlobalConfig.instance.selectedFeatures.clear();

      // setState でUIを更新
      setState(() {
        // UI状態を更新
      });

      print('[DynamicAttributeTable] 選択されたフィーチャを削除しました: ${selectedFeatures.length}個');

      // 成功メッセージ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${selectedFeatures.length}個のフィーチャを削除しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      print('[DynamicAttributeTable] フィーチャ削除エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('フィーチャの削除に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  /// 属性値の変更を保存
  Future<void> _saveAttributeChange(
    FeatureNode feature,
    String field,
    dynamic value,
  ) async {
    try {
      print('[DynamicAttributeTable] 属性変更保存: field=$field, value=$value');

      // 基本フィールドの処理
      if (field == 'id' || field == 'fid' || field == 'geom' || field == 'geometry') {
        // システムフィールドは編集不可
        print('[DynamicAttributeTable] システムフィールドのため保存をスキップ: $field');
        return;
      }

      // 全ての属性を統一的にsetAttributeValueで処理
      await feature.setAttributeValue(field, value);

      print('[DynamicAttributeTable] 属性変更保存成功: $field = $value');

      // 成功メッセージ（デバッグ時のみ表示）
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('属性が保存されました: $field = $value'),
            duration: const Duration(seconds: 1),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('[DynamicAttributeTable] 属性変更保存エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('属性の保存に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (columns.isEmpty || rows.isEmpty) {
      return const Center(
        child: Text('データがありません'),
      );
    }

    return Column(
      children: [
        // 極小ツールバー
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceVariant,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '${widget.layer.layerName} (${features.length})',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  fontSize: 9,
                  height: 1.0,
                ),
              ),
              const Spacer(),
              // 極小アイコンボタン
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 12,
                  icon: const Icon(Icons.refresh),
                  onPressed: _initializeTableData,
                  tooltip: '更新',
                ),
              ),
              if (widget.onAddFeature != null)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 12,
                    icon: const Icon(Icons.add),
                    onPressed: widget.onAddFeature,
                    tooltip: 'フィーチャ追加',
                  ),
                ),
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 12,
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: _deleteSelectedFeatures,
                  tooltip: '選択フィーチャ削除',
                ),
              ),
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 12,
                  icon: const Icon(Icons.save),
                  onPressed: () async {
                    // 即座に保存を実行（テスト用）
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
                      print('[ERROR] 即座保存エラー: $e');
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
                  },
                  tooltip: '即座に保存',
                ),
              ),
            ],
          ),
        ),
        // テーブル
        Expanded(
          child: PlutoGrid(
            columns: columns,
            rows: rows,
            mode: PlutoGridMode.selectWithOneTap, // セル選択を1タップで有効化
            onLoaded: (PlutoGridOnLoadedEvent event) {
              stateManager = event.stateManager;
            },
            onChanged: (PlutoGridOnChangedEvent event) async {
              final rowIndex = event.rowIdx;
              final field = event.column.field;
              final newValue = event.value;

              if (rowIndex < features.length) {
                final feature = features[rowIndex];
                await _saveAttributeChange(feature, field, newValue);
              }
            },
            onSelected: (PlutoGridOnSelectedEvent event) {
              print('[DynamicAttributeTable] onSelected イベント発生！');
              final selectedRow = event.row;
              if (selectedRow != null && event.rowIdx != null) {
                final rowIndex = event.rowIdx!;
                if (rowIndex < features.length) {
                  final feature = features[rowIndex];
                  
                  // 選択されたセルの列情報を取得
                  final selectedColumnField = event.cell?.column.field;
                  final selectedCellValue = event.cell?.value;
                  
                  // GlobalConfigのselectedFeaturesリストをクリアして選択されたFeatureNodeを追加
                  GlobalConfig.instance.selectedFeatures.clear();
                  GlobalConfig.instance.selectedFeatures.add(feature);
                  
                  // デバッグログ: 選択されたフィーチャの情報を出力
                  print('[DynamicAttributeTable] セル選択 - フィーチャ選択完了');
                  print('[DynamicAttributeTable] 選択セル情報:');
                  print('  - 行インデックス: $rowIndex');
                  print('  - 列フィールド: $selectedColumnField');
                  print('  - セル値: $selectedCellValue');
                  print('[DynamicAttributeTable] 選択フィーチャ情報:');
                  print('  - rowId: ${feature.rowId}');
                  print('  - name: ${feature.name}');
                  print('  - layerName: ${feature.layerName}');
                  print('  - フィーチャタイプ: ${feature.runtimeType}');
                  print('  - 座標: ${feature.centroid}');
                  print('[DynamicAttributeTable] GlobalConfig.selectedFeatures:');
                  print('  - 選択フィーチャ数: ${GlobalConfig.instance.selectedFeatures.length}');
                  for (int i = 0; i < GlobalConfig.instance.selectedFeatures.length; i++) {
                    final selectedFeature = GlobalConfig.instance.selectedFeatures[i];
                    if (selectedFeature is FeatureNode) {
                      print('  - [$i] ${selectedFeature.name} (ID: ${selectedFeature.rowId})');
                    } else {
                      print('  - [$i] 型不明: ${selectedFeature.runtimeType}');
                    }
                  }
                  
                  widget.onFeatureSelected?.call(feature);
                }
              }
            },
            configuration: PlutoGridConfiguration(
              columnSize: const PlutoGridColumnSizeConfig(
                autoSizeMode: PlutoAutoSizeMode.none, // 自動サイズ調整を無効化
                resizeMode: PlutoResizeMode.normal, // 手動リサイズを有効化
              ),
              style: PlutoGridStyleConfig(
                // 行の高さをコンパクトに（読みやすさも考慮）
                rowHeight: 20,
                columnHeight: 22,
                // フォントサイズを読みやすく調整
                cellTextStyle: const TextStyle(fontSize: 10, height: 1.1),
                columnTextStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, height: 1.1),
                // ボーダーを細く
                borderColor: Colors.grey.shade300,
                activatedBorderColor: Colors.blue.shade300,
                // 奇数行の背景色を薄くして見やすく
                evenRowColor: Colors.grey.shade50,
                oddRowColor: Colors.white,
              ),
              scrollbar: const PlutoGridScrollbarConfig(
                // スクロールバーを細く
                scrollbarThickness: 8,
                scrollbarThicknessWhileDragging: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
