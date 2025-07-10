// K-MAPS: フィーチャノードクラス
// GeoPackage内のフィーチャに対応するレイヤツリーノード

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';
import 'dart:convert';
import 'layer_tree_node.dart';
import 'layer_node.dart';
import '../geopackage_file.dart';
import '../../utils/global_config.dart';
import '../../utils/feature_calc_utils.dart';

/// フィーチャノード基底クラス
/// LayerNodeの子としてfeature単位で生成される
abstract class FeatureNode extends LayerTreeNode {
  /// 属性値キャッシュ（DBから読み込んだ全属性値を保持）
  Map<String, dynamic> _cachedAttributes = {};

  /// 属性値の読み込み状態
  bool _attributesLoaded = true; // rowから初期化済み

  /// DB上のrowId（主キー）
  int get rowId => _getAttributeSync('id') as int? ?? 0;

  /// フィーチャの重心座標
  LatLng get centroid => _calculateCentroid();

  /// ジオメトリデータ
  dynamic get geometry => _getAttributeSync('geometry');

  /// 名前のgetter（辞書から取得）
  @override
  String get name => _getAttributeSync('name') as String? ?? 'Unnamed Feature';

  /// 名前のsetter（辞書に設定）
  set name(String value) => _setAttributeSync('name', value);

  /// 説明のgetter（辞書から取得）
  String? get description => _getAttributeSync('description') as String?;

  /// 説明のsetter（辞書に設定）
  set description(String? value) => _setAttributeSync('description', value);

