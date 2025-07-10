// K-MAPS: フィーチャノードクラス
// GeoPackage内のフィーチャに対応するレイヤツリーノード

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'layer_tree_node.dart';
import 'layer_node.dart';
import '../geopackage_file.dart';
import '../../utils/global_config.dart';
import '../../utils/feature_calc_utils.dart';

/// フィーチャノード基底クラス
/// LayerNodeの子としてfeature単位で生成される
abstract class FeatureNode extends LayerTreeNode {
  /// 属性値
  @override
  String name;
  String? description;

  /// メタデータ（構造化されたデータ）
  Map<String, dynamic>? metadata;

  /// DB上のrowId（主キー）
  final int rowId;

  /// フィーチャの重心座標
  final LatLng centroid;

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

  /// 指定した属性名に対応する値をDBから取得
  Future<dynamic> getAttributeValue(String attributeName) async {
    // geoPackageFileから都度取得
    return await geoPackageFile.getFeatureAttribute(
      layerName,
      rowId,
      attributeName,
    );
  }

  /// フィーチャ削除（親子関係切断・UI更新の最適化）
  /// DBからの削除は各サブクラスで実装（ジオメトリ型に応じた適切な削除処理）
  @override
  Future<void> dispose() async {
    print('[DEBUG] FeatureNode.dispose: disposing ${name} (${runtimeType})');

    // 即座に親子関係を切断（UI更新を優先）
    if (parent != null) {
      parent!.children.remove(this);
      print('[DEBUG] FeatureNode.dispose: removed from parent children');
    }

    // 選択状態からも除去
    final globalConfig = GlobalConfig.instance;
    if (globalConfig.selectedFeatures.contains(this)) {
      globalConfig.selectedFeatures.remove(this);
      print('[DEBUG] FeatureNode.dispose: removed from selected features');
    }

    // parentを切断
    parent = null;

    // 子ノードはFeatureNodeにはないが、安全のためクリア
    children.clear();

    print('[DEBUG] FeatureNode.dispose: base dispose completed for ${name}');
  }

  /// ジオメトリ型ごとのデータ参照（点・線・面）
  Object get geometry;

  /// 親LayerNode
  @override
  final LayerNode parent;

  FeatureNode({
    required this.name,
    this.description,
    this.metadata,
    required this.parent,
    required this.rowId,
    required this.centroid,
  }) : super(
         name,
         visible: parent.visible,
         parent: parent,
         children: [],
         nodeType: 'feature',
       );

  /// GeoPackageFile参照
  GeoPackageFile get geoPackageFile => parent.geoPackageFile;

  /// レイヤ名
  String get layerName => parent.layerName;

  /// 指定した属性名の値をDB上で編集
  Future<void> editAttribute(String attributeName, dynamic newValue) async {
    await geoPackageFile.updateFeatureAttribute(
      layerName,
      rowId,
      attributeName,
      newValue,
    );
  }

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
  final List<LatLng> points;
  PointFeatureNode(
    this.points,
    String name, {
    required super.parent,
    required super.rowId,
    super.description,
    super.metadata,
  }) : super(name: name, centroid: GeometryCalc.calcPointsCentroid(points));

  @override
  List<MapEntry<String, String>> get detailEntries {
    return [...super.detailEntries];
  }

  @override
  Object get geometry => points;

  @override
  Future<void> dispose() async {
    print('[DEBUG] PointFeatureNode.dispose: disposing point feature ${name}');

    // 基底クラスの処理（親子関係切断・選択状態クリア）を先に実行
    await super.dispose();

    // DBからID指定で削除を非同期で実行（UIには影響させない）
    geoPackageFile
        .removePoint(layerName, rowId)
        .then((_) {
          print(
            '[DEBUG] PointFeatureNode.dispose: DB deletion completed for ${name}',
          );
        })
        .catchError((e) {
          print(
            '[ERROR] PointFeatureNode.dispose: DB deletion failed for ${name}: $e',
          );
        });

    print('[DEBUG] PointFeatureNode.dispose: point feature dispose completed');
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

    // DBへの保存を実行して実際のrowIdを取得
    final actualRowId = await gpkgFile.addPoint(
      layerName,
      point,
      name: name ?? '',
      description: description ?? '',
      metadata: metadata,
    );

    if (actualRowId == null) {
      print('[ERROR] PointFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // 実際のrowIdを使用してFeatureNodeを作成
    final node = PointFeatureNode(
      [point],
      name,
      parent: parent,
      rowId: actualRowId,
      description: description,
      metadata: metadata,
    );
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
      // ローカルのプロパティを更新
      this.name = name;
      this.description = description;
      this.metadata = metadata;

      // 新しいジオメトリが渡された場合はローカル変数も更新
      if (newGeometry != null) {
        points.clear();
        points.add(geometryToUpdate);
        print('[DEBUG] PointFeatureNode: ジオメトリ位置更新 - $geometryToUpdate');
      }

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
      // ローカルのジオメトリも更新（mutableリストなので直接変更）
      points.clear();
      points.add(newLocation);
      print('[DEBUG] PointFeatureNode: 位置更新成功 - $name to $newLocation');
    } else {
      print('[ERROR] PointFeatureNode: 位置更新失敗 - $name');
    }

    return success;
  }
}

/// LineFeatureNode: 線フィーチャ用
class LineFeatureNode extends FeatureNode {
  /// 単一の線分（頂点リスト）
  List<LatLng> line;
  LineFeatureNode(
    this.line,
    String name, {
    required super.parent,
    required super.rowId,
    super.description,
    super.metadata,
  }) : super(
         name: name,
         centroid:
             line.isNotEmpty
                 ? GeometryCalc.calcLineCentroid(line)
                 : LatLng(0, 0),
       );

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
  Object get geometry => line;

