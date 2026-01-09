// K-MAPS: 属性テーブルコントローラ
// PlutoGridの状態管理、フィーチャ操作、属性編集を担当

import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../utils/app_logger.dart';
import '../../utils/global_config.dart';
import '../../services/coordinate/index.dart';

/// 属性テーブルの表示設定
class AttributeTableSettings {
  final bool showWgs84;
  final EpsgDefinition? additionalEpsg;

  const AttributeTableSettings({
    this.showWgs84 = true,
    this.additionalEpsg,
  });

  AttributeTableSettings copyWith({
    bool? showWgs84,
    EpsgDefinition? additionalEpsg,
    bool clearAdditionalEpsg = false,
  }) {
    return AttributeTableSettings(
      showWgs84: showWgs84 ?? this.showWgs84,
      additionalEpsg: clearAdditionalEpsg ? null : (additionalEpsg ?? this.additionalEpsg),
    );
  }
}

/// 属性テーブルコントローラ
/// 状態管理とPlutoGridとの連携を担当
class AttributeTableController extends ChangeNotifier {
  final LayerNode layer;
  
  // 状態
  PlutoGridStateManager? _stateManager;
  List<PlutoColumn> _columns = [];
  List<PlutoRow> _rows = [];
  List<String> _columnNames = [];
  List<FeatureNode> _features = [];
  bool _isLoading = true;
  AttributeTableSettings _settings = const AttributeTableSettings();

  // ゲッター
  PlutoGridStateManager? get stateManager => _stateManager;
  List<PlutoColumn> get columns => _columns;
  List<PlutoRow> get rows => _rows;
  List<String> get columnNames => _columnNames;
  List<FeatureNode> get features => _features;
  bool get isLoading => _isLoading;
  AttributeTableSettings get settings => _settings;
  bool get isPointLayer => layer.runtimeType.toString().contains('PointLayerNode');

  AttributeTableController(this.layer);

  /// 初期化
  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();

    try {
      AppLogger.debug('[AttributeTableController] 初期化開始: ${layer.layerName}');

      // カラム名を取得
      _columnNames = await layer.getAttributeColumnNames(
        getAll: true,
        skipPrimaryKey: true,
      );
      AppLogger.debug('[AttributeTableController] カラム名: ${_columnNames.length}個');

      // フィーチャを取得
      _features = layer.features;
      AppLogger.debug('[AttributeTableController] フィーチャ: ${_features.length}個');

      // カラムと行を構築
      _columns = _createColumns();
      _rows = await _createRows();

      AppLogger.debug('[AttributeTableController] 初期化完了');
    } catch (e) {
      AppLogger.debug('[AttributeTableController] 初期化エラー: $e');
      _columnNames = [];
      _features = [];
      _columns = [];
      _rows = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// PlutoGridのStateManagerを設定
  void setStateManager(PlutoGridStateManager manager) {
    _stateManager = manager;
    
    // 編集モードの監視
    _stateManager?.addListener(_onStateChanged);
  }

  /// 設定を更新
  Future<void> updateSettings(AttributeTableSettings newSettings) async {
    if (_settings.showWgs84 != newSettings.showWgs84 ||
        _settings.additionalEpsg != newSettings.additionalEpsg) {
      _settings = newSettings;
      await initialize();
    }
  }

  /// 選択されたフィーチャを削除
  Future<void> deleteSelectedFeatures() async {
    if (GlobalConfig.instance.selectedFeatures.isEmpty) {
      AppLogger.debug('[AttributeTableController] 削除対象なし');
      return;
    }

    final featureCount = GlobalConfig.instance.selectedFeatures.length;
    final selectedFeaturesToDelete = List.from(
      GlobalConfig.instance.selectedFeatures.whereType<FeatureNode>(),
    );

    AppLogger.debug('[AttributeTableController] 削除開始: $featureCount個');

    // PlutoGridから行を削除
    final rowIndicesToRemove = <int>[];
    for (final feature in selectedFeaturesToDelete) {
      final index = _features.indexOf(feature);
      if (index >= 0) rowIndicesToRemove.add(index);
    }

    if (_stateManager != null && rowIndicesToRemove.isNotEmpty) {
      rowIndicesToRemove.sort((a, b) => b.compareTo(a));
      final rowsToRemove = <PlutoRow>[];
      for (final index in rowIndicesToRemove) {
        if (index < _rows.length) {
          rowsToRemove.add(_rows[index]);
        }
      }
      _stateManager!.removeRows(rowsToRemove);
    }

    // ローカルリストから削除
    for (final feature in selectedFeaturesToDelete) {
      _features.remove(feature);
    }

    // GlobalConfigの統一削除処理
    await GlobalConfig.instance.disposeSelectedFeatures(
      mapState: GlobalConfig.instance.mapState,
    );

    // 再読み込み
    await initialize();

    AppLogger.debug('[AttributeTableController] 削除完了: $featureCount個');
  }

  /// 属性値を保存
  Future<void> saveAttributeChange(
    FeatureNode feature,
    String field,
    dynamic value,
  ) async {
    // システムフィールドは編集不可
    if (field == 'id' || field == 'fid' || field == 'geom' || field == 'geometry') {
      return;
    }

    // 仮想カラム（_で始まる）は表示専用
    if (field.startsWith('_')) {
      return;
    }

    try {
      await feature.setAttributeValue(field, value);
      AppLogger.debug('[AttributeTableController] 属性保存: $field = $value');
    } catch (e) {
      AppLogger.debug('[AttributeTableController] 属性保存エラー: $e');
    }
  }

  /// フィーチャを選択
  void selectFeature(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _features.length) return;

    final feature = _features[rowIndex];

    // 既に選択されている場合はスキップ
    if (GlobalConfig.instance.selectedFeatures.length == 1 &&
        GlobalConfig.instance.selectedFeatures.first == feature) {
      return;
    }

    GlobalConfig.instance.selectedFeatures.clear();
    GlobalConfig.instance.selectedFeatures.add(feature);
    AppLogger.debug('[AttributeTableController] フィーチャ選択: rowId=${feature.rowId}');
  }

