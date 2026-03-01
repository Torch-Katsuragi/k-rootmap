import 'package:k_maps/utils/app_logger.dart';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import '../base_converter.dart';
import '../../utils/wkb_utils.dart';
import '../../utils/binary_utils.dart';

/// Shapefile形式のフィーチャ書き出しクラス
class ShapefileWriter {
  final bool convertToPointCloud;

  ShapefileWriter({this.convertToPointCloud = true});

  Future<ConversionResult> write(
    List<Map<String, dynamic>> features,
    String outputPath,
    void Function(double, String) notifyProgress,
  ) async {
    try {
      notifyProgress(0.5, 'Converting features to shapefile...');

      if (convertToPointCloud) {
        return await _exportToPointCloudShapefile(
          features,
          outputPath,
          notifyProgress,
        );
      } else {
        return await _exportToNativeShapefile(
          features,
          outputPath,
          notifyProgress,
        );
      }
    } catch (e) {
      return ConversionResult.error('Shapefile export failed: $e');
    }
  }

  /// ポイントクラウド形式でのShapefileエクスポート（既存機能）
  Future<ConversionResult> _exportToPointCloudShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
    void Function(double, String) notifyProgress,
  ) async {
    try {
      notifyProgress(0.5, 'Converting features to point cloud...');

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

        bool needWkbParsing = false;
        if (coordinates == null) {
          needWkbParsing = true;
        } else if (coordinates is List) {
          if (coordinates.isEmpty) {
            needWkbParsing = true;
          } else if (coordinates.every(
            (coord) => coord is List && coord.isEmpty,
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
            if (coordinates is List && coordinates.isNotEmpty) {
              AppLogger.debug('=== [ShapefileWriter] Polygon点群変換開始 ===');
              AppLogger.debug(
                '[ShapefileWriter] フィーチャID: ${feature['id']}',
              );
              AppLogger.debug(
                '[ShapefileWriter] リング数: ${coordinates.length}',
              );
              AppLogger.debug(
                '[ShapefileWriter] 重複点除去: ON (閉じたリングの最後の点をスキップ)',
              );

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

                  AppLogger.debug(
                    '[ShapefileWriter] リング $ringIndex 処理開始: ${ring.length}点 ($ringType)',
                  );

                  for (int i = 0; i < ring.length; i++) {
                    final coord = ring[i];
                    if (coord is List && coord.length >= 2) {
                      if (i == ring.length - 1 && ring.length > 1) {
                        final firstCoord = ring[0] as List;
                        final lastCoord = coord;
                        const tolerance = 0.000001;

                        AppLogger.debug(
                          '[ShapefileWriter] 最後の点の重複チェック (リング $ringIndex):',
                        );
                        AppLogger.debug(
                          '[ShapefileWriter]   最初の点: (${firstCoord[1]}, ${firstCoord[0]})',
                        );
                        AppLogger.debug(
                          '[ShapefileWriter]   最後の点: (${lastCoord[1]}, ${lastCoord[0]})',
                        );

                        final latDiff = (firstCoord[1] - lastCoord[1]).abs();
                        final lngDiff = (firstCoord[0] - lastCoord[0]).abs();
                        AppLogger.debug(
                          '[ShapefileWriter]   座標差分: 緯度=${latDiff.toStringAsFixed(8)}, 経度=${lngDiff.toStringAsFixed(8)}',
                        );

                        if (latDiff < tolerance && lngDiff < tolerance) {
                          AppLogger.debug(
                            '[ShapefileWriter] ✓ 重複する最後の点をスキップ (リング $ringIndex)',
                          );
                          continue;
                        } else {
                          AppLogger.debug(
                            '[ShapefileWriter] ✗ 最後の点は重複していない、追加します (リング $ringIndex)',
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
                        AppLogger.debug(
                          '[ShapefileWriter] 点追加[$addedPointsCount]: (${coord[1]}, ${coord[0]}) POINT_ID=${pointId - 1}',
                        );
                      }
                    }
                  }
                  AppLogger.debug(
                    '[ShapefileWriter] リング $ringIndex 完了: $originalRingSize点 -> $addedPointsCount点 (${originalRingSize - addedPointsCount}点除去)',
                  );
                }
              }
              AppLogger.debug(
                '[ShapefileWriter] Polygon変換完了: フィーチャID=${feature['id']}',
              );
            }
            break;
        }
      }

      if (points.isEmpty) {
        return ConversionResult.error('No valid points found for export');
      }

      notifyProgress(0.7, 'Creating Point Shapefile...');

      await _writePointShapefileComponents(points, outputPath);
      return ConversionResult.success(
        data: outputPath,
        metadata: {
          'exportFormat': 'shapefile',
          'shapeType': 'Point',
          'featureCount': features.length,
          'pointCount': points.length,
          'originalFeatures': features.length,
          'outputPath': outputPath,
        },
      );
    } catch (e) {
      return ConversionResult.error('Point cloud shapefile export failed: $e');
    }
  }

  /// 元の形状を保持したShapefileエクスポート
  Future<ConversionResult> _exportToNativeShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
    void Function(double, String) notifyProgress,
  ) async {
    try {
      if (features.isEmpty) {
        return ConversionResult.error('No features to export');
      }

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

      final primaryGeometryType = geometryTypes.first;

      notifyProgress(0.6, 'Creating $primaryGeometryType Shapefile...');

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
          'featureCount': features.length,
          'outputPath': outputPath,
        },
      );
    } catch (e) {
      return ConversionResult.error('Native shapefile export failed: $e');
    }
  }

  Future<void> _writeNativePointShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
  ) async {
    final basePath = _getBasePathWithoutExtension(outputPath);
    await _writeNativePointShpFile(features, '$basePath.shp');
    await _writeNativePointShxFile(features, '$basePath.shx');
    await _writeNativeDbfFile(features, '$basePath.dbf');
    await _writePrjFile('$basePath.prj');
  }

  Future<void> _writeNativePolygonShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
  ) async {
    final basePath = _getBasePathWithoutExtension(outputPath);
    await _writeNativePolygonShpFile(features, '$basePath.shp');
    await _writeNativePolygonShxFile(features, '$basePath.shx');
    await _writeNativeDbfFile(features, '$basePath.dbf');
    await _writePrjFile('$basePath.prj');
  }

  Future<void> _writeNativeLineShapefile(
    List<Map<String, dynamic>> features,
    String outputPath,
  ) async {
    final basePath = _getBasePathWithoutExtension(outputPath);
    await _writeNativeLineShpFile(features, '$basePath.shp');
    await _writeNativeLineShxFile(features, '$basePath.shx');
    await _writeNativeDbfFile(features, '$basePath.dbf');
    await _writePrjFile('$basePath.prj');
  }

  Future<void> _writeNativePointShpFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

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

        if (x.isFinite && y.isFinite) {
          minX = minX.isFinite ? (minX < x ? minX : x) : x;
          maxX = maxX.isFinite ? (maxX > x ? maxX : x) : x;
          minY = minY.isFinite ? (minY < y ? minY : y) : y;
          maxY = maxY.isFinite ? (maxY > y ? maxY : y) : y;
        }
      }
    }

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    final fileLengthInWords = 50 + (validFeatures.length * 14);

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(fileLengthInWords));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(10));

      bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));
      bytes.addAll(
        BinaryUtils.writeFloat64((coordinates[0] as num).toDouble()),
      );
      bytes.addAll(
        BinaryUtils.writeFloat64((coordinates[1] as num).toDouble()),
      );
    }

    await file.writeAsBytes(bytes);
  }

  Future<void> _writeNativePolygonShpFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

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

    int totalFileLength = 50;

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

      final recordContentSize =
          4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final recordSizeInWords = (recordContentSize + 1) ~/ 2;

      totalFileLength += 4 + recordSizeInWords;
    }

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(totalFileLength));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(5));

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) {
          totalPoints += ring.length;
        }
      }

      final contentSizeInBytes =
          4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final contentLength = (contentSizeInBytes + 1) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(contentLength));

      bytes.addAll(BinaryUtils.writeInt32LittleEndian(5));

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

      if (!polygonMinX.isFinite) polygonMinX = 0.0;
      if (!polygonMaxX.isFinite) polygonMaxX = 0.0;
      if (!polygonMinY.isFinite) polygonMinY = 0.0;
      if (!polygonMaxY.isFinite) polygonMaxY = 0.0;

      bytes.addAll(BinaryUtils.writeFloat64(polygonMinX));
      bytes.addAll(BinaryUtils.writeFloat64(polygonMinY));
      bytes.addAll(BinaryUtils.writeFloat64(polygonMaxX));
      bytes.addAll(BinaryUtils.writeFloat64(polygonMaxY));

      bytes.addAll(BinaryUtils.writeInt32LittleEndian(coordinates.length));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(totalPoints));

      int pointIndex = 0;
      for (int ringIndex = 0; ringIndex < coordinates.length; ringIndex++) {
        bytes.addAll(BinaryUtils.writeInt32LittleEndian(pointIndex));
        final ring = coordinates[ringIndex] as List;
        pointIndex += ring.length;
      }

      for (int ringIndex = 0; ringIndex < coordinates.length; ringIndex++) {
        final ring = coordinates[ringIndex] as List;
        if (ring.isNotEmpty) {
          final ringCoords = ring.cast<List<num>>();

          AppLogger.debug(
            '[ShapefileWriter] Polygon処理: フィーチャID=${feature['id']}, リング$ringIndex',
          );
          AppLogger.debug(
            '[ShapefileWriter] 元のリング座標数: ${ringCoords.length}',
          );
          AppLogger.debug(
            '[ShapefileWriter] リングタイプ: ${ringIndex == 0 ? "外側" : "内側（穴）"}',
          );

          final adjustedRing = _adjustPolygonRingOrientation(
            ringCoords,
            ringIndex == 0,
          );

          AppLogger.debug(
            '[ShapefileWriter] 調整後のリング座標数: ${adjustedRing.length}',
          );
          AppLogger.debug(
            '[ShapefileWriter] 座標調整: ${ringCoords.length != adjustedRing.length ? "エラー" : "正常"}',
          );

          for (final coord in adjustedRing) {
            if (coord.length >= 2) {
              final x = coord[0].toDouble();
              final y = coord[1].toDouble();

              final validX = x.isFinite ? x : 0.0;
              final validY = y.isFinite ? y : 0.0;

              bytes.addAll(BinaryUtils.writeFloat64(validX));
              bytes.addAll(BinaryUtils.writeFloat64(validY));
            }
          }

          AppLogger.debug('[ShapefileWriter] リング$ringIndex 書き込み完了');
        }
      }
    }

    await file.writeAsBytes(bytes);
  }

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

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      for (final coord in coordinates) {
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

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));

    final totalFileLength = 50 + (validFeatures.length * 4);
    bytes.addAll(BinaryUtils.writeInt32BigEndian(totalFileLength));

    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(3));

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    int offset = 50;
    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      final recordLength =
          (4 + 32 + 4 + 4 + 4 + (16 * coordinates.length)) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(recordLength));
      offset += recordLength + 4;
    }

    await file.writeAsBytes(bytes);
  }

  Future<void> _writeNativeDbfFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);

    if (features.isEmpty) {
      final bytes = <int>[];
      bytes.add(0x03);
      bytes.addAll(List.filled(31, 0));
      await file.writeAsBytes(bytes);
      return;
    }

    final fields = <Map<String, dynamic>>[];
    final allMetadata = <String, dynamic>{};

    const excludedColumns = {'fid', 'geom', 'id', 'rowid', 'geometry'};

    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      for (final entry in metadata.entries) {
        if (!excludedColumns.contains(entry.key.toLowerCase())) {
          allMetadata[entry.key] = entry.value;
        }
      }
    }

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

      String fieldName =
          entry.key.length > 10 ? entry.key.substring(0, 10) : entry.key;

      if (!fields.any((f) => f['name'] == fieldName.toUpperCase())) {
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

    bytes.add(0x03);
    bytes.add(24);
    bytes.add(12);
    bytes.add(19);
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(features.length));
    bytes.addAll(BinaryUtils.writeInt16LittleEndian(headerLength));
    bytes.addAll(BinaryUtils.writeInt16LittleEndian(recordLength));
    bytes.addAll(List.filled(20, 0));

    for (final field in fields) {
      final nameBytes = BinaryUtils.encodeToShiftJis(
        field['name'] as String,
        11,
      );
      bytes.addAll(nameBytes);
      bytes.add((field['type'] as String).codeUnitAt(0));
      bytes.addAll(List.filled(4, 0));
      bytes.add(field['length'] as int);
      bytes.add(field['decimal'] as int);
      bytes.addAll(List.filled(14, 0));
    }

    bytes.add(0x0D);

    for (int i = 0; i < features.length; i++) {
      final feature = features[i];
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};

      bytes.add(0x20);

      for (final field in fields) {
        final fieldName = field['name'] as String;
        final fieldLength = field['length'] as int;

        final metaValue =
            metadata.entries
                .firstWhere(
                  (entry) => entry.key.toUpperCase() == fieldName,
                  orElse: () => MapEntry('', ''),
                )
                .value;
        String value = metaValue?.toString() ?? '';

        if (field['type'] == 'N') {
          value = value.padLeft(fieldLength);
        } else {
          value = value.padRight(fieldLength);
        }

        final valueBytes = BinaryUtils.encodeToShiftJis(
          value,
          fieldLength,
          padWithSpace: true,
        );
        bytes.addAll(valueBytes);
      }
    }

    bytes.add(0x1A);

    await file.writeAsBytes(bytes);

    final cpgPath = path.replaceAll('.dbf', '.cpg');
    await File(cpgPath).writeAsString('CP932');
  }

  Future<void> _writePointShapefileComponents(
    List<Map<String, dynamic>> points,
    String outputPath,
  ) async {
    final basePath = _getBasePathWithoutExtension(outputPath);
    await _writeShpFile(points, '$basePath.shp');
    await _writeShxFile(points, '$basePath.shx');
    await _writeDbfFile(points, '$basePath.dbf');
    await _writePrjFile('$basePath.prj');
  }

  Future<void> _writeShpFile(
    List<Map<String, dynamic>> points,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(50 + points.length * 14));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));

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

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(10));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));
      bytes.addAll(
        BinaryUtils.writeFloat64(
          (point['LONGITUDE'] as num? ?? 0.0).toDouble(),
        ),
      );
      bytes.addAll(
        BinaryUtils.writeFloat64((point['LATITUDE'] as num? ?? 0.0).toDouble()),
      );
    }

    await file.writeAsBytes(bytes);
  }

  Future<void> _writeShxFile(
    List<Map<String, dynamic>> points,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(50 + points.length * 4));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));
    bytes.addAll(List.filled(64, 0));

    int offset = 50;
    for (int i = 0; i < points.length; i++) {
      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(14));
      offset += 14;
    }

    await file.writeAsBytes(bytes);
  }

  Future<void> _writeDbfFile(
    List<Map<String, dynamic>> points,
    String path,
  ) async {
    final file = File(path);

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

    bytes.add(0x03);
    bytes.add(24);
    bytes.add(12);
    bytes.add(19);
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(points.length));
    bytes.addAll(BinaryUtils.writeInt16LittleEndian(headerLength));
    bytes.addAll(BinaryUtils.writeInt16LittleEndian(recordLength));
    bytes.addAll(List.filled(20, 0));

    for (final field in fields) {
      final nameBytes = BinaryUtils.encodeToShiftJis(
        field['name'] as String,
        11,
      );
      bytes.addAll(nameBytes);
      bytes.add((field['type'] as String).codeUnitAt(0));
      bytes.addAll(List.filled(4, 0));
      bytes.add(field['length'] as int);
      bytes.add(field['decimal'] as int);
      bytes.addAll(List.filled(14, 0));
    }

    bytes.add(0x0D);

    for (int i = 0; i < points.length; i++) {
      final feature = points[i];
      bytes.add(0x20);

      for (final field in fields) {
        final fieldName = field['name'] as String;
        final fieldLength = field['length'] as int;
        String value = feature[fieldName]?.toString() ?? '';

        if (field['type'] == 'N') {
          value = value.padLeft(fieldLength);
        } else {
          value = value.padRight(fieldLength);
        }

        final valueBytes = BinaryUtils.encodeToShiftJis(
          value,
          fieldLength,
          padWithSpace: true,
        );
        bytes.addAll(valueBytes);
      }
    }

    bytes.add(0x1A);

    await file.writeAsBytes(bytes);

    final cpgPath = path.replaceAll('.dbf', '.cpg');
    await File(cpgPath).writeAsString('CP932');
  }

  Future<void> _writePrjFile(String path) async {
    final file = File(path);
    const wgs84Wkt =
        'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'
        'SPHEROID["WGS_1984",6378137.0,298.257223563]],'
        'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';
    await file.writeAsString(wgs84Wkt);
  }

  String _getBasePathWithoutExtension(String outputPath) {
    final lastDotIndex = outputPath.lastIndexOf('.');
    final lastSeparatorIndex = math.max(
      outputPath.lastIndexOf('/'),
      outputPath.lastIndexOf('\\'),
    );

    if (lastDotIndex == -1 || lastDotIndex < lastSeparatorIndex) {
      return outputPath;
    }

    return outputPath.substring(0, lastDotIndex);
  }

  // ignore: unused_element
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

  // ignore: unused_element
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
    if (ring.length < 3) return ring;

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

    final isCounterClockwise = signedArea > 0;

    AppLogger.debug(
      '[ShapefileWriter] リング向き分析: 面積=$signedArea, 反時計回り=$isCounterClockwise',
    );

    if (isExterior) {
      AppLogger.debug(
        '[ShapefileWriter] 外側リング調整: ${!isCounterClockwise ? "維持" : "反転"}',
      );
      return isCounterClockwise ? ring.reversed.toList() : ring;
    } else {
      AppLogger.debug(
        '[ShapefileWriter] 内側リング調整: ${isCounterClockwise ? "維持" : "反転"}',
      );
      return isCounterClockwise ? ring : ring.reversed.toList();
    }
  }

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

    AppLogger.debug(
      '[ShapefileWriter] PolygonSHX: 有効なフィーチャ数 = ${validFeatures.length}',
    );

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

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    AppLogger.debug(
      '[ShapefileWriter] PolygonSHX: バウンディングボックス = ($minX, $minY) to ($maxX, $maxY)',
    );

    final List<int> recordLengths = [];

    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) {
          totalPoints += ring.length;
        }
      }

      AppLogger.debug(
        '[ShapefileWriter] PolygonSHX: フィーチャ$i - リング数=${coordinates.length}, 総ポイント数=$totalPoints',
      );

      final contentSizeBytes =
          4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final recordLengthWords = (contentSizeBytes + 1) ~/ 2;

      recordLengths.add(recordLengthWords);

      AppLogger.debug(
        '[ShapefileWriter] PolygonSHX: フィーチャ$i - レコード長=$recordLengthWordsワード',
      );
    }

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(
      BinaryUtils.writeInt32BigEndian(50 + validFeatures.length * 4),
    );
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(5));

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    int offset = 50;

    for (int i = 0; i < validFeatures.length; i++) {
      final recordLength = recordLengths[i];

      AppLogger.debug(
        '[ShapefileWriter] PolygonSHX: フィーチャ$i - オフセット=$offsetワード, 長さ=$recordLengthワード',
      );

      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(recordLength));

      offset += 4 + recordLength;
    }

    AppLogger.debug(
      '[ShapefileWriter] PolygonSHX: 書き込み完了 - SHXファイルサイズ=${bytes.length}バイト',
    );

    await file.writeAsBytes(bytes);
  }

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

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    final fileLengthInWords = 50 + (validFeatures.length * 4);

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(fileLengthInWords));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    int offset = 50;
    for (int i = 0; i < validFeatures.length; i++) {
      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(10));
      offset += 14;
    }

    await file.writeAsBytes(bytes);
  }

  Future<void> _writeNativeLineShpFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    final file = File(path);
    final bytes = <int>[];

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    final validFeatures =
        features.where((feature) {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          return geometry != null && geometry['type'] == 'LineString';
        }).toList();

    int totalFileLength = 50;

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

      final recordContentSize = 4 + 32 + 4 + 4 + 4 + (16 * coordinates.length);
      totalFileLength += 4 + (recordContentSize ~/ 2);
    }

    if (!minX.isFinite || !maxX.isFinite || !minY.isFinite || !maxY.isFinite) {
      minX = maxX = minY = maxY = 0.0;
    }

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(totalFileLength));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(3));

    bytes.addAll(BinaryUtils.writeFloat64(minX));
    bytes.addAll(BinaryUtils.writeFloat64(minY));
    bytes.addAll(BinaryUtils.writeFloat64(maxX));
    bytes.addAll(BinaryUtils.writeFloat64(maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    for (int i = 0; i < validFeatures.length; i++) {
      final feature = validFeatures[i];
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      final contentLength =
          (4 + 32 + 4 + 4 + 4 + (16 * coordinates.length)) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(contentLength));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(3));

      double lineMinX = double.infinity, lineMinY = double.infinity;
      double lineMaxX = double.negativeInfinity,
          lineMaxY = double.negativeInfinity;

      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          final x = (coord[0] as num).toDouble();
          final y = (coord[1] as num).toDouble();
          if (x.isFinite && y.isFinite) {
            lineMinX = lineMinX.isFinite ? (lineMinX < x ? lineMinX : x) : x;
            lineMaxX = lineMaxX.isFinite ? (lineMaxX > x ? lineMaxX : x) : x;
            lineMinY = lineMinY.isFinite ? (lineMinY < y ? lineMinY : y) : y;
            lineMaxY = lineMaxY.isFinite ? (lineMaxY > y ? lineMaxY : y) : y;
          }
        }
      }

      if (!lineMinX.isFinite) lineMinX = 0.0;
      if (!lineMaxX.isFinite) lineMaxX = 0.0;
      if (!lineMinY.isFinite) lineMinY = 0.0;
      if (!lineMaxY.isFinite) lineMaxY = 0.0;

      bytes.addAll(BinaryUtils.writeFloat64(lineMinX));
      bytes.addAll(BinaryUtils.writeFloat64(lineMinY));
      bytes.addAll(BinaryUtils.writeFloat64(lineMaxX));
      bytes.addAll(BinaryUtils.writeFloat64(lineMaxY));

      bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(coordinates.length));

      bytes.addAll(BinaryUtils.writeInt32LittleEndian(0));

      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          bytes.addAll(BinaryUtils.writeFloat64((coord[0] as num).toDouble()));
          bytes.addAll(BinaryUtils.writeFloat64((coord[1] as num).toDouble()));
        }
      }
    }

    await file.writeAsBytes(bytes);
  }
}
