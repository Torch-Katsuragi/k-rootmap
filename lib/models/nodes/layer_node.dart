// K-MAPS: レイヤノードクラス
// GeoPackage内のレイヤに対応するレイヤツリーノード

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'layer_tree_node.dart';
import 'geopackage_node.dart';
import 'feature_node.dart';
import '../geopackage_file.dart';
import '../geometry_type.dart';

/// レイヤノード（LayerNode）: GeoPackage内のフィーチャテーブル＋FeatureNodeコレクション
abstract class LayerNode extends LayerTreeNode {
  /// GeoPackageファイル管理クラスへの参照
  final GeoPackageFile geoPackageFile;

  /// レイヤ名（DBテーブル名）
  final String layerName;

  /// 親のGeoPackageNodeを取得
  GeoPackageNode get geoPackageNode {
    LayerTreeNode? current = parent;
    while (current != null) {
      if (current is GeoPackageNode) {
        return current;
      }
      current = current.parent;
    }
    throw StateError('LayerNode must have a GeoPackageNode parent');
  }

  /// このレイヤに含まれるFeatureNodeリスト（型安全なchildren）
  List<FeatureNode> get features =>
      super.children.whereType<FeatureNode>().toList();

  /// データベースからFeatureNodeを非同期で読み込み（プライベートメソッド）
  /// サブクラスでoverrideして具体的な実装を提供する
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    return <FeatureNode>[];
  }

  /// FeatureNodeを安全に追加するメソッド
  void addFeature(FeatureNode feature) {
    super.addChild(feature);
  }

  /// FeatureNodeを安全に削除するメソッド
  void removeFeature(FeatureNode feature) {
    super.removeChild(feature);
  }

  /// コンストラクタ
  LayerNode(
    this.geoPackageFile,
    this.layerName, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(layerName, visible: visible, parent: parent, nodeType: "layer");

  /// （サブクラスでoverride推奨）親ノード直下の自分型インスタンスリストを返す（非同期化）
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    final nodes = <LayerTreeNode>[];
    if (parent is! GeoPackageNode) return nodes;
    final gpkgNode = parent;
    final tableNames = await gpkgNode.geoPackageFile.getLayerNames();
    for (final tableName in tableNames) {
      final type = await gpkgNode.geoPackageFile.getGeometryType(tableName);
      if (type == GeometryType.point) {
        nodes.add(
          PointLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      } else if (type == GeometryType.linestring) {
        nodes.add(
          LineLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      } else if (type == GeometryType.polygon) {
        nodes.add(
          PolygonLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      }
    }
    return nodes;
  }

  @override
  Future<void> dispose() async {
    // レイヤ（DBテーブル）削除
    await geoPackageFile.removeLayer(layerName);
    await super.dispose();
  }

  @override
  Future<void> updateChildren() async {
    children.clear();
    // _loadFeaturesFromDBからFeatureNodeをchildrenに追加
    final featureList = await _loadFeaturesFromDB();
    for (final node in featureList) {
      addChild(node);
    }
  }
}

/// ポイントレイヤノード
class PointLayerNode extends LayerNode {
  PointLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    final rawFeatures = await geoPackageFile.getFeatures(layerName);
    final features = <FeatureNode>[];

    for (final rawRow in rawFeatures) {
      final rowId = rawRow['id'] as int?;
      if (rowId == null) continue;

      // getFeatureを使用してgeometry変換済みのrowデータを取得
      final row = await geoPackageFile.getFeature(layerName, rowId);
      if (row == null || row['geometry'] == null) continue;

      final featureNode = PointFeatureNode(row, this);
      features.add(featureNode);
    }

    return features;
  }

  @override
  IconData get baseIcon => Icons.scatter_plot;
  @override
  Color get baseIconColor => Colors.blue;

  /// 指定したGeoPackageNodeの下に新しいPointレイヤを作成し、PointLayerNodeインスタンスを返す
  static Future<PointLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    final exists = existingLayers.contains(name);
    if (exists) return null;
    await gpkgFile.addLayer(name, GeometryType.point);
    final node = PointLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

/// ラインレイヤノード
class LineLayerNode extends LayerNode {
  LineLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    final rawFeatures = await geoPackageFile.getFeatures(layerName);
    final features = <FeatureNode>[];

    for (final rawRow in rawFeatures) {
      final rowId = rawRow['id'] as int?;
      if (rowId == null) continue;

      // getFeatureを使用してgeometry変換済みのrowデータを取得
      final row = await geoPackageFile.getFeature(layerName, rowId);
      if (row == null || row['geometry'] == null) continue;

      final featureNode = LineFeatureNode(row, this);
      features.add(featureNode);
    }

    return features;
  }

  @override
  IconData get baseIcon => Icons.show_chart;
  @override
  Color get baseIconColor => Colors.green;

  /// 指定したGeoPackageNodeの下に新しいLineレイヤを作成し、LineLayerNodeインスタンスを返す
  static Future<LineLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    final exists = existingLayers.contains(name);
    if (exists) return null;
    await gpkgFile.addLayer(name, GeometryType.linestring);
    final node = LineLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

/// ポリゴンレイヤノード
class PolygonLayerNode extends LayerNode {
  PolygonLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    final rawFeatures = await geoPackageFile.getFeatures(layerName);
    final features = <FeatureNode>[];

    for (final rawRow in rawFeatures) {
      final rowId = rawRow['id'] as int?;
      if (rowId == null) continue;

      // getFeatureを使用してgeometry変換済みのrowデータを取得
      final row = await geoPackageFile.getFeature(layerName, rowId);
      if (row == null || row['geometry'] == null) continue;

      final featureNode = PolygonFeatureNode(row, this);
      features.add(featureNode);
    }

    return features;
  }

  @override
  IconData get baseIcon => Icons.terrain;
  @override
  Color get baseIconColor => Colors.deepOrange;

  /// 指定したGeoPackageNodeの下に新しいPolygonレイヤを作成し、PolygonLayerNodeインスタンスを返す
  static Future<PolygonLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    final exists = existingLayers.contains(name);
    if (exists) return null;
    await gpkgFile.addLayer(name, GeometryType.polygon);
    final node = PolygonLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}
