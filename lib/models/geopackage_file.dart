// K-MAPS: GeoPackageファイル管理クラス（sqflite移行版）
// DB操作ラッパー。段階的移行により非同期処理へ対応。点・線・面レイヤ対応。
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert'; // JSON処理のため追加
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:latlong2/latlong.dart';
import '../utils/wkb_utils.dart'; // WKBユーティリティをインポート
import 'package:path/path.dart' as p;
import '../utils/global_config.dart';
import '../utils/background_save_manager.dart'; // バックグラウンド保存管理クラスをインポート
import 'package:flutter/widgets.dart';
import 'geometry_type.dart'; // ジオメトリタイプenumをインポート

/// GeoPackageファイルを管理するクラス（sqflite版）
/// 段階的移行のため、すべてのメソッドをFutureを返すように変更
class GeoPackageFile {
  /// ルートからのパスリスト
  final List<String> pathList;

  /// データベース接続インスタンス
  Database? _database;

  /// データベース初期化完了フラグ
  bool _isInitialized = false;

  /// サポートする属性カラム名リスト（属性テーブルで表示するカラム）
  /// geom のみを固定カラムとし、他は動的に追加
  /// 注意: id列はテーブルの主キーとして存在するが、属性データとしては扱わない
  final List<String> supportedAttributes = [
    "geom",
  ];

  /// コンストラクタ
  /// pathList: ルートからのサブディレクトリ＋ファイル名のリスト
  GeoPackageFile(this.pathList);

  /// 属性値の遅延更新をキューに追加（BackgroundSaveManagerに移譲）
  void queueAttributeUpdate(
    String tableName,
    int rowId,
    String attributeName,
    dynamic value,
  ) {
    BackgroundSaveManager.instance.queueAttributeUpdate(
      this,
      tableName,
      rowId,
      attributeName,
      value,
    );
  }

  /// 複数の属性値を一括で遅延更新キューに追加（BackgroundSaveManagerに移譲）
  void queueAttributeUpdates(
    String tableName,
    int rowId,
    Map<String, dynamic> attributes,
  ) {
    BackgroundSaveManager.instance.queueAttributeUpdates(
      this,
      tableName,
      rowId,
      attributes,
    );
  }

  /// 複数の属性値を一括更新（内部用）
  Future<bool> _updateFeatureAttributes(
    String tableName,
    int rowId,
    Map<String, dynamic> attributes,
  ) async {
    try {
      print('[DEBUG] GeoPackageFile: 属性更新開始 - テーブル:$tableName, 行ID:$rowId');
      
      // SQLiteでサポートされていない型を除外
      final filteredAttributes = <String, dynamic>{};
      for (final entry in attributes.entries) {
        final key = entry.key;
        final value = entry.value;
        
        // ジオメトリ関連フィールドとidフィールドは属性更新対象から除外
        if (key == 'geometry' || key == 'geom' || key == 'id') {
          print('[DEBUG] GeoPackageFile: スキップするフィールド: $key');
          continue;
        }
        
        // SQLiteでサポートされている型のみを含める
        if (value == null || 
            value is String || 
            value is num || 
            value is bool ||
            value is Uint8List) {
          filteredAttributes[key] = value;
        } else {
          print('[DEBUG] GeoPackageFile: サポートされていない型のためスキップ: $key = $value (${value.runtimeType})');
        }
      }
      
      if (filteredAttributes.isEmpty) {
        print('[DEBUG] GeoPackageFile: 更新対象の属性がありません');
        return true; // 更新対象がない場合は成功とみなす
      }
      
      print('[DEBUG] GeoPackageFile: 更新する属性: $filteredAttributes');
      
      final db = await _getDatabase();
      // テーブル名をエスケープしてUPDATE文を実行
      final columnAssignments = filteredAttributes.keys
          .map((key) => '"$key" = ?')
          .join(', ');
      final values = [...filteredAttributes.values, rowId];
      
      final sql = 'UPDATE "$tableName" SET $columnAssignments WHERE id = ?';
      print('[DEBUG] GeoPackageFile: 実行SQL: $sql');
      print('[DEBUG] GeoPackageFile: 実行値: $values');
      
      final rowsUpdated = await db.rawUpdate(sql, values);
      
      print('[DEBUG] GeoPackageFile: 更新された行数: $rowsUpdated');
      return rowsUpdated > 0;
    } catch (e) {
      print('[ERROR] GeoPackageFile: _updateFeatureAttributes failed: $e');
      return false;
    }
  }

  /// 複数の属性値を一括更新（BackgroundSaveManager用パブリックメソッド）
  Future<bool> updateFeatureAttributes(
    String tableName,
    int rowId,
    Map<String, dynamic> attributes,
  ) async {
    return await _updateFeatureAttributes(tableName, rowId, attributes);
  }

