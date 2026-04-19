// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// GeoPackageを使用したタイルキャッシュ管理
/// OGC GeoPackage標準仕様に準拠したタイル格納
library;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:root_maps/utils/app_logger.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;

/// 保存待ちタイル
class _PendingTile {
  final String providerId;
  final int z;
  final int x;
  final int y;
  final Uint8List data;
  final int tileRow;

  _PendingTile({
    required this.providerId,
    required this.z,
    required this.x,
    required this.y,
    required this.data,
    required this.tileRow,
  });
}

/// GeoPackage タイルキャッシュデータベース
/// OGC GeoPackage Encoding Standard準拠
class TileCacheGeoPackage {
  static const String _databaseName = 'tile_cache.gpkg';
  static const String _tilesTableName = 'map_tiles';

  // SQL Definitions
  static const String _sqlPragmaAppId = 'PRAGMA application_id = 0x47504B47'; // GPKG
  
  static const String _sqlCreateSpatialRefSys = '''
    CREATE TABLE gpkg_spatial_ref_sys (
      srs_name TEXT NOT NULL,
      srs_id INTEGER NOT NULL PRIMARY KEY,
      organization TEXT NOT NULL,
      organization_coordsys_id INTEGER NOT NULL,
      definition TEXT NOT NULL,
      description TEXT
    )
  ''';

  static const String _sqlInsertWebMercator = '''
    INSERT INTO gpkg_spatial_ref_sys (
      srs_name, srs_id, organization, organization_coordsys_id, definition, description
    ) VALUES (
      'WGS 84 / Pseudo-Mercator',
      3857,
      'EPSG',
      3857,
      'PROJCS["WGS 84 / Pseudo-Mercator",GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563,AUTHORITY["EPSG","7030"]],AUTHORITY["EPSG","6326"]],PRIMEM["Greenwich",0,AUTHORITY["EPSG","8901"]],UNIT["degree",0.0174532925199433,AUTHORITY["EPSG","9122"]],AUTHORITY["EPSG","4326"]],PROJECTION["Mercator_1SP"],PARAMETER["central_meridian",0],PARAMETER["scale_factor",1],PARAMETER["false_easting",0],PARAMETER["false_easting",0],UNIT["metre",1,AUTHORITY["EPSG","9001"]],AXIS["X",EAST],AXIS["Y",NORTH],EXTENSION["PROJ4","+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs"],AUTHORITY["EPSG","3857"]]',
      'Web Mercator projection used by most web mapping applications'
    )
  ''';

  static const String _sqlCreateContents = '''
    CREATE TABLE gpkg_contents (
      table_name TEXT NOT NULL PRIMARY KEY,
      data_type TEXT NOT NULL,
      identifier TEXT UNIQUE,
      description TEXT DEFAULT '',
      last_change TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      min_x REAL,
      min_y REAL,
      max_x REAL,
      max_y REAL,
      srs_id INTEGER,
      CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    )
  ''';

  static const String _sqlCreateTileMatrixSet = '''
    CREATE TABLE gpkg_tile_matrix_set (
      table_name TEXT NOT NULL PRIMARY KEY,
      srs_id INTEGER NOT NULL,
      min_x REAL NOT NULL,
      min_y REAL NOT NULL,
      max_x REAL NOT NULL,
      max_y REAL NOT NULL,
      CONSTRAINT fk_gtms_table_name FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
      CONSTRAINT fk_gtms_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
    )
  ''';

  static const String _sqlCreateTileMatrix = '''
    CREATE TABLE gpkg_tile_matrix (
      table_name TEXT NOT NULL,
      zoom_level INTEGER NOT NULL,
      matrix_width INTEGER NOT NULL,
      matrix_height INTEGER NOT NULL,
      tile_width INTEGER NOT NULL,
      tile_height INTEGER NOT NULL,
      pixel_x_size REAL NOT NULL,
      pixel_y_size REAL NOT NULL,
      CONSTRAINT pk_ttm PRIMARY KEY (table_name, zoom_level),
      CONSTRAINT fk_tmm_table_name FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name)
    )
  ''';

