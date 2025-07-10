/// K-MAPS: 属性テーブル表示パネル
library;

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/photo_node.dart';
import '../../../utils/global_config.dart';
import '../../../utils/global_drawing_state.dart';
import '../../../utils/metadata_parser.dart';
import '../../../converters/feature_converter.dart';
import '../../../converters/base_converter.dart';
import '../../../services/import_export_service.dart';
import '../../dialog_manager.dart';
import '../metadata_table/metadata_table_dialog.dart';

/// 属性テーブル表示用パネルWidget
class AttributeTablePanel extends StatefulWidget {
  final LayerNode layerNode;
  final VoidCallback onBack;

  /// 地図ジャンプ用コールバック
  final void Function(LatLng latLng)? onJumpTo;

  /// 追記モード開始用コールバック（ツール切り替えとレイヤー選択）
  final void Function(FeatureNode feature)? onStartAppendMode;

  const AttributeTablePanel({
    super.key,
    required this.layerNode,
    required this.onBack,
    this.onJumpTo,
    this.onStartAppendMode,
  });

  @override
  State<AttributeTablePanel> createState() => _AttributeTablePanelState();
}

class _AttributeTablePanelState extends State<AttributeTablePanel> {
  // 編集中セル: rowId, カラム名
  int? editingRowId;
  String? editingColumn;
  String editingValue = '';
  bool showAllColumns = false;

  // ページネーション関連
  int _currentPage = 0;
  int _pageSize = 50; // 1ページあたりの表示件数
  int _totalRecords = 0;

  // スクロール位置保持用のコントローラー
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  // データキャッシュ用変数（不必要な再読み込みを防ぐ）
  List<String>? _cachedColumns;
  List<FeatureNode>? _cachedFeatures;
  List<Map<String, dynamic>>? _cachedAttributeData; // 属性データキャッシュ
  bool _lastShowAllColumns = false;
  Future<List<dynamic>>? _dataFuture;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  /// メタデータダイアログを表示
  void _showMetadataDialog(
    BuildContext context,
    String metadataStr,
    FeatureNode featureNode,
  ) async {
    try {
      // JSONパースを試行
      final metadataJson = jsonDecode(metadataStr) as Map<String, dynamic>;

      // XY座標付きでメタデータをパース
      final tableData = await MetadataParser.parseMetadataWithCoordinates(
        metadataJson,
        featureNode.centroid,
      );

      if (tableData != null) {
        // GeoPackage名とレイヤ名を取得
        final gpkgPath =
            widget.layerNode.geoPackageFile.pathList.isNotEmpty
                ? p.joinAll([
                  GlobalConfig.instance.projectRootDir!,
                  ...widget.layerNode.geoPackageFile.pathList,
                ])
                : null;
        final gpkgName =
            gpkgPath != null ? p.basenameWithoutExtension(gpkgPath) : 'unknown';
        final layerName = widget.layerNode.layerName;

        // フィーチャ名を取得（FeatureNodeのnameを使用、利用できない場合はID）
        final featureName =
            featureNode.name.isNotEmpty
                ? featureNode.name
                : 'feature_${featureNode.rowId}';

        showDialog(
          context: context,
          builder:
              (context) => MetadataTableDialog(
                tableData: tableData,
                gpkgName: gpkgName,
                layerName: layerName,
                featureName: featureName,
                featureLatLng: featureNode.centroid,
              ),
        );
      } else {
        _showRawMetadataDialog(context, metadataStr);
      }
    } catch (e) {
      print('[AttributeTable] メタデータJSONパースエラー: $e');
      _showRawMetadataDialog(context, metadataStr);
    }
  }