  // ========== カラム構築 ==========

  List<PlutoColumn> _createColumns() {
    final tableColumns = <PlutoColumn>[];

    // 行番号カラム
    tableColumns.add(PlutoColumn(
      title: '#',
      field: '_row_num',
      type: PlutoColumnType.number(),
      enableEditingMode: false,
      width: 50,
      frozen: PlutoColumnFrozen.start,
    ));

    // Pointレイヤーの座標カラム
    if (isPointLayer) {
      if (_settings.showWgs84) {
        tableColumns.add(PlutoColumn(
          title: '_lat',
          field: '_lat',
          type: PlutoColumnType.text(),
          enableEditingMode: false,
          width: 100,
        ));
        tableColumns.add(PlutoColumn(
          title: '_lon',
          field: '_lon',
          type: PlutoColumnType.text(),
          enableEditingMode: false,
          width: 100,
        ));
      }

      if (_settings.additionalEpsg != null) {
        tableColumns.add(PlutoColumn(
          title: '_x',
          field: '_x',
          type: PlutoColumnType.text(),
          enableEditingMode: false,
          width: 110,
        ));
        tableColumns.add(PlutoColumn(
          title: '_y',
          field: '_y',
          type: PlutoColumnType.text(),
          enableEditingMode: false,
          width: 110,
        ));
      }
    }

    // 属性カラム
    for (final columnName in _columnNames) {
      tableColumns.add(PlutoColumn(
        title: columnName,
        field: columnName,
        type: _determineColumnType(columnName),
        enableEditingMode: _isColumnEditable(columnName),
        width: _getColumnWidth(columnName),
      ));
    }

    return tableColumns;
  }

  PlutoColumnType _determineColumnType(String columnName) {
    final lowerName = columnName.toLowerCase();
    if (lowerName == 'id' || lowerName == 'fid' || lowerName.contains('_id')) {
      return PlutoColumnType.number();
    } else if (lowerName.contains('date') || lowerName.contains('time')) {
      return PlutoColumnType.date();
    } else if (lowerName.contains('number') || lowerName.contains('count') ||
        lowerName.contains('size') || lowerName.contains('length') ||
        lowerName.contains('area')) {
      return PlutoColumnType.number();
    }
    return PlutoColumnType.text();
  }

  bool _isColumnEditable(String columnName) {
    final lowerName = columnName.toLowerCase();
    if (lowerName == 'id' || lowerName == 'fid' ||
        lowerName == 'geom' || lowerName == 'geometry' ||
        lowerName.startsWith('_')) {
      return false;
    }
    return true;
  }

  double _getColumnWidth(String columnName) {
    final lowerName = columnName.toLowerCase();
    if (lowerName == 'id' || lowerName == 'fid') return 40;
    if (lowerName == 'name') return 80;
    if (lowerName == 'description') return 100;
    if (lowerName == 'geom' || lowerName == 'geometry') return 70;
    return 60;
  }

  // ========== 行データ構築 ==========

  Future<List<PlutoRow>> _createRows() async {
    if (_features.isEmpty) return [];

    final tableRows = <PlutoRow>[];
    final coordService = CoordinateService.instance;

    for (int i = 0; i < _features.length; i++) {
      final feature = _features[i];
      final cells = <String, PlutoCell>{};

      // 行番号
      cells['_row_num'] = PlutoCell(value: i + 1);

      // 属性値
      for (final columnName in _columnNames) {
        try {
          final value = await feature.getAttributeValue(columnName);
          cells[columnName] = PlutoCell(value: value ?? '');
        } catch (e) {
          cells[columnName] = PlutoCell(value: '');
        }
      }

      // Pointレイヤーの座標
      if (isPointLayer && feature is PointFeatureNode) {
        final point = feature.point;

        if (_settings.showWgs84) {
          cells['_lat'] = PlutoCell(value: point.latitude.toStringAsFixed(6));
          cells['_lon'] = PlutoCell(value: point.longitude.toStringAsFixed(6));
        }

        if (_settings.additionalEpsg != null) {
          final xy = coordService.transformToXYFormatted(point, _settings.additionalEpsg!);
          cells['_x'] = PlutoCell(value: xy['x'] ?? '');
          cells['_y'] = PlutoCell(value: xy['y'] ?? '');
        }
      }

      tableRows.add(PlutoRow(cells: cells));
    }

    return tableRows;
  }

  // ========== 内部コールバック ==========

  void _onStateChanged() {
    final isEditing = _stateManager?.isEditing ?? false;
    if (GlobalConfig.instance.isAttributeTableEditing != isEditing) {
      GlobalConfig.instance.isAttributeTableEditing = isEditing;
    }
  }

  @override
  void dispose() {
    GlobalConfig.instance.isAttributeTableEditing = false;
    _stateManager?.removeListener(_onStateChanged);
    super.dispose();
  }
}
