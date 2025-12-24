// K-MAPS: Shapefile Exporter
// Shapefileエクスポートクラス
import 'dart:io';
import 'dart:typed_data';
import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';
import '../import_export_models.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/geometry_type.dart';
import '../../../utils/binary_utils.dart';
import '../../../utils/wkb_utils.dart';
import 'base_exporter.dart';

/// Shapefileエクスポーター
class ShapefileExporter extends BaseExporter {
  @override
  FileFormat get format => FileFormat.shapefile;

  @override
  Future<ImportExportResult> export(LayerNode layer, String outputPath) async {
    try {
      AppLogger.debug('[ShapefileExporter] エクスポート開始: ${layer.layerName}');

      final features = await layer.geoPackageNode.geoPackageFile.getFeatures(
        layer.layerName,
      );
      final geometryType = await layer.geoPackageNode.geoPackageFile
          .getGeometryType(layer.layerName);

      if (features.isEmpty) {
        return ImportExportResult.error('No features found in layer: ${layer.layerName}');
      }

      // フィーチャをGeoJSON形式に変換
      final geoJsonFeatures = await _convertFeaturesToGeoJson(features, geometryType);

      if (geoJsonFeatures.isEmpty) {
        return ImportExportResult.error('No valid features could be converted for export');
      }

      // ベースパスを取得
      final basePath = _getBasePathWithoutExtension(outputPath);

      // ジオメトリタイプに応じてShapefileを生成
      switch (geometryType) {
        case GeometryType.point:
          await _writePointShapefile(geoJsonFeatures, basePath);
          break;
        case GeometryType.linestring:
          await _writeLineShapefile(geoJsonFeatures, basePath);
          break;
        case GeometryType.polygon:
          await _writePolygonShapefile(geoJsonFeatures, basePath);
          break;
        default:
          return ImportExportResult.error('Unsupported geometry type: ${geometryType?.value}');
      }

      AppLogger.debug('[ShapefileExporter] エクスポート完了: ${geoJsonFeatures.length}個のフィーチャ');

      return ImportExportResult.success(
        metadata: {
          'outputPath': outputPath,
          'featureCount': geoJsonFeatures.length,
          'geometryType': geometryType?.value ?? 'Unknown',
          'format': 'Shapefile',
        },
      );
    } catch (e, stackTrace) {
      AppLogger.debug('[ShapefileExporter] エクスポートエラー: $e');
      AppLogger.debug('[ShapefileExporter] スタックトレース: $stackTrace');
      return ImportExportResult.error('Shapefile export failed: $e');
    }
  }

