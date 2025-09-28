// K-MAPS: フィーチャノードクラス
// GeoPackage内のフィーチャに対応するレイヤツリーノード
// turf_dartのFeatureオブジェクトをメインデータとして使用

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' as turf;
import 'dart:async';
import 'dart:convert';
import 'layer_tree_node.dart';
import 'layer_node.dart';
import '../geopackage_file.dart';
import '../../utils/global_config.dart';
import '../../converters/turf_converter.dart';

/// フィーチャノード基底クラス
/// LayerNodeの子としてfeature単位で生成される
/// turf_dartのFeatureオブジェクトをメインデータとして内部的に保持
abstract class FeatureNode extends LayerTreeNode {
  /// turf_dartのFeatureオブジェクト（メインデータ）
  turf.Feature _turfFeature;

  /// 変更の追跡フラグ
  bool _isDirty = false;

  /// turf_dartのFeatureオブジェクトを取得
  turf.Feature get turfFeature => _turfFeature;

  /// DB上のrowId（主キー）
  int get rowId => _turfFeature.properties?['id'] as int? ?? 0;

  /// フィーチャの重心座標（turf_dartで計算）
  LatLng get centroid {
    final calculatedCentroid = TurfConverter.calculateCentroid(_turfFeature);
    return calculatedCentroid ?? LatLng(0, 0);
  }

  /// 座標データをposition型で取得（turf_dart形式）
  List<double> get position {
    final geometry = _turfFeature.geometry;
    if (geometry is turf.Point) {
      return TurfConverter.latlngToPosition(
        TurfConverter.pointToLatlng(geometry),
      );
    }
    // Point以外の場合は重心のpositionを返す
    return TurfConverter.latlngToPosition(centroid);
  }

  /// 複数座標データをpositionリストで取得
  List<List<double>> get positions {
    final geometry = _turfFeature.geometry;
    if (geometry is turf.LineString) {
      return TurfConverter.latlngsToPositions(
        TurfConverter.lineStringToLatlngs(geometry),
      );
    } else if (geometry is turf.Polygon) {
      // 外環のみを返す（最初のリング）
      final rings = TurfConverter.polygonToLatlngs(geometry);
      if (rings.isNotEmpty) {
        return TurfConverter.latlngsToPositions(rings.first);
      }
    }
    return [];
  }

  /// ジオメトリデータ（レガシー互換用、turf_dartから変換して返す）
  dynamic get geometry {
    final geom = _turfFeature.geometry;
    if (geom is turf.Point) {
      return [TurfConverter.pointToLatlng(geom)];
    } else if (geom is turf.LineString) {
      return TurfConverter.lineStringToLatlngs(geom);
    } else if (geom is turf.Polygon) {
      return TurfConverter.polygonToLatlngs(geom);
    }
    return null;
  }

  /// 名前のgetter（turf_dartのpropertiesから取得）
  @override
  String get name =>
      _turfFeature.properties?['name'] as String? ?? 'Unnamed Feature';

  /// 名前のsetter（turf_dartのpropertiesに設定）
  set name(String value) {
    _turfFeature.properties ??= {};
    _turfFeature.properties!['name'] = value;
    _markDirty();
  }

  /// 説明のgetter（turf_dartのpropertiesから取得）
  String? get description => _turfFeature.properties?['description'] as String?;

  /// 説明のsetter（turf_dartのpropertiesに設定）
  set description(String? value) {
    _turfFeature.properties ??= {};
    _turfFeature.properties!['description'] = value;
    _markDirty();
  }

  /// メタデータのgetter（turf_dartのpropertiesから取得）
  Map<String, dynamic>? get metadata {
    final value = _turfFeature.properties?['kmaps_metadata'];
    if (value == null) return null;
    if (value is Map<String, dynamic>) return value;
    if (value is String) {
      try {
        return Map<String, dynamic>.from(json.decode(value));
      } catch (e) {
        print('[WARNING] FeatureNode: Failed to parse metadata JSON: $e');
        return null;
      }
    }
    return null;
  }

  /// メタデータのsetter（turf_dartのpropertiesに設定）
  set metadata(Map<String, dynamic>? value) {
    _turfFeature.properties ??= {};
    _turfFeature.properties!['kmaps_metadata'] = value;
    _markDirty();
  }

  /// 変更フラグをセット
  void _markDirty() {
    _isDirty = true;
    // GeoPackageFileの遅延保存キューに追加
    final rowData = TurfConverter.featureToRowData(_turfFeature);
    if (rowData != null) {
      geoPackageFile.queueAttributeUpdates(layerName, rowId, rowData);
    }
  }

