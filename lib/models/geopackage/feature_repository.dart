import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../../utils/app_logger.dart';
import '../../utils/wkb_utils.dart';
import '../geometry_type.dart';
import 'geopackage_connection.dart';
import 'geopackage_schema.dart';
import 'spatial_index_manager.dart';

/// compute()用パラメータ
class _GeometryParseParams {
  final List<Map<String, dynamic>> rows;
  final GeometryType geomType;
  _GeometryParseParams(this.rows, this.geomType);
}

/// WKBパース＋メタデータパースを別Isolateで実行するトップレベル関数
List<Map<String, dynamic>> _parseGeometryBatchInIsolate(
  _GeometryParseParams params,
) {
  for (final row in params.rows) {
    final geom = row['geom'] as Uint8List?;

    if (geom != null) {
      switch (params.geomType) {
        case GeometryType.point:
          final point = parseWkbPoint(geom);
          if (point != null) {
            row['geometry'] = [point];
          }
        case GeometryType.linestring:
          final lines = parseWkbLineString(geom);
          if (lines.isNotEmpty) row['geometry'] = lines;
        case GeometryType.polygon:
          final polygons = parseWkbPolygon(geom);
          if (polygons.isNotEmpty) row['geometry'] = polygons;
      }
    }

    final metadataStr = row['kmaps_metadata'] as String?;
    if (metadataStr != null && metadataStr.isNotEmpty) {
      try {
        row['kmaps_metadata'] =
            jsonDecode(metadataStr) as Map<String, dynamic>;
      } catch (_) {}
    }
  }
  return params.rows;
}

/// Isolate化する閾値（これ以上のフィーチャ数でcompute()を使用）
const _kIsolateThreshold = 500;

/// フィーチャのCRUD操作を管理するリポジトリクラス
class FeatureRepository {
  final GeoPackageConnection connection;
  final GeoPackageSchema schema;
  final SpatialIndexManager spatialIndex;

  FeatureRepository(this.connection, this.schema, this.spatialIndex);

  // ============================================================
  // エンベロープ計算（共通）
  // ============================================================

