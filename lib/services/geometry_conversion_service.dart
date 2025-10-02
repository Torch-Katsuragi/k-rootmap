// lib/services/geometry_conversion_service.dart
// ジオメトリ変換サービス（ポイント⇔ライン/ポリゴン）
import 'package:latlong2/latlong.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';

/// ジオメトリ変換サービス
class GeometryConversionService {
  /// ポリゴンリングを閉じる（最初と最後の座標を同じにする）
  static List<LatLng> closeRing(List<LatLng> pts) {
    if (pts.length < 3) return [];
    final first = pts.first;
    final last = pts.last;
    bool isClosed = (first.latitude == last.latitude) && (first.longitude == last.longitude);
    if (!isClosed) {
      return List<LatLng>.from(pts)..add(first);
    }
    return pts;
  }

  /// ノードツリーからライン/ポリゴンレイヤーを同期的に検索
  static void searchLineAndPolygonLayers(LayerTreeNode node, List<LayerNode> result) {
    // FeatureNodeは検索しない（パフォーマンス最適化）
    if (node is FeatureNode) {
      return;
    }
    
    if (node is LineLayerNode || node is PolygonLayerNode) {
      result.add(node as LayerNode);
      // レイヤーが見つかったら、その子（FeatureNode）は検索しない
      return;
    }
    
    // FolderNodeとGeoPackageNodeの子を再帰的に検索
    for (final child in node.children) {
      searchLineAndPolygonLayers(child, result);
    }
  }

  /// ノードツリーからポイントレイヤーを検索
  static void searchPointLayers(LayerTreeNode node, List<PointLayerNode> result) {
    if (node is FeatureNode) return;
    
    if (node is PointLayerNode) {
      result.add(node);
      return;
    }
    
    for (final child in node.children) {
      searchPointLayers(child, result);
    }
  }

  /// カレントディレクトリ直下のGeoPackage内のライン/ポリゴンレイヤーを検索
  static List<LayerNode> findTargetLayersForPoints(LayerTreeNode? currentDir) {
    final targetLayers = <LayerNode>[];
    if (currentDir == null) return targetLayers;
    
    // currentNodeの直接の子（GeoPackageNode）のみを検索
    for (final child in currentDir.children) {
      if (child is GeoPackageNode) {
        searchLineAndPolygonLayers(child, targetLayers);
      }
    }
    
    return targetLayers;
  }

  /// カレントディレクトリ直下のGeoPackage内のポイントレイヤーを検索
  static List<PointLayerNode> findTargetLayersForGeometry(LayerTreeNode? currentDir) {
    final pointLayers = <PointLayerNode>[];
    if (currentDir == null) return pointLayers;
    
    // currentNodeの直接の子（GeoPackageNode）のみを検索
    for (final child in currentDir.children) {
      if (child is GeoPackageNode) {
        searchPointLayers(child, pointLayers);
      }
    }
    
    return pointLayers;
  }

  /// ポイントレイヤーをライン/ポリゴンに変換
  static Future<FeatureNode?> convertPointsToGeometry({
    required PointLayerNode sourceLayer,
    required LayerNode targetLayer,
  }) async {
    // ポイントの座標リストを作成
    final points = sourceLayer.features.map((feature) => feature.centroid).toList();
    
    if (points.isEmpty) {
      return null;
    }

    // レイヤータイプに応じてフィーチャを作成
    if (targetLayer is LineLayerNode) {
      // ラインフィーチャを作成
      return await LineFeatureNode.createIn(
        targetLayer,
        points,
        'Converted from ${sourceLayer.name}',
        null,
      );
    } else if (targetLayer is PolygonLayerNode) {
      // ポリゴンフィーチャを作成（外環のみ、穴なし）
      // リングを閉じる（最初と最後の座標を同じにする）
      final closedPoints = closeRing(points);
      if (closedPoints.isEmpty) {
        return null;
      }
      final rings = [closedPoints]; // 閉じた外環のみのリスト
      return await PolygonFeatureNode.createIn(
        targetLayer,
        rings,
        'Converted from ${sourceLayer.name}',
        null,
      );
    }
    
    return null;
  }

  /// ライン/ポリゴンフィーチャをポイントに変換
  static Future<List<PointFeatureNode>> convertGeometryToPoints({
    required FeatureNode sourceFeature,
    required PointLayerNode targetLayer,
  }) async {
    // 座標リストを取得
    List<LatLng> points = [];
    
    if (sourceFeature is LineFeatureNode) {
      // ラインの場合：全頂点を取得
      points = sourceFeature.line;
    } else if (sourceFeature is PolygonFeatureNode) {
      // ポリゴンの場合：外環（最初のリング）を取得
      final geometry = sourceFeature.geometry as List<List<LatLng>>?;
      if (geometry != null && geometry.isNotEmpty) {
        final outerRing = geometry.first;
        
        // 閉じたポリゴンの場合、最後の座標が最初と同じなら削除
        if (outerRing.length >= 2) {
          final first = outerRing.first;
          final last = outerRing.last;
          if (first.latitude == last.latitude && first.longitude == last.longitude) {
            // 最後の座標を除外
            points = outerRing.sublist(0, outerRing.length - 1);
          } else {
            points = outerRing;
          }
        } else {
          points = outerRing;
        }
      }
    }

    if (points.isEmpty) {
      return [];
    }

    // 各座標をポイントフィーチャとして追加
    final createdFeatures = <PointFeatureNode>[];
    for (int i = 0; i < points.length; i++) {
      final pointFeature = await PointFeatureNode.createIn(
        targetLayer,
        points[i],
        'Point ${i + 1} from ${sourceFeature.name}',
        null,
      );
      if (pointFeature != null) {
        createdFeatures.add(pointFeature);
      }
    }

    return createdFeatures;
  }
}

