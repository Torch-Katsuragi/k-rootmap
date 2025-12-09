// K-MAPS: 動的属性テーブル表示・編集ウィジェット
// LayerNodeから直接属性スキーマを取得して動的にテーブル構造を構築

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:latlong2/latlong.dart';
import 'package:proj4dart/proj4dart.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../utils/global_config.dart';

/// EPSG座標系の定義
class EpsgDefinition {
  final String code;
  final String name;
  final String proj4String;

  const EpsgDefinition({
    required this.code,
    required this.name,
    required this.proj4String,
  });

  @override
  String toString() => '$code - $name';
}

/// 動的属性テーブル表示・編集ウィジェット
/// LayerNodeのスキーマから動的にテーブル構造を構築
class DynamicAttributeTableWidget extends StatefulWidget {
  final LayerNode layer;
  final Function(FeatureNode feature)? onFeatureSelected;
  final Function(FeatureNode feature)? onFeatureDeleted;
  final Function()? onAddFeature;

  const DynamicAttributeTableWidget({
    super.key,
    required this.layer,
    this.onFeatureSelected,
    this.onFeatureDeleted,
    this.onAddFeature,
  });

  @override
  State<DynamicAttributeTableWidget> createState() =>
      _DynamicAttributeTableWidgetState();
}

