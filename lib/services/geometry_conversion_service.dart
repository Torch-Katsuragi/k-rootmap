// lib/services/geometry_conversion_service.dart
// ジオメトリ変換サービス（ポイント⇔ライン/ポリゴン）
import 'dart:convert';
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

    // ポイントレイヤーの属性テーブルを取得してJSON化
    String? subTableJson;
    try {
      // getAll=trueで全カラムを取得（組み込みカラムも含む）
      final attributeTable = await sourceLayer.getAttributeTableData(getAll: true);
      print('[GeometryConversion] ポイントレイヤー「${sourceLayer.name}」の属性テーブル取得');
      print('[GeometryConversion] 行数: ${attributeTable.length}');
      if (attributeTable.isNotEmpty) {
        print('[GeometryConversion] ヘッダー行（カラム名）: ${attributeTable.first}');
        if (attributeTable.length > 1) {
          print('[GeometryConversion] データ行サンプル: ${attributeTable[1]}');
        }
      }
      
      if (attributeTable.length > 1) { // ヘッダー行 + 最低1データ行
        subTableJson = jsonEncode(attributeTable);
        print('[GeometryConversion] 属性テーブルをJSON化: ${subTableJson.length}文字');
      } else {
        print('[GeometryConversion] 属性テーブルが空（保存スキップ）');
      }
    } catch (e) {
      print('[GeometryConversion] 属性テーブル取得エラー: $e');
    }

    // 変換先レイヤーにsub_tableカラムを追加（存在しない場合）
    if (subTableJson != null) {
      try {
        await targetLayer.geoPackageFile.addAttributeColumn(
          targetLayer.layerName,
          'sub_table',
          'TEXT',
        );
        print('[GeometryConversion] sub_tableカラムを追加');
      } catch (e) {
        print('[GeometryConversion] sub_tableカラム追加エラー（既存の可能性）: $e');
      }
    }

    // レイヤータイプに応じてフィーチャを作成
    FeatureNode? createdFeature;
    if (targetLayer is LineLayerNode) {
      // ラインフィーチャを作成
      createdFeature = await LineFeatureNode.createIn(
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
      createdFeature = await PolygonFeatureNode.createIn(
        targetLayer,
        rings,
        'Converted from ${sourceLayer.name}',
        null,
      );
    }

    // sub_table属性を設定
    if (createdFeature != null && subTableJson != null) {
      try {
        print('[GeometryConversion] sub_table設定開始: rowId=${createdFeature.rowId}, layer=${createdFeature.layerName}');
        print('[GeometryConversion] 親レイヤーのfeature数: ${targetLayer.features.length}');
        
        // 少し待機（フィーチャが完全に登録されるまで）
        await Future.delayed(const Duration(milliseconds: 50));
        
        await createdFeature.setAttributeValue('sub_table', subTableJson);
        print('[GeometryConversion] sub_table属性を設定完了（メモリ）');
        
        // 即座にDBに保存（バックグラウンド保存を待たない）
        await createdFeature.flushChanges();
        print('[GeometryConversion] sub_table属性をDBに即座保存完了');
      } catch (e, stack) {
        print('[GeometryConversion] sub_table属性設定エラー: $e');
        print('[GeometryConversion] スタックトレース: $stack');
      }
    }
    
    return createdFeature;
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

    // sub_table属性から復元する属性テーブルを取得
    List<List<dynamic>>? attributeTable;
    try {
      final subTableValue = await sourceFeature.getAttributeValue('sub_table');
      if (subTableValue != null && subTableValue is String && subTableValue.isNotEmpty) {
        final decoded = jsonDecode(subTableValue);
        if (decoded is List) {
          attributeTable = decoded.map((row) => List<dynamic>.from(row as List)).toList();
          print('[GeometryConversion] 属性テーブルを復元: ${attributeTable.length}行');
        }
      }
    } catch (e) {
      print('[GeometryConversion] sub_table復元エラー: $e');
    }

    // 属性テーブルからカラム名とデータ行を分離
    List<String>? columnNames;
    List<List<dynamic>>? dataRows;
    if (attributeTable != null && attributeTable.isNotEmpty) {
      columnNames = attributeTable.first.map((col) => col.toString()).toList();
      dataRows = attributeTable.skip(1).toList();
      
      print('[GeometryConversion] 復元対象カラム: $columnNames');
      
      // 必要に応じて変換先レイヤーに属性カラムを追加
      int addedCount = 0;
      int skippedCount = 0;
      try {
        for (final columnName in columnNames) {
          // 組み込みカラム（id, geom）はスキップ
          if (columnName == 'id' || columnName == 'geom') {
            print('[GeometryConversion] カラムをスキップ（組み込み）: $columnName');
            skippedCount++;
            continue;
          }
          
          print('[GeometryConversion] カラムを追加: $columnName');
          await targetLayer.geoPackageFile.addAttributeColumn(
            targetLayer.layerName,
            columnName,
            'TEXT', // 型情報がないのでTEXTにフォールバック
          );
          addedCount++;
        }
        print('[GeometryConversion] 属性カラムを復元: ${addedCount}個追加, ${skippedCount}個スキップ');
      } catch (e) {
        print('[GeometryConversion] 属性カラム追加エラー: $e');
      }
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
        
        // 属性テーブルがあれば、対応する行の属性を復元
        if (dataRows != null && columnNames != null && i < dataRows.length) {
          try {
            final rowData = dataRows[i];
            final attributes = <String, dynamic>{};
            
            print('[GeometryConversion] ポイント${i + 1}: データ行=${rowData}');
            
            for (int colIdx = 0; colIdx < columnNames.length && colIdx < rowData.length; colIdx++) {
              final columnName = columnNames[colIdx];
              // 組み込みカラムはスキップ
              if (columnName == 'id' || columnName == 'geom') {
                print('[GeometryConversion]   カラム[$columnName]をスキップ（組み込み）');
                continue;
              }
              
              final value = rowData[colIdx];
              attributes[columnName] = value;
              print('[GeometryConversion]   カラム[$columnName] = $value');
            }
            
            if (attributes.isNotEmpty) {
              print('[GeometryConversion] ポイント${i + 1}に属性を設定: $attributes');
              await pointFeature.setAttributeValues(attributes);
              
              // 即座にDBに保存（updateChildren()の前に確実に保存）
              await pointFeature.flushChanges();
              print('[GeometryConversion] ポイント${i + 1}の属性設定完了＆DB保存: ${attributes.length}個');
            } else {
              print('[GeometryConversion] ポイント${i + 1}: 復元する属性なし');
            }
          } catch (e) {
            print('[GeometryConversion] ポイント${i + 1}の属性復元エラー: $e');
          }
        }
      }
    }

    return createdFeatures;
  }
}