  @override
  Future<void> dispose() async {
    print('[DEBUG] LineFeatureNode.dispose: disposing line feature ${name}');

    // 基底クラスの処理（親子関係切断・選択状態クリア）を先に実行
    await super.dispose();

    // DBから該当線を削除（非同期で実行、UIには影響させない）
    geoPackageFile
        .removeLine(layerName, rowId)
        .then((_) {
          print(
            '[DEBUG] LineFeatureNode.dispose: DB deletion completed for ${name}',
          );
        })
        .catchError((e) {
          print(
            '[ERROR] LineFeatureNode.dispose: DB deletion failed for ${name}: $e',
          );
        });

    print('[DEBUG] LineFeatureNode.dispose: line feature dispose completed');
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

    // DBへの保存を実行して実際のrowIdを取得
    final actualRowId = await gpkgFile.addLine(
      layerName,
      line,
      name: name ?? '',
      description: description ?? '',
      metadata: metadata,
    );

    if (actualRowId == null) {
      print('[ERROR] LineFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // 実際のrowIdを使用してFeatureNodeを作成
    final node = LineFeatureNode(
      line,
      name,
      parent: parent,
      rowId: actualRowId,
      description: description,
      metadata: metadata,
    );
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
      // ローカルのプロパティを更新
      this.name = name;
      this.description = description;
      this.metadata = metadata;

      // 新しいジオメトリが渡された場合はローカル変数も更新（追記機能で重要！）
      if (newGeometry != null) {
        line.clear();
        line.addAll(geometryToUpdate);
        print(
          '[DEBUG] LineFeatureNode: ジオメトリ形状更新 - ${geometryToUpdate.length} vertices',
        );
      }

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
      // ローカルのジオメトリも更新（mutableリストなので直接変更）
      line.clear();
      line.addAll(newLine);
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
  /// 単一のポリゴン（外環＋穴リスト）
  List<List<LatLng>> polygon;
  PolygonFeatureNode(
    this.polygon,
    String name, {
    required super.parent,
    required super.rowId,
    super.description,
    super.metadata,
  }) : super(
         name: name,
         centroid:
             (polygon.isNotEmpty && polygon[0].isNotEmpty)
                 ? GeometryCalc.calcPolygonCentroid(polygon)
                 : LatLng(0, 0),
       );

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
  Object get geometry => polygon;

  @override
  Future<void> dispose() async {
    print(
      '[DEBUG] PolygonFeatureNode.dispose: disposing polygon feature ${name}',
    );

    // 基底クラスの処理（親子関係切断・選択状態クリア）を先に実行
    await super.dispose();

    // DBから該当ポリゴンを削除（非同期で実行、UIには影響させない）
    geoPackageFile
        .removePolygon(layerName, rowId)
        .then((_) {
          print(
            '[DEBUG] PolygonFeatureNode.dispose: DB deletion completed for ${name}',
          );
        })
        .catchError((e) {
          print(
            '[ERROR] PolygonFeatureNode.dispose: DB deletion failed for ${name}: $e',
          );
        });

    print(
      '[DEBUG] PolygonFeatureNode.dispose: polygon feature dispose completed',
    );
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

    // DBへの保存を実行して実際のrowIdを取得
    final actualRowId = await gpkgFile.addPolygon(
      layerName,
      polygon,
      name: name ?? '',
      description: description ?? '',
      metadata: metadata,
    );

    if (actualRowId == null) {
      print('[ERROR] PolygonFeatureNode: DB保存に失敗しました - $name');
      return null;
    }

    // 実際のrowIdを使用してFeatureNodeを作成
    final node = PolygonFeatureNode(
      polygon,
      name,
      parent: parent,
      rowId: actualRowId,
      description: description,
      metadata: metadata,
    );
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
      // ローカルのプロパティを更新
      this.name = name;
      this.description = description;
      this.metadata = metadata;

      // 新しいジオメトリが渡された場合はローカル変数も更新（追記機能で重要！）
      if (newGeometry != null) {
        polygon.clear();
        polygon.addAll(geometryToUpdate);
        print(
          '[DEBUG] PolygonFeatureNode: ジオメトリ形状更新 - ${geometryToUpdate.length} rings',
        );
      }

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
      // ローカルのジオメトリも更新（mutableリストなので直接変更）
      polygon.clear();
      polygon.addAll(newPolygon);
      print(
        '[DEBUG] PolygonFeatureNode: ポリゴン更新成功 - $name (${newPolygon.length} rings)',
      );
    } else {
      print('[ERROR] PolygonFeatureNode: ポリゴン更新失敗 - $name');
    }

    return success;
  }
}