  /// 生のメタデータ文字列をダイアログで表示
  void _showRawMetadataDialog(BuildContext context, String metadataStr) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('メタデータ（生データ）'),
            content: SingleChildScrollView(child: Text(metadataStr)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
    );
  }

  /// データを取得または再利用（キャッシュ機能付き）
  Future<List<dynamic>> _getTableData() {
    // showAllColumnsが変更された場合、またはページが変更された場合は再読み込み
    if (_dataFuture == null || _lastShowAllColumns != showAllColumns) {
      _lastShowAllColumns = showAllColumns;
      _dataFuture = _loadTableDataOptimized();
    }
    return _dataFuture!;
  }

  /// 最適化されたテーブルデータ読み込み（一括属性取得）
  Future<List<dynamic>> _loadTableDataOptimized() async {
    try {
      print('[AttributeTable] 最適化データ読み込み開始');

      // カラム名を取得
      final columns = await widget.layerNode.geoPackageFile.getColumnNames(
        widget.layerNode.layerName,
        getAll: showAllColumns,
      );

      // 基本データを取得（同期的）
      final features = widget.layerNode.features;

      print(
        '[AttributeTable] カラム数: ${columns.length}, フィーチャ数: ${features.length}',
      );

      // 属性データを一括取得
      final attributeData = await widget.layerNode.geoPackageFile
          .getAllFeatureAttributes(
            widget.layerNode.layerName,
            columns: columns,
          );

      print('[AttributeTable] 属性データ一括取得完了: ${attributeData.length}件');

      // 総レコード数を保存（ページネーション用）
      _totalRecords = features.length;

      // データが0件の場合の処理
      if (_totalRecords == 0) {
        print('[AttributeTable] データなし: 0件');
        _cachedColumns = columns;
        _cachedFeatures = features;
        _cachedAttributeData = attributeData;
        return [columns, <FeatureNode>[], <Map<String, dynamic>>[]];
      }

      // ページングされたデータを作成
      final startIndex = _currentPage * _pageSize;
      final endIndex = (startIndex + _pageSize).clamp(
        startIndex,
        features.length,
      );

      final pagedFeatures = features.sublist(startIndex, endIndex);
      final pagedAttributeData =
          attributeData.length > startIndex
              ? attributeData.sublist(
                startIndex,
                endIndex.clamp(startIndex, attributeData.length),
              )
              : <Map<String, dynamic>>[];

      print(
        '[AttributeTable] ページング: $startIndex-${endIndex - 1} / $_totalRecords件',
      );

      // キャッシュに保存（全データを保持）
      _cachedColumns = columns;
      _cachedFeatures = features;
      _cachedAttributeData = attributeData;

      return [columns, pagedFeatures, pagedAttributeData];
    } catch (e, stack) {
      print('[AttributeTable] データ読み込みエラー: $e');
      print('[AttributeTable] スタックトレース: $stack');
      return [<String>[], <FeatureNode>[], <Map<String, dynamic>>[]];
    }
  }

  /// TSVエクスポート処理（最適化版）
  Future<void> _exportToTSV(BuildContext context) async {
    try {
      // データを取得（一括取得済みの場合はそれを使用）
      final tableData = await _getTableData();
      final columns = tableData[0] as List<String>;
      final features = tableData[1] as List<FeatureNode>;
      final attributeData = tableData[2] as List<Map<String, dynamic>>;

      // エクスポート先パスを構築
      final gpkgPath =
          widget.layerNode.geoPackageFile.pathList.isNotEmpty
              ? p.joinAll([
                GlobalConfig.instance.projectRootDir!,
                ...widget.layerNode.geoPackageFile.pathList,
              ])
              : null;
      if (gpkgPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoPackageファイルのパスが見つかりません')),
        );
        return;
      }

      final gpkgDir = p.dirname(gpkgPath);
      final gpkgName = p.basenameWithoutExtension(gpkgPath);
      final layerName = widget.layerNode.layerName;
      final tsvFileName = '${gpkgName}_${layerName}_propety_table.tsv';
      final tsvPath = p.join(gpkgDir, tsvFileName);

      print('[AttributeTable] TSVエクスポート開始: $tsvPath');

      // TSVファイルを作成
      final tsvFile = File(tsvPath);
      final sink = tsvFile.openWrite();

      // ヘッダー行を書き込み（TSVエスケープ付き）
      final headerLine = columns.map(_escapeTsvField).join('\t');
      sink.writeln(headerLine);

      // データ行を書き込み（一括取得した属性データを使用）
      for (int i = 0; i < features.length; i++) {
        final rowValues = <String>[];
        final attributeRow =
            attributeData.length > i ? attributeData[i] : <String, dynamic>{};

        for (final col in columns) {
          if (col == 'geom') {
            // geomカラムは'GEOMETRY'として出力
            rowValues.add(_escapeTsvField('GEOMETRY'));
          } else {
            final value = attributeRow[col];
            rowValues.add(_escapeTsvField(value?.toString() ?? ''));
          }
        }

        final rowLine = rowValues.join('\t');
        sink.writeln(rowLine);
      }

      await sink.close();

      print('[AttributeTable] TSVエクスポート完了: $tsvPath');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('TSVファイルを出力しました:\n$tsvFileName'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      print('[AttributeTable] TSVエクスポートエラー: $e');
      print('[AttributeTable] スタックトレース: $stackTrace');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('TSVエクスポートに失敗しました: $e')));
    }
  }

  /// TSV用フィールドエスケープ処理
  String _escapeTsvField(String field) {
    // タブ、改行、復帰文字を置換してエスケープ
    return field
        .replaceAll('\t', ' ') // タブをスペースに置換
        .replaceAll('\n', ' ') // 改行をスペースに置換
        .replaceAll('\r', ' '); // 復帰文字をスペースに置換
  }

  /// 現在のページをリフレッシュ（編集後のデータ更新用）
  void _refreshCurrentPage() {
    _dataFuture = null;
    _cachedAttributeData = null;
    setState(() {
      editingRowId = null;
      editingColumn = null;
    });
  }

  /// 最適化されたDataRowを構築（一括取得した属性データを使用）
  DataRow _buildOptimizedDataRow(
    FeatureNode feature,
    List<String> columns,
    Map<String, dynamic> attributeRow,
  ) {
    return DataRow(
      cells: [
        for (final col in columns)
          col == 'geom'
              ? DataCell(
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) {
                    _showRowContextMenu(
                      context,
                      feature,
                      attributeRow,
                      details.globalPosition,
                    );
                  },
                  child: SizedBox(
                    height: 28,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(40, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        // geom選択時に地図ジャンプ
                        if (widget.onJumpTo != null) {
                          widget.onJumpTo!(feature.centroid);
                        }
                        // feature選択: selectedFeaturesにセット
                        final wasSelected = GlobalConfig
                            .instance
                            .selectedFeatures
                            .contains(feature);
                        if (!wasSelected) {
                          GlobalConfig.instance.selectedFeatures = [feature];
                          // 地図本体のみ再描画（属性テーブルは再描画しない）
                          if (GlobalConfig.instance.mapState != null) {
                            GlobalConfig.instance.mapState.setState(() {});
                          }
                        }
                      },
                      child: const Text('選択', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
              )
              : col == 'kmaps_metadata'
              ? DataCell(() {
                final metadataStr = attributeRow[col] as String?;
                if (metadataStr == null || metadataStr.isEmpty) {
                  return const Text('');
                }

                return SizedBox(
                  height: 28,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      minimumSize: const Size(40, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      _showMetadataDialog(context, metadataStr, feature);
                    },
                    child: const Text('表示', style: TextStyle(fontSize: 13)),
                  ),
                );
              }())
              : (editingRowId == feature.rowId && editingColumn == col)
              ? DataCell(
                SizedBox(
                  width: 120,
                  child: TextField(
                    autofocus: true,
                    controller: TextEditingController(text: editingValue)
                      ..selection = TextSelection.collapsed(
                        offset: editingValue.length,
                      ),
                    onChanged: (v) {
                      setState(() {
                        editingValue = v;
                      });
                    },
                    onSubmitted: (v) {
                      feature.editAttribute(col, v);
                      // 編集後はキャッシュをクリアして再読み込み（ページは維持）
                      _refreshCurrentPage();
                    },
                    onEditingComplete: () {
                      feature.editAttribute(col, editingValue);
                      // 編集後はキャッシュをクリアして再読み込み（ページは維持）
                      _refreshCurrentPage();
                    },
                  ),
                ),
              )
              : DataCell(
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final value = attributeRow[col];
                    setState(() {
                      editingRowId = feature.rowId;
                      editingColumn = col;
                      editingValue = '${value ?? ''}';
                    });
                  },
                  onSecondaryTapDown: (details) {
                    _showRowContextMenu(
                      context,
                      feature,
                      attributeRow,
                      details.globalPosition,
                    );
                  },
                  child: Container(
                    alignment: Alignment.centerLeft,
                    constraints: const BoxConstraints(
                      minWidth: 80,
                      minHeight: 40,
                    ),
                    child: Text('${attributeRow[col] ?? ''}'),
                  ),
                ),
              ),
        // 追記ボタン用のセルを追加
        _buildAppendCell(feature),
      ],
    );
  }

  /// 行の右クリックメニューを表示
  void _showRowContextMenu(
    BuildContext context,
    FeatureNode feature,
    Map<String, dynamic> attributeRow,
    Offset globalPosition,
  ) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'export_feature',
          child: const Row(
            children: [
              Icon(Icons.repeat, size: 16),
              SizedBox(width: 8),
              Text('Export Feature'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_coordinates',
          child: const Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('Copy Coordinates'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleContextMenuAction(value, feature, attributeRow);
      }
    });
  }

  /// コンテキストメニューのアクション処理
  void _handleContextMenuAction(
    String action,
    FeatureNode feature,
    Map<String, dynamic> attributeRow,
  ) {
    switch (action) {
      case 'export_feature':
        _exportSingleFeature(feature, attributeRow);
        break;
      case 'copy_coordinates':
        _copyCoordinates(feature);
        break;
    }
  }

  /// 単一フィーチャのエクスポート（ダイアログ表示）
  Future<void> _exportSingleFeature(
    FeatureNode feature,
    Map<String, dynamic> attributeRow,
  ) async {
    try {
      // フィーチャデータを構築
      final featureData = {
        'id': feature.rowId,
        'geometry': _buildGeometryFromFeature(feature),
        'metadata': attributeRow,
      };

      // DialogManagerを使用してフィーチャエクスポートダイアログを表示
      await DialogManager.showFeatureExportDialog(
        context,
        features: [featureData],
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      print('[AttributeTable] エクスポートエラー: $e');
    }
  }

  /// 座標のコピー
  Future<void> _copyCoordinates(FeatureNode feature) async {
    try {
      final coordinates = feature.centroid;
      final coordText = '${coordinates.latitude}, ${coordinates.longitude}';

      // クリップボードにコピー
      await Clipboard.setData(ClipboardData(text: coordText));
      print('[AttributeTable] 座標コピー: $coordText');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coordinates copied: $coordText'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy coordinates: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// フィーチャからジオメトリデータを構築
  Map<String, dynamic> _buildGeometryFromFeature(FeatureNode feature) {
    // 実際の実装では、フィーチャのジオメトリタイプに応じて適切なGeoJSON形式を生成
    if (feature is PointFeatureNode) {
      final coord = feature.centroid;
      return {
        'type': 'Point',
        'coordinates': [coord.longitude, coord.latitude],
      };
    } else if (feature is LineFeatureNode) {
      // 実際の線の座標データが必要
      return {
        'type': 'LineString',
        'coordinates': [], // 実際の座標配列
      };
    } else if (feature is PolygonFeatureNode) {
      // 実際のポリゴンの座標データが必要
      return {
        'type': 'Polygon',
        'coordinates': [[]], // 実際の座標配列
      };
    }

    return {
      'type': 'Point',
      'coordinates': [0.0, 0.0],
    };
  }

  /// 追記ボタン用のDataCellを構築
  /// 線と面のフィーチャの場合のみボタンを表示
  DataCell _buildAppendCell(FeatureNode feature) {
    // 線または面のフィーチャの場合のみ追記ボタンを表示
    if (feature is LineFeatureNode || feature is PolygonFeatureNode) {
      return DataCell(
        SizedBox(
          height: 28,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(40, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.orange.shade100,
            ),
            onPressed: () {
              // GlobalDrawingStateで追記モードを開始
              final drawingState = GlobalDrawingState.instance;
              final success = drawingState.startEditingFeature(feature);

              if (success) {
                // 追記モード開始のコールバックを呼び出し
                widget.onStartAppendMode?.call(feature);

                // 属性テーブルを閉じて地図画面に戻る
                widget.onBack();

                // ユーザーに追記モード開始を通知
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${feature.name}の追記モードを開始しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                // エラーメッセージを表示
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('追記モードの開始に失敗しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('追記', style: TextStyle(fontSize: 13)),
          ),
        ),
      );
    } else {
      // 点フィーチャの場合は空のセル
      return const DataCell(SizedBox(height: 28, child: Text('')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.blue,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: '戻る',
                onPressed: widget.onBack,
              ),
              Expanded(
                child: Text(
                  widget.layerNode.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  showAllColumns ? Icons.view_column : Icons.filter_alt,
                  color: Colors.white,
                ),
                tooltip: showAllColumns ? 'supported属性のみ表示' : '全カラム表示',
                onPressed: () {
                  setState(() {
                    showAllColumns = !showAllColumns;
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.file_download, color: Colors.white),
                tooltip: 'TSVエクスポート',
                onPressed: () => _exportToTSV(context),
              ),
              IconButton(
                icon: const Icon(Icons.transform, color: Colors.white),
                tooltip: 'Feature変換出力',
                onPressed: () => _showFeatureExportDialog(context),
              ),
            ],
          ),
        ),
        // ページネーションコントロール
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 表示情報
              Text(
                _totalRecords == 0
                    ? '0 / 0 件'
                    : '${_currentPage * _pageSize + 1}-${((_currentPage + 1) * _pageSize).clamp(_currentPage * _pageSize + 1, _totalRecords)} / $_totalRecords 件',
                style: const TextStyle(fontSize: 14),
              ),
              // ページネーションボタン
              Row(
                children: [
                  // ページサイズ選択
                  DropdownButton<int>(
                    value: _pageSize,
                    items:
                        [25, 50, 100, 200]
                            .map(
                              (size) => DropdownMenuItem(
                                value: size,
                                child: Text('$size件'),
                              ),
                            )
                            .toList(),
                    onChanged: (newSize) {
                      if (newSize != null) {
                        setState(() {
                          _pageSize = newSize;
                          _currentPage = 0; // 最初のページに戻る
                          _dataFuture = null; // データ再読み込み
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  // 前のページボタン
                  IconButton(
                    onPressed:
                        _totalRecords > 0 && _currentPage > 0
                            ? () {
                              setState(() {
                                _currentPage--;
                                _dataFuture = null; // データ再読み込み
                              });
                            }
                            : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  // ページ番号表示
                  Text(
                    _totalRecords == 0
                        ? '0 / 0'
                        : '${_currentPage + 1} / ${((_totalRecords / _pageSize).ceil()).clamp(1, double.infinity).toInt()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // 次のページボタン
                  IconButton(
                    onPressed:
                        _totalRecords > 0 &&
                                (_currentPage + 1) * _pageSize < _totalRecords
                            ? () {
                              setState(() {
                                _currentPage++;
                                _dataFuture = null; // データ再読み込み
                              });
                            }
                            : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _getTableData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('エラー: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: Text('データが見つかりません'));
              }

              final columns = snapshot.data![0] as List<String>;
              final features = snapshot.data![1] as List<FeatureNode>;
              final attributeData =
                  snapshot.data![2] as List<Map<String, dynamic>>;

              return SingleChildScrollView(
                controller: _verticalScrollController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                    columns: [
                      for (final col in columns) DataColumn(label: Text(col)),
                      // 追記ボタン用の列を追加
                      const DataColumn(label: Text('追記')),
                    ],
                    rows: [
                      for (int i = 0; i < features.length; i++)
                        _buildOptimizedDataRow(
                          features[i],
                          columns,
                          attributeData.length > i ? attributeData[i] : {},
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Feature変換出力ダイアログを表示
  Future<void> _showFeatureExportDialog(BuildContext context) async {
    String selectedFormat = 'geojson';
    bool convertToPointCloud = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Feature変換出力'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '出力形式を選択してください：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: selectedFormat,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'geojson',
                        child: Text('GeoJSON (.geojson)'),
                      ),
                      DropdownMenuItem(value: 'csv', child: Text('CSV (.csv)')),
                      DropdownMenuItem(value: 'kml', child: Text('KML (.kml)')),
                      DropdownMenuItem(
                        value: 'shapefile',
                        child: Text('Shapefile (.shp)'),
                      ),
                    ],
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedFormat = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('ポイントクラウドに変換'),
                    subtitle: const Text('LineやPolygonを構成点に分解してPoint形式で出力'),
                    value: convertToPointCloud,
                    onChanged: (bool? value) {
                      setState(() {
                        convertToPointCloud = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'フィーチャ数: ${_cachedFeatures?.length ?? 0}件',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed:
                      () => Navigator.of(context).pop({
                        'format': selectedFormat,
                        'pointCloud': convertToPointCloud,
                      }),
                  child: const Text('エクスポート'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await _executeFeatureExport(
        context,
        result['format'] as String,
        result['pointCloud'] as bool,
      );
    }
  }

  /// Feature変換出力を実行
  Future<void> _executeFeatureExport(
    BuildContext context,
    String format,
    bool convertToPointCloud,
  ) async {
    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      // エクスポート先パスを構築
      final gpkgPath =
          widget.layerNode.geoPackageFile.pathList.isNotEmpty
              ? p.joinAll([
                GlobalConfig.instance.projectRootDir!,
                ...widget.layerNode.geoPackageFile.pathList,
              ])
              : null;
      if (gpkgPath == null) {
        Navigator.of(context).pop(); // ローディング閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoPackageファイルのパスが見つかりません')),
        );
        return;
      }

      final gpkgDir = p.dirname(gpkgPath);
      final gpkgName = p.basenameWithoutExtension(gpkgPath);
      final layerName = widget.layerNode.layerName;

      // ファイル拡張子を決定
      final extension = _getFileExtension(format);
      final fileName = '${gpkgName}_${layerName}_features$extension';
      final outputPath = p.join(gpkgDir, fileName);

      print('[AttributeTable] Feature変換出力開始: $outputPath');
      print('[AttributeTable] 形式: $format, ポイントクラウド: $convertToPointCloud');

      // レイヤーエクスポートと同じ処理フローを使用
      // 1. DBから直接フィーチャを取得
      final features = await widget.layerNode.geoPackageFile.getFeatures(
        layerName,
      );
      final geometryType = await widget.layerNode.geoPackageFile
          .getGeometryType(layerName);

      if (features.isEmpty) {
        Navigator.of(context).pop(); // ローディング閉じる
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('エクスポートするフィーチャがありません')));
        return;
      }

      print(
        '[AttributeTable] DBフィーチャ取得完了: ${features.length}個 (タイプ: ${geometryType?.value})',
      );

      // 2. import_export_serviceの統一されたGeoJSON変換を使用
      final importExportService = ImportExportService();
      final geoJsonFeatures = await importExportService
          .convertFeaturesToGeoJson(features, geometryType);

      if (geoJsonFeatures.isEmpty) {
        Navigator.of(context).pop(); // ローディング閉じる
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('フィーチャの変換に失敗しました')));
        return;
      }

      print('[AttributeTable] GeoJSON変換完了: ${geoJsonFeatures.length}個のフィーチャ');

      // 3. FeatureExportConverterを使用（レイヤーエクスポートと同じ）
      final converter = FeatureExportConverter(
        exportFormat: _parseFileFormat(format),
        outputPath: outputPath,
        convertToPointCloud: convertToPointCloud,
      );

      final params = FeatureConversionParams(
        targetLayer: widget.layerNode,
        features: geoJsonFeatures,
        selectedFeatureIds: null, // 全フィーチャをエクスポート
      );

      final result = await converter.convert(params);

      Navigator.of(context).pop(); // ローディング閉じる

      if (result.success) {
        print('[AttributeTable] Feature変換出力完了: $outputPath');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ファイルを出力しました:\n$fileName'),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        print('[AttributeTable] Feature変換出力失敗: ${result.errorMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エクスポートに失敗しました: ${result.errorMessage}')),
        );
      }
    } catch (e, stackTrace) {
      Navigator.of(context).pop(); // ローディング閉じる
      print('[AttributeTable] Feature変換出力エラー: $e');
      print('[AttributeTable] スタックトレース: $stackTrace');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エクスポートエラー: $e')));
    }
  }

  /// ファイル形式から拡張子を取得
  String _getFileExtension(String format) {
    switch (format) {
      case 'geojson':
        return '.geojson';
      case 'csv':
        return '.csv';
      case 'kml':
        return '.kml';
      case 'shapefile':
        return '.shp';
      default:
        return '.txt';
    }
  }

  /// 文字列からFileFormat enumに変換
  FileFormat _parseFileFormat(String format) {
    switch (format) {
      case 'geojson':
        return FileFormat.geojson;
      case 'csv':
        return FileFormat.csv;
      case 'kml':
        return FileFormat.kml;
      case 'shapefile':
        return FileFormat.shapefile;
      default:
        return FileFormat.geojson;
    }
  }
}