  /// 属性値の取得（turf_dartのpropertiesから）
  Future<dynamic> getAttributeValue(String attributeName) async {
    return _turfFeature.properties?[attributeName];
  }

  /// 属性値の設定（turf_dartのpropertiesに設定し、バックグラウンドでDB書き込み）
  Future<void> setAttributeValue(String attributeName, dynamic value) async {
    print('[DEBUG] FeatureNode: Setting attribute $attributeName = $value');

    _turfFeature.properties ??= {};
    _turfFeature.properties![attributeName] = value;
    _markDirty();
  }

  /// 複数の属性値を一括設定
  Future<void> setAttributeValues(Map<String, dynamic> attributes) async {
    print('[DEBUG] FeatureNode: Setting ${attributes.length} attributes');

    _turfFeature.properties ??= {};
    _turfFeature.properties!.addAll(attributes);
    _markDirty();
  }

  /// 全属性値を取得
  Future<Map<String, dynamic>> getAllAttributes() async {
    return Map<String, dynamic>.from(_turfFeature.properties ?? {});
  }

  /// 即座に全ての変更をDBに保存
  Future<void> flushChanges() async {
    await geoPackageFile.flushChanges();
  }

  /// 属性値の直接編集（レガシー互換用）
  @Deprecated('Use setAttributeValue instead')
  Future<void> editAttribute(String attributeName, dynamic newValue) async {
    await setAttributeValue(attributeName, newValue);
  }

  /// 詳細情報（項目名と値のペア、順序付き）
  List<MapEntry<String, String>> get detailEntries => [
    MapEntry('name', name),
    if (description != null && description!.isNotEmpty)
      MapEntry('description', description!),
    if (metadata != null && metadata!.isNotEmpty)
      ...metadata!.entries.map(
        (e) => MapEntry('metadata.${e.key}', e.value.toString()),
      ),
    MapEntry('id', rowId.toString()),
    MapEntry('latitude', centroid.latitude.toStringAsFixed(6)),
    MapEntry('longitude', centroid.longitude.toStringAsFixed(6)),
  ];

  /// 詳細情報をMap形式で返す（表示用）
  Map<String, String> get infoMap {
    final details = <String, String>{};

    // 基本情報
    details['name'] = name;
    if (description != null && description!.isNotEmpty) {
      details['description'] = description!;
    }

    // メタデータ
    if (metadata != null && metadata!.isNotEmpty) {
      for (final entry in metadata!.entries) {
        details['metadata.${entry.key}'] = entry.value.toString();
      }
    }

    // ID情報
    details['id'] = rowId.toString();

    // 座標情報
    details['latitude'] = centroid.latitude.toStringAsFixed(6);
    details['longitude'] = centroid.longitude.toStringAsFixed(6);

    return details;
  }

  /// フィーチャ削除（親子関係切断・UI更新の最適化）
  /// DBからの削除も基底クラスで統一処理
  @override
  Future<void> dispose() async {
    print('[DEBUG] FeatureNode.dispose: disposing ${name} (${runtimeType})');

    // 保留中の変更を即座に保存
    await flushChanges();

    // 即座に親子関係を切断（UI更新を優先）
    parent.children.remove(this);
    print('[DEBUG] FeatureNode.dispose: removed from parent children');

    // 選択状態からも除去
    final globalConfig = GlobalConfig.instance;
    if (globalConfig.selectedFeatures.contains(this)) {
      globalConfig.selectedFeatures.remove(this);
      print('[DEBUG] FeatureNode.dispose: removed from selected features');
    }

    // 子ノードはFeatureNodeにはないが、安全のためクリア
    children.clear();

    // DBからID指定で削除を非同期で実行（UIには影響させない）
    geoPackageFile
        .removeFeature(layerName, rowId)
        .then((_) {
          print(
            '[DEBUG] FeatureNode.dispose: DB deletion completed for ${name}',
          );
        })
        .catchError((e) {
          print(
            '[ERROR] FeatureNode.dispose: DB deletion failed for ${name}: $e',
          );
        });

    print('[DEBUG] FeatureNode.dispose: base dispose completed for ${name}');

    // 基底クラスのdisposeを呼び出し
    await super.dispose();
  }

  /// 親LayerNode
  @override
  final LayerNode parent;