  /// フィーチャをGeoJSON形式に変換
  Future<List<Map<String, dynamic>>> _convertFeaturesToGeoJson(
    List<Map<String, dynamic>> features,
    GeometryType? geometryType,
  ) async {
    final geoJsonFeatures = <Map<String, dynamic>>[];
    const reservedKeys = {'fid', 'geom', 'id', 'rowid', 'geometry', 'points', 'lines', 'polygons', 'rings', 'point', 'line'};

    for (final feature in features) {
      Map<String, dynamic>? geometry;
      final Map<String, dynamic> metadata = {};

      feature.forEach((key, value) {
        if (!reservedKeys.contains(key.toLowerCase()) && value != null) {
          metadata[key] = value;
        }
      });

      switch (geometryType) {
        case GeometryType.point:
          List<LatLng>? points = feature['points'] as List<LatLng>?;
          
          if ((points == null || points.isEmpty) && feature['geom'] != null) {
            final geom = feature['geom'];
            Uint8List? wkbData;
            if (geom is Uint8List) {
              wkbData = geom;
            } else if (geom is List<int>) {
              wkbData = Uint8List.fromList(geom);
            }
            if (wkbData != null) {
              final point = parseWkbPoint(wkbData);
              if (point != null) {
                points = [point];
              }
            }
          }
          
          if (points != null && points.isNotEmpty) {
            final point = points.first;
            geometry = {
              'type': 'Point',
              'coordinates': [point.longitude, point.latitude],
            };
          }
          break;

        case GeometryType.linestring:
          List<List<LatLng>>? lines = feature['lines'] as List<List<LatLng>>?;
          
          if ((lines == null || lines.isEmpty) && feature['geom'] != null) {
            final geom = feature['geom'];
            Uint8List? wkbData;
            if (geom is Uint8List) {
              wkbData = geom;
            } else if (geom is List<int>) {
              wkbData = Uint8List.fromList(geom);
            }
            if (wkbData != null) {
              final linePoints = parseWkbLineString(wkbData);
              if (linePoints.isNotEmpty) {
                lines = [linePoints];
              }
            }
          }
          
          if (lines != null && lines.isNotEmpty) {
            final linePoints = lines.first;
            final coordinates = linePoints
                .map((point) => [point.longitude, point.latitude])
                .toList();
            geometry = {'type': 'LineString', 'coordinates': coordinates};
          }
          break;

        case GeometryType.polygon:
          List<List<LatLng>>? polygons = feature['polygons'] as List<List<LatLng>>?;
          
          if ((polygons == null || polygons.isEmpty) && feature['geom'] != null) {
            final geom = feature['geom'];
            Uint8List? wkbData;
            if (geom is Uint8List) {
              wkbData = geom;
            } else if (geom is List<int>) {
              wkbData = Uint8List.fromList(geom);
            }
            if (wkbData != null) {
              polygons = parseWkbPolygon(wkbData);
            }
          }
          
          if (polygons != null && polygons.isNotEmpty) {
            final allRings = <List<List<double>>>[];

            for (final ring in polygons) {
              final ringCoordinates = ring
                  .map((point) => [point.longitude, point.latitude])
                  .toList();

              // ポリゴンを閉じる
              if (ringCoordinates.isNotEmpty) {
                final firstPoint = ringCoordinates.first;
                final lastPoint = ringCoordinates.last;
                if (firstPoint[0] != lastPoint[0] || firstPoint[1] != lastPoint[1]) {
                  ringCoordinates.add(firstPoint);
                }
              }

              allRings.add(ringCoordinates);
            }

            geometry = {'type': 'Polygon', 'coordinates': allRings};
          }
          break;

        default:
          continue;
      }

      if (geometry != null) {
        geoJsonFeatures.add({
          'id': feature['id'],
          'geometry': geometry,
          'metadata': metadata,
        });
      }
    }

    return geoJsonFeatures;
  }

  /// Point Shapefileを書き込み
  Future<void> _writePointShapefile(
    List<Map<String, dynamic>> features,
    String basePath,
  ) async {
    final bbox = BoundingBox();
    final validFeatures = features.where((f) {
      final geometry = f['geometry'] as Map<String, dynamic>?;
      return geometry != null && geometry['type'] == 'Point';
    }).toList();

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      if (coordinates.length >= 2) {
        bbox.extend(
          (coordinates[0] as num).toDouble(),
          (coordinates[1] as num).toDouble(),
        );
      }
    }
    bbox.ensureValid();

    // SHP
    await _writePointShpFile(validFeatures, bbox, '$basePath.shp');
    
    // SHX
    await _writePointShxFile(validFeatures, bbox, '$basePath.shx');
    
    // DBF
    await _writeDbfFile(validFeatures, '$basePath.dbf');
    