class _DynamicAttributeTableWidgetState
    extends State<DynamicAttributeTableWidget> {
  PlutoGridStateManager? stateManager;
  List<PlutoColumn> columns = [];
  List<PlutoRow> rows = [];
  List<String> columnNames = [];
  List<FeatureNode> features = [];
  bool _isLoading = true;

  // 座標表示用EPSG設定
  EpsgDefinition _selectedEpsg = _epsgDefinitions.first;

  // PlutoGrid再構築用のKey
  Key _plutoGridKey = UniqueKey();

  // 日本で一般的に使用されるEPSGコードのリスト（拡張版）
  static const List<EpsgDefinition> _epsgDefinitions = [
    // 地理座標系
    EpsgDefinition(
      code: 'EPSG:4326',
      name: 'WGS 84 (GPS/Webマップ標準)',
      proj4String: '+proj=longlat +datum=WGS84 +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:3857',
      name: 'Web Mercator (Google Maps等)',
      proj4String:
          '+proj=merc +a=6378137 +b=6378137 +lat_ts=0 +lon_0=0 +x_0=0 +y_0=0 +k=1 +units=m +nadgrids=@null +wktext +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6668',
      name: 'JGD2011 地理座標系',
      proj4String: '+proj=longlat +ellps=GRS80 +no_defs',
    ),

    // JGD2011 平面直角座標系（全19系）
    EpsgDefinition(
      code: 'EPSG:6669',
      name: 'JGD2011 / 平面直角 I系 (長崎・佐賀)',
      proj4String:
          '+proj=tmerc +lat_0=33 +lon_0=129.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6670',
      name: 'JGD2011 / 平面直角 II系 (福岡・熊本・大分・宮崎・鹿児島)',
      proj4String:
          '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6671',
      name: 'JGD2011 / 平面直角 III系 (山口・島根・広島)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=132.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6672',
      name: 'JGD2011 / 平面直角 IV系 (香川・愛媛・徳島・高知)',
      proj4String:
          '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6673',
      name: 'JGD2011 / 平面直角 V系 (兵庫・鳥取・岡山)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6674',
      name: 'JGD2011 / 平面直角 VI系 (京都・大阪・福井・滋賀・三重・奈良・和歌山)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6675',
      name: 'JGD2011 / 平面直角 VII系 (石川・富山・岐阜・愛知)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6676',
      name: 'JGD2011 / 平面直角 VIII系 (新潟・長野・山梨・静岡)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6677',
      name: 'JGD2011 / 平面直角 IX系 (東京・福島・栃木・茨城・埼玉・千葉・群馬・神奈川)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6678',
      name: 'JGD2011 / 平面直角 X系 (青森・秋田・山形・岩手・宮城)',
      proj4String:
          '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6679',
      name: 'JGD2011 / 平面直角 XI系 (北海道西部)',
      proj4String:
          '+proj=tmerc +lat_0=44 +lon_0=140.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6680',
      name: 'JGD2011 / 平面直角 XII系 (北海道中央部)',
      proj4String:
          '+proj=tmerc +lat_0=44 +lon_0=142.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6681',
      name: 'JGD2011 / 平面直角 XIII系 (北海道東部)',
      proj4String:
          '+proj=tmerc +lat_0=44 +lon_0=144.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6682',
      name: 'JGD2011 / 平面直角 XIV系 (東京都・島しょ部)',
      proj4String:
          '+proj=tmerc +lat_0=26 +lon_0=142 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6683',
      name: 'JGD2011 / 平面直角 XV系 (沖縄本島)',
      proj4String:
          '+proj=tmerc +lat_0=26 +lon_0=127.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6684',
      name: 'JGD2011 / 平面直角 XVI系 (沖縄・宮古島)',
      proj4String:
          '+proj=tmerc +lat_0=26 +lon_0=124 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6685',
      name: 'JGD2011 / 平面直角 XVII系 (沖縄・石垣島)',
      proj4String:
          '+proj=tmerc +lat_0=26 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6686',
      name: 'JGD2011 / 平面直角 XVIII系 (小笠原諸島)',
      proj4String:
          '+proj=tmerc +lat_0=20 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:6687',
      name: 'JGD2011 / 平面直角 XIX系 (南鳥島)',
      proj4String:
          '+proj=tmerc +lat_0=26 +lon_0=154 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),

    // JGD2000 平面直角座標系（互換性のため）
    EpsgDefinition(
      code: 'EPSG:2443',
      name: 'JGD2000 / 平面直角 I系 (長崎・佐賀)',
      proj4String:
          '+proj=tmerc +lat_0=33 +lon_0=129.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2444',
      name: 'JGD2000 / 平面直角 II系 (福岡・熊本・大分・宮崎・鹿児島)',
      proj4String:
          '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2445',
      name: 'JGD2000 / 平面直角 III系 (山口・島根・広島)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=132.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2446',
      name: 'JGD2000 / 平面直角 IV系 (香川・愛媛・徳島・高知)',
      proj4String:
          '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2447',
      name: 'JGD2000 / 平面直角 V系 (兵庫・鳥取・岡山)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2448',
      name: 'JGD2000 / 平面直角 VI系 (京都・大阪・福井・滋賀・三重・奈良・和歌山)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2449',
      name: 'JGD2000 / 平面直角 VII系 (石川・富山・岐阜・愛知)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2450',
      name: 'JGD2000 / 平面直角 VIII系 (新潟・長野・山梨・静岡)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2451',
      name: 'JGD2000 / 平面直角 IX系 (東京・福島・栃木・茨城・埼玉・千葉・群馬・神奈川)',
      proj4String:
          '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:2452',
      name: 'JGD2000 / 平面直角 X系 (青森・秋田・山形・岩手・宮城)',
      proj4String:
          '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    ),

    // UTM座標系（日本周辺）
    EpsgDefinition(
      code: 'EPSG:32651',
      name: 'WGS 84 / UTM zone 51N (九州西部)',
      proj4String: '+proj=utm +zone=51 +datum=WGS84 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:32652',
      name: 'WGS 84 / UTM zone 52N (九州・四国)',
      proj4String: '+proj=utm +zone=52 +datum=WGS84 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:32653',
      name: 'WGS 84 / UTM zone 53N (本州西部)',
      proj4String: '+proj=utm +zone=53 +datum=WGS84 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:32654',
      name: 'WGS 84 / UTM zone 54N (本州中部・東部)',
      proj4String: '+proj=utm +zone=54 +datum=WGS84 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:32655',
      name: 'WGS 84 / UTM zone 55N (北海道・東北)',
      proj4String: '+proj=utm +zone=55 +datum=WGS84 +units=m +no_defs',
    ),
    EpsgDefinition(
      code: 'EPSG:32656',
      name: 'WGS 84 / UTM zone 56N (千島列島)',
      proj4String: '+proj=utm +zone=56 +datum=WGS84 +units=m +no_defs',
    ),
  ];

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

  @override
  void dispose() {
    // 属性テーブルが閉じられた時に編集中フラグをリセット
    GlobalConfig.instance.isAttributeTableEditing = false;
    super.dispose();
  }

  /// テーブルデータを初期化
  Future<void> _initializeTableData() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      AppLogger.debug('[DynamicAttributeTable] データ初期化開始: ${widget.layer.layerName}');

      // LayerNodeから属性カラム名を取得
      columnNames = await widget.layer.getAttributeColumnNames(getAll: true);
      AppLogger.debug('[DynamicAttributeTable] カラム名取得: ${columnNames.length}個');

      // LayerNodeからFeatureNodeリストを取得
      features = widget.layer.features;
      AppLogger.debug('[DynamicAttributeTable] フィーチャ取得: ${features.length}個');

      // 重複チェック（LayerNode.featuresゲッターレベル）
      final featureRowIds = features.map((f) => f.rowId).toList();
      final uniqueRowIds = featureRowIds.toSet();
      if (featureRowIds.length != uniqueRowIds.length) {
        AppLogger.debug('[DynamicAttributeTable] !! LayerNode.featuresに重複を検出！');
        AppLogger.debug('[DynamicAttributeTable] 全rowId: $featureRowIds');
        AppLogger.debug('[DynamicAttributeTable] ユニークrowId: $uniqueRowIds');
      }

      // カラムとデータを構築
      columns = _createColumns();
      rows = await _createRows();

      AppLogger.debug('[DynamicAttributeTable] テーブル構築完了');

      // PlutoGridが既に構築されている場合は、データを更新
      if (stateManager != null && mounted) {
        AppLogger.debug(
          '[DynamicAttributeTable] PlutoGridを更新: ${columns.length}カラム, ${rows.length}行',
        );

        // 行データを更新
        stateManager!.removeAllRows();
        stateManager!.appendRows(rows);

        // カラムも更新（PlutoGridは動的なカラム変更をサポートしていないので、
        // カラムが変わった場合はWidgetを再構築する必要がある）
        // そのため、setStateを呼び出してWidget全体を再構築

        AppLogger.debug('[DynamicAttributeTable] PlutoGrid更新完了');
      }
    } catch (e) {
      AppLogger.debug('[DynamicAttributeTable] データ初期化エラー: $e');
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
    final isPointLayer = _isPointLayer();

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

      // id列の直後にPointレイヤーの場合のみ_coordinate列を追加
      if (isPointLayer && columnName.toLowerCase() == 'id') {
        tableColumns.add(
          PlutoColumn(
            title: '_coordinate',
            field: '_coordinate',
            type: PlutoColumnType.text(),
            enableEditingMode: true,
            width: 150,
          ),
        );
      }
    }

    return tableColumns;
  }

  /// Pointレイヤーかどうかを判定
  bool _isPointLayer() {
    return widget.layer.runtimeType.toString().contains('PointLayerNode');
  }

  /// 座標文字列を解析してLatLngに変換
  /// [lat, lon]または[lon, lat]形式をサポート
  /// 返り値: {'valid': bool, 'point': LatLng?, 'error': String?}
  Map<String, dynamic> _parseCoordinate(String value) {
    try {
      // 前後の空白を削除
      final trimmed = value.trim();

      // []で囲まれているかチェック
      if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
        return {'valid': false, 'error': 'Must be in [...] format'};
      }

      // []を除去してカンマで分割
      final content = trimmed.substring(1, trimmed.length - 1);
      final parts = content.split(',').map((s) => s.trim()).toList();

      // 2つの要素があるかチェック
      if (parts.length != 2) {
        return {'valid': false, 'error': 'Must have exactly 2 values'};
      }

      // 数値に変換
      final num1 = double.tryParse(parts[0]);
      final num2 = double.tryParse(parts[1]);

      if (num1 == null || num2 == null) {
        return {'valid': false, 'error': 'Values must be numbers'};
      }

      // 選択されたEPSGがWGS84の場合は緯度経度として解析
      if (_selectedEpsg.code == 'EPSG:4326' ||
          _selectedEpsg.code == 'EPSG:6668') {
        double lat, lon;
        // 緯度は-90～90、経度は-180～180の範囲
        if (num1.abs() <= 90 && num2.abs() <= 180) {
          // [lat, lon]形式
          lat = num1;
          lon = num2;
        } else if (num2.abs() <= 90 && num1.abs() <= 180) {
          // [lon, lat]形式の可能性
          lon = num1;
          lat = num2;
        } else {
          return {
            'valid': false,
            'error': 'Out of range (lat: -90~90, lon: -180~180)',
          };
        }
        return {'valid': true, 'point': LatLng(lat, lon)};
      } else {
        // 投影座標系の場合はXY座標として解析し、WGS84に変換
        try {
          final proj =
              Projection.get(_selectedEpsg.code) ??
              Projection.add(_selectedEpsg.code, _selectedEpsg.proj4String);

          final wgs84 =
              Projection.get('EPSG:4326') ??
              Projection.add(
                'EPSG:4326',
                '+proj=longlat +datum=WGS84 +no_defs',
              );

          // XY座標をWGS84に変換
          final point = Point(x: num1, y: num2);
          final result = proj.transform(wgs84, point);
          return {'valid': true, 'point': LatLng(result.y, result.x)};
        } catch (e) {
          return {'valid': false, 'error': 'Transform error: $e'};
        }
      }
    } catch (e) {
      return {'valid': false, 'error': 'Parse error: $e'};
    }
  }

  /// WGS84座標を選択されたEPSGの座標系に変換して文字列化
  String _formatCoordinate(LatLng point) {
    try {
      // WGS84の場合はそのまま緯度経度を表示
      if (_selectedEpsg.code == 'EPSG:4326' ||
          _selectedEpsg.code == 'EPSG:6668') {
        return '[${point.latitude}, ${point.longitude}]';
      }

      // 投影座標系の場合はWGS84からXY座標に変換
      final wgs84 =
          Projection.get('EPSG:4326') ??
          Projection.add('EPSG:4326', '+proj=longlat +datum=WGS84 +no_defs');

      final proj =
          Projection.get(_selectedEpsg.code) ??
          Projection.add(_selectedEpsg.code, _selectedEpsg.proj4String);

      // WGS84から目標座標系に変換
      final p = Point(x: point.longitude, y: point.latitude);
      final result = wgs84.transform(proj, p);
      return '[${result.x.toStringAsFixed(3)}, ${result.y.toStringAsFixed(3)}]';
    } catch (e) {
      AppLogger.debug('[DynamicAttributeTable] 座標変換エラー: $e');
      return '[${point.latitude}, ${point.longitude}]';
    }
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

    AppLogger.debug('[DynamicAttributeTable] 行データ作成開始: ${features.length}個のフィーチャ');

    // 重複チェック: rowIdのセットを作成
    final seenRowIds = <int>{};
    final duplicateRowIds = <int>[];

    for (final feature in features) {
      if (seenRowIds.contains(feature.rowId)) {
        duplicateRowIds.add(feature.rowId);
      } else {
        seenRowIds.add(feature.rowId);
      }
    }

    if (duplicateRowIds.isNotEmpty) {
      AppLogger.debug('[DynamicAttributeTable] ! 重複するrowIdを検出: $duplicateRowIds');
      AppLogger.debug('[DynamicAttributeTable] features配列に重複があります！');
    }

    final List<PlutoRow> tableRows = [];
    final isPointLayer = _isPointLayer();

    for (final feature in features) {
      final Map<String, PlutoCell> cells = {};

      // 各カラムの値をFeatureNodeから取得
      for (final columnName in columnNames) {
        try {
          final value = await feature.getAttributeValue(columnName);
          cells[columnName] = PlutoCell(value: value ?? '');
        } catch (e) {
          AppLogger.debug('[DynamicAttributeTable] 属性値取得エラー ($columnName): $e');
          cells[columnName] = PlutoCell(value: '');
        }
      }

      // Pointレイヤーの場合、仮想的な_coordinate列を追加
      if (isPointLayer && feature is PointFeatureNode) {
        final point = feature.point;
        // 選択されたEPSGで座標を変換して表示
        cells['_coordinate'] = PlutoCell(value: _formatCoordinate(point));
      }

      tableRows.add(PlutoRow(cells: cells));
    }

    AppLogger.debug('[DynamicAttributeTable] 行データ作成完了: ${tableRows.length}行');
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
        AppLogger.debug('[DynamicAttributeTable] 削除するフィーチャーが選択されていません');
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
      AppLogger.debug('[DynamicAttributeTable] 削除処理開始: $featureCount個のフィーチャ');
      AppLogger.debug(
        '[DynamicAttributeTable] 削除対象フィーチャ: ${selectedFeaturesToDelete.map((f) => 'rowId=${f.rowId}, name=${f.name}').toList()}',
      );

      // 削除対象の行インデックスを事前に収集（UI即座更新用）
      final rowIndicesToRemove = <int>[];
      for (final feature in selectedFeaturesToDelete) {
        final index = features.indexOf(feature);
        AppLogger.debug(
          '[DynamicAttributeTable] フィーチャ rowId=${feature.rowId} のインデックス: $index',
        );
        if (index >= 0) {
          rowIndicesToRemove.add(index);
        }
      }

      AppLogger.debug('[DynamicAttributeTable] 削除対象行インデックス（ソート前）: $rowIndicesToRemove');

      // PlutoGridから該当する行を即座に削除（UI更新優先）
      if (stateManager != null && rowIndicesToRemove.isNotEmpty) {
        rowIndicesToRemove.sort((a, b) => b.compareTo(a)); // 後ろから削除
        AppLogger.debug(
          '[DynamicAttributeTable] 削除対象行インデックス（ソート後、後ろから）: $rowIndicesToRemove',
        );

        final rowsToRemove = <PlutoRow>[];
        for (final index in rowIndicesToRemove) {
          if (index < rows.length) {
            final row = rows[index];
            AppLogger.debug('[DynamicAttributeTable] 削除する行[$index]: ${row.cells}');
            rowsToRemove.add(row);
          } else {
            AppLogger.debug(
              '[DynamicAttributeTable] ⚠️ インデックス$indexが範囲外（rows.length=${rows.length}）',
            );
          }
        }

        AppLogger.debug(
          '[DynamicAttributeTable] PlutoGrid行を即座に削除: ${rowsToRemove.length}行',
        );
        stateManager!.removeRows(rowsToRemove);

        // NOTE: rowsリストはPlutoGridが自動管理しているため、
        // ここで手動削除する必要はない。最後の_initializeTableData()で再同期される。
        AppLogger.debug('[DynamicAttributeTable] PlutoGridの行削除完了');
      }

      // ローカルのfeaturesリストからも削除
      AppLogger.debug('[DynamicAttributeTable] featuresリストから削除開始（現在${features.length}個）');
      for (final feature in selectedFeaturesToDelete) {
        features.remove(feature);
        AppLogger.debug(
          '[DynamicAttributeTable] features.remove: rowId=${feature.rowId}',
        );
      }
      AppLogger.debug('[DynamicAttributeTable] featuresリスト削除完了（現在${features.length}個）');

      // GlobalConfigの統一削除処理を使用（pen_toolと同じロジック）
      await GlobalConfig.instance.disposeSelectedFeatures(
        mapState: GlobalConfig.instance.mapState,
      );

      AppLogger.debug('[DynamicAttributeTable] DB削除完了、テーブルを再読み込み');

      // 削除完了後に再読み込み（データ整合性確保）
      await _initializeTableData();

      // PlutoGridに新しいデータを明示的にセット
      if (stateManager != null && mounted) {
        AppLogger.debug(
          '[DynamicAttributeTable] PlutoGridに新しいデータをセット: ${columns.length}カラム, ${rows.length}行',
        );
        stateManager!.removeAllRows();
        stateManager!.appendRows(rows);
        stateManager!.notifyListeners();
        AppLogger.debug('[DynamicAttributeTable] PlutoGrid更新完了');
      }

      AppLogger.debug('[DynamicAttributeTable] 選択されたフィーチャを削除しました: $featureCount個');

      // 成功メッセージ
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$featureCount個のフィーチャを削除しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[DynamicAttributeTable] フィーチャ削除エラー: $e');
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
      AppLogger.debug('[DynamicAttributeTable] 属性変更保存: field=$field, value=$value');

      // 基本フィールドの処理
      if (field == 'id' ||
          field == 'fid' ||
          field == 'geom' ||
          field == 'geometry') {
        // システムフィールドは編集不可
        AppLogger.debug('[DynamicAttributeTable] システムフィールドのため保存をスキップ: $field');
        return;
      }

      // 仮想カラム(_coordinate)の処理
      if (field == '_coordinate') {
        if (feature is! PointFeatureNode) {
          AppLogger.debug('[DynamicAttributeTable] _coordinateはPointレイヤーでのみ編集可能');
          return;
        }

        // 座標文字列を解析
        final coordinateResult = _parseCoordinate(value.toString());

        if (!coordinateResult['valid']) {
          AppLogger.debug('[DynamicAttributeTable] 無効な座標形式: $value');
          AppLogger.debug('[DynamicAttributeTable] エラー: ${coordinateResult['error']}');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Invalid coordinate: ${coordinateResult['error']}',
                ),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 3),
              ),
            );
          }

          // 元の値に戻す
          await _initializeTableData();
          return;
        }

        final newPoint = coordinateResult['point'] as LatLng;

        // ジオメトリを更新
        final success = await feature.updateLocation(newPoint);

        if (success) {
          AppLogger.debug(
            '[DynamicAttributeTable] 座標更新成功: ${newPoint.latitude}, ${newPoint.longitude}',
          );

          // マップを更新
          GlobalConfig.instance.mapState?.refreshFeatures();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Coordinate updated: [${newPoint.latitude}, ${newPoint.longitude}]',
                ),
                duration: const Duration(seconds: 1),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          AppLogger.debug('[DynamicAttributeTable] 座標更新失敗');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Failed to update coordinate'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }

          // 元の値に戻す
          await _initializeTableData();
        }

        return;
      }

      // 全ての属性を統一的にsetAttributeValueで処理
      await feature.setAttributeValue(field, value);

      AppLogger.debug('[DynamicAttributeTable] 属性変更保存成功: $field = $value');

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
      AppLogger.debug('[DynamicAttributeTable] 属性変更保存エラー: $e');
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

  /// カラム追加ダイアログを表示
  Future<void> _showAddColumnDialog() async {
    final columnNameController = TextEditingController();
    String selectedType = 'TEXT';

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.add_box, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('カラム追加'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: columnNameController,
                    decoration: const InputDecoration(
                      labelText: 'カラム名',
                      hintText: '例: 備考, 数量, 日付',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedType,
                    decoration: const InputDecoration(
                      labelText: 'データ型',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'TEXT',
                        child: Text('テキスト (TEXT)'),
                      ),
                      DropdownMenuItem(
                        value: 'INTEGER',
                        child: Text('整数 (INTEGER)'),
                      ),
                      DropdownMenuItem(value: 'REAL', child: Text('小数 (REAL)')),
                      DropdownMenuItem(
                        value: 'BLOB',
                        child: Text('バイナリ (BLOB)'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          selectedType = value;
                        });
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    final columnName = columnNameController.text.trim();
                    if (columnName.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('カラム名を入力してください'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }
                    Navigator.of(
                      context,
                    ).pop({'name': columnName, 'type': selectedType});
                  },
                  icon: const Icon(Icons.check),
                  label: const Text('追加'),
                ),
              ],
            );
          },
        );
      },
    );

    // ダイアログから結果が返ってきたらカラムを追加
    if (result != null && mounted) {
      final columnName = result['name']!;
      final columnType = result['type']!;

      try {
        // GeoPackageにカラムを追加
        await widget.layer.geoPackageFile.addAttributeColumn(
          widget.layer.layerName,
          columnName,
          columnType,
        );

        // カラム名キャッシュをクリア
        widget.layer.clearColumnNamesCache();

        // テーブルを再読み込み
        await _initializeTableData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('カラム「$columnName」を追加しました'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        AppLogger.debug('[DynamicAttributeTable] カラム追加エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('カラム追加に失敗しました: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // カラムが空の場合はエラー表示
    if (columns.isEmpty) {
      return const Center(child: Text('カラム定義がありません'));
    }

    // フィーチャが0個の場合は、空のテーブルを表示
    // （rowsが空でもPlutoGridは正常に動作する）

    return Column(
      children: [
        // 極小ツールバー
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
              // Pointレイヤーの場合のみEPSG選択を表示
              if (_isPointLayer()) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: 200,
                  height: 22,
                  child: Autocomplete<EpsgDefinition>(
                    initialValue: TextEditingValue(
                      text: _selectedEpsg.toString(),
                    ),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return _epsgDefinitions;
                      }
                      // 検索文字列にマッチするEPSGをフィルタリング
                      final searchText = textEditingValue.text.toLowerCase();
                      return _epsgDefinitions.where((epsg) {
                        final epsgStr = epsg.toString().toLowerCase();
                        return epsgStr.contains(searchText);
                      });
                    },
                    displayStringForOption:
                        (EpsgDefinition option) => option.toString(),
                    onSelected: (EpsgDefinition selection) async {
                      setState(() {
                        _selectedEpsg = selection;
                        // PlutoGridを完全に再構築するために新しいKeyを生成
                        _plutoGridKey = UniqueKey();
                      });
                      // 座標表示を更新
                      await _initializeTableData();
                    },
                    fieldViewBuilder: (
                      BuildContext context,
                      TextEditingController textEditingController,
                      FocusNode focusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      // フォーカス時にテキストを全選択
                      focusNode.addListener(() {
                        if (focusNode.hasFocus) {
                          textEditingController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: textEditingController.text.length,
                          );
                        }
                      });

                      return TextField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        style: const TextStyle(fontSize: 8, height: 1.0),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                          hintText: 'EPSG検索...',
                          hintStyle: const TextStyle(fontSize: 8),
                        ),
                        onSubmitted: (String value) {
                          onFieldSubmitted();
                        },
                      );
                    },
                    optionsViewBuilder: (
                      BuildContext context,
                      AutocompleteOnSelected<EpsgDefinition> onSelected,
                      Iterable<EpsgDefinition> options,
                    ) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 4.0,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxHeight: 200,
                              maxWidth: 400,
                            ),
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final option = options.elementAt(index);
                                return InkWell(
                                  onTap: () {
                                    onSelected(option);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(8.0),
                                    child: Text(
                                      option.toString(),
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const Spacer(),
              // 極小アイコンボタン
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 12,
                  icon: const Icon(Icons.add_box, color: Colors.blue),
                  onPressed: _showAddColumnDialog,
                  tooltip: 'カラム追加',
                ),
              ),
              SizedBox(
                width: 20,
                height: 20,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 12,
                  icon: const Icon(Icons.refresh),
                  onPressed: () {
                    setState(() {
                      _plutoGridKey = UniqueKey();
                    });
                    _initializeTableData();
                  },
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
                      AppLogger.debug('[ERROR] 即座保存エラー: $e');
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
            key: _plutoGridKey, // EPSGが変わったら完全に再構築
            columns: columns,
            rows: rows,
            mode: PlutoGridMode.normal, // 通常モード（ダブルタップで編集、セルクリックでフィーチャ選択）
            onLoaded: (PlutoGridOnLoadedEvent event) {
              stateManager = event.stateManager;
              // セル選択モードを有効化（デフォルト）
              stateManager?.setSelectingMode(PlutoGridSelectingMode.cell);

              // 編集モードの変化を監視してグローバルフラグを更新
              stateManager?.addListener(() {
                final isEditing = stateManager?.isEditing ?? false;
                if (GlobalConfig.instance.isAttributeTableEditing !=
                    isEditing) {
                  GlobalConfig.instance.isAttributeTableEditing = isEditing;
                  AppLogger.debug('[DynamicAttributeTable] 編集モード変更: $isEditing');
                }
              });

              // セル選択が変更されたときにフィーチャを選択
              stateManager?.addListener(() {
                final currentCell = stateManager?.currentCell;
                final currentRowIdx = stateManager?.currentRowIdx;
                final currentColumnField = currentCell?.column.field;

                AppLogger.debug(
                  '[DynamicAttributeTable] ========== stateManager.listener 発火 ==========',
                );
                AppLogger.debug(
                  '[DynamicAttributeTable] currentCell: ${currentCell != null ? "存在" : "null"}',
                );
                AppLogger.debug('[DynamicAttributeTable] currentRowIdx: $currentRowIdx');
                AppLogger.debug(
                  '[DynamicAttributeTable] currentColumnField: $currentColumnField',
                );
                AppLogger.debug(
                  '[DynamicAttributeTable] features.length: ${features.length}',
                );

                if (currentCell != null &&
                    currentRowIdx != null &&
                    currentRowIdx >= 0 &&
                    currentRowIdx < features.length) {
                  final feature = features[currentRowIdx];

                  AppLogger.debug('[DynamicAttributeTable] 有効な行選択を検出');
                  AppLogger.debug('[DynamicAttributeTable] 選択フィーチャ情報:');
                  AppLogger.debug('  - rowId: ${feature.rowId}');
                  AppLogger.debug('  - name: ${feature.name}');
                  AppLogger.debug('  - layerName: ${feature.layerName}');
                  AppLogger.debug('  - フィーチャタイプ: ${feature.runtimeType}');
                  AppLogger.debug('  - 座標: ${feature.centroid}');

                  // 既に選択されている場合はスキップ（無限ループ防止）
                  if (GlobalConfig.instance.selectedFeatures.length == 1 &&
                      GlobalConfig.instance.selectedFeatures.first == feature) {
                    AppLogger.debug('[DynamicAttributeTable] 既に選択済み → スキップ');
                    return;
                  }

                  AppLogger.debug('[DynamicAttributeTable] GlobalConfigに追加開始');

                  // GlobalConfigのselectedFeaturesリストをクリアして選択されたFeatureNodeを追加
                  GlobalConfig.instance.selectedFeatures.clear();
                  GlobalConfig.instance.selectedFeatures.add(feature);

                  AppLogger.debug(
                    '[DynamicAttributeTable] GlobalConfig.selectedFeatures:',
                  );
                  AppLogger.debug(
                    '  - 選択フィーチャ数: ${GlobalConfig.instance.selectedFeatures.length}',
                  );
                  for (
                    int i = 0;
                    i < GlobalConfig.instance.selectedFeatures.length;
                    i++
                  ) {
                    final selectedFeature =
                        GlobalConfig.instance.selectedFeatures[i];
                    if (selectedFeature is FeatureNode) {
                      AppLogger.debug(
                        '  - [$i] ${selectedFeature.name} (ID: ${selectedFeature.rowId})',
                      );
                    } else {
                      AppLogger.debug('  - [$i] 型不明: ${selectedFeature.runtimeType}');
                    }
                  }

                  AppLogger.debug('[DynamicAttributeTable] onFeatureSelected コールバック呼び出し');
                  widget.onFeatureSelected?.call(feature);
                  AppLogger.debug('[DynamicAttributeTable] フィーチャ選択処理完了');
                } else {
                  AppLogger.debug('[DynamicAttributeTable] 無効な選択状態 → フィーチャ選択スキップ');
                }
                AppLogger.debug(
                  '[DynamicAttributeTable] ========================================',
                );
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
                columnTextStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
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
              // キーボードショートカットを全て無効化
              shortcut: const PlutoGridShortcut(actions: {}),
              enterKeyAction: PlutoGridEnterKeyAction.none,
            ),
          ),
        ),
      ],
    );
  }
}