  static String get _sqlCreateTilesTable => '''
    CREATE TABLE $_tilesTableName (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      zoom_level INTEGER NOT NULL,
      tile_column INTEGER NOT NULL,
      tile_row INTEGER NOT NULL,
      tile_data BLOB NOT NULL,
      provider_id TEXT NOT NULL,
      cached_at INTEGER NOT NULL
    )
  ''';

  static String get _sqlCreateIndexLookup => '''
    CREATE UNIQUE INDEX idx_tiles_lookup 
    ON $_tilesTableName(provider_id, zoom_level, tile_column, tile_row)
  ''';

  static String get _sqlCreateIndexProvider => '''
    CREATE INDEX idx_tiles_provider 
    ON $_tilesTableName(provider_id)
  ''';

  static String get _sqlInsertContents => '''
    INSERT INTO gpkg_contents (
      table_name, data_type, identifier, description, srs_id,
      min_x, min_y, max_x, max_y
    ) VALUES (
      '$_tilesTableName',
      'tiles',
      'map_tiles',
      'Cached map tiles from various providers',
      3857,
      -20037508.342789244,
      -20037508.342789244,
      20037508.342789244,
      20037508.342789244
    )
  ''';

  static String get _sqlInsertTileMatrixSet => '''
    INSERT INTO gpkg_tile_matrix_set (
      table_name, srs_id, min_x, min_y, max_x, max_y
    ) VALUES (
      '$_tilesTableName',
      3857,
      -20037508.342789244,
      -20037508.342789244,
      20037508.342789244,
      20037508.342789244
    )
  ''';
  
  Database? _database;
  String? _databasePath;
  
  // バッチ書き込み用
  final List<_PendingTile> _writeQueue = [];
  Timer? _batchTimer;
  bool _isFlushing = false;

  /// データベース初期化
  Future<void> initialize(String cacheDirectory) async {
    _databasePath = path.join(cacheDirectory, _databaseName);
    
    // データベースを開く（なければ作成）
    _database = await openDatabase(
      _databasePath!,
      version: 1,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );
    
    // initialized silently
  }

  /// データベース作成時の処理
  Future<void> _onCreate(Database db, int version) async {
    // 1. GeoPackageアプリケーションID設定
    await db.rawQuery(_sqlPragmaAppId);
    
    // 2. メタデータテーブル作成
    await db.execute(_sqlCreateSpatialRefSys);
    await db.execute(_sqlInsertWebMercator);
    await db.execute(_sqlCreateContents);
    await db.execute(_sqlCreateTileMatrixSet);
    await db.execute(_sqlCreateTileMatrix);
    
    // 3. タイルテーブル作成
    await db.execute(_sqlCreateTilesTable);
    await db.execute(_sqlCreateIndexLookup);
    await db.execute(_sqlCreateIndexProvider);
    
    // 4. メタデータ登録
    await db.execute(_sqlInsertContents);
    await db.execute(_sqlInsertTileMatrixSet);
    
    // 5. ズームレベル情報登録（0-22レベル）
    for (int zoom = 0; zoom <= 22; zoom++) {
      final matrixSize = 1 << zoom; // 2^zoom
      final pixelSize = (20037508.342789244 * 2) / (matrixSize * 256);
      
      await db.execute('''
        INSERT INTO gpkg_tile_matrix (
          table_name, zoom_level, matrix_width, matrix_height,
          tile_width, tile_height, pixel_x_size, pixel_y_size
        ) VALUES (
          '$_tilesTableName',
          $zoom,
          $matrixSize,
          $matrixSize,
          256,
          256,
          $pixelSize,
          $pixelSize
        )
      ''');
    }
  }