    // PRJ
    await _writePrjFile('$basePath.prj');
  }

  /// LineString Shapefileを書き込み
  Future<void> _writeLineShapefile(
    List<Map<String, dynamic>> features,
    String basePath,
  ) async {
    final bbox = BoundingBox();
    final validFeatures = features.where((f) {
      final geometry = f['geometry'] as Map<String, dynamic>?;
      return geometry != null && geometry['type'] == 'LineString';
    }).toList();

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          bbox.extend(
            (coord[0] as num).toDouble(),
            (coord[1] as num).toDouble(),
          );
        }
      }
    }
    bbox.ensureValid();

    await _writeLineShpFile(validFeatures, bbox, '$basePath.shp');
    await _writeLineShxFile(validFeatures, bbox, '$basePath.shx');
    await _writeDbfFile(validFeatures, '$basePath.dbf');
    await _writePrjFile('$basePath.prj');
  }

  /// Polygon Shapefileを書き込み
  Future<void> _writePolygonShapefile(
    List<Map<String, dynamic>> features,
    String basePath,
  ) async {
    final bbox = BoundingBox();
    final validFeatures = features.where((f) {
      final geometry = f['geometry'] as Map<String, dynamic>?;
      return geometry != null && geometry['type'] == 'Polygon';
    }).toList();

    for (final feature in validFeatures) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      for (final ring in coordinates) {
        if (ring is List) {
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              bbox.extend(
                (coord[0] as num).toDouble(),
                (coord[1] as num).toDouble(),
              );
            }
          }
        }
      }
    }
    bbox.ensureValid();

    await _writePolygonShpFile(validFeatures, bbox, '$basePath.shp');
    await _writePolygonShxFile(validFeatures, bbox, '$basePath.shx');
    await _writeDbfFile(validFeatures, '$basePath.dbf');
    await _writePrjFile('$basePath.prj');
  }

  /// Point SHPファイルを書き込み
  Future<void> _writePointShpFile(
    List<Map<String, dynamic>> features,
    BoundingBox bbox,
    String path,
  ) async {
    final bytes = <int>[];
    final fileLengthInWords = 50 + (features.length * 14);

    // ヘッダー
    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(fileLengthInWords));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1)); // Point

    bytes.addAll(BinaryUtils.writeFloat64(bbox.minX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.minY));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0)); // Zmin
    bytes.addAll(BinaryUtils.writeFloat64(0.0)); // Zmax
    bytes.addAll(BinaryUtils.writeFloat64(0.0)); // Mmin
    bytes.addAll(BinaryUtils.writeFloat64(0.0)); // Mmax

    // レコード
    for (int i = 0; i < features.length; i++) {
      final geometry = features[i]['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(10));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));
      bytes.addAll(BinaryUtils.writeFloat64((coordinates[0] as num).toDouble()));
      bytes.addAll(BinaryUtils.writeFloat64((coordinates[1] as num).toDouble()));
    }

    await File(path).writeAsBytes(bytes);
  }

  /// Point SHXファイルを書き込み
  Future<void> _writePointShxFile(
    List<Map<String, dynamic>> features,
    BoundingBox bbox,
    String path,
  ) async {
    final bytes = <int>[];
    final fileLengthInWords = 50 + (features.length * 4);

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(fileLengthInWords));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1));

    bytes.addAll(BinaryUtils.writeFloat64(bbox.minX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.minY));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxY));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));
    bytes.addAll(BinaryUtils.writeFloat64(0.0));

    int offset = 50;
    for (int i = 0; i < features.length; i++) {
      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(10));
      offset += 14;
    }

    await File(path).writeAsBytes(bytes);
  }

  /// Line SHPファイルを書き込み
  Future<void> _writeLineShpFile(
    List<Map<String, dynamic>> features,
    BoundingBox bbox,
    String path,
  ) async {
    final bytes = <int>[];
    
    // ファイル長を計算
    int totalFileLength = 50;
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final contentSize = 4 + 32 + 4 + 4 + 4 + (16 * coordinates.length);
      totalFileLength += 4 + ((contentSize + 1) ~/ 2);
    }

    // ヘッダー
    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(totalFileLength));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(3)); // PolyLine

    bytes.addAll(BinaryUtils.writeFloat64(bbox.minX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.minY));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxY));
    bytes.addAll(List.filled(32, 0)); // Z and M

    // レコード
    for (int i = 0; i < features.length; i++) {
      final geometry = features[i]['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      final lineBbox = BoundingBox();
      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          lineBbox.extend(
            (coord[0] as num).toDouble(),
            (coord[1] as num).toDouble(),
          );
        }
      }
      lineBbox.ensureValid();

      final contentSize = 4 + 32 + 4 + 4 + 4 + (16 * coordinates.length);
      final contentLength = (contentSize + 1) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(contentLength));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(3));
      
      bytes.addAll(BinaryUtils.writeFloat64(lineBbox.minX));
      bytes.addAll(BinaryUtils.writeFloat64(lineBbox.minY));
      bytes.addAll(BinaryUtils.writeFloat64(lineBbox.maxX));
      bytes.addAll(BinaryUtils.writeFloat64(lineBbox.maxY));
      
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(1)); // 1 part
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(coordinates.length));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(0)); // Part start index

      for (final coord in coordinates) {
        if (coord is List && coord.length >= 2) {
          bytes.addAll(BinaryUtils.writeFloat64((coord[0] as num).toDouble()));
          bytes.addAll(BinaryUtils.writeFloat64((coord[1] as num).toDouble()));
        }
      }
    }

    await File(path).writeAsBytes(bytes);
  }

  /// Line SHXファイルを書き込み
  Future<void> _writeLineShxFile(
    List<Map<String, dynamic>> features,
    BoundingBox bbox,
    String path,
  ) async {
    final bytes = <int>[];
    final fileLengthInWords = 50 + (features.length * 4);

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(fileLengthInWords));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(3));

    bytes.addAll(BinaryUtils.writeFloat64(bbox.minX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.minY));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxY));
    bytes.addAll(List.filled(32, 0));

    int offset = 50;
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      final contentSize = 4 + 32 + 4 + 4 + 4 + (16 * coordinates.length);
      final contentLength = (contentSize + 1) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(contentLength));
      offset += 4 + contentLength;
    }

    await File(path).writeAsBytes(bytes);
  }

  /// Polygon SHPファイルを書き込み
  Future<void> _writePolygonShpFile(
    List<Map<String, dynamic>> features,
    BoundingBox bbox,
    String path,
  ) async {
    final bytes = <int>[];
    
    // ファイル長を計算
    int totalFileLength = 50;
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) totalPoints += ring.length;
      }
      final contentSize = 4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      totalFileLength += 4 + ((contentSize + 1) ~/ 2);
    }

    // ヘッダー
    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(totalFileLength));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(5)); // Polygon

    bytes.addAll(BinaryUtils.writeFloat64(bbox.minX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.minY));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxY));
    bytes.addAll(List.filled(32, 0));

    // レコード
    for (int i = 0; i < features.length; i++) {
      final geometry = features[i]['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;

      int totalPoints = 0;
      final polyBbox = BoundingBox();
      for (final ring in coordinates) {
        if (ring is List) {
          totalPoints += ring.length;
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              polyBbox.extend(
                (coord[0] as num).toDouble(),
                (coord[1] as num).toDouble(),
              );
            }
          }
        }
      }
      polyBbox.ensureValid();

      final contentSize = 4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final contentLength = (contentSize + 1) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(i + 1));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(contentLength));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(5));
      
      bytes.addAll(BinaryUtils.writeFloat64(polyBbox.minX));
      bytes.addAll(BinaryUtils.writeFloat64(polyBbox.minY));
      bytes.addAll(BinaryUtils.writeFloat64(polyBbox.maxX));
      bytes.addAll(BinaryUtils.writeFloat64(polyBbox.maxY));
      
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(coordinates.length));
      bytes.addAll(BinaryUtils.writeInt32LittleEndian(totalPoints));

      // Parts配列
      int pointIndex = 0;
      for (int j = 0; j < coordinates.length; j++) {
        bytes.addAll(BinaryUtils.writeInt32LittleEndian(pointIndex));
        final ring = coordinates[j] as List;
        pointIndex += ring.length;
      }

      // Points配列
      for (final ring in coordinates) {
        if (ring is List) {
          for (final coord in ring) {
            if (coord is List && coord.length >= 2) {
              bytes.addAll(BinaryUtils.writeFloat64((coord[0] as num).toDouble()));
              bytes.addAll(BinaryUtils.writeFloat64((coord[1] as num).toDouble()));
            }
          }
        }
      }
    }

    await File(path).writeAsBytes(bytes);
  }

  /// Polygon SHXファイルを書き込み
  Future<void> _writePolygonShxFile(
    List<Map<String, dynamic>> features,
    BoundingBox bbox,
    String path,
  ) async {
    final bytes = <int>[];
    final fileLengthInWords = 50 + (features.length * 4);

    bytes.addAll(BinaryUtils.writeInt32BigEndian(9994));
    bytes.addAll(List.filled(20, 0));
    bytes.addAll(BinaryUtils.writeInt32BigEndian(fileLengthInWords));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(1000));
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(5));

    bytes.addAll(BinaryUtils.writeFloat64(bbox.minX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.minY));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxX));
    bytes.addAll(BinaryUtils.writeFloat64(bbox.maxY));
    bytes.addAll(List.filled(32, 0));

    int offset = 50;
    for (final feature in features) {
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final coordinates = geometry['coordinates'] as List;
      int totalPoints = 0;
      for (final ring in coordinates) {
        if (ring is List) totalPoints += ring.length;
      }
      final contentSize = 4 + 32 + 4 + 4 + (4 * coordinates.length) + (16 * totalPoints);
      final contentLength = (contentSize + 1) ~/ 2;

      bytes.addAll(BinaryUtils.writeInt32BigEndian(offset));
      bytes.addAll(BinaryUtils.writeInt32BigEndian(contentLength));
      offset += 4 + contentLength;
    }

    await File(path).writeAsBytes(bytes);
  }

  /// DBFファイルを書き込み
  Future<void> _writeDbfFile(
    List<Map<String, dynamic>> features,
    String path,
  ) async {
    if (features.isEmpty) {
      await File(path).writeAsBytes([0x03, ...List.filled(31, 0)]);
      return;
    }

    // フィールド定義を収集
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

      String fieldName = entry.key.length > 10 ? entry.key.substring(0, 10) : entry.key;

      if (!fields.any((f) => f['name'] == fieldName.toUpperCase())) {
        fields.add({
          'name': fieldName.toUpperCase(),
          'type': fieldType,
          'length': fieldLength,
          'decimal': fieldDecimal,
        });
      }
    }

    final recordLength = fields.fold<int>(1, (sum, field) => sum + (field['length'] as int));
    final headerLength = 32 + fields.length * 32 + 1;

    final bytes = <int>[];

    // ヘッダー
    bytes.add(0x03);
    bytes.add(DateTime.now().year - 1900);
    bytes.add(DateTime.now().month);
    bytes.add(DateTime.now().day);
    bytes.addAll(BinaryUtils.writeInt32LittleEndian(features.length));
    bytes.addAll(BinaryUtils.writeInt16LittleEndian(headerLength));
    bytes.addAll(BinaryUtils.writeInt16LittleEndian(recordLength));
    bytes.addAll(List.filled(20, 0));

    // フィールド記述子
    for (final field in fields) {
      final nameBytes = BinaryUtils.encodeToShiftJis(field['name'] as String, 11);
      bytes.addAll(nameBytes);
      bytes.add((field['type'] as String).codeUnitAt(0));
      bytes.addAll(List.filled(4, 0));
      bytes.add(field['length'] as int);
      bytes.add(field['decimal'] as int);
      bytes.addAll(List.filled(14, 0));
    }

    bytes.add(0x0D);

    // レコード
    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      bytes.add(0x20);

      for (final field in fields) {
        final fieldName = field['name'] as String;
        final fieldLength = field['length'] as int;

        final metaValue = metadata.entries
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

        final valueBytes = BinaryUtils.encodeToShiftJis(value, fieldLength, padWithSpace: true);
        bytes.addAll(valueBytes);
      }
    }

    bytes.add(0x1A);

    await File(path).writeAsBytes(bytes);

    // CPGファイル
    final cpgPath = path.replaceAll('.dbf', '.cpg');
    await File(cpgPath).writeAsString('CP932');
  }

  /// PRJファイルを書き込み
  Future<void> _writePrjFile(String path) async {
    const wgs84Wkt =
        'GEOGCS["GCS_WGS_1984",DATUM["D_WGS_1984",'
        'SPHEROID["WGS_1984",6378137.0,298.257223563]],'
        'PRIMEM["Greenwich",0.0],UNIT["Degree",0.0174532925199433]]';
    await File(path).writeAsString(wgs84Wkt);
  }

  /// 拡張子なしのベースパスを取得
  String _getBasePathWithoutExtension(String outputPath) {
    final lastDotIndex = outputPath.lastIndexOf('.');
    final lastSeparatorIndex = [
      outputPath.lastIndexOf('/'),
      outputPath.lastIndexOf('\\'),
    ].reduce((a, b) => a > b ? a : b);

    if (lastDotIndex == -1 || lastDotIndex < lastSeparatorIndex) {
      return outputPath;
    }

    return outputPath.substring(0, lastDotIndex);
  }
}

