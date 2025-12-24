// K-MAPS: GeoJSON Importer
// GeoJSONインポートクラス（turfパッケージ活用版）
import 'dart:convert';
import 'dart:io';
import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:turf/turf.dart' as turf;
import '../import_export_models.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/geometry_type.dart';
import '../../../converters/turf_converter.dart';
import 'base_importer.dart';

/// GeoJSONインポーター（turfパッケージ活用）
class GeoJSONImporter extends BaseImporter {
  @override
  bool canHandle(String extension) {
    final ext = extension.toLowerCase();
    return ext == '.geojson' || ext == '.json';
  }

  @override
  FileFormat get format => FileFormat.geojson;

  @override
  Future<ImportExportResult> import(
    String filePath,
    GeoPackageNode targetGeoPackage, {
    String? layerName,
  }) async {
    try {
      AppLogger.debug('[GeoJSONImporter] インポート開始: $filePath');

      final file = File(filePath);
      if (!file.existsSync()) {
        return ImportExportResult.error('GeoJSONファイルが見つかりません: $filePath');
      }

      final fileContent = await file.readAsString();
      
      // turfでGeoJSONをパース
      final geoJson = turf.GeoJSONObject.fromJson(json.decode(fileContent));
      
      if (geoJson is! turf.FeatureCollection) {
        return ImportExportResult.error('FeatureCollection形式のGeoJSONのみサポートしています');
      }

      final turfFeatures = geoJson.features;
      if (turfFeatures.isEmpty) {
        return ImportExportResult.error('フィーチャが含まれていません');
      }

      AppLogger.debug('[GeoJSONImporter] フィーチャ数: ${turfFeatures.length}');

      // 最初のフィーチャからジオメトリタイプを判定
      final geometryType = _detectGeometryType(turfFeatures.first);
      if (geometryType == null) {
        return ImportExportResult.error('サポートされていないジオメトリタイプです');
      }

      // レイヤ名決定
      final fileName = p.basenameWithoutExtension(filePath);
      final actualLayerName = await _generateUniqueLayerName(
        targetGeoPackage,
        layerName ?? fileName,
      );

      // レイヤ作成
      await targetGeoPackage.geoPackageFile.addLayer(actualLayerName, geometryType);

      // GeoJSONスキーマをGeoPackageに追加
      await _addSchemaFromFeatures(targetGeoPackage, actualLayerName, turfFeatures);

      // フィーチャをインポート
      final batchData = <Map<String, dynamic>>[];
      int successCount = 0;
      int skipCount = 0;

      for (int i = 0; i < turfFeatures.length; i++) {
        try {
          final turfFeature = turfFeatures[i];
          final featureData = _convertTurfFeatureToData(turfFeature, geometryType);

          if (featureData != null) {
            batchData.add(featureData);
            successCount++;
          } else {
            skipCount++;
          }

          // バッチ処理
          if (batchData.length >= 1000) {
            await _processBatch(targetGeoPackage, actualLayerName, geometryType, batchData);
            batchData.clear();
            AppLogger.debug('[GeoJSONImporter] バッチ処理完了: $successCount件');
          }
        } catch (e) {
          AppLogger.debug('[GeoJSONImporter] フィーチャ[$i]の処理エラー: $e');
          skipCount++;
        }
      }

      // 残りのバッチを処理
      if (batchData.isNotEmpty) {
        await _processBatch(targetGeoPackage, actualLayerName, geometryType, batchData);
      }

      AppLogger.debug('[GeoJSONImporter] インポート完了: $successCount成功, $skipCountスキップ');

      // レイヤ更新
      await targetGeoPackage.updateChildren();

      // 作成されたレイヤノードを取得
      final createdLayer = targetGeoPackage.children
          .whereType<LayerNode>()
          .where((layer) => layer.layerName == actualLayerName)
          .firstOrNull;

      if (createdLayer == null) {
        return ImportExportResult.error('GeoJSONレイヤー作成後の取得に失敗しました: $actualLayerName');
      }

      return ImportExportResult.success(
        createdLayer: createdLayer,
        metadata: {
          'sourceFile': filePath,
          'featureCount': successCount,
          'skippedCount': skipCount,
          'geometryType': geometryType.value,
        },
      );
    } catch (e, stack) {
      AppLogger.debug('[GeoJSONImporter] インポートエラー: $e');
      AppLogger.debug('スタックトレース: $stack');
      return ImportExportResult.error('GeoJSONの読み込みでエラーが発生しました: $e');
    }
  }

  /// turfのFeatureからジオメトリタイプを判定
  GeometryType? _detectGeometryType(turf.Feature feature) {
    final geometry = feature.geometry;
    if (geometry is turf.Point) return GeometryType.point;
    if (geometry is turf.MultiPoint) return GeometryType.point;
    if (geometry is turf.LineString) return GeometryType.linestring;
    if (geometry is turf.MultiLineString) return GeometryType.linestring;
    if (geometry is turf.Polygon) return GeometryType.polygon;
    if (geometry is turf.MultiPolygon) return GeometryType.polygon;
    return null;
  }