  /// メタデータのgetter（辞書から取得）
  Map<String, dynamic>? get metadata {
    final value = _getAttributeSync('kmaps_metadata');
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

  /// メタデータのsetter（辞書に設定）
  set metadata(Map<String, dynamic>? value) {
    if (value == null) {
      _setAttributeSync('kmaps_metadata', null);
    } else {
      _setAttributeSync('kmaps_metadata', value);
    }
  }

  /// 重心座標を計算（サブクラスでオーバーライド）
  LatLng _calculateCentroid() {
    final geom = geometry;
    if (geom is List<LatLng> && geom.isNotEmpty) {
      return GeometryCalc.calcPointsCentroid(geom);
    } else if (geom is List<LatLng> && geom.isNotEmpty) {
      return GeometryCalc.calcLineCentroid(geom);
    } else if (geom is List<List<LatLng>> &&
        geom.isNotEmpty &&
        geom[0].isNotEmpty) {
      return GeometryCalc.calcPolygonCentroid(geom);
    }
    return LatLng(0, 0);
  }

  /// 属性値の同期取得（内部用）
  dynamic _getAttributeSync(String attributeName) {
    return _cachedAttributes[attributeName];
  }

  /// 属性値の同期設定（内部用）
  void _setAttributeSync(String attributeName, dynamic value) {
    // キャッシュに即座に反映（UI表示用）
    _cachedAttributes[attributeName] = value;

    // GeoPackageFileの遅延保存キューに追加
    geoPackageFile.queueAttributeUpdate(layerName, rowId, attributeName, value);
  }

  /// 属性値キャッシュの初期化（DBから全属性値を読み込み）
  Future<void> _loadAttributesFromDB() async {
    if (_attributesLoaded) return;

    try {
      print(
        '[DEBUG] FeatureNode: Loading attributes from DB for ${name} (rowId: $rowId)',
      );

      // DBから全属性値を取得
      final row = await geoPackageFile.getFeature(layerName, rowId);

      if (row != null) {
        _cachedAttributes = Map<String, dynamic>.from(row);
        print(
          '[DEBUG] FeatureNode: Loaded ${_cachedAttributes.length} attributes',
        );
      } else {
        print('[WARNING] FeatureNode: No attributes found for ${name}');
        _cachedAttributes = {};
      }

      _attributesLoaded = true;
    } catch (e) {
      print('[ERROR] FeatureNode: Failed to load attributes for ${name}: $e');
      _cachedAttributes = {};
    }
  }

  /// 属性値の取得（キャッシュから）
  Future<dynamic> getAttributeValue(String attributeName) async {
    // 属性値が未読み込みの場合は読み込み
    if (!_attributesLoaded) {
      await _loadAttributesFromDB();
    }

    return _getAttributeSync(attributeName);
  }

  /// 属性値の設定（キャッシュに保存し、バックグラウンドでDB書き込み）
  Future<void> setAttributeValue(String attributeName, dynamic value) async {
    print('[DEBUG] FeatureNode: Setting attribute $attributeName = $value');

    // 属性値が未読み込みの場合は読み込み
    if (!_attributesLoaded) {
      await _loadAttributesFromDB();
    }

    _setAttributeSync(attributeName, value);
  }

  /// 複数の属性値を一括設定
  Future<void> setAttributeValues(Map<String, dynamic> attributes) async {
    print('[DEBUG] FeatureNode: Setting ${attributes.length} attributes');

    // 属性値が未読み込みの場合は読み込み
    if (!_attributesLoaded) {
      await _loadAttributesFromDB();
    }

    // キャッシュに即座に反映
    _cachedAttributes.addAll(attributes);

    // GeoPackageFileの遅延保存キューに一括追加
    geoPackageFile.queueAttributeUpdates(layerName, rowId, attributes);
  }

  /// 全属性値を取得
  Future<Map<String, dynamic>> getAllAttributes() async {
    // 属性値が未読み込みの場合は読み込み
    if (!_attributesLoaded) {
      await _loadAttributesFromDB();
    }

    return Map<String, dynamic>.from(_cachedAttributes);
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

  /// rowデータを基にFeatureNodeを作成
  FeatureNode(Map<String, dynamic> row, this.parent)
    : super(
        row['name'] as String? ?? 'Unnamed Feature',
        visible: parent.visible,
        parent: parent,
        children: [],
        nodeType: 'feature',
      ) {
    // rowデータをそのまま_cachedAttributesに格納
    _cachedAttributes = Map<String, dynamic>.from(row);
    _attributesLoaded = true; // rowから初期化済み
  }

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
    : super(row, parent);

  /// 点座標リスト（geometryから取得）
  List<LatLng> get points => geometry as List<LatLng>? ?? <LatLng>[];

  @override
  LatLng _calculateCentroid() {
    return points.isNotEmpty
        ? GeometryCalc.calcPointsCentroid(points)
        : LatLng(0, 0);
  }

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
  /// DBへの保存は非同期で実行し、FeatureNodeは即座に作成・追加される
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

    // 属性値を辞書として準備
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (metadata != null) {
      attributes['kmaps_metadata'] = metadata;
    }

    // 新しい辞書ベースAPIを使用してDBへの保存を実行
    final actualRowId = await gpkgFile.addPointWithAttributes(
      layerName,
      point,
      attributes,
    );

    if (actualRowId == null) {
      print('[ERROR] PointFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // DBから実際のrowデータを取得
    final row = await gpkgFile.getFeature(layerName, actualRowId);
    if (row == null) {
      print('[ERROR] PointFeatureNode: 作成後のrow取得に失敗しました - $name');
      return null;
    }

    // rowデータを使用してFeatureNodeを作成
    final node = PointFeatureNode(row, parent);
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
    // 新しいジオメトリが渡された場合はそれを使用、なければ現在のpointsを使用
    final geometryToUpdate =
        newGeometry as LatLng? ?? (points.isNotEmpty ? points.first : null);

    if (geometryToUpdate == null) return false;

    final success = await geoPackageFile.updatePoint(
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
        'geometry': [geometryToUpdate],
      });

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
      // ローカルのジオメトリも更新
      await setAttributeValue('geometry', [newLocation]);
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
    : super(row, parent);

  /// 単一の線分（頂点リスト）
  List<LatLng> get line => geometry as List<LatLng>? ?? <LatLng>[];

  @override
  LatLng _calculateCentroid() {
    return line.isNotEmpty ? GeometryCalc.calcLineCentroid(line) : LatLng(0, 0);
  }

  @override
  List<MapEntry<String, String>> get detailEntries {
    final len = GeometryCalc.calcLineLength(line);
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
    final len = GeometryCalc.calcLineLength(line);
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
  /// DBへの保存を同期で実行し、実際のrowIdを取得してからFeatureNodeを作成
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

    // 属性値を辞書として準備
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (metadata != null) {
      attributes['kmaps_metadata'] = metadata;
    }

    // 新しい辞書ベースAPIを使用してDBへの保存を実行
    final actualRowId = await gpkgFile.addLineWithAttributes(
      layerName,
      line,
      attributes,
    );

    if (actualRowId == null) {
      print('[ERROR] LineFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // DBから実際のrowデータを取得
    final row = await gpkgFile.getFeature(layerName, actualRowId);
    if (row == null) {
      print('[ERROR] LineFeatureNode: 作成後のrow取得に失敗しました - $name');
      return null;
    }

    // rowデータを使用してFeatureNodeを作成
    final node = LineFeatureNode(row, parent);
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
      // ローカルのプロパティを一括更新
      await setAttributeValues({
        'name': name,
        'description': description,
        'kmaps_metadata': metadata,
        'geometry': geometryToUpdate,
      });

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
      // ローカルのジオメトリも更新
      await setAttributeValue('geometry', newLine);
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
    : super(row, parent);

  /// 単一のポリゴン（外環＋穴リスト）
  List<List<LatLng>> get polygon =>
      geometry as List<List<LatLng>>? ?? <List<LatLng>>[];

  @override
  LatLng _calculateCentroid() {
    return (polygon.isNotEmpty && polygon[0].isNotEmpty)
        ? GeometryCalc.calcPolygonCentroid(polygon)
        : LatLng(0, 0);
  }

  @override
  List<MapEntry<String, String>> get detailEntries {
    final areaDeg2 = GeometryCalc.calcPolygonArea(polygon);
    final centroid = this.centroid;
    final areaM2 = DegreeMeterConverter.convertAreaToMeters2(
      areaDeg2,
      centroid.latitude,
    );
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
    final areaDeg2 = GeometryCalc.calcPolygonArea(polygon);
    final centroid = this.centroid;
    final areaM2 = DegreeMeterConverter.convertAreaToMeters2(
      areaDeg2,
      centroid.latitude,
    );
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
      attributes['kmaps_metadata'] = metadata;
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