  /// rowデータとジオメトリタイプを基にFeatureNodeを作成
  FeatureNode(Map<String, dynamic> row, this.parent, String geometryType)
    : _turfFeature =
          TurfConverter.createFeatureFromRow(row, geometryType) ??
          turf.Feature(
            geometry: turf.Point(coordinates: turf.Position.of([0, 0])),
            properties: row,
          ),
      super(
        row['name'] as String? ?? 'Unnamed Feature',
        visible: parent.visible,
        parent: parent,
        children: [],
        nodeType: 'feature',
      );

  /// turf_dartのFeatureオブジェクトから直接FeatureNodeを作成
  FeatureNode.fromTurfFeature(this._turfFeature, this.parent)
    : super(
        _turfFeature.properties?['name'] as String? ?? 'Unnamed Feature',
        visible: parent.visible,
        parent: parent,
        children: [],
        nodeType: 'feature',
      );

  /// GeoPackageFile参照
  GeoPackageFile get geoPackageFile => parent.geoPackageFile;

  /// レイヤ名
  String get layerName => parent.layerName;

  /// ジオメトリと属性を更新する抽象メソッド
  /// サブクラスでジオメトリ型に応じた具体的な実装を行う
  Future<bool> updateGeometry({
    required String name,
    String? description,
    Map<String, dynamic>? metadata,
    dynamic newGeometry,
  }) async {
    // 基底クラスでは何もしない（サブクラスでオーバーライド必須）
    throw UnimplementedError('updateGeometry must be implemented by subclass');
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeatureNode &&
        other.rowId == rowId &&
        other.layerName == layerName &&
        other.geoPackageFile == geoPackageFile;
  }

  @override
  int get hashCode => Object.hash(rowId, layerName, geoPackageFile);
}

/// PointFeatureNode: 点フィーチャ用
class PointFeatureNode extends FeatureNode {
  /// rowデータから点フィーチャノードを作成
  PointFeatureNode(Map<String, dynamic> row, LayerNode parent)
    : super(row, parent, 'Point');

  /// turf_dartのFeatureから点フィーチャノードを作成
  PointFeatureNode.fromTurfFeature(turf.Feature feature, LayerNode parent)
    : super.fromTurfFeature(feature, parent);

  /// 点座標（単一座標）
  LatLng get point {
    final geometry = turfFeature.geometry;
    if (geometry is turf.Point) {
      return TurfConverter.pointToLatlng(geometry);
    }
    return LatLng(0, 0);
  }

  /// 点座標をposition形式で取得
  @override
  List<double> get position {
    return TurfConverter.latlngToPosition(point);
  }

  /// 点座標リスト（レガシー互換用）
  List<LatLng> get points => [point];

  @override
  List<MapEntry<String, String>> get detailEntries {
    return [...super.detailEntries];
  }