  /// 即座に全ての変更をDBに保存（BackgroundSaveManagerに移譲）
  Future<void> flushChanges() async {
    await BackgroundSaveManager.instance.flushChanges(this);
  }

  /// 辞書ベースの点フィーチャ追加
  Future<int?> addPointWithAttributes(
    String tableName,
    LatLng point,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await _getDatabase();
      final wkb = createWkbPoint(point.longitude, point.latitude);

      // WKBデータの妥当性チェック（デバッグ）
      if (!validateWkbData(wkb)) {
        print('[GeoPackageFile] 警告: 無効なWKBデータが生成されました');
        debugWkbData(
          wkb,
          'addPointWithAttributes - ${point.latitude}, ${point.longitude}',
        );
      }

      final data = <String, dynamic>{'geom': wkb};
      data.addAll(attributes);

      // insertして実際のrowIdを取得
      final rowId = await db.insert(tableName, data);

      // gpkg_contentsテーブルのエンベロープを更新
      await _updateLayerEnvelope(
        tableName,
        point.longitude,
        point.latitude,
        point.longitude,
        point.latitude,
      );

      return rowId;
    } catch (e) {
      print('[ERROR] GeoPackageFile: addPointWithAttributes failed: $e');
      return null;
    }
  }

  /// 辞書ベースの線フィーチャ追加
  Future<int?> addLineWithAttributes(
    String tableName,
    List<LatLng> line,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await _getDatabase();
      final wkb = createWkbLineString(line);

      final data = <String, dynamic>{'geom': wkb};
      data.addAll(attributes);

      // insertして実際のrowIdを取得
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

        await _updateLayerEnvelope(tableName, minX, minY, maxX, maxY);
      }

      return rowId;
    } catch (e) {
      print('[ERROR] GeoPackageFile: addLineWithAttributes failed: $e');
      return null;
    }
  }

  /// 辞書ベースの面フィーチャ追加
  Future<int?> addPolygonWithAttributes(
    String tableName,
    List<List<LatLng>> polygon,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await _getDatabase();
      final wkb = createWkbPolygon(polygon);

      final data = <String, dynamic>{'geom': wkb};
      data.addAll(attributes);

      // insertして実際のrowIdを取得
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

        await _updateLayerEnvelope(tableName, minX, minY, maxX, maxY);
      }

      return rowId;
    } catch (e) {
      print('[ERROR] GeoPackageFile: addPolygonWithAttributes failed: $e');
      return null;
    }
  }

  /// データベース初期化（遅延初期化）
  /// プライベートメソッドで、必要に応じて自動的に呼び出される
  Future<void> _initializeDatabase() async {
    if (_isInitialized && _database != null) {
      return;
    }

    final baseDir = GlobalConfig.instance.projectRootDir;

    if (baseDir == null) {
      print('[GeoPackageFile] 初期化失敗: projectRootDirが未設定');
      return;
    }

    final absPath = p.joinAll([baseDir, ...pathList]);

    final file = File(absPath);
    final dir = file.parent;

    if (!dir.existsSync()) {
      print('[GeoPackageFile] 親ディレクトリを作成: ${dir.path}');
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        print('[GeoPackageFile] 初期化失敗: 親ディレクトリ作成エラー - $e');
        return;
      }
    }

    try {
      WidgetsFlutterBinding.ensureInitialized();

      _database = await openDatabase(
        absPath,
        version: 1,
        onCreate: _createDatabase,
        onUpgrade: _upgradeDatabase,
      );
      _isInitialized = true;
      print('[GeoPackageFile] 初期化成功: ${p.basename(absPath)}');
    } catch (e, stack) {
      print('[GeoPackageFile] 初期化時にエラー発生:');
      print('  パス: $absPath');
      print('  エラー: $e');
      print('  スタックトレース: $stack');

      try {
        final dirWritable = await Directory(dir.path).stat();
        print('  親ディレクトリ情報: ${dirWritable.type}');
      } catch (dirError) {
        print('  親ディレクトリアクセスエラー: $dirError');
      }
    }
  }

  /// データベースのクローズ処理
  Future<void> dispose() async {
    // 保留中の変更を全て保存
    await flushChanges();

    // BackgroundSaveManagerから変更キューをクリア
    BackgroundSaveManager.instance.clearPendingChanges(this);

    // データベースを閉じる
    if (_database != null) {
      await _database!.close();
      _database = null;
    }

    _isInitialized = false;
    print('[DEBUG] GeoPackageFile: Disposed database connection');
  }

  /// データベース作成時のコールバック（OGC GeoPackage仕様準拠）
  Future<void> _createDatabase(Database db, int version) async {
    // 空間参照系テーブル
    await db.execute('''
			CREATE TABLE gpkg_spatial_ref_sys (
				srs_name TEXT NOT NULL,
				srs_id INTEGER NOT NULL PRIMARY KEY,
				organization TEXT NOT NULL,
				organization_coordsys_id INTEGER NOT NULL,
				definition TEXT NOT NULL,
				description TEXT
			);
		''');

    // コンテンツテーブル
    await db.execute('''
			CREATE TABLE gpkg_contents (
				table_name TEXT NOT NULL PRIMARY KEY,
				data_type TEXT NOT NULL,
				identifier TEXT UNIQUE,
				description TEXT DEFAULT '',
				last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
				min_x DOUBLE,
				min_y DOUBLE,
				max_x DOUBLE,
				max_y DOUBLE,
				srs_id INTEGER,
				CONSTRAINT fk_gc_r_srs_id FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys(srs_id)
			);
		''');

    // ジオメトリカラムテーブル
    await db.execute('''
			CREATE TABLE gpkg_geometry_columns (
				table_name TEXT NOT NULL,
				column_name TEXT NOT NULL,
				geometry_type_name TEXT NOT NULL,
				srs_id INTEGER NOT NULL,
				z TINYINT NOT NULL,
				m TINYINT NOT NULL,
				CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name),
				CONSTRAINT uk_gc_table_name UNIQUE (table_name),
				CONSTRAINT fk_gc_tn FOREIGN KEY (table_name) REFERENCES gpkg_contents(table_name),
				CONSTRAINT fk_gc_srs FOREIGN KEY (srs_id) REFERENCES gpkg_spatial_ref_sys (srs_id)
			);
		''');

    // 必須SRSレコード（WGS84, undefined geographic, undefined cartesian）
    await db.insert('gpkg_spatial_ref_sys', {
      'srs_name': 'WGS 84 geodetic',
      'srs_id': 4326,
      'organization': 'EPSG',
      'organization_coordsys_id': 4326,
      'definition':
          'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]',
      'description':
          'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid',
    });

    await db.insert('gpkg_spatial_ref_sys', {
      'srs_name': 'Undefined geographic SRS',
      'srs_id': 0,
      'organization': 'NONE',
      'organization_coordsys_id': 0,
      'definition': 'undefined',
      'description': 'undefined geographic coordinate reference system',
    });

    await db.insert('gpkg_spatial_ref_sys', {
      'srs_name': 'Undefined cartesian SRS',
      'srs_id': -1,
      'organization': 'NONE',
      'organization_coordsys_id': -1,
      'definition': 'undefined',
      'description': 'undefined cartesian coordinate reference system',
    });
  }

  /// データベースアップグレード時のコールバック
  Future<void> _upgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // 将来のスキーマ更新時に実装
    print('データベースをバージョン $oldVersion から $newVersion にアップグレード');
  }

  /// データベース接続取得（初期化を含む）
  Future<Database> _getDatabase() async {
    await _initializeDatabase();
    if (_database == null) {
      throw Exception('データベースの初期化に失敗しました');
    }
    return _database!;
  }

  /// 空のGeoPackageファイルを明示的に作成（即座に初期化）
  /// GeoPackageNode作成時に呼び出す
  Future<bool> createEmptyDatabase() async {
    try {
      await _initializeDatabase();
      if (_database != null && _isInitialized) {
        return true;
      } else {
        print('[GeoPackageFile] 空のGeoPackageファイル作成失敗: 初期化未完了');
        return false;
      }
    } catch (e) {
      print('[GeoPackageFile] 空のGeoPackageファイル作成エラー: $e');
      return false;
    }
  }

  /// 点フィーチャを追加（属性付き）
  /// name, description, metadata は属性として追加（カラムが存在する場合のみ）
  Future<int?> addPoint(
    String tableName,
    LatLng pt, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      // カラムの存在確認
      final db = await _getDatabase();
      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();
      
      // 新しい辞書ベースAPIを使用
      final attributes = <String, dynamic>{};

      // カラムが存在する場合のみ値を設定（空でも設定）
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
      print('[ERROR] GeoPackageFile: addPoint failed: $e');
      return null;
    }
  }

  /// 指定IDのフィーチャを削除
  Future<void> removeFeature(String tableName, int id) async {
    try {
      final db = await _getDatabase();
      await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
    } catch (e) {
      print('removeFeature: エラー発生 - $e');
    }
  }

  /// 指定レイヤのジオメトリタイプを取得
  Future<GeometryType?> getGeometryType(String tableName) async {
    try {
      final db = await _getDatabase();
      final rows = await db.query(
        'gpkg_geometry_columns',
        where: 'table_name = ?',
        whereArgs: [tableName],
      );
      if (rows.isEmpty) return null;
      final typeString = rows.first['geometry_type_name'] as String?;
      return typeString != null ? GeometryType.fromString(typeString) : null;
    } catch (e) {
      print('getGeometryType: エラー発生 - $e');
      return null;
    }
  }

  /// 単一フィーチャを取得（geom列をgeometry typeに応じて変換）
  Future<Map<String, dynamic>?> getFeature(String tableName, int rowId) async {
    try {
      final db = await _getDatabase();
      final geomType = await getGeometryType(tableName);

      final rows = await db.rawQuery(
        'SELECT * FROM "$tableName" WHERE id = ?',
        [rowId],
      );

      if (rows.isEmpty) return null;

      final row = Map<String, dynamic>.from(rows.first);
      final geom = row['geom'] as Uint8List?;

      // geom列をgeometry typeに応じて変換
      if (geom != null && geomType != null) {
        if (geomType == GeometryType.point) {
          // GPBinaryヘッダーをスキップして純粋なWKBデータを取得
          Uint8List pureWkb = geom;
          if (geom.length > 8 && geom[0] == 0x47 && geom[1] == 0x50) {
            // GPBinaryヘッダーのサイズを正確に計算
            final flags = geom[3];
            final envelopeType = (flags >> 1) & 0x07; // bits 1-3
            int headerSize = 8; // 基本サイズ（GP + Version + Flags + SRS ID）

            // エンベロープサイズを計算
            switch (envelopeType) {
              case 1: // XY
                headerSize += 32; // 4 doubles
                break;
              case 2: // XYZ
                headerSize += 48; // 6 doubles
                break;
              case 3: // XYM
                headerSize += 48; // 6 doubles
                break;
              case 4: // XYZM
                headerSize += 64; // 8 doubles
                break;
            }

            if (geom.length > headerSize) {
              pureWkb = geom.sublist(headerSize);
            }
          }

          if (pureWkb.length >= 21 && pureWkb[0] == 1 && pureWkb[1] == 1) {
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
            row['geometry'] = [LatLng(lat, lon)];
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

      // kmaps_metadataをパース
      final metadataStr = row['kmaps_metadata'] as String?;
      if (metadataStr != null && metadataStr.isNotEmpty) {
        try {
          row['kmaps_metadata'] =
              jsonDecode(metadataStr) as Map<String, dynamic>;
        } catch (e) {
          print('getFeature: メタデータのJSONパースエラー - $e');
        }
      }

      return row;
    } catch (e) {
      print('getFeature: エラー発生 - $e');
      return null;
    }
  }

  /// 指定レイヤの全フィーチャ（rawデータをそのまま返す）
  Future<List<Map<String, dynamic>>> getFeatures(String tableName) async {
    try {
      final db = await _getDatabase();
      final rows = await db.rawQuery('SELECT * FROM "$tableName"');

      // rawデータをそのまま返す（geometry変換は行わない）
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      print('getFeatures: エラー発生 - $e');
      return [];
    }
  }

  /// DBからレイヤ（フィーチャテーブル）名一覧を取得
  Future<List<String>> getLayerNames() async {
    try {
      final db = await _getDatabase();
      final contents = await db.query(
        'gpkg_contents',
        where: 'data_type = ?',
        whereArgs: ['features'],
      );
      return contents.map((row) => row['table_name'] as String).toList();
    } catch (e) {
      print('getLayerNames: エラー発生 - $e');
      return [];
    }
  }

  /// レイヤ追加（DBにテーブル作成）
  Future<void> addLayer(String name, GeometryType geomType) async {
    try {
      final db = await _getDatabase();

      // フィーチャテーブル作成（必須カラムのみ：id と geom）
      await db.execute('''
				CREATE TABLE IF NOT EXISTS "$name" (
					id INTEGER PRIMARY KEY AUTOINCREMENT,
					geom BLOB NOT NULL
				);
			''');

      // gpkg_contentsに登録（初期エンベロープは未設定、後でフィーチャー追加時に更新）
      await db.insert('gpkg_contents', {
        'table_name': name,
        'data_type': 'features',
        'identifier': name,
        'description': '',
        'srs_id': 4326,
        'min_x': null,
        'min_y': null,
        'max_x': null,
        'max_y': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      // gpkg_geometry_columnsに登録
      await db.insert('gpkg_geometry_columns', {
        'table_name': name,
        'column_name': 'geom',
        'geometry_type_name': geomType.value,
        'srs_id': 4326,
        'z': 0,
        'm': 0,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      // 空間インデックスを作成（QGISでの認識を改善）
      await _createSpatialIndex(name);
    } catch (e) {
      print('addLayer: エラー発生 - $e');
    }
  }

  /// 空間インデックス作成（GeoPackageの空間インデックス機能を利用）
  Future<void> _createSpatialIndex(String tableName) async {
    try {
      final db = await _getDatabase();

      // SpatiaLiteスタイルの空間インデックス作成
      // GeoPackageでは必須ではないが、QGISでの認識を改善
      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_${tableName}_geom 
        ON "$tableName" (geom)
      ''');

    } catch (e) {
      print('[ERROR] GeoPackageFile._createSpatialIndex: $e');
    }
  }

  /// gpkg_contentsテーブルのエンベロープを更新
  Future<void> _updateLayerEnvelope(
    String tableName,
    double minX,
    double minY,
    double maxX,
    double maxY,
  ) async {
    try {
      final db = await _getDatabase();

      // 現在のエンベロープを取得
      final currentEnvelope = await db.query(
        'gpkg_contents',
        columns: ['min_x', 'min_y', 'max_x', 'max_y'],
        where: 'table_name = ?',
        whereArgs: [tableName],
      );

      double? currentMinX, currentMinY, currentMaxX, currentMaxY;
      if (currentEnvelope.isNotEmpty) {
        final row = currentEnvelope.first;
        currentMinX = row['min_x'] as double?;
        currentMinY = row['min_y'] as double?;
        currentMaxX = row['max_x'] as double?;
        currentMaxY = row['max_y'] as double?;
      }

      // エンベロープを拡張
      final newMinX =
          currentMinX != null
              ? (currentMinX < minX ? currentMinX : minX)
              : minX;
      final newMinY =
          currentMinY != null
              ? (currentMinY < minY ? currentMinY : minY)
              : minY;
      final newMaxX =
          currentMaxX != null
              ? (currentMaxX > maxX ? currentMaxX : maxX)
              : maxX;
      final newMaxY =
          currentMaxY != null
              ? (currentMaxY > maxY ? currentMaxY : maxY)
              : maxY;

      // エンベロープを更新
      await db.update(
        'gpkg_contents',
        {
          'min_x': newMinX,
          'min_y': newMinY,
          'max_x': newMaxX,
          'max_y': newMaxY,
        },
        where: 'table_name = ?',
        whereArgs: [tableName],
      );

      print(
        '[GeoPackageFile] Layer envelope updated: $tableName ($newMinX, $newMinY, $newMaxX, $newMaxY)',
      );
    } catch (e) {
      print('[GeoPackageFile] エンベロープ更新エラー: $e');
    }
  }

  /// レイヤ削除（DBからテーブル・メタ情報削除）
  Future<void> removeLayer(String name) async {
    try {
      final db = await _getDatabase();

      // フィーチャテーブル削除
      await db.execute('DROP TABLE IF EXISTS "$name";');

      // メタデータ削除
      await db.delete(
        'gpkg_contents',
        where: 'table_name = ?',
        whereArgs: [name],
      );
      await db.delete(
        'gpkg_geometry_columns',
        where: 'table_name = ?',
        whereArgs: [name],
      );
    } catch (e) {
      print('removeLayer: エラー発生 - $e');
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
    // 新しい辞書ベースAPIを使用
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (metadata != null) {
      attributes['kmaps_metadata'] = jsonEncode(metadata);
    }

    return await addLineWithAttributes(tableName, line, attributes);
  }

  /// ポリゴンフィーチャを追加（属性付き、外環＋穴リスト対応）
  Future<int?> addPolygon(
    String tableName,
    List<List<LatLng>> rings, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    // 新しい辞書ベースAPIを使用
    final attributes = <String, dynamic>{
      'name': name,
      'description': description,
    };

    if (metadata != null) {
      attributes['kmaps_metadata'] = jsonEncode(metadata);
    }

    return await addPolygonWithAttributes(tableName, rings, attributes);
  }

  /// 指定テーブルのカラム名一覧を返す（getAll=trueなら全属性カラム、falseならsupportedAttributesのみ）
  /// 注意: id（主キー）とgeom（ジオメトリ）は常に除外される
  Future<List<String>> getColumnNames(
    String tableName, {
    bool getAll = false,
  }) async {
    try {
      final db = await _getDatabase();
      final result = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columns = result.map((row) => row['name'] as String).toList();

      // id と geom は属性データではないため常に除外
      final filteredColumns = columns.where((c) => c != 'id' && c != 'geom').toList();

      if (getAll) return filteredColumns;
      // supportedAttributesに含まれるものだけ返す
      return filteredColumns.where((c) => supportedAttributes.contains(c)).toList();
    } catch (e) {
      print('getColumnNames: エラー発生 - $e');
      return [];
    }
  }

  /// 指定テーブル・rowId・カラム名から値を取得
  Future<dynamic> getFeatureAttribute(
    String tableName,
    int rowId,
    String attributeName,
  ) async {
    try {
      final db = await _getDatabase();
      final result = await db.query(
        tableName,
        where: 'id = ?',
        whereArgs: [rowId],
      );
      if (result.isNotEmpty) {
        return result.first[attributeName];
      }
      return null;
    } catch (e) {
      print('getFeatureAttribute: エラー発生 - $e');
      return null;
    }
  }

  /// 指定テーブル・rowIdの全属性値を取得
  Future<Map<String, dynamic>?> getFeatureAttributes(
    String tableName,
    int rowId,
  ) async {
    try {
      final db = await _getDatabase();
      final result = await db.query(
        tableName,
        where: 'id = ?',
        whereArgs: [rowId],
      );
      if (result.isNotEmpty) {
        return Map<String, dynamic>.from(result.first);
      }
      return null;
    } catch (e) {
      print('getFeatureAttributes: エラー発生 - $e');
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
      final db = await _getDatabase();
      final rowsUpdated = await db.rawUpdate(
        'UPDATE "$tableName" SET "$attributeName" = ? WHERE id = ?',
        [newValue, rowId],
      );
      return rowsUpdated > 0;
    } catch (e) {
      print('updateFeatureAttribute: エラー発生 - $e');
      return false;
    }
  }


  /// 属性カラムを動的に追加
  /// [tableName] テーブル名
  /// [columnName] カラム名
  /// [columnType] カラム型（'TEXT', 'INTEGER', 'REAL', 'BLOB'）
  Future<void> addAttributeColumn(
    String tableName,
    String columnName,
    String columnType,
  ) async {
    try {
      final db = await _getDatabase();

      // カラム名の安全性チェック（SQLインジェクション対策）
      if (!RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$').hasMatch(columnName)) {
        throw Exception('無効なカラム名です: $columnName');
      }

      // 既存カラムのチェック
      final result = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columns = result.map((row) => row['name'] as String).toList();

      if (!columns.contains(columnName)) {
        await db.execute(
          'ALTER TABLE "$tableName" ADD COLUMN "$columnName" $columnType;',
        );
      }
    } catch (e) {
      print('[GeoPackageFile] addAttributeColumn エラー発生 - $e');
      throw e;
    }
  }

  /// シェープファイルの属性構造を元にGeoPackageテーブルを拡張
  /// [tableName] テーブル名
  /// [attributeSchema] 属性スキーマ（カラム名 -> データ型のマップ）
  Future<void> addAttributeColumns(
    String tableName,
    Map<String, String> attributeSchema,
  ) async {
    try {
      for (final entry in attributeSchema.entries) {
        final columnName = entry.key;
        final columnType = entry.value;
        await addAttributeColumn(tableName, columnName, columnType);
      }
    } catch (e) {
      print('[GeoPackageFile] addAttributeColumns エラー発生 - $e');
      throw e;
    }
  }

  /// フィーチャを完全な属性テーブルとして追加
  /// [tableName] テーブル名
  /// [geometry] ジオメトリデータ（WKB形式）
  /// [attributes] 属性データ（カラム名 -> 値のマップ）
  Future<int?> addFeatureWithAttributes(
    String tableName,
    Uint8List geometry,
    Map<String, dynamic> attributes,
  ) async {
    try {
      final db = await _getDatabase();

      // geomカラムを追加
      final data = <String, dynamic>{'geom': geometry};
      data.addAll(attributes);

      // insertして実際のrowIdを取得
      final rowId = await db.insert(tableName, data);
      return rowId;
    } catch (e) {
      print('[GeoPackageFile] addFeatureWithAttributes エラー発生 - $e');
      return null;
    }
  }

  /// レイヤの全属性カラム情報を取得（詳細）
  /// [tableName] テーブル名
  /// [includeBuiltIn] 組み込みカラム（id, geom）を含めるか
  Future<List<Map<String, dynamic>>> getAttributeColumnInfo(
    String tableName, {
    bool includeBuiltIn = false,
  }) async {
    try {
      final db = await _getDatabase();
      final result = await db.rawQuery('PRAGMA table_info("$tableName");');

      final columnInfo = <Map<String, dynamic>>[];
      final builtInColumns = {
        'id',
        'geom',
      };

      for (final row in result) {
        final columnName = row['name'] as String;

        if (!includeBuiltIn && builtInColumns.contains(columnName)) {
          continue; // 組み込みカラムをスキップ
        }

        columnInfo.add({
          'name': columnName,
          'type': row['type'] as String,
          'notNull': (row['notnull'] as int) == 1,
          'defaultValue': row['dflt_value'],
          'primaryKey': (row['pk'] as int) == 1,
        });
      }

      return columnInfo;
    } catch (e) {
      print('[GeoPackageFile] getAttributeColumnInfo エラー発生 - $e');
      return [];
    }
  }

  /// ファイル自体を削除（物理削除）
  Future<bool> deleteFile() async {
    try {
      // まずデータベース接続を閉じる
      await dispose();

      final baseDir = GlobalConfig.instance.projectRootDir;
      if (baseDir == null) {
        print('[GeoPackageFile] deleteFile: projectRootDirが未設定');
        return false;
      }

      final absPath = p.joinAll([baseDir, ...pathList]);
      final file = File(absPath);

      if (!file.existsSync()) {
        print('[GeoPackageFile] deleteFile: ファイルが存在しません - $absPath');
        return true; // 既に存在しないので成功とみなす
      }

      await file.delete();
      print('[GeoPackageFile] deleteFile: ファイル削除完了 - $absPath');
      return true;
    } catch (e, stack) {
      print('[GeoPackageFile] deleteFile: ファイル削除エラー - $e');
      print('スタックトレース: $stack');
      return false;
    }
  }

  /// 点フィーチャを更新（位置と属性を完全更新）
  /// 注: カラムの存在を確認し、存在するカラムのみ更新
  Future<bool> updatePoint(
    String tableName,
    int id,
    LatLng pt, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await _getDatabase();
      final wkb = createWkbPoint(pt.longitude, pt.latitude);

      // WKBデータの妥当性チェック（デバッグ）
      if (!validateWkbData(wkb)) {
        print('[GeoPackageFile] 警告: 無効なWKBデータが生成されました');
        debugWkbData(wkb, 'updatePoint - ${pt.latitude}, ${pt.longitude}');
      }

      // カラムの存在確認
      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      // 更新するカラムと値のリストを動的に構築
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

      updateValues.add(id); // WHERE句のid

      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE id = ?';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      print('updatePoint: エラー発生 - $e');
      return false;
    }
  }

  /// 線フィーチャを更新（ジオメトリと属性を完全更新）
  /// 注: カラムの存在を確認し、存在するカラムのみ更新
  Future<bool> updateLine(
    String tableName,
    int id,
    List<LatLng> line, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await _getDatabase();
      final wkb = createWkbLineString(line);

      // カラムの存在確認
      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      // 更新するカラムと値のリストを動的に構築
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

      updateValues.add(id); // WHERE句のid

      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE id = ?';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      print('updateLine: エラー発生 - $e');
      return false;
    }
  }

  /// ポリゴンフィーチャを更新（ジオメトリと属性を完全更新）
  /// 注: カラムの存在を確認し、存在するカラムのみ更新
  Future<bool> updatePolygon(
    String tableName,
    int id,
    List<List<LatLng>> rings, {
    String name = '',
    String description = '',
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final db = await _getDatabase();
      final wkb = createWkbPolygon(rings);

      // カラムの存在確認
      final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columnNames = columns.map((row) => row['name'] as String).toSet();

      // 更新するカラムと値のリストを動的に構築
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

      updateValues.add(id); // WHERE句のid

      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE id = ?';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      print('updatePolygon: エラー発生 - $e');
      return false;
    }
  }

  /// バッチ処理でポリゴンを高速追加
  /// [tableName] テーブル名
  /// [polygonData] ポリゴンデータのリスト
  Future<List<int>> addPolygonsBatch(
    String tableName,
    List<Map<String, dynamic>> polygonData,
  ) async {
    try {
      final db = await _getDatabase();
      final batch = db.batch();
      final insertedIds = <int>[];

      // バッチでINSERT文を準備
      for (int i = 0; i < polygonData.length; i++) {
        final data = polygonData[i];
        final rings = data['rings'] as List<List<LatLng>>;
        
        // WKBジオメトリを作成
        final wkb = createWkbPolygon(rings);
        
        // insertData を構築（ringsを除く全ての属性を含める）
        final insertData = <String, dynamic>{'geom': wkb};
        
        // dataから全ての属性をコピー（ringsは除外）
        data.forEach((key, value) {
          if (key != 'rings') {
            insertData[key] = value;
          }
        });
        
        // カラム名とプレースホルダーを動的に生成
        final columns = insertData.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        final columnNames = columns.map((c) => '"$c"').join(', ');
        final values = columns.map((c) => insertData[c]).toList();
        
        // 動的INSERT文を実行
        batch.rawInsert(
          'INSERT INTO "$tableName" ($columnNames) VALUES ($placeholders)',
          values,
        );
      }

      // バッチ実行
      final results = await batch.commit(noResult: false);

      // 結果をrowIdリストに変換
      for (final result in results) {
        if (result is int) {
          insertedIds.add(result);
        }
      }

      return insertedIds;
    } catch (e) {
      print('[ERROR] GeoPackageFile.addPolygonsBatch: $e');
      return [];
    }
  }

  /// バッチ処理でポイントを高速追加
  /// [tableName] テーブル名
  /// [pointData] ポイントデータのリスト
  Future<List<int>> addPointsBatch(
    String tableName,
    List<Map<String, dynamic>> pointData,
  ) async {
    try {
      final db = await _getDatabase();
      final batch = db.batch();
      final insertedIds = <int>[];

      // バッチでINSERT文を準備
      for (int i = 0; i < pointData.length; i++) {
        final data = pointData[i];
        final point = data['point'] as LatLng;
        
        // WKBジオメトリを作成
        final wkb = createWkbPoint(point.longitude, point.latitude);
        
        // insertData を構築（pointを除く全ての属性を含める）
        final insertData = <String, dynamic>{'geom': wkb};
        
        // dataから全ての属性をコピー（pointは除外）
        data.forEach((key, value) {
          if (key != 'point') {
            insertData[key] = value;
          }
        });
        
        // カラム名とプレースホルダーを動的に生成
        final columns = insertData.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        final columnNames = columns.map((c) => '"$c"').join(', ');
        final values = columns.map((c) => insertData[c]).toList();
        
        // 動的INSERT文を実行
        batch.rawInsert(
          'INSERT INTO "$tableName" ($columnNames) VALUES ($placeholders)',
          values,
        );
      }

      // バッチ実行
      final results = await batch.commit(noResult: false);

      // 結果をrowIdリストに変換
      for (final result in results) {
        if (result is int) {
          insertedIds.add(result);
        }
      }

      return insertedIds;
    } catch (e) {
      print('[ERROR] GeoPackageFile.addPointsBatch: $e');
      return [];
    }
  }

  /// バッチ処理でラインを高速追加
  /// [tableName] テーブル名
  /// [lineData] ラインデータのリスト
  Future<List<int>> addLinesBatch(
    String tableName,
    List<Map<String, dynamic>> lineData,
  ) async {
    try {
      final db = await _getDatabase();
      final batch = db.batch();
      final insertedIds = <int>[];

      // バッチでINSERT文を準備
      for (int i = 0; i < lineData.length; i++) {
        final data = lineData[i];
        final line = data['line'] as List<LatLng>;
        
        // WKBジオメトリを作成
        final wkb = createWkbLineString(line);
        
        // insertData を構築（lineを除く全ての属性を含める）
        final insertData = <String, dynamic>{'geom': wkb};
        
        // dataから全ての属性をコピー（lineは除外）
        data.forEach((key, value) {
          if (key != 'line') {
            insertData[key] = value;
          }
        });
        
        // カラム名とプレースホルダーを動的に生成
        final columns = insertData.keys.toList();
        final placeholders = List.filled(columns.length, '?').join(', ');
        final columnNames = columns.map((c) => '"$c"').join(', ');
        final values = columns.map((c) => insertData[c]).toList();
        
        // 動的INSERT文を実行
        batch.rawInsert(
          'INSERT INTO "$tableName" ($columnNames) VALUES ($placeholders)',
          values,
        );
      }

      // バッチ実行
      final results = await batch.commit(noResult: false);

      // 結果をrowIdリストに変換
      for (final result in results) {
        if (result is int) {
          insertedIds.add(result);
        }
      }

      return insertedIds;
    } catch (e) {
      print('[ERROR] GeoPackageFile.addLinesBatch: $e');
      return [];
    }
  }

  /// 指定レイヤーの全フィーチャの属性データを一括取得（属性テーブル表示用最適化）
  /// [tableName] テーブル名
  /// [columns] 取得するカラムのリスト（nullの場合は全カラムを取得）
  /// 戻り値: List<Map<String, dynamic>> - 各行の属性データ
  Future<List<Map<String, dynamic>>> getAllFeatureAttributes(
    String tableName, {
    List<String>? columns,
  }) async {
    try {
      final db = await _getDatabase();

      // カラム指定がある場合は指定されたカラムのみ、ない場合は全カラム
      final columnList = columns?.join(', ') ?? '*';

      print('[GeoPackageFile] 一括属性取得開始: $tableName, カラム: $columnList');

      final result = await db.rawQuery(
        'SELECT $columnList FROM "$tableName" ORDER BY id',
      );

      print('[GeoPackageFile] 一括属性取得完了: ${result.length}件');
      return result;
    } catch (e) {
      print('[GeoPackageFile] getAllFeatureAttributes エラー発生 - $e');
      return [];
    }
  }
}
