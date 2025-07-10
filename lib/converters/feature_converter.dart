// K-MAPS: Feature Converter
// フィーチャ変換操作に特化したコンバーター
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'base_converter.dart';
import '../services/import_export_service.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/folder_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../models/nodes/photo_node.dart';
import '../models/geometry_type.dart';
import '../utils/wkb_utils.dart';

/// フィーチャインポート用コンバーター
class FeatureImportConverter
    extends BaseConverter<FeatureConversionParams, List<Map<String, dynamic>>> {
  @override
  Future<bool> validate(FeatureConversionParams input) async {
    try {
      // ターゲットレイヤー確認
      if (input.targetLayer == null) {
        return false;
      }

      // フィーチャデータ確認
      if (input.features.isEmpty) {
        return false;
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<ConversionResult> convert(FeatureConversionParams input) async {
    try {
      notifyProgress(0.4, 'Processing features...');

      final successfulImports = <Map<String, dynamic>>[];
      final errors = <String>[];

      // 最大インポート数制限
      final maxFeatures =
          input.options['maxFeatures'] as int? ?? input.features.length;
      final featuresToProcess = input.features.take(maxFeatures).toList();

      for (int i = 0; i < featuresToProcess.length; i++) {
        try {
          final feature = featuresToProcess[i];

          // 進行状況更新
          final progress = 0.4 + (0.5 * (i / featuresToProcess.length));
          notifyProgress(
            progress,
            'Importing feature ${i + 1}/${featuresToProcess.length}...',
          );

          // フィーチャをレイヤーに追加
          await input.targetLayer!.geoPackageFile.addFeatureWithAttributes(
            input.targetLayer!.layerName,
            feature['geometry'],
            feature['metadata'] ?? {},
          );

          successfulImports.add(feature);
        } catch (e) {
          errors.add('Feature ${i + 1}: $e');
        }
      }

      final metadata = {
        'totalFeatures': featuresToProcess.length,
        'successfulImports': successfulImports.length,
        'errors': errors.length,
        'targetLayer': input.targetLayer!.layerName,
      };

      if (errors.isNotEmpty) {
        metadata['errorDetails'] = errors;
      }

      return ConversionResult.success(
        data: successfulImports,
        metadata: metadata,
      );
    } catch (e) {
      return ConversionResult.error('Feature import failed: $e');
    }
  }
}

/// フィーチャエクスポート用コンバーター
class FeatureExportConverter
    extends BaseConverter<FeatureConversionParams, String> {
  final FileFormat exportFormat;
  final String outputPath;
  final bool convertToPointCloud;

  FeatureExportConverter({
    required this.exportFormat,
    required this.outputPath,
    this.convertToPointCloud = true,
  });

  @override
  Future<bool> validate(FeatureConversionParams input) async {
    try {
      // フィーチャデータ確認
      if (input.features.isEmpty) {
        return false;
      }

      // 出力パス確認
      final outputDir = Directory(File(outputPath).parent.path);

      if (!await outputDir.exists()) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<ConversionResult> convert(FeatureConversionParams input) async {
    try {
      notifyProgress(0.1, 'Validating features...');

      // 選択されたフィーチャのみエクスポート
      final featuresToExport =
          input.selectedFeatureIds != null
              ? input.features.where((feature) {
                final id = feature['id'] as int?;
                return id != null && input.selectedFeatureIds!.contains(id);
              }).toList()
              : input.features;

      if (featuresToExport.isEmpty) {
        return ConversionResult.error('No features selected for export');
      }

      notifyProgress(0.6, 'Converting to ${exportFormat.value} format...');

      String exportData;
      switch (exportFormat) {
        case FileFormat.geojson:
          exportData = _convertToGeoJSON(featuresToExport);
          break;
        case FileFormat.csv:
          exportData = _convertToCSV(featuresToExport);
          break;
        case FileFormat.kml:
          exportData = _convertToKML(featuresToExport);
          break;
        case FileFormat.shapefile:
          // Shapefileは複数ファイル生成なので別処理
          return await _exportToShapefile(featuresToExport);
        default:
          return ConversionResult.error(
            'Unsupported export format: ${exportFormat.value}',
          );
      }

      notifyProgress(0.8, 'Writing file...');
      // ファイル書き込み
      final file = File(outputPath);
      await file.writeAsString(exportData);
      return ConversionResult.success(
        data: outputPath,
        metadata: {
          'exportFormat': exportFormat.value,
          'featureCount': featuresToExport.length,
          'outputPath': outputPath,
        },
      );
    } catch (e) {
      return ConversionResult.error('Feature export failed: $e');
    }
  }

  /// GeoJSON形式への変換
  String _convertToGeoJSON(List<Map<String, dynamic>> features) {
    final geojsonFeatures =
        features.map((feature) {
          return {
            'type': 'Feature',
            'properties': feature['metadata'] ?? {},
            'geometry': feature['geometry'],
          };
        }).toList();

    final geojson = {'type': 'FeatureCollection', 'features': geojsonFeatures};

    return jsonEncode(geojson);
  }

  /// CSV形式への変換
  String _convertToCSV(List<Map<String, dynamic>> features) {
    if (features.isEmpty) return '';

    final csvLines = <String>[];

    // ヘッダー行を作成
    final headers = <String>{'id', 'geometry_type'};
    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      headers.addAll(metadata.keys.cast<String>());
    }
    csvLines.add(headers.join(','));

    // データ行を作成
    for (final feature in features) {
      final row = <String>[];
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};

      for (final header in headers) {
        String value;
        switch (header) {
          case 'id':
            value = (feature['id'] ?? '').toString();
            break;
          case 'geometry_type':
            value = _getGeometryType(feature['geometry']).toString();
            break;
          default:
            value = (metadata[header] ?? '').toString();
            break;
        }
        // CSVエスケープ
        if (value.contains(',') ||
            value.contains('"') ||
            value.contains('\n')) {
          value = '"${value.replaceAll('"', '""')}"';
        }
        row.add(value);
      }
      csvLines.add(row.join(','));
    }

    return csvLines.join('\n');
  }

  /// KML形式への変換
  String _convertToKML(List<Map<String, dynamic>> features) {
    final kmlElements = <String>[];

    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      final name = metadata['name'] ?? 'Feature ${feature['id']}';
      final description = metadata['description'] ?? '';

      kmlElements.add(_createKMLPlacemark(feature, name, description));
    }

    return '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Exported Features</name>
    ${kmlElements.join('\n    ')}
  </Document>
</kml>''';
  }

  /// KMLプレースマークを作成
  String _createKMLPlacemark(
    Map<String, dynamic> feature,
    String name,
    String description,
  ) {
    // 実装省略（実際にはジオメトリタイプに応じてKML要素を生成）
    return '''<Placemark>
      <name>$name</name>
      <description>$description</description>
      <!-- Geometry elements would be added here -->
    </Placemark>''';
  }

  /// Shapefile形式への変換（点群）
  Future<ConversionResult> _exportToShapefile(
    List<Map<String, dynamic>> features,
  ) async {
    try {
      notifyProgress(0.5, 'Converting features to shapefile...');

      // convertToPointCloudオプションを確認
      if (convertToPointCloud) {
        return await _exportToPointCloudShapefile(features);
      } else {
        return await _exportToNativeShapefile(features);
      }
    } catch (e) {
      return ConversionResult.error('Shapefile export failed: $e');
    }
  }

  /// ポイントクラウド形式でのShapefileエクスポート（既存機能）
  Future<ConversionResult> _exportToPointCloudShapefile(
    List<Map<String, dynamic>> features,
  ) async {
    try {
      notifyProgress(0.5, 'Converting features to point cloud...');

      // フィーチャを点群に変換
      final points = <Map<String, dynamic>>[];
      int pointId = 1;

      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};

        if (geometry == null) {
          continue;
        }

        var coordinates = geometry['coordinates'];
        final geometryType = geometry['type'] as String?;

        // 座標データが空またはnullの場合、WKBデータから解析
        bool needWkbParsing = false;
        if (coordinates == null) {
          needWkbParsing = true;
        } else if (coordinates is List) {
          if (coordinates.isEmpty) {
            needWkbParsing = true;
          } else if (coordinates.every(
            (coord) => coord is List && (coord as List).isEmpty,
          )) {
            needWkbParsing = true;
          }
        }

        if (needWkbParsing && metadata.containsKey('geom')) {
          final parsedCoordinates = await _parseWkbToCoordinates(
            metadata['geom'],
            geometryType,
          );
          if (parsedCoordinates != null) {
            coordinates = parsedCoordinates;
          } else {
            continue;
          }
        }

        switch (geometryType) {
          case 'Point':
            // ポイントはそのまま追加
            if (coordinates is List && coordinates.length >= 2) {
              points.add({
                'POINT_ID': pointId++,
                'SOURCE_ID': feature['id'] ?? 0,
                'SRC_TYPE': 'Point',
                'LONGITUDE': coordinates[0],
                'LATITUDE': coordinates[1],
                'SEGMENT_ID': 0,
                'RING_TYPE': 'exterior',
                ...metadata,
              });
            }
            break;

          case 'LineString':
            // 線の各頂点をポイントに変換
            if (coordinates is List) {
              for (int i = 0; i < coordinates.length; i++) {
                final coord = coordinates[i];
                if (coord is List && coord.length >= 2) {
                  points.add({
                    'POINT_ID': pointId++,
                    'SOURCE_ID': feature['id'] ?? 0,
                    'SRC_TYPE': 'LineString',
                    'LONGITUDE': coord[0],
                    'LATITUDE': coord[1],
                    'SEGMENT_ID': i,
                    'RING_TYPE': 'line',
                    ...metadata,
                  });
                }
              }
            }
            break;

          case 'Polygon':
            // ポリゴンの各頂点をポイントに変換（重複点除去付き）
            if (coordinates is List && coordinates.isNotEmpty) {
              print('=== [FeatureExportConverter] Polygon点群変換開始 ===');
              print('[FeatureExportConverter] フィーチャID: ${feature['id']}');
              print('[FeatureExportConverter] リング数: ${coordinates.length}');
              print('[FeatureExportConverter] 重複点除去: ON (閉じたリングの最後の点をスキップ)');

              for (
                int ringIndex = 0;
                ringIndex < coordinates.length;
                ringIndex++
              ) {
                final ring = coordinates[ringIndex];
                if (ring is List) {
                  final ringType = ringIndex == 0 ? 'exterior' : 'hole';
                  final originalRingSize = ring.length;
                  int addedPointsCount = 0;

                  print(
                    '[FeatureExportConverter] リング $ringIndex 処理開始: ${ring.length}点 ($ringType)',
                  );

                  for (int i = 0; i < ring.length; i++) {
                    final coord = ring[i];
                    if (coord is List && coord.length >= 2) {
                      // 最後の点で、かつ最初の点と同じ場合はスキップ
                      if (i == ring.length - 1 && ring.length > 1) {
                        final firstCoord = ring[0] as List;
                        final lastCoord = coord;
                        const tolerance = 0.000001;

                        print(
                          '[FeatureExportConverter] 最後の点の重複チェック (リング $ringIndex):',
                        );
                        print(
                          '[FeatureExportConverter]   最初の点: (${firstCoord[1]}, ${firstCoord[0]})',
                        );
                        print(
                          '[FeatureExportConverter]   最後の点: (${lastCoord[1]}, ${lastCoord[0]})',
                        );

                        final latDiff = (firstCoord[1] - lastCoord[1]).abs();
                        final lngDiff = (firstCoord[0] - lastCoord[0]).abs();
                        print(
                          '[FeatureExportConverter]   座標差分: 緯度=${latDiff.toStringAsFixed(8)}, 経度=${lngDiff.toStringAsFixed(8)}',
                        );

                        if (latDiff < tolerance && lngDiff < tolerance) {
                          print(
                            '[FeatureExportConverter] ✓ 重複する最後の点をスキップ (リング $ringIndex)',
                          );
                          continue; // 最後の重複点をスキップ
                        } else {
                          print(
                            '[FeatureExportConverter] ✗ 最後の点は重複していない、追加します (リング $ringIndex)',
                          );
                        }
                      }

                      final point = {
                        'POINT_ID': pointId++,
                        'SOURCE_ID': feature['id'] ?? 0,
                        'SRC_TYPE': 'Polygon',
                        'LONGITUDE': coord[0],
                        'LATITUDE': coord[1],
                        'SEGMENT_ID': addedPointsCount,
                        'RING_TYPE': ringType,
                        'ORIG_RING': originalRingSize,
                        'DEDUP_RING': addedPointsCount + 1,
                        ...metadata,
                      };
                      points.add(point);
                      addedPointsCount++;

                      if (addedPointsCount <= 3 || i == ring.length - 1) {
                        print(
                          '[FeatureExportConverter] 点追加[$addedPointsCount]: (${coord[1]}, ${coord[0]}) POINT_ID=${pointId - 1}',
                        );
                      }
                    }
                  }
                  print(
                    '[FeatureExportConverter] リング $ringIndex 完了: ${originalRingSize}点 -> ${addedPointsCount}点 (${originalRingSize - addedPointsCount}点除去)',
                  );
                }
              }
              print(
                '[FeatureExportConverter] Polygon変換完了: フィーチャID=${feature['id']}',
              );
            }
            break;
        }
      }

      if (points.isEmpty) {
        return ConversionResult.error('No valid points found for export');
      }

      notifyProgress(0.7, 'Creating Point Shapefile...');

      // Shapefile形式での直接ファイル出力
      await _writePointShapefileComponents(points, outputPath);
      return ConversionResult.success(
        data: outputPath,
        metadata: {
          'exportFormat': 'shapefile',
          'shapeType': 'Point',
          'featureCount': features.length, // ポップアップ表示用
          'pointCount': points.length,
          'originalFeatures': features.length,
          'outputPath': outputPath,
        },
      );
    } catch (e) {
      return ConversionResult.error('Point cloud shapefile export failed: $e');
    }
  }

  /// 元の形状を保持したShapefileエクスポート（新機能）
  Future<ConversionResult> _exportToNativeShapefile(
    List<Map<String, dynamic>> features,
  ) async {
    try {
      if (features.isEmpty) {
        return ConversionResult.error('No features to export');
      }

      // 主要なジオメトリタイプを特定
      final geometryTypes = <String>{};
      for (final feature in features) {
        final geometry = feature['geometry'] as Map<String, dynamic>?;
        if (geometry != null) {
          final type = geometry['type'] as String?;
          if (type != null) {
            geometryTypes.add(type);
          }
        }
      }

      if (geometryTypes.isEmpty) {
        return ConversionResult.error('No valid geometries found');
      }

      // 複数のジオメトリタイプがある場合は、最初のタイプを使用
      final primaryGeometryType = geometryTypes.first;

      notifyProgress(0.6, 'Creating $primaryGeometryType Shapefile...');

      // ジオメトリタイプに応じてShapefileを生成
      switch (primaryGeometryType) {
        case 'Point':
          await _writeNativePointShapefile(features, outputPath);
          break;
        case 'LineString':
          await _writeNativeLineShapefile(features, outputPath);
          break;
        case 'Polygon':
          await _writeNativePolygonShapefile(features, outputPath);
          break;
        default:
          return ConversionResult.error(
            'Unsupported geometry type: $primaryGeometryType',
          );
      }

      return ConversionResult.success(
        data: outputPath,
        metadata: {
          'exportFormat': 'shapefile',
          'shapeType': primaryGeometryType,
          'featureCount': features.length, // ポップアップ表示用（確認済み）
          'outputPath': outputPath,
        },
      );
    } catch (e) {
      return ConversionResult.error('Native shapefile export failed: $e');
    }
  }

  /// ネイティブPoint Shapefileの書き込み
  Future<void> _writeNativePointShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
  ) async {
    final basePath = outputPath.substring(0, outputPath.lastIndexOf('.'));

    // .shpファイル（ジオメトリデータ）
    await _writeNativePointShpFile(features, '$basePath.shp');

    // .shxファイル（インデックス）
    await _writeNativePointShxFile(features, '$basePath.shx');

    // .dbfファイル（属性データ）
    await _writeNativeDbfFile(features, '$basePath.dbf');

    // .prjファイル（座標系定義）
    await _writePrjFile('$basePath.prj');
  }

  /// ネイティブPolygon Shapefileの書き込み
  Future<void> _writeNativePolygonShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
  ) async {
    final basePath = outputPath.substring(0, outputPath.lastIndexOf('.'));

    // .shpファイル（ジオメトリデータ）
    await _writeNativePolygonShpFile(features, '$basePath.shp');

    // .shxファイル（インデックス）
    await _writeNativePolygonShxFile(features, '$basePath.shx');

    // .dbfファイル（属性データ）
    await _writeNativePolygonDbfFile(features, '$basePath.dbf');

    // .prjファイル（座標系定義）
    await _writePrjFile('$basePath.prj');
  }

  /// ネイティブLineString Shapefileの書き込み
  Future<void> _writeNativeLineShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
  ) async {
    final basePath = outputPath.substring(0, outputPath.lastIndexOf('.'));

    // .shpファイル（ジオメトリデータ）
    await _writeNativeLineShpFile(features, '$basePath.shp');

    // .shxファイル（インデックス）
    await _writeNativeLineShxFile(features, '$basePath.shx');

    // .dbfファイル（属性データ）
    await _writeNativeDbfFile(features, '$basePath.dbf');

    // .prjファイル（座標系定義）
    await _writePrjFile('$basePath.prj');
  }

  /// ネイティブPoint用.shpファイルを書き込み
  Future<void> _writeNativePointShpFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    // バウンディングボックス計算
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'Point';
        }).toList();

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      if (coordinates.length >= 2) {
        final x = (coordinates[0] as num).toDouble();
        final y = (coordinates[1] as num).toDouble();

        // 有効な座標値のみでバウンディングボックスを計算
        if (x.isFinite && y.isFinite) {
          minX = minX.isFinite ? (minX < x ? minX : x) : x;
          maxX = maxX.isFinite ? (maxX > x ? maxX : x) : x;
          minY = minY.isFinite ? (minY < y ? minY : y) : y;
          maxY = maxY.isFinite ? (maxY > y ? maxY : y) : y;
        }
      }
    }

    // バウンディングボックスの初期値チェック（Point用の重要な修正）
    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      // デフォルト値を設定（無効な座標の場合）
      minX = maxX = minY = maxY = 0.0;
    }

    // ファイル長を正確に計算（16bit words単位）
    // ヘッダー: 100バイト = 50ワード
    // 各Pointレコード: レコードヘッダー(8バイト) + シェープタイプ(4バイト) + X(8バイト) + Y(8バイト) = 28バイト = 14ワード
    final fileLengthInWords = 50 + (validFeatures.length * 14);

    // SHPヘッダー（100バイト）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用（5 * 4バイト）
    bytes.addAll(
      _writeInt32BigEndian(fileLengthInWords),
    ); // ファイル長（16bit words単位）
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(1)); // シェープタイプ（Point）

    // バウンディングボックス（64バイト）
    bytes.addAll(_writeFloat64(minX));
    bytes.addAll(_writeFloat64(minY));
    bytes.addAll(_writeFloat64(maxX));
    bytes.addAll(_writeFloat64(maxY));
    bytes.addAll(_writeFloat64(0.0)); // Zmin
    bytes.addAll(_writeFloat64(0.0)); // Zmax
    bytes.addAll(_writeFloat64(0.0)); // Mmin
    bytes.addAll(_writeFloat64(0.0)); // Mmax

    // ポイントレコード
    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      // レコードヘッダー（8バイト）
      bytes.addAll(_writeInt32BigEndian(i + 1)); // レコード番号（1から開始）
      bytes.addAll(_writeInt32BigEndian(10)); // コンテンツ長（10ワード = 20バイト）

      // レコードコンテンツ（20バイト）
      bytes.addAll(_writeInt32LittleEndian(1)); // シェープタイプ（Point）
      bytes.addAll(_writeFloat64((coordinates[0] as num).toDouble())); // X座標
      bytes.addAll(_writeFloat64((coordinates[1] as num).toDouble())); // Y座標
    }

    await file.writeAsBytes(bytes);
  }

  /// ネイティブPolygon用.shpファイルを書き込み
  Future<void> _writeNativePolygonShpFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    // バウンディングボックス計算とレコードサイズ計算
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'Polygon';
        }).toList();

    if (validFeatures.isEmpty) {
      throw Exception('No valid polygon features found');
    }

    // 全体のバウンディングボックスとファイル長を正確に計算
    int totalFileLength = 50; // ヘッダーサイズ（16bit words単位）

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) {
          totalPoints += ring.length;
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              final x = (coord[0] as num).toDouble();
              final y = (coord[1] as num).toDouble();

              // 有効な座標値のみでバウンディングボックスを計算
              if (x.isFinite && y.isFinite) {
                minX = minX.isFinite ? (minX < x ? minX : x) : x;
                maxX = maxX.isFinite ? (maxX > x ? maxX : x) : x;
                minY = minY.isFinite ? (minY < y ? minY : y) : y;
                maxY = maxY.isFinite ? (maxY > y ? maxY : y) : y;
              }
            }
          }
        }
      }

      // レコードサイズを正確に計算（16bit words単位）
      // レコードヘッダー(8バイト) + シェープタイプ(4) + バウンディングボックス(32) + パーツ数(4) + ポイント数(4) + パーツ配列(4*パーツ数) + ポイント配列(16*ポイント数)
      final recordContentSize =
          4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final recordSizeInWords =
          (recordContentSize + 1) ~/ 2; // 16bit words単位に変換（切り上げ）

      totalFileLength += 4 + recordSizeInWords; // レコードヘッダー(4 words) + コンテンツ
    }

    // バウンディングボックスの初期値チェック
    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      // デフォルト値を設定（無効な座標の場合）
      minX = maxX = minY = maxY = 0.0;
    }

    // SHPヘッダー（100バイト = 50 words）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用フィールド（5つの32bit値）
    bytes.addAll(_writeInt32BigEndian(totalFileLength)); // ファイル長（16bit words単位）
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(5)); // シェープタイプ（Polygon = 5）

    // バウンディングボックス（64バイト）
    bytes.addAll(_writeFloat64(minX));
    bytes.addAll(_writeFloat64(minY));
    bytes.addAll(_writeFloat64(maxX));
    bytes.addAll(_writeFloat64(maxY));
    bytes.addAll(_writeFloat64(0.0)); // Zmin
    bytes.addAll(_writeFloat64(0.0)); // Zmax
    bytes.addAll(_writeFloat64(0.0)); // Mmin
    bytes.addAll(_writeFloat64(0.0)); // Mmax

    // ポリゴンレコード
    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      // レコードのトータルポイント数を計算
      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) {
          totalPoints += ring.length;
        }
      }

      // コンテンツ長を正確に計算（16bit words単位）
      final contentSizeInBytes =
          4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final contentLength =
          (contentSizeInBytes + 1) ~/ 2; // 16bit words単位（切り上げ）

      // レコードヘッダー（8バイト）
      bytes.addAll(_writeInt32BigEndian(i + 1)); // レコード番号（1から開始）
      bytes.addAll(
        _writeInt32BigEndian(contentLength),
      ); // コンテンツ長（16bit words単位）

      // レコードコンテンツ
      bytes.addAll(_writeInt32LittleEndian(5)); // シェープタイプ（Polygon = 5）

      // ポリゴンのバウンディングボックス計算
      double polygonMinX = double.infinity, polygonMinY = double.infinity;
      double polygonMaxX = double.negativeInfinity,
          polygonMaxY = double.negativeInfinity;

      for (final ring in coordinates) {
        if (ring is List) {
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              final x = (coord[0] as num).toDouble();
              final y = (coord[1] as num).toDouble();

              if (x.isFinite && y.isFinite) {
                polygonMinX =
                    polygonMinX.isFinite
                        ? (polygonMinX < x ? polygonMinX : x)
                        : x;
                polygonMaxX =
                    polygonMaxX.isFinite
                        ? (polygonMaxX > x ? polygonMaxX : x)
                        : x;
                polygonMinY =
                    polygonMinY.isFinite
                        ? (polygonMinY < y ? polygonMinY : y)
                        : y;
                polygonMaxY =
                    polygonMaxY.isFinite
                        ? (polygonMaxY > y ? polygonMaxY : y)
                        : y;
              }
            }
          }
        }
      }

      // バウンディングボックスの妥当性チェック
      if (!polygonMinX.isFinite) polygonMinX = 0.0;
      if (!polygonMaxX.isFinite) polygonMaxX = 0.0;
      if (!polygonMinY.isFinite) polygonMinY = 0.0;
      if (!polygonMaxY.isFinite) polygonMaxY = 0.0;

      // ポリゴンのバウンディングボックス（32バイト）
      bytes.addAll(_writeFloat64(polygonMinX));
      bytes.addAll(_writeFloat64(polygonMinY));
      bytes.addAll(_writeFloat64(polygonMaxX));
      bytes.addAll(_writeFloat64(polygonMaxY));

      // パーツ数とポイント数
      bytes.addAll(_writeInt32LittleEndian(coordinates.length)); // パーツ数（リング数）
      bytes.addAll(_writeInt32LittleEndian(totalPoints)); // 総ポイント数

      // パーツ配列（各リングの開始ポイントインデックス）
      int pointIndex = 0;
      for (int ringIndex = 0; ringIndex < coordinates.length; ringIndex++) {
        bytes.addAll(_writeInt32LittleEndian(pointIndex));
        final ring = coordinates[ringIndex] as List;
        pointIndex += ring.length;
      }

      // ポイント配列（実際の座標データ）
      for (int ringIndex = 0; ringIndex < coordinates.length; ringIndex++) {
        final ring = coordinates[ringIndex] as List;
        if (ring.isNotEmpty) {
          // リングの順序をShapefile仕様に合わせて調整
          final ringCoords = ring.cast<List<num>>();

          print(
            '[FeatureConverter] Polygon処理: フィーチャID=${feature['id']}, リング$ringIndex',
          );
          print('[FeatureConverter] 元のリング座標数: ${ringCoords.length}');
          print(
            '[FeatureConverter] リングタイプ: ${ringIndex == 0 ? "外側" : "内側（穴）"}',
          );

          final adjustedRing = _adjustPolygonRingOrientation(
            ringCoords,
            ringIndex == 0,
          );

          print('[FeatureConverter] 調整後のリング座標数: ${adjustedRing.length}');
          print(
            '[FeatureConverter] 座標調整: ${ringCoords.length != adjustedRing.length ? "エラー" : "正常"}',
          );

          for (final coord in adjustedRing) {
            if (coord.length >= 2) {
              final x = coord[0].toDouble();
              final y = coord[1].toDouble();

              // 有効な座標値のチェック
              final validX = x.isFinite ? x : 0.0;
              final validY = y.isFinite ? y : 0.0;

              bytes.addAll(_writeFloat64(validX));
              bytes.addAll(_writeFloat64(validY));
            }
          }

          print('[FeatureConverter] リング$ringIndex 書き込み完了');
        }
      }
    }

    await file.writeAsBytes(bytes);
  }

  /// ネイティブLineString用.shxファイルを書き込み
  Future<void> _writeNativeLineShxFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'LineString';
        }).toList();

    // SHXヘッダー
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用

    // ファイル長計算
    int totalFileLength = 50; // ヘッダー
    for (final feature in validFeatures) {
      totalFileLength += 4; // インデックスレコード1つあたり4ワード
    }
    bytes.addAll(_writeInt32BigEndian(totalFileLength)); // ファイル長

    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(3)); // シェープタイプ
    bytes.addAll(List.filled(64, 0)); // バウンディングボックス（簡略）

    // インデックスレコード
    int offset = 50; // ヘッダー後の開始位置
    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      final recordLength = (44 + 4 + (16 * coordinates.length)) ~/ 2;

      bytes.addAll(_writeInt32BigEndian(offset)); // オフセット
      bytes.addAll(_writeInt32BigEndian(recordLength)); // レコード長
      offset += recordLength + 4; // レコードヘッダー(4ワード)を加算
    }

    await file.writeAsBytes(bytes);
  }

  /// ネイティブフィーチャ用.dbfファイルを書き込み
  Future<void> _writeNativeDbfFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);

    if (features.isEmpty) {
      // 空のDBFファイルを作成
      final bytes = <int>[];
      bytes.add(0x03); // バージョン
      bytes.addAll(List.filled(31, 0)); // 空のヘッダー
      await file.writeAsBytes(bytes);
      return;
    }

    // 属性フィールド定義を動的に生成
    final fields = <Map<String, dynamic>>[];
    final allMetadata = <String, dynamic>{};

    // 全フィーチャから属性フィールドを収集
    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      allMetadata.addAll(metadata);
    }

    // 基本フィールド
    fields.add({'name': 'FID', 'type': 'N', 'length': 10, 'decimal': 0});

    // メタデータフィールド
    for (final entry in allMetadata.entries) {
      final value = entry.value;
      String fieldType = 'C';
      int fieldLength = 50;
      int fieldDecimal = 0;

      if (value is num) {
        fieldType = 'N';
        if (value is double) {
          fieldLength = 15;
          fieldDecimal = 8;
        } else {
          fieldLength = 10;
        }
      } else if (value is bool) {
        fieldType = 'L';
        fieldLength = 1;
      }

      // フィールド名を8文字以内に制限
      String fieldName =
          entry.key.length > 8 ? entry.key.substring(0, 8) : entry.key;

      // 重複チェック
      if (!fields.any((f) => f['name'] == fieldName)) {
        fields.add({
          'name': fieldName.toUpperCase(),
          'type': fieldType,
          'length': fieldLength,
          'decimal': fieldDecimal,
        });
      }
    }

    final recordLength = fields.fold<int>(
      1,
      (sum, field) => sum + (field['length'] as int? ?? 0),
    );
    final headerLength = 32 + fields.length * 32 + 1;

    final bytes = <int>[];

    // DBFヘッダー
    bytes.add(0x03); // バージョン
    bytes.add(24); // 年（2024-1900）
    bytes.add(12); // 月
    bytes.add(19); // 日
    bytes.addAll(_writeInt32LittleEndian(features.length)); // レコード数
    bytes.addAll(_writeInt16LittleEndian(headerLength)); // ヘッダー長
    bytes.addAll(_writeInt16LittleEndian(recordLength)); // レコード長
    bytes.addAll(List.filled(20, 0)); // 予約領域

    // フィールド記述子
    for (final field in fields) {
      final nameBytes = (field['name'] as String).codeUnits;
      bytes.addAll(nameBytes);
      bytes.addAll(List.filled(11 - nameBytes.length, 0)); // フィールド名（11バイト）
      bytes.add((field['type'] as String).codeUnitAt(0)); // フィールドタイプ
      bytes.addAll(List.filled(4, 0)); // フィールドアドレス
      bytes.add(field['length'] as int); // フィールド長
      bytes.add(field['decimal'] as int); // 小数点以下桁数
      bytes.addAll(List.filled(14, 0)); // 予約領域
    }

    bytes.add(0x0D); // フィールド記述子終了

    // データレコード
    for (int i = 0; i < features.length; i++) {
      final feature = features[i];
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};

      bytes.add(0x20); // レコード削除フラグ（スペース）

      for (final field in fields) {
        final fieldName = field['name'] as String;
        final fieldLength = field['length'] as int;
        String value;

        if (fieldName == 'FID') {
          value = (feature['id'] ?? i + 1).toString();
        } else {
          // メタデータから対応する値を取得（大文字小文字を無視）
          final metaValue =
              metadata.entries
                  .firstWhere(
                    (entry) => entry.key.toUpperCase() == fieldName,
                    orElse: () => MapEntry('', ''),
                  )
                  .value;
          value = metaValue?.toString() ?? '';
        }

        if (field['type'] == 'N') {
          // 数値フィールド：右寄せ、スペース埋め
          value = value.padLeft(fieldLength);
        } else {
          // 文字フィールド：左寄せ、スペース埋め
          value = value.padRight(fieldLength);
        }

        final valueBytes = value.substring(0, fieldLength).codeUnits;
        bytes.addAll(valueBytes);
      }
    }

    bytes.add(0x1A); // ファイル終了マーカー

    await file.writeAsBytes(bytes);
  }

  /// ポイントクラウド用Shapefileコンポーネントファイルを書き込み
  Future<void> _writePointShapefileComponents(
    List<Map<String, dynamic>> points,
    String outputPath,
  ) async {
    final basePath = outputPath.substring(0, outputPath.lastIndexOf('.'));

    // .shpファイル（ジオメトリデータ）
    await _writeShpFile(points, '$basePath.shp');

    // .shxファイル（インデックス）
    await _writeShxFile(points, '$basePath.shx');

    // .dbfファイル（属性データ）
    await _writeDbfFile(points, '$basePath.dbf');

    // .prjファイル（座標系定義）
    await _writePrjFile('$basePath.prj');
  }

  /// .shpファイルを書き込み（Point形状）
  Future<void> _writeShpFile(
    List<Map<String, dynamic>> points,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    // SHPヘッダー（100バイト）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用
    bytes.addAll(_writeInt32BigEndian(50 + points.length * 14)); // ファイル長
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(1)); // シェープタイプ（Point）

    // バウンディングボックス（8倍精度×4）
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final point in points) {
      final x = (point['LONGITUDE'] as num? ?? 0.0).toDouble();
      final y = (point['LATITUDE'] as num? ?? 0.0).toDouble();
      minX = minX < x ? minX : x;
      maxX = maxX > x ? maxX : x;
      minY = minY < y ? minY : y;
      maxY = maxY > y ? maxY : y;
    }

    bytes.addAll(_writeFloat64(minX));
    bytes.addAll(_writeFloat64(minY));
    bytes.addAll(_writeFloat64(maxX));
    bytes.addAll(_writeFloat64(maxY));
    bytes.addAll(_writeFloat64(0.0)); // Zmin
    bytes.addAll(_writeFloat64(0.0)); // Zmax
    bytes.addAll(_writeFloat64(0.0)); // Mmin
    bytes.addAll(_writeFloat64(0.0)); // Mmax

    // ポイントレコード
    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      bytes.addAll(_writeInt32BigEndian(i + 1)); // レコード番号
      bytes.addAll(_writeInt32BigEndian(10)); // コンテンツ長（Point=10ワード）
      bytes.addAll(_writeInt32LittleEndian(1)); // シェープタイプ（Point）
      bytes.addAll(
        _writeFloat64((point['LONGITUDE'] as num? ?? 0.0).toDouble()),
      );
      bytes.addAll(
        _writeFloat64((point['LATITUDE'] as num? ?? 0.0).toDouble()),
      );
    }

    await file.writeAsBytes(bytes);
  }

  /// .shxファイルを書き込み（インデックス）
  Future<void> _writeShxFile(
    List<Map<String, dynamic>> points,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    // SHXヘッダー（.shpと同じ最初の100バイト）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用
    bytes.addAll(_writeInt32BigEndian(50 + points.length * 4)); // ファイル長
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(1)); // シェープタイプ
    bytes.addAll(List.filled(64, 0)); // バウンディングボックス（簡略）

    // インデックスレコード
    int offset = 50; // ヘッダー後の開始位置
    for (int i = 0; i < points.length; i++) {
      bytes.addAll(_writeInt32BigEndian(offset)); // オフセット
      bytes.addAll(_writeInt32BigEndian(14)); // レコード長
      offset += 14;
    }

    await file.writeAsBytes(bytes);
  }

  /// .dbfファイルを書き込み（属性データ）
  Future<void> _writeDbfFile(
    List<Map<String, dynamic>> points,
    String path,
  ) async {
    final file = File(path);

    // 属性フィールド定義
    final fields = [
      {'name': 'POINT_ID', 'type': 'N', 'length': 10, 'decimal': 0},
      {'name': 'SOURCE_ID', 'type': 'N', 'length': 10, 'decimal': 0},
      {'name': 'SRC_TYPE', 'type': 'C', 'length': 20, 'decimal': 0},
      {'name': 'LONGITUDE', 'type': 'N', 'length': 15, 'decimal': 8},
      {'name': 'LATITUDE', 'type': 'N', 'length': 15, 'decimal': 8},
      {'name': 'SEGMENT_ID', 'type': 'N', 'length': 10, 'decimal': 0},
      {'name': 'RING_TYPE', 'type': 'C', 'length': 10, 'decimal': 0},
    ];

    final recordLength = fields.fold<int>(
      1,
      (sum, field) => sum + (field['length'] as int? ?? 0),
    );
    final headerLength = 32 + fields.length * 32 + 1;

    final bytes = <int>[];

    // DBFヘッダー
    bytes.add(0x03); // バージョン
    bytes.add(24); // 年（2024-1900）
    bytes.add(12); // 月
    bytes.add(19); // 日
    bytes.addAll(_writeInt32LittleEndian(points.length)); // レコード数
    bytes.addAll(_writeInt16LittleEndian(headerLength)); // ヘッダー長
    bytes.addAll(_writeInt16LittleEndian(recordLength)); // レコード長
    bytes.addAll(List.filled(20, 0)); // 予約領域

    // フィールド記述子
    for (final field in fields) {
      final nameBytes = (field['name'] as String).codeUnits;
      bytes.addAll(nameBytes);
      bytes.addAll(List.filled(11 - nameBytes.length, 0)); // フィールド名（11バイト）
      bytes.add((field['type'] as String).codeUnitAt(0)); // フィールドタイプ
      bytes.addAll(List.filled(4, 0)); // フィールドアドレス
      bytes.add(field['length'] as int); // フィールド長
      bytes.add(field['decimal'] as int); // 小数点以下桁数
      bytes.addAll(List.filled(14, 0)); // 予約領域
    }

    bytes.add(0x0D); // フィールド記述子終了

    // データレコード
    for (int i = 0; i < points.length; i++) {
      final feature = points[i];
      bytes.add(0x20); // レコード削除フラグ（スペース）

      for (final field in fields) {
        final fieldName = field['name'] as String;
        final fieldLength = field['length'] as int;
        String value = feature[fieldName]?.toString() ?? '';

        if (field['type'] == 'N') {
          // 数値フィールド：右寄せ、スペース埋め
          value = value.padLeft(fieldLength);
        } else {
          // 文字フィールド：左寄せ、スペース埋め
          value = value.padRight(fieldLength);
        }

        final valueBytes = value.substring(0, fieldLength).codeUnits;
        bytes.addAll(valueBytes);
      }
    }

    bytes.add(0x1A); // ファイル終了マーカー

    await file.writeAsBytes(bytes);
  }

  /// .prjファイルを書き込み（WGS84座標系）
  Future<void> _writePrjFile(String path) async {
    final file = File(path);
    const wgs84Wkt =
        'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'
        'SPHEROID["WGS_1984",6378137.0,298.257223563]],'
        'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';
    await file.writeAsString(wgs84Wkt);
  }

  /// バイト変換ヘルパーメソッド
  List<int> _writeInt32BigEndian(int value) {
    return [
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ];
  }

  List<int> _writeInt32LittleEndian(int value) {
    return [
      value & 0xFF,
      (value >> 8) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 24) & 0xFF,
    ];
  }

  List<int> _writeInt16LittleEndian(int value) {
    return [value & 0xFF, (value >> 8) & 0xFF];
  }

  List<int> _writeFloat64(double value) {
    final buffer = ByteData(8);
    buffer.setFloat64(0, value, Endian.little);
    return buffer.buffer.asUint8List();
  }

  /// ジオメトリタイプを取得
  String _getGeometryType(Map<String, dynamic>? geometry) {
    if (geometry == null) return 'Unknown';
    return geometry['type']?.toString() ?? 'Unknown';
  }

  /// Polygon用.dbfファイルを書き込み（属性データ）
  Future<void> _writeNativePolygonDbfFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);

    // Polygon用属性フィールド定義
    final fields = [
      {'name': 'FID', 'type': 'N', 'length': 10, 'decimal': 0},
      {'name': 'ID', 'type': 'N', 'length': 10, 'decimal': 0},
      {'name': 'NAME', 'type': 'C', 'length': 100, 'decimal': 0},
      {'name': 'DESC', 'type': 'C', 'length': 255, 'decimal': 0},
      {'name': 'AREA', 'type': 'N', 'length': 15, 'decimal': 6},
      {'name': 'PERIMETER', 'type': 'N', 'length': 15, 'decimal': 6},
      {'name': 'PARTS', 'type': 'N', 'length': 5, 'decimal': 0},
      {'name': 'POINTS', 'type': 'N', 'length': 8, 'decimal': 0},
    ];

    final recordLength =
        1 + fields.fold<int>(0, (sum, field) => sum + (field['length'] as int));
    final headerLength = 32 + (fields.length * 32) + 1;

    final bytes = <int>[];

    // DBFヘッダー（32バイト）
    bytes.add(0x03); // バージョン（dBASE III）

    // 日付（年-月-日）
    final now = DateTime.now();
    bytes.add(now.year - 1900); // 年（1900年からの経過年数）
    bytes.add(now.month); // 月
    bytes.add(now.day); // 日

    bytes.addAll(_writeInt32LittleEndian(features.length)); // レコード数
    bytes.addAll(_writeInt16LittleEndian(headerLength)); // ヘッダー長
    bytes.addAll(_writeInt16LittleEndian(recordLength)); // レコード長
    bytes.addAll(List.filled(20, 0)); // 予約領域

    // フィールド記述子（各フィールド32バイト）
    for (final field in fields) {
      final fieldName = field['name'] as String;
      final nameBytes = fieldName.codeUnits;

      // フィールド名（11バイト、null埋め）
      bytes.addAll(nameBytes.take(11));
      bytes.addAll(List.filled(11 - nameBytes.length, 0));

      bytes.add((field['type'] as String).codeUnitAt(0)); // フィールドタイプ
      bytes.addAll(List.filled(4, 0)); // フィールドアドレス（未使用）
      bytes.add(field['length'] as int); // フィールド長
      bytes.add(field['decimal'] as int); // 小数点以下桁数
      bytes.addAll(List.filled(14, 0)); // 予約領域
    }

    bytes.add(0x0D); // フィールド記述子終了マーカー

    // データレコード
    for (int i = 0; i < features.length; i++) {
      final feature = features[i];
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
      final coordinates = geometry['coordinates'] as List? ?? [];

      bytes.add(0x20); // レコード削除フラグ（スペース = 非削除）

      // 各フィールドのデータを書き込み
      for (final field in fields) {
        final fieldName = field['name'] as String;
        final fieldType = field['type'] as String;
        final fieldLength = field['length'] as int;

        String value = '';

        switch (fieldName) {
          case 'FID':
            value = (i + 1).toString(); // 1から始まるFeature ID
            break;
          case 'ID':
            value = (feature['id'] ?? (i + 1)).toString();
            break;
          case 'NAME':
            value = metadata['name']?.toString() ?? '';
            break;
          case 'DESC':
            value = metadata['description']?.toString() ?? '';
            break;
          case 'AREA':
            // 簡易的な面積計算（実際の測地面積ではない）
            value = _calculatePolygonArea(coordinates).toStringAsFixed(6);
            break;
          case 'PERIMETER':
            // 簡易的な周囲長計算
            value = _calculatePolygonPerimeter(coordinates).toStringAsFixed(6);
            break;
          case 'PARTS':
            value = coordinates.length.toString();
            break;
          case 'POINTS':
            int totalPoints = 0;
            for (final ring in coordinates) {
              if (ring is List) totalPoints += ring.length;
            }
            value = totalPoints.toString();
            break;
          default:
            value = '';
        }

        // フィールドタイプに応じたフォーマット
        if (fieldType == 'N') {
          // 数値フィールド：右寄せ、スペース埋め
          value = value.padLeft(fieldLength, ' ');
        } else {
          // 文字フィールド：左寄せ、スペース埋め
          if (value.length > fieldLength) {
            value = value.substring(0, fieldLength);
          }
          value = value.padRight(fieldLength, ' ');
        }

        // 文字列をバイト配列に変換
        final valueBytes = value.codeUnits.take(fieldLength).toList();
        while (valueBytes.length < fieldLength) {
          valueBytes.add(0x20); // スペース文字で埋める
        }
        bytes.addAll(valueBytes);
      }
    }

    bytes.add(0x1A); // ファイル終了マーカー

    await file.writeAsBytes(bytes);
  }

  /// 簡易ポリゴン面積計算（度数単位、測地面積ではない）
  double _calculatePolygonArea(List coordinates) {
    if (coordinates.isEmpty) return 0.0;

    try {
      final firstRing = coordinates.first as List?;
      if (firstRing == null || firstRing.length < 3) return 0.0;

      double area = 0.0;
      for (int i = 0; i < firstRing.length - 1; i++) {
        final p1 = firstRing[i] as List?;
        final p2 = firstRing[i + 1] as List?;

        if (p1 != null && p2 != null && p1.length >= 2 && p2.length >= 2) {
          final x1 = (p1[0] as num).toDouble();
          final y1 = (p1[1] as num).toDouble();
          final x2 = (p2[0] as num).toDouble();
          final y2 = (p2[1] as num).toDouble();

          area += (x1 * y2) - (x2 * y1);
        }
      }

      return (area.abs() / 2.0);
    } catch (e) {
      return 0.0;
    }
  }

  /// 簡易ポリゴン周囲長計算（度数単位、測地距離ではない）
  double _calculatePolygonPerimeter(List coordinates) {
    if (coordinates.isEmpty) return 0.0;

    try {
      double perimeter = 0.0;

      for (final ring in coordinates) {
        if (ring is List && ring.length >= 2) {
          for (int i = 0; i < ring.length - 1; i++) {
            final p1 = ring[i] as List?;
            final p2 = ring[i + 1] as List?;

            if (p1 != null && p2 != null && p1.length >= 2 && p2.length >= 2) {
              final x1 = (p1[0] as num).toDouble();
              final y1 = (p1[1] as num).toDouble();
              final x2 = (p2[0] as num).toDouble();
              final y2 = (p2[1] as num).toDouble();

              final dx = x2 - x1;
              final dy = y2 - y1;
              perimeter += math.sqrt((dx * dx) + (dy * dy));
            }
          }
        }
      }

      return perimeter;
    } catch (e) {
      return 0.0;
    }
  }

  /// WKBデータから座標を解析するヘルパーメソッド
  Future<List?> _parseWkbToCoordinates(
    dynamic wkbData,
    String? geometryType,
  ) async {
    try {
      if (wkbData == null) return null;

      List<int> wkbBytes;
      if (wkbData is List<int>) {
        wkbBytes = wkbData;
      } else if (wkbData is List<dynamic>) {
        wkbBytes = wkbData.cast<int>();
      } else {
        return null;
      }

      final wkbUint8List = Uint8List.fromList(wkbBytes);

      switch (geometryType) {
        case 'Point':
          // Point用のWKB解析（簡易実装）
          final pureWkb =
              wkbUint8List.length > 8 &&
                      wkbUint8List[0] == 0x47 &&
                      wkbUint8List[1] == 0x50
                  ? wkbUint8List.sublist(8)
                  : wkbUint8List;

          if (pureWkb.length >= 21) {
            final lon = ByteData.sublistView(
              pureWkb,
              5,
              13,
            ).getFloat64(0, Endian.little);
            final lat = ByteData.sublistView(
              pureWkb,
              13,
              21,
            ).getFloat64(0, Endian.little);
            return [lon, lat];
          }
          break;

        case 'LineString':
          final linePoints = parseWkbLineString(wkbUint8List);
          if (linePoints.isNotEmpty) {
            final coordinates =
                linePoints
                    .map((point) => [point.longitude, point.latitude])
                    .toList();
            return coordinates;
          }
          break;

        case 'Polygon':
          final polygonRings = parseWkbPolygon(wkbUint8List);
          if (polygonRings.isNotEmpty) {
            final coordinates =
                polygonRings.map((ring) {
                  return ring
                      .map((point) => [point.longitude, point.latitude])
                      .toList();
                }).toList();
            return coordinates;
          }
          break;

        default:
          break;
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Polygonのリング向きを調整（ESRI Shapefile仕様準拠）
  /// 外側のリング: 時計回り（負の面積）
  /// 内側の穴: 反時計回り（正の面積）
  List<List<num>> _adjustPolygonRingOrientation(
    List<List<num>> ring,
    bool isExterior,
  ) {
    if (ring.length < 3) return ring; // 最低3点必要

    // Shoelace公式でリングの符号付き面積を計算
    double signedArea = 0.0;
    final ringLength = ring.length;

    for (int i = 0; i < ringLength; i++) {
      final current = ring[i];
      final next = ring[(i + 1) % ringLength];

      if (current.length >= 2 && next.length >= 2) {
        final x1 = current[0].toDouble();
        final y1 = current[1].toDouble();
        final x2 = next[0].toDouble();
        final y2 = next[1].toDouble();

        signedArea += (x1 * y2) - (x2 * y1);
      }
    }

    signedArea = signedArea / 2.0;

    // 符号で向きを判定（正：反時計回り、負：時計回り）
    final isCounterClockwise = signedArea > 0;

    print(
      '[FeatureConverter] リング向き分析: 面積=$signedArea, 反時計回り=$isCounterClockwise',
    );

    if (isExterior) {
      // ESRI仕様: 外側のリングは時計回り（負の面積）であるべき
      print('[FeatureConverter] 外側リング調整: ${!isCounterClockwise ? "維持" : "反転"}');
      return isCounterClockwise ? ring.reversed.toList() : ring;
    } else {
      // ESRI仕様: 内側の穴は反時計回り（正の面積）であるべき
      print('[FeatureConverter] 内側リング調整: ${isCounterClockwise ? "維持" : "反転"}');
      return isCounterClockwise ? ring : ring.reversed.toList();
    }
  }

  /// ネイティブPolygon用.shxファイルを書き込み
  Future<void> _writeNativePolygonShxFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'Polygon';
        }).toList();

    print('[FeatureConverter] PolygonSHX: 有効なフィーチャ数 = ${validFeatures.length}');

    // バウンディングボックス計算（SHPファイルと同じ）
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      for (final ring in coordinates) {
        if (ring is List) {
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              final x = (coord[0] as num).toDouble();
              final y = (coord[1] as num).toDouble();

              if (x.isFinite && y.isFinite) {
                minX = minX.isFinite ? (minX < x ? minX : x) : x;
                maxX = maxX.isFinite ? (maxX > x ? maxX : x) : x;
                minY = minY.isFinite ? (minY < y ? minY : y) : y;
                maxY = maxY.isFinite ? (maxY > y ? maxY : y) : y;
              }
            }
          }
        }
      }
    }

    // バウンディングボックスの妥当性チェック
    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    print(
      '[FeatureConverter] PolygonSHX: バウンディングボックス = ($minX, $minY) to ($maxX, $maxY)',
    );

    // SHXファイル長とレコード情報を事前計算
    final List<int> recordLengths = [];
    int totalFileLengthWords = 50; // ヘッダー部分

    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      // このポリゴンの総ポイント数を計算
      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) {
          totalPoints += ring.length;
        }
      }

      print(
        '[FeatureConverter] PolygonSHX: フィーチャ$i - リング数=${coordinates.length}, 総ポイント数=$totalPoints',
      );

      // レコード長を正確に計算（16bit words単位）
      // レコードコンテンツ = シェープタイプ(4) + バウンディングボックス(32) + パーツ数(4) + ポイント数(4) + パーツ配列(4*パーツ数) + ポイント配列(16*ポイント数)
      final contentSizeBytes =
          4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final recordLengthWords = (contentSizeBytes + 1) ~/ 2; // バイトをワードに変換（切り上げ）

      recordLengths.add(recordLengthWords);
      totalFileLengthWords += 4 + recordLengthWords; // レコードヘッダー(4ワード) + コンテンツ

      print(
        '[FeatureConverter] PolygonSHX: フィーチャ$i - レコード長=${recordLengthWords}ワード',
      );
    }

    // SHXヘッダー（SHPファイルと同じ構造の100バイト）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用フィールド（5 * 4バイト）
    bytes.addAll(
      _writeInt32BigEndian(50 + validFeatures.length * 4),
    ); // SHXファイル長（ヘッダー + インデックスレコード数）
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(5)); // シェープタイプ（Polygon = 5）

    // バウンディングボックス（SHPファイルと同じ64バイト）
    bytes.addAll(_writeFloat64(minX));
    bytes.addAll(_writeFloat64(minY));
    bytes.addAll(_writeFloat64(maxX));
    bytes.addAll(_writeFloat64(maxY));
    bytes.addAll(_writeFloat64(0.0)); // Zmin
    bytes.addAll(_writeFloat64(0.0)); // Zmax
    bytes.addAll(_writeFloat64(0.0)); // Mmin
    bytes.addAll(_writeFloat64(0.0)); // Mmax

    // インデックスレコード作成（各8バイト）
    int offset = 50; // ヘッダー後の開始位置（16bit words単位）

    for (int i = 0; i < validFeatures.length; i++) {
      final recordLength = recordLengths[i];

      print(
        '[FeatureConverter] PolygonSHX: フィーチャ$i - オフセット=${offset}ワード, 長さ=${recordLength}ワード',
      );

      // インデックスレコード（8バイト = 4ワード）
      bytes.addAll(_writeInt32BigEndian(offset)); // オフセット（16bit words単位）
      bytes.addAll(_writeInt32BigEndian(recordLength)); // レコード長（16bit words単位）

      // 次のレコードのオフセットを計算
      offset += 4 + recordLength; // レコードヘッダー(4ワード) + レコード長
    }

    print(
      '[FeatureConverter] PolygonSHX: 書き込み完了 - SHXファイルサイズ=${bytes.length}バイト',
    );

    await file.writeAsBytes(bytes);
  }

  /// ネイティブPoint用.shxファイルを書き込み
  Future<void> _writeNativePointShxFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'Point';
        }).toList();

    // バウンディングボックス計算（SHPファイルと同じ）
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      if (coordinates.length >= 2) {
        final x = (coordinates[0] as num).toDouble();
        final y = (coordinates[1] as num).toDouble();

        if (x.isFinite && y.isFinite) {
          minX = minX.isFinite ? (minX < x ? minX : x) : x;
          maxX = maxX.isFinite ? (maxX > x ? maxX : x) : x;
          minY = minY.isFinite ? (minY < y ? minY : y) : y;
          maxY = maxY.isFinite ? (maxY > y ? maxY : y) : y;
        }
      }
    }

    // バウンディングボックスの初期値チェック
    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    // SHXファイル長を正確に計算（16bit words単位）
    // ヘッダー: 100バイト = 50ワード
    // 各インデックスレコード: 8バイト = 4ワード
    final fileLengthInWords = 50 + (validFeatures.length * 4);

    // SHXヘッダー（SHPファイルと同じ構造の100バイト）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用（5 * 4バイト）
    bytes.addAll(
      _writeInt32BigEndian(fileLengthInWords),
    ); // ファイル長（16bit words単位）
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(1)); // シェープタイプ（Point）

    // バウンディングボックス（SHPファイルと同じ64バイト）
    bytes.addAll(_writeFloat64(minX));
    bytes.addAll(_writeFloat64(minY));
    bytes.addAll(_writeFloat64(maxX));
    bytes.addAll(_writeFloat64(maxY));
    bytes.addAll(_writeFloat64(0.0)); // Zmin
    bytes.addAll(_writeFloat64(0.0)); // Zmax
    bytes.addAll(_writeFloat64(0.0)); // Mmin
    bytes.addAll(_writeFloat64(0.0)); // Mmax

    // インデックスレコード（各8バイト）
    int offset = 50; // ヘッダー後の開始位置（16bit words単位）
    for (int i = 0; i < validFeatures.length; i++) {
      bytes.addAll(_writeInt32BigEndian(offset)); // オフセット（16bit words単位）
      bytes.addAll(_writeInt32BigEndian(10)); // コンテンツ長（10ワード = 20バイト）
      offset += 14; // 次のレコードへ（レコードヘッダー4ワード + コンテンツ10ワード）
    }

    await file.writeAsBytes(bytes);
  }

  /// ネイティブLineString用.shpファイルを書き込み
  Future<void> _writeNativeLineShpFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    // バウンディングボックス計算
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'LineString';
        }).toList();

    int totalFileLength = 50; // ヘッダーサイズ

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          final x = (coord[0] as num).toDouble();
          final y = (coord[1] as num).toDouble();
          minX = minX < x ? minX : x;
          maxX = maxX > x ? maxX : x;
          minY = minY < y ? minY : y;
          maxY = maxY > y ? maxY : y;
        }
      }

      // レコードサイズ = ヘッダー(4) + シェープタイプ(4) + バウンディングボックス(32) + パーツ数(4) + ポイント数(4) + パーツ配列(4*1) + ポイント配列(16*ポイント数)
      final recordSize = 4 + 4 + 32 + 4 + 4 + 4 + (16 * coordinates.length);
      totalFileLength += (recordSize + 8) ~/ 2; // レコードヘッダー(8バイト)を含む、ワード単位
    }

    // SHPヘッダー（100バイト）
    bytes.addAll(_writeInt32BigEndian(9994)); // ファイルコード
    bytes.addAll(List.filled(20, 0)); // 未使用
    bytes.addAll(_writeInt32BigEndian(totalFileLength)); // ファイル長
    bytes.addAll(_writeInt32LittleEndian(1000)); // バージョン
    bytes.addAll(_writeInt32LittleEndian(3)); // シェープタイプ（PolyLine）

    // バウンディングボックス
    bytes.addAll(_writeFloat64(minX));
    bytes.addAll(_writeFloat64(minY));
    bytes.addAll(_writeFloat64(maxX));
    bytes.addAll(_writeFloat64(maxY));
    bytes.addAll(_writeFloat64(0.0)); // Zmin
    bytes.addAll(_writeFloat64(0.0)); // Zmax
    bytes.addAll(_writeFloat64(0.0)); // Mmin
    bytes.addAll(_writeFloat64(0.0)); // Mmax

    // ラインストリングレコード
    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      final contentLength = (44 + 4 + (16 * coordinates.length)) ~/ 2; // ワード単位

      bytes.addAll(_writeInt32BigEndian(i + 1)); // レコード番号
      bytes.addAll(_writeInt32BigEndian(contentLength)); // コンテンツ長
      bytes.addAll(_writeInt32LittleEndian(3)); // シェープタイプ（PolyLine）

      // ラインのバウンディングボックス
      double lineMinX = double.infinity, lineMinY = double.infinity;
      double lineMaxX = double.negativeInfinity,
          lineMaxY = double.negativeInfinity;

      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          final x = (coord[0] as num).toDouble();
          final y = (coord[1] as num).toDouble();
          lineMinX = lineMinX < x ? lineMinX : x;
          lineMaxX = lineMaxX > x ? lineMaxX : x;
          lineMinY = lineMinY < y ? lineMinY : y;
          lineMaxY = lineMaxY > y ? lineMaxY : y;
        }
      }

      bytes.addAll(_writeFloat64(lineMinX));
      bytes.addAll(_writeFloat64(lineMinY));
      bytes.addAll(_writeFloat64(lineMaxX));
      bytes.addAll(_writeFloat64(lineMaxY));

      // パーツ数とポイント数
      bytes.addAll(_writeInt32LittleEndian(1)); // パーツ数（LineStringは1つのパート）
      bytes.addAll(_writeInt32LittleEndian(coordinates.length)); // ポイント数

      // パーツ配列（開始ポイントインデックス）
      bytes.addAll(_writeInt32LittleEndian(0)); // 開始インデックス0

      // ポイント配列
      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          bytes.addAll(_writeFloat64((coord[0] as num).toDouble()));
          bytes.addAll(_writeFloat64((coord[1] as num).toDouble()));
        }
      }
    }

    await file.writeAsBytes(bytes);
  }
}

/// フィーチャ変換・処理用コンバーター
class FeatureTransformConverter
    extends BaseConverter<FeatureConversionParams, List<Map<String, dynamic>>> {
  final String Function(Map<String, dynamic>) transformFunction;

  FeatureTransformConverter({required this.transformFunction});

  @override
  Future<ConversionResult> convert(FeatureConversionParams input) async {
    try {
      notifyProgress(0.4, 'Transforming features...');

      final transformedFeatures = <Map<String, dynamic>>[];

      for (int i = 0; i < input.features.length; i++) {
        try {
          final feature = input.features[i];

          // 進行状況更新
          final progress = 0.4 + (0.5 * (i / input.features.length));
          notifyProgress(
            progress,
            'Transforming feature ${i + 1}/${input.features.length}...',
          );

          // カスタム変換関数を適用
          final transformedFeature = Map<String, dynamic>.from(feature);
          final transformResult = transformFunction(transformedFeature);

          // 変換結果をフィーチャに反映（例：座標変換結果など）
          if (transformResult.isNotEmpty) {
            transformedFeature['transformed'] = transformResult;
          }

          transformedFeatures.add(transformedFeature);
        } catch (e) {
          // エラーがあっても処理を続行
          transformedFeatures.add(input.features[i]);
        }
      }

      return ConversionResult.success(
        data: transformedFeatures,
        metadata: {
          'originalCount': input.features.length,
          'transformedCount': transformedFeatures.length,
        },
      );
    } catch (e) {
      return ConversionResult.error('Feature transformation failed: $e');
    }
  }
}

/// フィーチャバリデーションコンバーター
class FeatureValidationConverter
    extends BaseConverter<List<Map<String, dynamic>>, Map<String, dynamic>> {
  @override
  Future<ConversionResult> convert(List<Map<String, dynamic>> input) async {
    try {
      notifyProgress(0.4, 'Validating features...');

      final validationResults = {
        'totalFeatures': input.length,
        'validFeatures': 0,
        'invalidFeatures': 0,
        'errors': <Map<String, dynamic>>[],
      };

      for (int i = 0; i < input.length; i++) {
        try {
          final feature = input[i];
          final progress = 0.4 + (0.5 * (i / input.length));
          notifyProgress(
            progress,
            'Validating feature ${i + 1}/${input.length}...',
          );

          final isValid = _validateFeature(feature);
          if (isValid) {
            validationResults['validFeatures'] =
                (validationResults['validFeatures'] as int) + 1;
          } else {
            validationResults['invalidFeatures'] =
                (validationResults['invalidFeatures'] as int) + 1;
            (validationResults['errors'] as List).add({
              'featureIndex': i,
              'featureId': feature['id'],
              'error': 'Invalid feature structure',
            });
          }
        } catch (e) {
          validationResults['invalidFeatures'] =
              (validationResults['invalidFeatures'] as int) + 1;
          (validationResults['errors'] as List).add({
            'featureIndex': i,
            'error': e.toString(),
          });
        }
      }

      return ConversionResult.success(
        data: validationResults,
        metadata: {
          'validationCompleted': true,
          'successRate':
              (validationResults['validFeatures'] as int) / input.length,
        },
      );
    } catch (e) {
      return ConversionResult.error('Feature validation failed: $e');
    }
  }

  /// 個別フィーチャのバリデーション
  bool _validateFeature(Map<String, dynamic> feature) {
    // 基本的なバリデーション
    if (!feature.containsKey('id')) return false;
    if (!feature.containsKey('geometry')) return false;

    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) return false;
    if (!geometry.containsKey('type')) return false;
    if (!geometry.containsKey('coordinates')) return false;

    return true;
  }
}
