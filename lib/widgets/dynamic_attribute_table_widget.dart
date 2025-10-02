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
    // カラム名が空の場合は、'no_data'カラムに対応する行を返す
    if (columnNames.isEmpty) {
      return [
        PlutoRow(cells: {'no_data': PlutoCell(value: 'No features available')}),
      ];
    }

    // フィーチャが空の場合は、空のリストを返す（カラム定義は存在する）
    if (features.isEmpty) {
      return [];
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

  /// 選択されたフィーチャを削除（GlobalConfig統一処理を使用）
  Future<void> _deleteSelectedFeatures() async {
    try {
      // 選択されたフィーチャーがない場合は処理を終了
      if (GlobalConfig.instance.selectedFeatures.isEmpty) {
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

      final featureCount = GlobalConfig.instance.selectedFeatures.length;
      final selectedFeaturesToDelete = List.from(
        GlobalConfig.instance.selectedFeatures.whereType<FeatureNode>(),
      );
      print('[DynamicAttributeTable] 削除処理開始: $featureCount個のフィーチャ');

      // 削除対象の行インデックスを事前に収集（UI即座更新用）
      final rowIndicesToRemove = <int>[];
      for (final feature in selectedFeaturesToDelete) {
        final index = features.indexOf(feature);
        if (index >= 0) {
          rowIndicesToRemove.add(index);
        }
      }

      // PlutoGridから該当する行を即座に削除（UI更新優先）
      if (stateManager != null && rowIndicesToRemove.isNotEmpty) {
        rowIndicesToRemove.sort((a, b) => b.compareTo(a)); // 後ろから削除
        final rowsToRemove = <PlutoRow>[];
        for (final index in rowIndicesToRemove) {
          if (index < rows.length) {
            rowsToRemove.add(rows[index]);
          }
        }
        
        print('[DynamicAttributeTable] PlutoGrid行を即座に削除: ${rowsToRemove.length}行');
        stateManager!.removeRows(rowsToRemove);
        
        // rowsリストからも削除
        for (final index in rowIndicesToRemove.reversed) {
          if (index < rows.length) {
            rows.removeAt(index);
          }
        }
      }

      // ローカルのfeaturesリストからも削除
      for (final feature in selectedFeaturesToDelete) {
        features.remove(feature);
      }

      // GlobalConfigの統一削除処理を使用（pen_toolと同じロジック）
      await GlobalConfig.instance.disposeSelectedFeatures(
        mapState: GlobalConfig.instance.mapState,
      );

      // 削除完了後に念のため再読み込み（データ整合性確保）
      await _initializeTableData();

      print('[DynamicAttributeTable] 選択されたフィーチャを削除しました: $featureCount個');

      // 成功メッセージ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${featureCount}個のフィーチャを削除しました'),
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

    // カラムが空の場合はエラー表示
    if (columns.isEmpty) {
      return const Center(
        child: Text('カラム定義がありません'),
      );
    }

    // フィーチャが0個の場合は、空のテーブルを表示
    // （rowsが空でもPlutoGridは正常に動作する）

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
            mode: PlutoGridMode.normal, // 通常モード（ダブルタップで編集、セルクリックでフィーチャ選択）
            onLoaded: (PlutoGridOnLoadedEvent event) {
              stateManager = event.stateManager;
              // セル選択モードを有効化（デフォルト）
              stateManager?.setSelectingMode(PlutoGridSelectingMode.cell);
              
              // セル選択が変更されたときにフィーチャを選択
              stateManager?.addListener(() {
                final currentCell = stateManager?.currentCell;
                final currentRowIdx = stateManager?.currentRowIdx;
                final currentColumnField = currentCell?.column.field;
                
                print('[DynamicAttributeTable] ========== stateManager.listener 発火 ==========');
                print('[DynamicAttributeTable] currentCell: ${currentCell != null ? "存在" : "null"}');
                print('[DynamicAttributeTable] currentRowIdx: $currentRowIdx');
                print('[DynamicAttributeTable] currentColumnField: $currentColumnField');
                print('[DynamicAttributeTable] features.length: ${features.length}');
                
                if (currentCell != null && currentRowIdx != null && currentRowIdx >= 0 && currentRowIdx < features.length) {
                  final feature = features[currentRowIdx];
                  
                  print('[DynamicAttributeTable] 有効な行選択を検出');
                  print('[DynamicAttributeTable] 選択フィーチャ情報:');
                  print('  - rowId: ${feature.rowId}');
                  print('  - name: ${feature.name}');
                  print('  - layerName: ${feature.layerName}');
                  print('  - フィーチャタイプ: ${feature.runtimeType}');
                  print('  - 座標: ${feature.centroid}');
                  
                  // 既に選択されている場合はスキップ（無限ループ防止）
                  if (GlobalConfig.instance.selectedFeatures.length == 1 && 
                      GlobalConfig.instance.selectedFeatures.first == feature) {
                    print('[DynamicAttributeTable] 既に選択済み → スキップ');
                    return;
                  }
                  
                  print('[DynamicAttributeTable] GlobalConfigに追加開始');
                  
                  // GlobalConfigのselectedFeaturesリストをクリアして選択されたFeatureNodeを追加
                  GlobalConfig.instance.selectedFeatures.clear();
                  GlobalConfig.instance.selectedFeatures.add(feature);
                  
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
                  
                  print('[DynamicAttributeTable] onFeatureSelected コールバック呼び出し');
                  widget.onFeatureSelected?.call(feature);
                  print('[DynamicAttributeTable] フィーチャ選択処理完了');
                } else {
                  print('[DynamicAttributeTable] 無効な選択状態 → フィーチャ選択スキップ');
                }
                print('[DynamicAttributeTable] ========================================');
              });
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