  /// データベースオープン時の処理
  Future<void> _onOpen(Database db) async {
    // WALモード有効化（パフォーマンス向上）
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await db.rawQuery('PRAGMA synchronous = NORMAL');
  }

  /// タイルを保存（バッチキューに追加）
  Future<void> saveTile({
    required String providerId,
    required int z,
    required int x,
    required int y,
    required Uint8List data,
  }) async {
    if (_database == null) {
      return; // 初期化前は静かにスキップ
    }
    
    // GeoPackageのタイル座標系はTMS方式（左下原点）
    // Web地図のXYZ方式（左上原点）から変換
    final tileRow = (1 << z) - 1 - y;
    
    // キューに追加
    _writeQueue.add(_PendingTile(
      providerId: providerId,
      z: z,
      x: x,
      y: y,
      data: data,
      tileRow: tileRow,
    ));
    
    // 上限チェック: 一定数溜まったら即フラッシュ（飢餓状態防止）
    if (_writeQueue.length >= 50) {
      _batchTimer?.cancel();
      await _flushBatch();
      return;
    }
    
    // 少量ならDebounceで待つ（100ms後にまとめて書き込み）
    _batchTimer?.cancel();
    _batchTimer = Timer(const Duration(milliseconds: 100), _flushBatch);
  }
  