  @override
  IconData get baseIcon => Icons.location_on;
  @override
  Color get baseIconColor => Colors.red;
  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  /// 指定したPointLayerNodeの下に新しい点フィーチャを作成し、PointFeatureNodeインスタンスを返す
  /// turf_dartのFeatureオブジェクトを作成してからDBに保存
  static Future<PointFeatureNode?> createIn(
    LayerNode parent,
    LatLng point,
    String name,
    String? description, {
    Map<String, dynamic>? metadata,
  }) async {
    if (parent is! PointLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;

    // turf_dartのFeatureオブジェクトを作成
    final properties = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (metadata != null) {
      properties['kmaps_metadata'] = jsonEncode(metadata);
    }

    final turfFeature = turf.Feature(
      geometry: TurfConverter.createPoint(point),
      properties: properties,
    );

    // FeatureNodeを先に作成
    final node = PointFeatureNode.fromTurfFeature(turfFeature, parent);

    // DBへの保存を実行
    final actualRowId = await gpkgFile.addPointWithAttributes(
      layerName,
      point,
      properties,
    );

    if (actualRowId == null) {
      print('[ERROR] PointFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // DBから実際のrowIdをturf_dartのpropertiesに設定
    node._turfFeature.properties!['id'] = actualRowId;
    parent.addChild(node);

    print('[DEBUG] PointFeatureNode: DB保存完了 - $name (rowId: $actualRowId)');
    return node;
  }

  /// 点フィーチャのジオメトリと属性を更新
  @override
  Future<bool> updateGeometry({
    required String name,
    String? description,
    Map<String, dynamic>? metadata,
    dynamic newGeometry,
  }) async {
    // 新しいジオメトリが渡された場合はそれを使用、なければ現在のpointを使用
    final geometryToUpdate = newGeometry as LatLng? ?? point;

    final success = await geoPackageFile.updatePoint(
      layerName,
      rowId,
      geometryToUpdate,
      name: name,
      description: description ?? '',
      metadata: metadata,
    );

    if (success) {
      // turf_dartのFeatureオブジェクトを更新
      _turfFeature = turf.Feature(
        geometry: TurfConverter.createPoint(geometryToUpdate),
        properties: {
          ..._turfFeature.properties ?? {},
          'name': name,
          'description': description,
          'kmaps_metadata': metadata,
        },
      );
      _markDirty();

      print('[DEBUG] PointFeatureNode: ジオメトリ更新成功 - $name');
    } else {
      print('[ERROR] PointFeatureNode: ジオメトリ更新失敗 - $name');
    }

    return success;
  }

  /// 点フィーチャのジオメトリのみを更新（位置変更）
  Future<bool> updateLocation(LatLng newLocation) async {
    final success = await geoPackageFile.updatePoint(
      layerName,
      rowId,
      newLocation,
      name: name,
      description: description ?? '',
      metadata: metadata,
    );

    if (success) {
      // turf_dartのジオメトリを更新
      _turfFeature = turf.Feature(
        geometry: TurfConverter.createPoint(newLocation),
        properties: _turfFeature.properties,
      );
      _markDirty();
      print('[DEBUG] PointFeatureNode: 位置更新成功 - $name to $newLocation');
    } else {
      print('[ERROR] PointFeatureNode: 位置更新失敗 - $name');
    }

    return success;
  }
}

/// LineFeatureNode: 線フィーチャ用
class LineFeatureNode extends FeatureNode {
  /// rowデータから線フィーチャノードを作成
  LineFeatureNode(Map<String, dynamic> row, LayerNode parent)
    : super(row, parent, 'LineString');

  /// turf_dartのFeatureから線フィーチャノードを作成
  LineFeatureNode.fromTurfFeature(turf.Feature feature, LayerNode parent)
    : super.fromTurfFeature(feature, parent);

  /// 単一の線分（頂点リスト）
  List<LatLng> get line {
    final geometry = turfFeature.geometry;
    if (geometry is turf.LineString) {
      return TurfConverter.lineStringToLatlngs(geometry);
    }
    return [];
  }

  /// 線の座標をpositionリストで取得
  @override
  List<List<double>> get positions {
    return TurfConverter.latlngsToPositions(line);
  }

  /// 線の長さを計算（turf_dartで計算）
  double get length {
    final calculatedLength = TurfConverter.calculateLength(turfFeature);
    return calculatedLength ?? 0.0;
  }

  @override
  List<MapEntry<String, String>> get detailEntries {
    final len = length;
    String lengthStr;
    if (len >= 10000) {
      lengthStr = '${(len / 1000).toStringAsFixed(2)} km';
    } else {
      lengthStr = '${len.toStringAsFixed(2)} m';
    }
    return [
      ...super.detailEntries,
      MapEntry('length', lengthStr),
      MapEntry('vertex_count', '${line.length}'),
    ];
  }

  @override
  Map<String, String> get infoMap {
    final details = <String, String>{};

    // 基底クラスの情報をコピー
    details.addAll(super.infoMap);

    // 線の長さ情報
    final len = length;
    String lengthStr;
    if (len >= 10000) {
      lengthStr = '${(len / 1000).toStringAsFixed(2)} km';
    } else {
      lengthStr = '${len.toStringAsFixed(2)} m';
    }
    details['length'] = lengthStr;

    // 頂点数情報
    details['vertex_count'] = '${line.length}';

    return details;
  }

  @override
  IconData get baseIcon => Icons.timeline;
  @override
  Color get baseIconColor => Colors.blueGrey;
  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  /// 指定したLineLayerNodeの下に新しい線フィーチャを作成し、LineFeatureNodeインスタンスを返す
  /// turf_dartのFeatureオブジェクトを作成してからDBに保存
  static Future<LineFeatureNode?> createIn(
    LayerNode parent,
    List<LatLng> line,
    String name,
    String? description, {
    Map<String, dynamic>? metadata,
  }) async {
    if (parent is! LineLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;

    // turf_dartのFeatureオブジェクトを作成
    final properties = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (metadata != null) {
      properties['kmaps_metadata'] = jsonEncode(metadata);
    }

    final turfFeature = turf.Feature(
      geometry: TurfConverter.createLineString(line),
      properties: properties,
    );

    // FeatureNodeを先に作成
    final node = LineFeatureNode.fromTurfFeature(turfFeature, parent);

    // DBへの保存を実行
    final actualRowId = await gpkgFile.addLineWithAttributes(
      layerName,
      line,
      properties,
    );

    if (actualRowId == null) {
      print('[ERROR] LineFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // DBから実際のrowIdをturf_dartのpropertiesに設定
    node._turfFeature.properties!['id'] = actualRowId;
    parent.addChild(node);

    print('[DEBUG] LineFeatureNode: DB保存完了 - $name (rowId: $actualRowId)');
    return node;
  }

  /// 線フィーチャのジオメトリと属性を更新
  @override
  Future<bool> updateGeometry({
    required String name,
    String? description,
    Map<String, dynamic>? metadata,
    dynamic newGeometry,
  }) async {
    // 新しいジオメトリが渡された場合はそれを使用、なければ現在のlineを使用
    final geometryToUpdate = newGeometry as List<LatLng>? ?? line;

    final success = await geoPackageFile.updateLine(
      layerName,
      rowId,
      geometryToUpdate,
      name: name,
      description: description ?? '',
      metadata: metadata,
    );

    if (success) {
      // turf_dartのFeatureオブジェクトを更新
      _turfFeature = turf.Feature(
        geometry: TurfConverter.createLineString(geometryToUpdate),
        properties: {
          ..._turfFeature.properties ?? {},
          'name': name,
          'description': description,
          'kmaps_metadata': metadata,
        },
      );
      _markDirty();

      print('[DEBUG] LineFeatureNode: ジオメトリ更新成功 - $name');
    } else {
      print('[ERROR] LineFeatureNode: ジオメトリ更新失敗 - $name');
    }

    return success;
  }

  /// 線フィーチャのジオメトリのみを更新（頂点変更）
  Future<bool> updateLine(List<LatLng> newLine) async {
    final success = await geoPackageFile.updateLine(
      layerName,
      rowId,
      newLine,
      name: name,
      description: description ?? '',
      metadata: metadata,
    );

    if (success) {
      // turf_dartのジオメトリを更新
      _turfFeature = turf.Feature(
        geometry: TurfConverter.createLineString(newLine),
        properties: _turfFeature.properties,
      );
      _markDirty();
      print(
        '[DEBUG] LineFeatureNode: 線更新成功 - $name (${newLine.length} vertices)',
      );
    } else {
      print('[ERROR] LineFeatureNode: 線更新失敗 - $name');
    }

    return success;
  }
}

/// PolygonFeatureNode: 面フィーチャ用
class PolygonFeatureNode extends FeatureNode {
  /// rowデータから面フィーチャノードを作成
  PolygonFeatureNode(Map<String, dynamic> row, LayerNode parent)
    : super(row, parent, 'Polygon');

  /// turf_dartのFeatureから面フィーチャノードを作成
  PolygonFeatureNode.fromTurfFeature(turf.Feature feature, LayerNode parent)
    : super.fromTurfFeature(feature, parent);

  /// 単一のポリゴン（外環＋穴リスト）
  List<List<LatLng>> get polygon {
    final geometry = turfFeature.geometry;
    if (geometry is turf.Polygon) {
      return TurfConverter.polygonToLatlngs(geometry);
    }
    return [];
  }

  /// ポリゴンの座標をpositionリストで取得（外環のみ）
  @override
  List<List<double>> get positions {
    final rings = polygon;
    if (rings.isNotEmpty) {
      return TurfConverter.latlngsToPositions(rings.first);
    }
    return [];
  }

  /// ポリゴンの面積を計算（turf_dartで計算）
  double get area {
    final calculatedArea = TurfConverter.calculateArea(turfFeature);
    return calculatedArea ?? 0.0;
  }

  @override
  List<MapEntry<String, String>> get detailEntries {
    final areaM2 = area; // turf_dartで計算された面積（平方メートル）
    String areaStr;
    if (areaM2 >= 10000) {
      areaStr = '${(areaM2 / 10000).toStringAsFixed(3)} ha';
    } else {
      areaStr = '${areaM2.toStringAsFixed(3)} m²';
    }
    // 全リングの頂点数の合計を計算（閉じたリングの最後の点を除く）
    final totalVertices = polygon.fold<int>(0, (sum, ring) {
      if (ring.isEmpty) return sum;
      // 閉じたリングの場合は最後の点を除く（最初と最後が同じため）
      return sum + (ring.length > 1 ? ring.length - 1 : ring.length);
    });
    return [
      ...super.detailEntries,
      MapEntry('area', areaStr),
      MapEntry('vertex_count', '$totalVertices'),
    ];
  }

  @override
  Map<String, String> get infoMap {
    final details = <String, String>{};

    // 基底クラスの情報をコピー
    details.addAll(super.infoMap);

    // 面積情報
    final areaM2 = area; // turf_dartで計算された面積（平方メートル）
    String areaStr;
    if (areaM2 >= 10000) {
      areaStr = '${(areaM2 / 10000).toStringAsFixed(3)} ha';
    } else {
      areaStr = '${areaM2.toStringAsFixed(3)} m²';
    }
    details['area'] = areaStr;

    // 頂点数情報（閉じたリングの最後の点を除く）
    final totalVertices = polygon.fold<int>(0, (sum, ring) {
      if (ring.isEmpty) return sum;
      // 閉じたリングの場合は最後の点を除く（最初と最後が同じため）
      return sum + (ring.length > 1 ? ring.length - 1 : ring.length);
    });
    details['vertex_count'] = '$totalVertices';

    return details;
  }

  @override
  IconData get baseIcon => Icons.crop_square;
  @override
  Color get baseIconColor => Colors.orange;
  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  /// 指定したPolygonLayerNodeの下に新しい面フィーチャを作成し、PolygonFeatureNodeインスタンスを返す
  /// DBへの保存を同期で実行し、実際のrowIdを取得してからFeatureNodeを作成
  static Future<PolygonFeatureNode?> createIn(
    LayerNode parent,
    List<List<LatLng>> polygon,
    String name,
    String? description, {
    Map<String, dynamic>? metadata,
  }) async {
    if (parent is! PolygonLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;
    if (polygon.isEmpty) return null;

    // 属性値を辞書として準備
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (metadata != null) {
      attributes['kmaps_metadata'] = jsonEncode(metadata);
    }

    // 新しい辞書ベースAPIを使用してDBへの保存を実行
    final actualRowId = await gpkgFile.addPolygonWithAttributes(
      layerName,
      polygon,
      attributes,
    );

    if (actualRowId == null) {
      print('[ERROR] PolygonFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // DBから実際のrowデータを取得
    final row = await gpkgFile.getFeature(layerName, actualRowId);
    if (row == null) {
      print('[ERROR] PolygonFeatureNode: 作成後のrow取得に失敗しました - $name');
      return null;
    }

    // rowデータを使用してFeatureNodeを作成
    final node = PolygonFeatureNode(row, parent);
    parent.addChild(node);

    print('[DEBUG] PolygonFeatureNode: DB保存完了 - $name (rowId: $actualRowId)');
    return node;
  }

  /// 面フィーチャのジオメトリと属性を更新
  @override
  Future<bool> updateGeometry({
    required String name,
    String? description,
    Map<String, dynamic>? metadata,
    dynamic newGeometry,
  }) async {
    // 新しいジオメトリが渡された場合はそれを使用、なければ現在のpolygonを使用
    final geometryToUpdate = newGeometry as List<List<LatLng>>? ?? polygon;

    final success = await geoPackageFile.updatePolygon(
      layerName,
      rowId,
      geometryToUpdate,
      name: name,
      description: description ?? '',
      metadata: metadata,
    );

    if (success) {
      // ローカルのプロパティを一括更新
      await setAttributeValues({
        'name': name,
        'description': description,
        'kmaps_metadata': metadata,
        'geometry': geometryToUpdate,
      });

      print('[DEBUG] PolygonFeatureNode: ジオメトリ更新成功 - $name');
    } else {
      print('[ERROR] PolygonFeatureNode: ジオメトリ更新失敗 - $name');
    }

    return success;
  }

  /// 面フィーチャのジオメトリのみを更新（ポリゴン変更）
  Future<bool> updatePolygon(List<List<LatLng>> newPolygon) async {
    final success = await geoPackageFile.updatePolygon(
      layerName,
      rowId,
      newPolygon,
      name: name,
      description: description ?? '',
      metadata: metadata,
    );

    if (success) {
      // ローカルのジオメトリも更新
      await setAttributeValue('geometry', newPolygon);
      print(
        '[DEBUG] PolygonFeatureNode: ポリゴン更新成功 - $name (${newPolygon.length} rings)',
      );
    } else {
      print('[ERROR] PolygonFeatureNode: ポリゴン更新失敗 - $name');
    }

    return success;
  }
}