  /// turfのFeatureをGeoPackage保存用データに変換
  Map<String, dynamic>? _convertTurfFeatureToData(
    turf.Feature turfFeature,
    GeometryType geometryType,
  ) {
    try {
      final geometry = turfFeature.geometry;
      if (geometry == null) return null;

      // プロパティを取得
      final properties = turfFeature.properties ?? {};
      final featureData = Map<String, dynamic>.from(properties);

      switch (geometryType) {
        case GeometryType.point:
          if (geometry is turf.Point) {
            featureData['point'] = TurfConverter.pointToLatlng(geometry);
          } else if (geometry is turf.MultiPoint) {
            // MultiPointの最初のポイントを使用
            final coords = geometry.coordinates;
            if (coords.isNotEmpty) {
              featureData['point'] = LatLng(
                coords.first.lat.toDouble(),
                coords.first.lng.toDouble(),
              );
            }
          } else {
            return null;
          }
          break;

        case GeometryType.linestring:
          if (geometry is turf.LineString) {
            final line = TurfConverter.lineStringToLatlngs(geometry);
            if (line.length >= 2) {
              featureData['line'] = line;
            } else {
              return null;
            }
          } else if (geometry is turf.MultiLineString) {
            // MultiLineStringの最初のラインを使用
            final coords = geometry.coordinates;
            if (coords.isNotEmpty && coords.first.length >= 2) {
              featureData['line'] = coords.first
                  .map((pos) => LatLng(pos.lat.toDouble(), pos.lng.toDouble()))
                  .toList();
            } else {
              return null;
            }
          } else {
            return null;
          }
          break;

        case GeometryType.polygon:
          if (geometry is turf.Polygon) {
            final rings = TurfConverter.polygonToLatlngs(geometry);
            if (rings.isNotEmpty && rings.first.length >= 3) {
              featureData['rings'] = rings;
            } else {
              return null;
            }
          } else if (geometry is turf.MultiPolygon) {
            // MultiPolygonの最初のポリゴンを使用
            final coords = geometry.coordinates;
            if (coords.isNotEmpty && coords.first.isNotEmpty) {
              final rings = coords.first
                  .map((ring) => ring
                      .map((pos) => LatLng(pos.lat.toDouble(), pos.lng.toDouble()))
                      .toList())
                  .toList();
              if (rings.isNotEmpty && rings.first.length >= 3) {
                featureData['rings'] = rings;
              } else {
                return null;
              }
            } else {
              return null;
            }
          } else {
            return null;
          }
          break;
      }

      return featureData;
    } catch (e) {
      AppLogger.debug('[GeoJSONImporter] Feature変換エラー: $e');
      return null;
    }
  }

  /// 重複しないレイヤ名を生成
  Future<String> _generateUniqueLayerName(
    GeoPackageNode geoPackageNode,
    String baseName,
  ) async {
    final existingLayerNames = await geoPackageNode.geoPackageFile.getLayerNames();

    if (!existingLayerNames.contains(baseName)) {
      return baseName;
    }

    int counter = 1;
    String candidateName;
    do {
      candidateName = '${baseName}_$counter';
      counter++;
    } while (existingLayerNames.contains(candidateName));

    return candidateName;
  }

  /// turfのFeatureリストからスキーマを抽出してGeoPackageに追加
  Future<void> _addSchemaFromFeatures(
    GeoPackageNode targetGeoPackage,
    String layerName,
    List<turf.Feature> features,
  ) async {
    try {
      final attributeSchema = <String, String>{};

      for (final feature in features) {
        final properties = feature.properties;
        if (properties == null) continue;

        for (final entry in properties.entries) {
          final fieldName = entry.key;
          final value = entry.value;

          if (attributeSchema.containsKey(fieldName)) continue;

          String sqliteType = 'TEXT';
          if (value is num || value is int || value is double) {
            sqliteType = 'REAL';
          } else if (value is bool) {
            sqliteType = 'INTEGER';
          }

          attributeSchema[fieldName] = sqliteType;
        }
      }

      if (attributeSchema.isNotEmpty) {
        await targetGeoPackage.geoPackageFile.addAttributeColumns(
          layerName,
          attributeSchema,
        );
      }
    } catch (e) {
      AppLogger.debug('[GeoJSONImporter] スキーマ追加エラー: $e');
    }
  }

  /// バッチデータを処理
  Future<void> _processBatch(
    GeoPackageNode targetGeoPackage,
    String layerName,
    GeometryType geometryType,
    List<Map<String, dynamic>> batchData,
  ) async {
    if (batchData.isEmpty) return;

    switch (geometryType) {
      case GeometryType.point:
        await targetGeoPackage.geoPackageFile.addPointsBatch(layerName, batchData);
        break;
      case GeometryType.linestring:
        await targetGeoPackage.geoPackageFile.addLinesBatch(layerName, batchData);
        break;
      case GeometryType.polygon:
        await targetGeoPackage.geoPackageFile.addPolygonsBatch(layerName, batchData);
        break;
    }
  }
}