  /// バッチ書き込み実行（キューに溜まったタイルを一括保存）
  Future<void> _flushBatch() async {
    if (_isFlushing || _writeQueue.isEmpty || _database == null) return;
    
    _isFlushing = true;
    final batch = _writeQueue.toList();
    _writeQueue.clear();
    
    try {
      // トランザクションで一括書き込み（SQL渋滞を回避）
      await _database!.transaction((txn) async {
        for (final tile in batch) {
          await txn.insert(
            _tilesTableName,
            {
              'zoom_level': tile.z,
              'tile_column': tile.x,
              'tile_row': tile.tileRow,
              'tile_data': tile.data,
              'provider_id': tile.providerId,
              'cached_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Batch save failed: $e');
    } finally {
      _isFlushing = false;
      // フラッシュ中に新たに溜まったタイルがあれば再フラッシュ
      if (_writeQueue.isNotEmpty) {
        _batchTimer?.cancel();
        _batchTimer = Timer(const Duration(milliseconds: 50), _flushBatch);
      }
    }
  }

  /// タイルを取得
  Future<Uint8List?> getTile({
    required String providerId,
    required int z,
    required int x,
    required int y,
  }) async {
    // 書き込みキュー内のタイルもヒットさせる（未フラッシュデータ対応）
    for (final pending in _writeQueue) {
      if (pending.providerId == providerId &&
          pending.z == z &&
          pending.x == x &&
          pending.y == y) {
        return pending.data;
      }
    }
    
    if (_database == null) {
      // 初期化前は静かにnullを返す（キャッシュなしとして扱われる）
      return null;
    }
    
    // XYZ → TMS 座標変換
    final tileRow = (1 << z) - 1 - y;
    
    try {
      final results = await _database!.query(
        _tilesTableName,
        columns: ['id', 'tile_data'],
        where: 'provider_id = ? AND zoom_level = ? AND tile_column = ? AND tile_row = ?',
        whereArgs: [providerId, z, x, tileRow],
        limit: 1,
      );
      
      if (results.isNotEmpty) {
        final id = results.first['id'] as int;
        final data = results.first['tile_data'] as Uint8List;
        
        // データサイズチェック
        if (data.length < 100) {
          // 破損データを自動削除
          await _database!.delete(_tilesTableName, where: 'id = ?', whereArgs: [id]);
          AppLogger.debug('[TILE-CACHE] 🗑️ Deleted corrupted tile (too small)');
          return null;
        }
        
        // PNGヘッダーチェック
        if (data.length >= 8) {
          // 以前はここでPNGシグネチャのチェックを行っていたが、
          // JPEGやWebPなどの他の画像形式を許容するため、
          // ヘッダーチェックは廃止する。
          // if (!isValidPng) { ... }
        }
        
        return data;
      }
      
      return null;
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Get tile error: $e');
      return null;
    }
  }

  /// プロバイダー別のタイル数を取得
  Future<Map<String, int>> getStatistics() async {
    if (_database == null) {
      return {}; // 初期化前は空の統計を返す
    }
    
    try {
      final results = await _database!.rawQuery('''
        SELECT provider_id, COUNT(*) as count
        FROM $_tilesTableName
        GROUP BY provider_id
      ''');
      
      final stats = <String, int>{};
      for (final row in results) {
        stats[row['provider_id'] as String] = row['count'] as int;
      }
      
      return stats;
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Statistics error: $e');
      return {};
    }
  }

  /// 総タイル数を取得
  Future<int> getTotalTileCount() async {
    if (_database == null) return 0;
    
    try {
      final result = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM $_tilesTableName',
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Count error: $e');
      return 0;
    }
  }

  /// キャッシュサイズを取得（バイト）
  Future<int> getCacheSize() async {
    if (_databasePath == null) return 0;
    
    try {
      final file = File(_databasePath!);
      if (file.existsSync()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Size error: $e');
      return 0;
    }
  }

  /// キャッシュをクリア（プロバイダー指定可能）
  Future<void> clearCache({String? providerId}) async {
    if (_database == null) return;
    
    try {
      await _database!.delete(
        _tilesTableName,
        where: providerId != null ? 'provider_id = ?' : null,
        whereArgs: providerId != null ? [providerId] : null,
      );
      
      // VACUUM実行でディスク容量を回収
      await _database!.rawQuery('VACUUM');
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Clear error: $e');
      rethrow;
    }
  }

  /// 破損タイル検証・修復
  Future<Map<String, dynamic>> validateAndRepair() async {
    if (_database == null) {
      return {
        'totalTiles': 0,
        'validTiles': 0,
        'invalidTiles': 0,
        'removedTiles': 0,
      }; // 初期化前は空の結果を返す
    }
    
    final result = {
      'totalTiles': 0,
      'validTiles': 0,
      'invalidTiles': 0,
      'removedTiles': 0,
    };
    
    try {
      // 全タイルを取得
      final tiles = await _database!.query(_tilesTableName);
      result['totalTiles'] = tiles.length;
      
      final idsToDelete = <int>[];
      
      for (final tile in tiles) {
        final id = tile['id'] as int;
        final tileData = tile['tile_data'] as Uint8List;
        
        // サイズチェック
        if (tileData.length < 100) {
          idsToDelete.add(id);
          result['invalidTiles'] = (result['invalidTiles'] as int) + 1;
          continue;
        }
        
        // PNGヘッダーチェック
        if (tileData.length >= 8) {
          // 以前はここでPNGシグネチャのチェックを行っていたが、
          // JPEGやWebPなどの他の画像形式を許容するため、
          // ヘッダーチェックは廃止する。
          // if (!isValidPng) { ... }
        }
        
        result['validTiles'] = (result['validTiles'] as int) + 1;
      }
      
      // 破損タイルを削除
      if (idsToDelete.isNotEmpty) {
        for (final id in idsToDelete) {
          await _database!.delete(
            _tilesTableName,
            where: 'id = ?',
            whereArgs: [id],
          );
        }
        result['removedTiles'] = idsToDelete.length;
        
        // VACUUM実行
        await _database!.rawQuery('VACUUM');
      }
    } catch (e) {
      AppLogger.debug('[TILE-CACHE] ❌ Validation error: $e');
    }
    
    return result;
  }

  /// データベースを閉じる
  Future<void> close() async {
    // 残りのバッチを保存
    _batchTimer?.cancel();
    await _flushBatch();
    
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// データベースパスを取得
  String? get databasePath => _databasePath;
}