  /// 座標リストからエンベロープ(minX, minY, maxX, maxY)を計算
  ({double minX, double minY, double maxX, double maxY})? _calculateEnvelope(
    List<LatLng> coordinates,
  ) {
    if (coordinates.isEmpty) return null;
    double minX = coordinates.first.longitude;
    double maxX = minX;
    double minY = coordinates.first.latitude;
    double maxY = minY;
    for (final pt in coordinates) {
      if (pt.longitude < minX) minX = pt.longitude;
      if (pt.longitude > maxX) maxX = pt.longitude;
      if (pt.latitude < minY) minY = pt.latitude;
      if (pt.latitude > maxY) maxY = pt.latitude;
    }
    return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// ポリゴンの全リングからエンベロープを計算
  ({double minX, double minY, double maxX, double maxY})?
      _calculatePolygonEnvelope(List<List<LatLng>> rings) {
    final allPoints = rings.expand((ring) => ring).toList();
    return _calculateEnvelope(allPoints);
  }

  /// エンベロープをDB（空間インデックス）に反映
  Future<void> _updateSpatialIndex(
    String tableName,
    int rowId,
    ({double minX, double minY, double maxX, double maxY}) envelope,
  ) async {
    await spatialIndex.updateLayerEnvelope(
      tableName,
      envelope.minX,
      envelope.minY,
      envelope.maxX,
      envelope.maxY,
    );
    await spatialIndex.updateRTreeIndex(
      tableName,
      rowId,
      envelope.minX,
      envelope.minY,
      envelope.maxX,
      envelope.maxY,
    );
  }

  // ============================================================
  // 属性ビルダー（共通）
  // ============================================================

  /// テーブルに存在するカラムのみを含む属性マップを構築
  Future<Map<String, dynamic>> _buildSafeAttributes(
    String tableName, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    final db = await connection.getDatabase();
    final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
    final columnNames = columns.map((row) => row['name'] as String).toSet();

    final attributes = <String, dynamic>{};
    if (columnNames.contains('name')) attributes['name'] = name;
    if (columnNames.contains('description')) {
      attributes['description'] = description;
    }
    if (columnNames.contains('kmaps_metadata') && metadata != null) {
      attributes['kmaps_metadata'] = jsonEncode(metadata);
    }
    return attributes;
  }

  /// ジオメトリ＋属性のUPDATE SQLを構築・実行する共通処理
  Future<bool> _updateFeatureGeometry(
    String tableName,
    int id,
    Uint8List wkb, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await connection.getDatabase();
      final attributes = await _buildSafeAttributes(
        tableName,
        name: name,
        description: description,
        metadata: metadata,
      );

      final updateColumns = <String>['geom = ?'];
      final updateValues = <dynamic>[wkb];

      for (final entry in attributes.entries) {
        updateColumns.add('"${entry.key}" = ?');
        updateValues.add(entry.value);
      }

      updateValues.add(id);
      final whereClause = await schema.buildWhereClause(tableName);
      final sql =
          'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);
      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] _updateFeatureGeometry: エラー発生 - $e',
      );
      return false;
    }
  }

  // ============================================================
  // WKBバリデーション（共通）
  // ============================================================

  void _validateAndLogWkb(Uint8List wkb, String context) {
    if (!validateWkbData(wkb)) {
      AppLogger.debug('[FeatureRepository] 警告: 無効なWKBデータが生成されました');
      debugWkbData(wkb, context);
    }
  }

  // ============================================================
  // フィーチャ追加（WithAttributes版 - ジオメトリ型共通化）
  // ============================================================

  Future<int?> addPointWithAttributes(
    String tableName,
    LatLng point,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbPoint(point.longitude, point.latitude);
      _validateAndLogWkb(
        wkb,
        'addPointWithAttributes - ${point.latitude}, ${point.longitude}',
      );

      final data = <String, dynamic>{'geom': wkb, ...attributes};
      final rowId = await db.insert(tableName, data);

      final env = _calculateEnvelope([point]);
      if (env != null) await _updateSpatialIndex(tableName, rowId, env);

      return rowId;
    } catch (e) {
      AppLogger.debug(
        '[ERROR] FeatureRepository: addPointWithAttributes failed: $e',
      );
      return null;
    }
  }

  Future<int?> addLineWithAttributes(
    String tableName,
    List<LatLng> line,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbLineString(line);

      final data = <String, dynamic>{'geom': wkb, ...attributes};
      final rowId = await db.insert(tableName, data);

      final env = _calculateEnvelope(line);
      if (env != null) await _updateSpatialIndex(tableName, rowId, env);

      return rowId;
    } catch (e) {
      AppLogger.debug(
        '[ERROR] FeatureRepository: addLineWithAttributes failed: $e',
      );
      return null;
    }
  }

  Future<int?> addPolygonWithAttributes(
    String tableName,
    List<List<LatLng>> polygon,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbPolygon(polygon);

      final data = <String, dynamic>{'geom': wkb, ...attributes};
      final rowId = await db.insert(tableName, data);

      final env = _calculatePolygonEnvelope(polygon);
      if (env != null) await _updateSpatialIndex(tableName, rowId, env);

      return rowId;
    } catch (e) {
      AppLogger.debug(
        '[ERROR] FeatureRepository: addPolygonWithAttributes failed: $e',
      );
      return null;
    }
  }

  // ============================================================
  // フィーチャ追加（簡易版）
  // ============================================================

  Future<int?> addPoint(
    String tableName,
    LatLng pt, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final attributes = await _buildSafeAttributes(
        tableName,
        name: name,
        description: description,
        metadata: metadata,
      );
      return await addPointWithAttributes(tableName, pt, attributes);
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository: addPoint failed: $e');
      return null;
    }
  }

  Future<int?> addLine(
    String tableName,
    List<LatLng> line, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (metadata != null) attributes['kmaps_metadata'] = jsonEncode(metadata);
    return await addLineWithAttributes(tableName, line, attributes);
  }

  Future<int?> addPolygon(
    String tableName,
    List<List<LatLng>> rings, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };
    if (metadata != null) attributes['kmaps_metadata'] = jsonEncode(metadata);
    return await addPolygonWithAttributes(tableName, rings, attributes);
  }

  // ============================================================
  // フィーチャ更新（共通メソッドに統一）
  // ============================================================

  Future<bool> updatePoint(
    String tableName,
    int id,
    LatLng pt, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    final wkb = createWkbPoint(pt.longitude, pt.latitude);
    _validateAndLogWkb(wkb, 'updatePoint - ${pt.latitude}, ${pt.longitude}');
    return _updateFeatureGeometry(
      tableName,
      id,
      wkb,
      name: name,
      description: description,
      metadata: metadata,
    );
  }

  Future<bool> updateLine(
    String tableName,
    int id,
    List<LatLng> line, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    final wkb = createWkbLineString(line);
    return _updateFeatureGeometry(
      tableName,
      id,
      wkb,
      name: name,
      description: description,
      metadata: metadata,
    );
  }

  Future<bool> updatePolygon(
    String tableName,
    int id,
    List<List<LatLng>> rings, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    final wkb = createWkbPolygon(rings);
    return _updateFeatureGeometry(
      tableName,
      id,
      wkb,
      name: name,
      description: description,
      metadata: metadata,
    );
  }

  // ============================================================
  // 共通 Feature 操作
  // ============================================================

  Future<void> removeFeature(String tableName, int id) async {
    try {
      final db = await connection.getDatabase();
      final whereClause = await schema.buildWhereClause(tableName);
      await db.delete(tableName, where: whereClause, whereArgs: [id]);
      await spatialIndex.removeFromRTreeIndex(tableName, id);
    } catch (e) {
      AppLogger.debug('[FeatureRepository] removeFeature: エラー発生 - $e');
    }
  }

  Future<Map<String, dynamic>?> getFeature(
    String tableName,
    int rowId,
    GeometryType? geomType,
  ) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      final selectClause = pkColumn == 'rowid'
          ? 'SELECT rowid, * FROM "$tableName" WHERE rowid = ?'
          : 'SELECT * FROM "$tableName" WHERE "$pkColumn" = ?';

      final rows = await db.rawQuery(selectClause, [rowId]);
      if (rows.isEmpty) return null;

      final row = Map<String, dynamic>.from(rows.first);
      _normalizePrimaryKey(row, pkColumn);

      final geom = row['geom'] as Uint8List?;
      if (geom != null && geomType != null) {
        _parseGeometry(row, geom, geomType, rowId);
      }

      _parseMetadata(row);
      return row;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getFeature: エラー発生 - $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getFeatures(String tableName) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      final selectClause = pkColumn == 'rowid'
          ? 'SELECT rowid, * FROM "$tableName"'
          : 'SELECT * FROM "$tableName"';

      final rows = await db.rawQuery(selectClause);
      return rows.map((row) {
        final normalizedRow = Map<String, dynamic>.from(row);
        _normalizePrimaryKey(normalizedRow, pkColumn);
        return normalizedRow;
      }).toList();
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getFeatures: エラー発生 - $e');
      return [];
    }
  }

  /// 全フィーチャをジオメトリパース済みで一括取得（N+1クエリ解消版）
  /// getFeatures + getFeature のN+1パターンを1クエリに統合
  /// フィーチャ数が閾値を超える場合、WKBパースを別Isolateで実行
  Future<List<Map<String, dynamic>>> getFeaturesWithGeometry(
    String tableName,
    GeometryType? geomType,
  ) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      final selectClause = pkColumn == 'rowid'
          ? 'SELECT rowid, * FROM "$tableName"'
          : 'SELECT * FROM "$tableName"';

      final rows = await db.rawQuery(selectClause);

      // PK正規化（Isolateに渡す前にMutable Mapに変換）
      final mutableRows = <Map<String, dynamic>>[];
      for (final row in rows) {
        final normalizedRow = Map<String, dynamic>.from(row);
        _normalizePrimaryKey(normalizedRow, pkColumn);
        if (normalizedRow['id'] == null) continue;
        mutableRows.add(normalizedRow);
      }

      if (geomType == null) return mutableRows;

      // 閾値以上なら別Isolateでジオメトリ＋メタデータパース
      if (mutableRows.length >= _kIsolateThreshold) {
        AppLogger.debug(
          '[FeatureRepository] Isolateパース: $tableName (${mutableRows.length}件)',
        );
        return await compute(
          _parseGeometryBatchInIsolate,
          _GeometryParseParams(mutableRows, geomType),
        );
      }

      // 閾値未満はメインスレッドでパース
      for (final row in mutableRows) {
        final geom = row['geom'] as Uint8List?;
        final rowId = row['id'] as int? ?? 0;
        if (geom != null) {
          _parseGeometry(row, geom, geomType, rowId);
        }
        _parseMetadata(row);
      }

      return mutableRows;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] getFeaturesWithGeometry: エラー発生 - $e',
      );
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getAllFeatureAttributes(
    String tableName, {
    List<String>? columns,
  }) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      final columnList = columns?.join(', ') ?? '*';
      final orderByClause = pkColumn == 'rowid'
          ? 'ORDER BY rowid'
          : 'ORDER BY "$pkColumn"';

      return await db.rawQuery(
        'SELECT $columnList FROM "$tableName" $orderByClause',
      );
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] getAllFeatureAttributes エラー発生 - $e',
      );
      return [];
    }
  }

  // ============================================================
  // 属性操作
  // ============================================================

  Future<dynamic> getFeatureAttribute(
    String tableName,
    int rowId,
    String attributeName,
  ) async {
    try {
      final db = await connection.getDatabase();
      final whereClause = await schema.buildWhereClause(tableName);
      final result = await db.query(
        tableName,
        where: whereClause,
        whereArgs: [rowId],
      );
      return result.isNotEmpty ? result.first[attributeName] : null;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] getFeatureAttribute: エラー発生 - $e',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>?> getFeatureAttributes(
    String tableName,
    int rowId,
  ) async {
    try {
      final db = await connection.getDatabase();
      final whereClause = await schema.buildWhereClause(tableName);
      final result = await db.query(
        tableName,
        where: whereClause,
        whereArgs: [rowId],
      );
      return result.isNotEmpty
          ? Map<String, dynamic>.from(result.first)
          : null;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] getFeatureAttributes: エラー発生 - $e',
      );
      return null;
    }
  }

  Future<bool> updateFeatureAttribute(
    String tableName,
    int rowId,
    String attributeName,
    dynamic newValue,
  ) async {
    try {
      final db = await connection.getDatabase();
      final whereClause = await schema.buildWhereClause(tableName);
      final rowsUpdated = await db.rawUpdate(
        'UPDATE "$tableName" SET "$attributeName" = ? WHERE $whereClause',
        [newValue, rowId],
      );
      return rowsUpdated > 0;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] updateFeatureAttribute: エラー発生 - $e',
      );
      return false;
    }
  }

  Future<bool> updateFeatureAttributes(
    String tableName,
    int rowId,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);
      final existingColumns =
          (await schema.getColumnNames(tableName, getAll: true)).toSet();

      final filteredAttributes = <String, dynamic>{};
      for (final entry in attributes.entries) {
        final key = entry.key;
        final value = entry.value;

        if (_isReservedColumn(key, pkColumn)) continue;
        if (!existingColumns.contains(key)) {
          AppLogger.debug(
            '[FeatureRepository] カラム未存在のためスキップ: $key',
          );
          continue;
        }
        if (_isSupportedType(value)) {
          filteredAttributes[key] = value;
        } else {
          AppLogger.debug(
            '[FeatureRepository] サポートされていない型: $key = ${value.runtimeType}',
          );
        }
      }

      if (filteredAttributes.isEmpty) return true;

      final columnAssignments =
          filteredAttributes.keys.map((key) => '"$key" = ?').join(', ');
      final values = [...filteredAttributes.values, rowId];
      final whereClause = await schema.buildWhereClause(tableName);
      final sql =
          'UPDATE "$tableName" SET $columnAssignments WHERE $whereClause';
      final rowsUpdated = await db.rawUpdate(sql, values);
      return rowsUpdated > 0;
    } catch (e) {
      AppLogger.debug(
        '[ERROR] FeatureRepository: updateFeatureAttributes failed: $e',
      );
      return false;
    }
  }

  // ============================================================
  // バッチ操作
  // ============================================================

  Future<List<int>> _addGeometryBatch<T>(
    String tableName,
    List<Map<String, dynamic>> dataList,
    String geometryKey,
    Uint8List Function(T) createWkb,
  ) async {
    final reservedColumns = {
      'fid',
      'geom',
      'id',
      'rowid',
      'geometry',
      geometryKey,
    };

    try {
      final db = await connection.getDatabase();
      final batch = db.batch();
      final insertedIds = <int>[];

      final tableColumns = await schema.getTableColumns(tableName);
      final tableColumnSet = tableColumns.map((c) => c.toLowerCase()).toSet();

      for (final data in dataList) {
        final geometry = data[geometryKey] as T;
        final wkb = createWkb(geometry);
        final insertData = <String, dynamic>{'geom': wkb};

        data.forEach((key, value) {
          if (!reservedColumns.contains(key.toLowerCase())) {
            final sanitizedKey = schema.sanitizeColumnName(key);
            if (sanitizedKey.isNotEmpty &&
                tableColumnSet.contains(sanitizedKey.toLowerCase())) {
              insertData[sanitizedKey] = value;
            }
          }
        });

        final columns = insertData.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        final columnNames = columns.map((c) => '"$c"').join(', ');
        final values = columns.map((c) => insertData[c]).toList();

        batch.rawInsert(
          'INSERT INTO "$tableName" ($columnNames) VALUES ($placeholders)',
          values,
        );
      }

      final results = await batch.commit(noResult: false);
      for (final result in results) {
        if (result is int) insertedIds.add(result);
      }
      return insertedIds;
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository._addGeometryBatch<$T>: $e');
      return [];
    }
  }

  Future<List<int>> addPointsBatch(
    String tableName,
    List<Map<String, dynamic>> pointData,
  ) =>
      _addGeometryBatch<LatLng>(
        tableName,
        pointData,
        'point',
        (point) => createWkbPoint(point.longitude, point.latitude),
      );

  Future<List<int>> addLinesBatch(
    String tableName,
    List<Map<String, dynamic>> lineData,
  ) =>
      _addGeometryBatch<List<LatLng>>(
        tableName,
        lineData,
        'line',
        createWkbLineString,
      );

  Future<List<int>> addPolygonsBatch(
    String tableName,
    List<Map<String, dynamic>> polygonData,
  ) =>
      _addGeometryBatch<List<List<LatLng>>>(
        tableName,
        polygonData,
        'rings',
        createWkbPolygon,
      );

  /// WHERE句でフィルタしたフィーチャのrowIdリストを取得
  Future<List<int>> getFilteredFeatureIds(
    String tableName,
    String whereClause,
  ) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      final selectClause = pkColumn == 'rowid'
          ? 'SELECT rowid FROM "$tableName" WHERE $whereClause'
          : 'SELECT "$pkColumn" FROM "$tableName" WHERE $whereClause';

      final rows = await db.rawQuery(selectClause);
      return rows.map((row) {
        final val = row.values.first;
        return val is int ? val : 0;
      }).where((id) => id != 0).toList();
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] getFilteredFeatureIds: エラー発生 - $e',
      );
      return [];
    }
  }

  /// WHERE句にマッチするフィーチャ数を取得（プレビュー用）
  Future<int> countFilteredFeatures(
    String tableName,
    String whereClause,
  ) async {
    try {
      final db = await connection.getDatabase();
      final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM "$tableName" WHERE $whereClause',
      );
      return (result.first['cnt'] as int?) ?? 0;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] countFilteredFeatures: エラー発生 - $e',
      );
      return -1;
    }
  }

  /// WHERE句でフィルタしたフィーチャを別レイヤに複製
  Future<int> duplicateFilteredFeatures(
    String sourceTable,
    String targetTable,
    String whereClause,
  ) async {
    try {
      final db = await connection.getDatabase();
      final sourceColumns = await schema.getTableColumns(sourceTable);
      final columnsToInsert = sourceColumns
          .where((c) => c.toLowerCase() != 'id' && c.toLowerCase() != 'fid')
          .toList();

      if (columnsToInsert.isEmpty) return 0;

      final columnList = columnsToInsert.map((c) => '"$c"').join(', ');
      await db.execute('''
        INSERT INTO "$targetTable" ($columnList)
        SELECT $columnList FROM "$sourceTable"
        WHERE $whereClause
      ''');

      final countResult = await db.rawQuery('SELECT changes() as count');
      final copiedCount = (countResult.first['count'] as int?) ?? 0;
      AppLogger.debug(
        '[FeatureRepository] duplicateFilteredFeatures: '
        '$sourceTable -> $targetTable ($copiedCount件, WHERE: $whereClause)',
      );
      return copiedCount;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] duplicateFilteredFeatures エラー: $e',
      );
      return 0;
    }
  }

  Future<int> copyFeaturesBetweenLayers(
    String sourceTable,
    String targetTable,
  ) async {
    try {
      final db = await connection.getDatabase();
      final sourceColumns = await schema.getTableColumns(sourceTable);
      final columnsToInsert = sourceColumns
          .where((c) => c.toLowerCase() != 'id' && c.toLowerCase() != 'fid')
          .toList();

      if (columnsToInsert.isEmpty) {
        AppLogger.debug('[FeatureRepository] コピー可能なカラムがありません');
        return 0;
      }

      final columnList = columnsToInsert.map((c) => '"$c"').join(', ');
      await db.execute('''
        INSERT INTO "$targetTable" ($columnList)
        SELECT $columnList FROM "$sourceTable"
      ''');

      final countResult = await db.rawQuery('SELECT changes() as count');
      final copiedCount = (countResult.first['count'] as int?) ?? 0;
      AppLogger.debug(
        '[FeatureRepository] フィーチャコピー完了: $sourceTable -> $targetTable ($copiedCount件)',
      );
      return copiedCount;
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] copyFeaturesBetweenLayers エラー: $e',
      );
      return 0;
    }
  }

  Future<int?> addFeatureWithAttributes(
    String tableName,
    Uint8List geometry,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final data = <String, dynamic>{'geom': geometry, ...attributes};
      return await db.insert(tableName, data);
    } catch (e) {
      AppLogger.debug(
        '[FeatureRepository] addFeatureWithAttributes エラー発生 - $e',
      );
      return null;
    }
  }

  // ============================================================
  // プライベートヘルパー
  // ============================================================

  void _normalizePrimaryKey(Map<String, dynamic> row, String pkColumn) {
    if (pkColumn != 'id') {
      if (row.containsKey(pkColumn)) {
        row['id'] = row[pkColumn];
      } else {
        AppLogger.debug(
          '[FeatureRepository] 警告: PRIMARY KEYカラム "$pkColumn" が見つかりません',
        );
        row['id'] = 0;
      }
    }
  }

  void _parseMetadata(Map<String, dynamic> row) {
    final metadataStr = row['kmaps_metadata'] as String?;
    if (metadataStr != null && metadataStr.isNotEmpty) {
      try {
        row['kmaps_metadata'] =
            jsonDecode(metadataStr) as Map<String, dynamic>;
      } catch (e) {
        AppLogger.debug(
          '[FeatureRepository] メタデータのJSONパースエラー - $e',
        );
      }
    }
  }

  bool _isReservedColumn(String key, String pkColumn) =>
      key == 'geometry' || key == 'geom' || key == pkColumn || key == 'id';

  bool _isSupportedType(dynamic value) =>
      value == null ||
      value is String ||
      value is num ||
      value is bool ||
      value is Uint8List;

  void _parseGeometry(
    Map<String, dynamic> row,
    Uint8List geom,
    GeometryType geomType,
    int rowId,
  ) {
    if (geomType == GeometryType.point) {
      Uint8List pureWkb = _stripGpbHeader(geom);
      if (pureWkb.length >= 21 && pureWkb[0] == 1 && pureWkb[1] == 1) {
        final lon =
            ByteData.sublistView(pureWkb, 5, 13).getFloat64(0, Endian.little);
        final lat =
            ByteData.sublistView(pureWkb, 13, 21).getFloat64(0, Endian.little);
        if (_isValidCoordinate(lat, lon)) {
          row['geometry'] = [LatLng(lat, lon)];
        } else {
          AppLogger.debug(
            '[FeatureRepository] 警告: 無効なPoint座標値: lat=$lat, lon=$lon (rowId=$rowId)',
          );
        }
      }
    } else if (geomType == GeometryType.linestring) {
      final lines = parseWkbLineString(geom);
      if (lines.isNotEmpty) row['geometry'] = lines;
    } else if (geomType == GeometryType.polygon) {
      final polygons = parseWkbPolygon(geom);
      if (polygons.isNotEmpty) row['geometry'] = polygons;
    }
  }

  /// GPBinaryヘッダーをスキップして純粋なWKBデータを取得
  Uint8List _stripGpbHeader(Uint8List geom) {
    if (geom.length > 8 && geom[0] == 0x47 && geom[1] == 0x50) {
      final flags = geom[3];
      final envelopeType = (flags >> 1) & 0x07;
      int headerSize = 8;
      switch (envelopeType) {
        case 1:
          headerSize += 32;
        case 2:
        case 3:
          headerSize += 48;
        case 4:
          headerSize += 64;
      }
      if (geom.length > headerSize) return geom.sublist(headerSize);
    }
    return geom;
  }

  bool _isValidCoordinate(double lat, double lon) =>
      lat >= -90.0 &&
      lat <= 90.0 &&
      lon >= -180.0 &&
      lon <= 180.0 &&
      !lat.isNaN &&
      !lon.isNaN &&
      !lat.isInfinite &&
      !lon.isInfinite;
}
