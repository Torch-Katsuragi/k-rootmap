// K-MAPS: フィーチャリポジトリクラス
// Point/Line/PolygonのCRUD操作を担当
import 'dart:typed_data';
import 'dart:convert';
import 'package:latlong2/latlong.dart';
import '../../utils/app_logger.dart';
import '../../utils/wkb_utils.dart';
import '../geometry_type.dart';
import 'geopackage_connection.dart';
import 'geopackage_schema.dart';
import 'spatial_index_manager.dart';

/// フィーチャのCRUD操作を管理するリポジトリクラス
/// 責務: Point/Line/Polygonの追加・取得・更新・削除
class FeatureRepository {
  /// DB接続への参照
  final GeoPackageConnection connection;

  /// スキーマ管理への参照
  final GeoPackageSchema schema;

  /// 空間インデックス管理への参照
  final SpatialIndexManager spatialIndex;

  /// コンストラクタ
  FeatureRepository(this.connection, this.schema, this.spatialIndex);

  // ============================================================
  // Point Feature CRUD
  // ============================================================

  /// 辞書ベースの点フィーチャ追加
  Future<int?> addPointWithAttributes(
    String tableName,
    LatLng point,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbPoint(point.longitude, point.latitude);

      // WKBデータの妥当性チェック
      if (!validateWkbData(wkb)) {
        AppLogger.debug('[FeatureRepository] 警告: 無効なWKBデータが生成されました');
        debugWkbData(wkb, 'addPointWithAttributes - ${point.latitude}, ${point.longitude}');
      }

      final data = <String, dynamic>{'geom': wkb};
      data.addAll(attributes);

      final rowId = await db.insert(tableName, data);

      // 空間インデックスを更新
      await spatialIndex.updateLayerEnvelope(
        tableName,
        point.longitude,
        point.latitude,
        point.longitude,
        point.latitude,
      );

      await spatialIndex.updateRTreeIndex(
        tableName,
        rowId,
        point.longitude,
        point.latitude,
        point.longitude,
        point.latitude,
      );

      return rowId;
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository: addPointWithAttributes failed: $e');
      return null;
    }
  }

  /// 点フィーチャを追加（属性付き）
  Future<int?> addPoint(
    String tableName,
    LatLng pt, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await connection.getDatabase();
      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      final attributes = <String, dynamic>{};

      if (columnNames.contains('name')) {
        attributes['name'] = name;
      }
      if (columnNames.contains('description')) {
        attributes['description'] = description;
      }
      if (columnNames.contains('kmaps_metadata') && metadata != null) {
        attributes['kmaps_metadata'] = jsonEncode(metadata);
      }

      return await addPointWithAttributes(tableName, pt, attributes);
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository: addPoint failed: $e');
      return null;
    }
  }

  /// 点フィーチャを更新
  Future<bool> updatePoint(
    String tableName,
    int id,
    LatLng pt, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbPoint(pt.longitude, pt.latitude);

      if (!validateWkbData(wkb)) {
        AppLogger.debug('[FeatureRepository] 警告: 無効なWKBデータが生成されました');
        debugWkbData(wkb, 'updatePoint - ${pt.latitude}, ${pt.longitude}');
      }

      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      final updateColumns = <String>[];
      final updateValues = <dynamic>[];

      updateColumns.add('geom = ?');
      updateValues.add(wkb);

      if (columnNames.contains('name')) {
        updateColumns.add('name = ?');
        updateValues.add(name);
      }
      if (columnNames.contains('description')) {
        updateColumns.add('description = ?');
        updateValues.add(description);
      }
      if (columnNames.contains('kmaps_metadata') && metadata != null) {
        updateColumns.add('kmaps_metadata = ?');
        updateValues.add(jsonEncode(metadata));
      }

      updateValues.add(id);

      final whereClause = await schema.buildWhereClause(tableName);
      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] updatePoint: エラー発生 - $e');
      return false;
    }
  }

  // ============================================================
  // Line Feature CRUD
  // ============================================================

  /// 辞書ベースの線フィーチャ追加
  Future<int?> addLineWithAttributes(
    String tableName,
    List<LatLng> line,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbLineString(line);

      final data = <String, dynamic>{'geom': wkb};
      data.addAll(attributes);

      final rowId = await db.insert(tableName, data);

      // エンベロープを計算して更新
      if (line.isNotEmpty) {
        double minX = line.first.longitude;
        double maxX = line.first.longitude;
        double minY = line.first.latitude;
        double maxY = line.first.latitude;

        for (final pt in line) {
          minX = minX < pt.longitude ? minX : pt.longitude;
          maxX = maxX > pt.longitude ? maxX : pt.longitude;
          minY = minY < pt.latitude ? minY : pt.latitude;
          maxY = maxY > pt.latitude ? maxY : pt.latitude;
        }

        await spatialIndex.updateLayerEnvelope(tableName, minX, minY, maxX, maxY);
        await spatialIndex.updateRTreeIndex(tableName, rowId, minX, minY, maxX, maxY);
      }

      return rowId;
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository: addLineWithAttributes failed: $e');
      return null;
    }
  }

  /// 線フィーチャを追加（属性付き）
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

    if (metadata != null) {
      attributes['kmaps_metadata'] = jsonEncode(metadata);
    }

    return await addLineWithAttributes(tableName, line, attributes);
  }

  /// 線フィーチャを更新
  Future<bool> updateLine(
    String tableName,
    int id,
    List<LatLng> line, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbLineString(line);

      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      final updateColumns = <String>[];
      final updateValues = <dynamic>[];

      updateColumns.add('geom = ?');
      updateValues.add(wkb);

      if (columnNames.contains('name')) {
        updateColumns.add('name = ?');
        updateValues.add(name);
      }
      if (columnNames.contains('description')) {
        updateColumns.add('description = ?');
        updateValues.add(description);
      }
      if (columnNames.contains('kmaps_metadata') && metadata != null) {
        updateColumns.add('kmaps_metadata = ?');
        updateValues.add(jsonEncode(metadata));
      }

      updateValues.add(id);

      final whereClause = await schema.buildWhereClause(tableName);
      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] updateLine: エラー発生 - $e');
      return false;
    }
  }

  // ============================================================
  // Polygon Feature CRUD
  // ============================================================

  /// 辞書ベースの面フィーチャ追加
  Future<int?> addPolygonWithAttributes(
    String tableName,
    List<List<LatLng>> polygon,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbPolygon(polygon);

      final data = <String, dynamic>{'geom': wkb};
      data.addAll(attributes);

      final rowId = await db.insert(tableName, data);

      // エンベロープを計算して更新
      if (polygon.isNotEmpty && polygon.first.isNotEmpty) {
        double minX = polygon.first.first.longitude;
        double maxX = polygon.first.first.longitude;
        double minY = polygon.first.first.latitude;
        double maxY = polygon.first.first.latitude;

        for (final ring in polygon) {
          for (final pt in ring) {
            minX = minX < pt.longitude ? minX : pt.longitude;
            maxX = maxX > pt.longitude ? maxX : pt.longitude;
            minY = minY < pt.latitude ? minY : pt.latitude;
            maxY = maxY > pt.latitude ? maxY : pt.latitude;
          }
        }

        await spatialIndex.updateLayerEnvelope(tableName, minX, minY, maxX, maxY);
        await spatialIndex.updateRTreeIndex(tableName, rowId, minX, minY, maxX, maxY);
      }

      return rowId;
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository: addPolygonWithAttributes failed: $e');
      return null;
    }
  }

  /// ポリゴンフィーチャを追加（属性付き）
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

    if (metadata != null) {
      attributes['kmaps_metadata'] = jsonEncode(metadata);
    }

    return await addPolygonWithAttributes(tableName, rings, attributes);
  }

  /// ポリゴンフィーチャを更新
  Future<bool> updatePolygon(
    String tableName,
    int id,
    List<List<LatLng>> rings, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await connection.getDatabase();
      final wkb = createWkbPolygon(rings);

      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      final updateColumns = <String>[];
      final updateValues = <dynamic>[];

      updateColumns.add('geom = ?');
      updateValues.add(wkb);

      if (columnNames.contains('name')) {
        updateColumns.add('name = ?');
        updateValues.add(name);
      }
      if (columnNames.contains('description')) {
        updateColumns.add('description = ?');
        updateValues.add(description);
      }
      if (columnNames.contains('kmaps_metadata') && metadata != null) {
        updateColumns.add('kmaps_metadata = ?');
        updateValues.add(jsonEncode(metadata));
      }

      updateValues.add(id);

      final whereClause = await schema.buildWhereClause(tableName);
      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] updatePolygon: エラー発生 - $e');
      return false;
    }
  }

  // ============================================================
  // 共通 Feature 操作
  // ============================================================

  /// 指定IDのフィーチャを削除
  Future<void> removeFeature(String tableName, int id) async {
    try {
      final db = await connection.getDatabase();
      final whereClause = await schema.buildWhereClause(tableName);

      await db.delete(tableName, where: whereClause, whereArgs: [id]);

      // R-Tree空間インデックスからも削除
      await spatialIndex.removeFromRTreeIndex(tableName, id);
    } catch (e) {
      AppLogger.debug('[FeatureRepository] removeFeature: エラー発生 - $e');
    }
  }

  /// 単一フィーチャを取得（geom列をgeometry typeに応じて変換）
  Future<Map<String, dynamic>?> getFeature(
    String tableName,
    int rowId,
    GeometryType? geomType,
  ) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      // rowidを使用する場合は明示的にSELECTに含める
      final selectClause = pkColumn == 'rowid'
          ? 'SELECT rowid, * FROM "$tableName" WHERE rowid = ?'
          : 'SELECT * FROM "$tableName" WHERE "$pkColumn" = ?';

      final rows = await db.rawQuery(selectClause, [rowId]);

      if (rows.isEmpty) return null;

      final row = Map<String, dynamic>.from(rows.first);

      // PRIMARY KEYカラムが'id'以外の場合、正規化
      if (pkColumn != 'id') {
        if (row.containsKey(pkColumn)) {
          row['id'] = row[pkColumn];
        } else {
          AppLogger.debug('[FeatureRepository] ⚠️ 警告: PRIMARY KEYカラム "$pkColumn" が見つかりません！');
          row['id'] = 0;
        }
      }

      final geom = row['geom'] as Uint8List?;

      // geom列をgeometry typeに応じて変換
      if (geom != null && geomType != null) {
        _parseGeometry(row, geom, geomType, rowId);
      }

      // kmaps_metadataをパース
      final metadataStr = row['kmaps_metadata'] as String?;
      if (metadataStr != null && metadataStr.isNotEmpty) {
        try {
          row['kmaps_metadata'] = jsonDecode(metadataStr) as Map<String, dynamic>;
        } catch (e) {
          AppLogger.debug('[FeatureRepository] getFeature: メタデータのJSONパースエラー - $e');
        }
      }

      return row;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getFeature: エラー発生 - $e');
      return null;
    }
  }

  /// ジオメトリデータを解析してrowに追加
  void _parseGeometry(
    Map<String, dynamic> row,
    Uint8List geom,
    GeometryType geomType,
    int rowId,
  ) {
    if (geomType == GeometryType.point) {
      // GPBinaryヘッダーをスキップして純粋なWKBデータを取得
      Uint8List pureWkb = geom;
      if (geom.length > 8 && geom[0] == 0x47 && geom[1] == 0x50) {
        final flags = geom[3];
        final envelopeType = (flags >> 1) & 0x07;
        int headerSize = 8;

        switch (envelopeType) {
          case 1:
            headerSize += 32;
            break;
          case 2:
          case 3:
            headerSize += 48;
            break;
          case 4:
            headerSize += 64;
            break;
        }

        if (geom.length > headerSize) {
          pureWkb = geom.sublist(headerSize);
        }
      }

      if (pureWkb.length >= 21 && pureWkb[0] == 1 && pureWkb[1] == 1) {
        final lon = ByteData.sublistView(pureWkb, 5, 13).getFloat64(0, Endian.little);
        final lat = ByteData.sublistView(pureWkb, 13, 21).getFloat64(0, Endian.little);

        if (lat >= -90.0 && lat <= 90.0 &&
            lon >= -180.0 && lon <= 180.0 &&
            !lat.isNaN && !lon.isNaN &&
            !lat.isInfinite && !lon.isInfinite) {
          row['geometry'] = [LatLng(lat, lon)];
        } else {
          AppLogger.debug('[FeatureRepository] ⚠️ 警告: 無効なPoint座標値を検出: lat=$lat, lon=$lon (rowId=$rowId)');
        }
      }
    } else if (geomType == GeometryType.linestring) {
      final lines = parseWkbLineString(geom);
      if (lines.isNotEmpty) {
        row['geometry'] = lines;
      }
    } else if (geomType == GeometryType.polygon) {
      final polygons = parseWkbPolygon(geom);
      if (polygons.isNotEmpty) {
        row['geometry'] = polygons;
      }
    }
  }

  /// 指定レイヤの全フィーチャを取得（rawデータ、内部形式に正規化）
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

        if (pkColumn != 'id') {
          if (row.containsKey(pkColumn)) {
            normalizedRow['id'] = row[pkColumn];
          } else {
            AppLogger.debug('[FeatureRepository] ⚠️ 警告: PRIMARY KEYカラム "$pkColumn" が見つかりません！');
            normalizedRow['id'] = 0;
          }
        }

        return normalizedRow;
      }).toList();
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getFeatures: エラー発生 - $e');
      return [];
    }
  }

  /// 指定レイヤーの全フィーチャの属性データを一括取得
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

      final result = await db.rawQuery(
        'SELECT $columnList FROM "$tableName" $orderByClause',
      );

      return result;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getAllFeatureAttributes エラー発生 - $e');
      return [];
    }
  }

  // ============================================================
  // 属性操作
  // ============================================================

  /// 指定テーブル・rowId・カラム名から値を取得
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
      if (result.isNotEmpty) {
        return result.first[attributeName];
      }
      return null;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getFeatureAttribute: エラー発生 - $e');
      return null;
    }
  }

  /// 指定テーブル・rowIdの全属性値を取得
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
      if (result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first);
      }
      return null;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] getFeatureAttributes: エラー発生 - $e');
      return null;
    }
  }

  /// 指定テーブル・rowId・カラム名の属性値を更新
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
      AppLogger.debug('[FeatureRepository] updateFeatureAttribute: エラー発生 - $e');
      return false;
    }
  }

  /// 複数の属性値を一括更新
  Future<bool> updateFeatureAttributes(
    String tableName,
    int rowId,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();
      final pkColumn = await schema.getPrimaryKeyColumn(tableName);

      // 実際に存在するカラム名を取得
      final existingColumns = await schema.getColumnNames(tableName, getAll: true);
      final existingColumnSet = existingColumns.toSet();

      // SQLiteでサポートされていない型と存在しないカラムを除外
      final filteredAttributes = <String, dynamic>{};
      for (final entry in attributes.entries) {
        final key = entry.key;
        final value = entry.value;

        // ジオメトリ関連フィールド、PRIMARY KEYフィールド、id（仮想カラム）は除外
        if (key == 'geometry' ||
            key == 'geom' ||
            key == pkColumn ||
            key == 'id') {
          continue;
        }

        // 存在しないカラムは除外
        if (!existingColumnSet.contains(key)) {
          AppLogger.debug(
            '[FeatureRepository] ⚠️ カラム未存在のためスキップ: $key',
          );
          continue;
        }

        if (value == null ||
            value is String ||
            value is num ||
            value is bool ||
            value is Uint8List) {
          filteredAttributes[key] = value;
        } else {
          AppLogger.debug(
            '[FeatureRepository] ⚠️ サポートされていない型: $key = ${value.runtimeType}',
          );
        }
      }

      if (filteredAttributes.isEmpty) {
        return true;
      }

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

  /// ジェネリックなバッチ追加処理
  Future<List<int>> _addGeometryBatch<T>(
    String tableName,
    List<Map<String, dynamic>> dataList,
    String geometryKey,
    Uint8List Function(T) createWkb,
  ) async {
    final reservedColumns = {'fid', 'geom', 'id', 'rowid', 'geometry', geometryKey};

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
        if (result is int) {
          insertedIds.add(result);
        }
      }

      return insertedIds;
    } catch (e) {
      AppLogger.debug('[ERROR] FeatureRepository._addGeometryBatch<$T>: $e');
      return [];
    }
  }

  /// バッチ処理でポイントを高速追加
  Future<List<int>> addPointsBatch(
    String tableName,
    List<Map<String, dynamic>> pointData,
  ) async {
    return _addGeometryBatch<LatLng>(
      tableName,
      pointData,
      'point',
      (point) => createWkbPoint(point.longitude, point.latitude),
    );
  }

  /// バッチ処理でラインを高速追加
  Future<List<int>> addLinesBatch(
    String tableName,
    List<Map<String, dynamic>> lineData,
  ) async {
    return _addGeometryBatch<List<LatLng>>(
      tableName,
      lineData,
      'line',
      (line) => createWkbLineString(line),
    );
  }

  /// バッチ処理でポリゴンを高速追加
  Future<List<int>> addPolygonsBatch(
    String tableName,
    List<Map<String, dynamic>> polygonData,
  ) async {
    return _addGeometryBatch<List<List<LatLng>>>(
      tableName,
      polygonData,
      'rings',
      (rings) => createWkbPolygon(rings),
    );
  }

  /// レイヤー間でフィーチャをコピー
  Future<int> copyFeaturesBetweenLayers(String sourceTable, String targetTable) async {
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

      final sql = '''
        INSERT INTO "$targetTable" ($columnList)
        SELECT $columnList FROM "$sourceTable"
      ''';

      await db.execute(sql);

      final countResult = await db.rawQuery('SELECT changes() as count');
      final copiedCount = (countResult.first['count'] as int?) ?? 0;

      AppLogger.debug('[FeatureRepository] フィーチャコピー完了: $sourceTable -> $targetTable ($copiedCount件)');
      return copiedCount;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] copyFeaturesBetweenLayers エラー: $e');
      return 0;
    }
  }

  /// フィーチャを完全な属性テーブルとして追加
  Future<int?> addFeatureWithAttributes(
    String tableName,
    Uint8List geometry,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await connection.getDatabase();

      final data = <String, dynamic>{'geom': geometry};
      data.addAll(attributes);

      final rowId = await db.insert(tableName, data);
      return rowId;
    } catch (e) {
      AppLogger.debug('[FeatureRepository] addFeatureWithAttributes エラー発生 - $e');
      return null;
    }
  }
}

