// K-MAPS: GeoPackageファイル管理クラス（sqflite移行版）
// DB操作ラッパー。段階的移行により非同期処理へ対応。点・線・面レイヤ対応。
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert'; // JSON処理のため追加
import 'dart:async';
import 'package:k_maps/utils/app_logger.dart';
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
/// 
/// PRIMARY KEY戦略:
/// - 新規作成: fid INTEGER PRIMARY KEY AUTOINCREMENT（QGIS互換）
/// - 読み込み: 動的検出（fid, id, rowid等）して内部的に'id'として正規化
/// - FeatureNode互換性: row['id']で常にPRIMARY KEYにアクセス可能
class GeoPackageFile {
  /// ルートからのパスリスト
  final List<String> pathList;

  /// データベース接続インスタンス
  Database? _database;

  /// データベース初期化完了フラグ
  bool _isInitialized = false;

  /// PRIMARY KEYカラム名のキャッシュ（テーブル名 → PRIMARY KEYカラム名）
  final Map<String, String> _primaryKeyCache = {};

  /// サポートする属性カラム名リスト（属性テーブルで表示するカラム）
  /// 内部正規化により、PRIMARY KEY（fid, id等）は常に'id'として扱われる
  /// geom はジオメトリカラムで属性データではないため除外
  final List<String> supportedAttributes = [
    "id", // 内部的にPRIMARY KEYを正規化したもの（実テーブルではfid等）
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
      final db = await _getDatabase();
      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // SQLiteでサポートされていない型を除外
      final filteredAttributes = <String, dynamic>{};
      for (final entry in attributes.entries) {
        final key = entry.key;
        final value = entry.value;
        
        // ジオメトリ関連フィールドとPRIMARY KEYフィールドは属性更新対象から除外
        if (key == 'geometry' || key == 'geom' || key == pkColumn) {
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
          AppLogger.debug('[GeoPackageFile] ⚠️ サポートされていない型: $key = ${value.runtimeType}');
        }
      }
      
      if (filteredAttributes.isEmpty) {
        return true; // 更新対象がない場合は成功とみなす
      }
      
      // テーブル名をエスケープしてUPDATE文を実行
      final columnAssignments = filteredAttributes.keys
          .map((key) => '"$key" = ?')
          .join(', ');
      final values = [...filteredAttributes.values, rowId];
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
      final sql = 'UPDATE "$tableName" SET $columnAssignments WHERE $whereClause';
      final rowsUpdated = await db.rawUpdate(sql, values);
      
      return rowsUpdated > 0;
    } catch (e) {
      AppLogger.debug('[ERROR] GeoPackageFile: _updateFeatureAttributes failed: $e');
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
        AppLogger.debug('[GeoPackageFile] 警告: 無効なWKBデータが生成されました');
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
      AppLogger.debug('[ERROR] GeoPackageFile: addPointWithAttributes failed: $e');
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
      AppLogger.debug('[ERROR] GeoPackageFile: addLineWithAttributes failed: $e');
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
      AppLogger.debug('[ERROR] GeoPackageFile: addPolygonWithAttributes failed: $e');
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
      AppLogger.debug('[GeoPackageFile] 初期化失敗: projectRootDirが未設定');
      return;
    }

    final absPath = p.joinAll([baseDir, ...pathList]);

    final file = File(absPath);
    final dir = file.parent;

    if (!dir.existsSync()) {
      AppLogger.debug('[GeoPackageFile] 親ディレクトリを作成: ${dir.path}');
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        AppLogger.debug('[GeoPackageFile] 初期化失敗: 親ディレクトリ作成エラー - $e');
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
      
      // GeoPackageファイルの基本構造をチェック
      await _validateGeoPackageStructure();
      
      _isInitialized = true;
      // 正常時のログは不要（異常時のみ出力）
    } catch (e, stack) {
      AppLogger.debug('[GeoPackageFile] 初期化時にエラー発生:');
      AppLogger.debug('  パス: $absPath');
      AppLogger.debug('  エラー: $e');
      AppLogger.debug('  スタックトレース: $stack');

      try {
        final dirWritable = await Directory(dir.path).stat();
        AppLogger.debug('  親ディレクトリ情報: ${dirWritable.type}');
      } catch (dirError) {
        AppLogger.debug('  親ディレクトリアクセスエラー: $dirError');
      }
    }
  }

  /// GeoPackageファイルの基本構造を検証
  /// K-MAPS標準形式かどうかをチェックし、問題があればログを出力
  Future<void> _validateGeoPackageStructure() async {
    if (_database == null) return;

    try {
      // 必須テーブルの存在チェック
      final tables = await _database!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table';",
      );
      final tableNames = tables.map((row) => row['name'] as String).toSet();

      // GeoPackage標準の必須テーブル
      final requiredTables = {
        'gpkg_contents',
        'gpkg_spatial_ref_sys',
        'gpkg_geometry_columns',
      };

      final missingTables = requiredTables.difference(tableNames);
      
      if (missingTables.isNotEmpty) {
        AppLogger.debug('[GeoPackageFile] ⚠️ 警告: GeoPackage標準テーブルが不足しています: $missingTables');
        AppLogger.debug('[GeoPackageFile] ⚠️ これはK-MAPS標準形式ではない可能性があります。');
        return; // 必須テーブルがない場合は以降のチェックをスキップ
      }

      // gpkg_contentsテーブルの構造チェック
      final contentsColumns = await _database!.rawQuery('PRAGMA table_info("gpkg_contents");');
      final contentsColumnNames = contentsColumns.map((row) => row['name'] as String).toSet();
      
      final requiredContentsColumns = {
        'table_name',
        'data_type',
        'identifier',
        'srs_id',
      };

      final missingContentsColumns = requiredContentsColumns.difference(contentsColumnNames);
      
      if (missingContentsColumns.isNotEmpty) {
        AppLogger.debug('[GeoPackageFile] ⚠️ 警告: gpkg_contentsテーブルの構造が不正です。不足カラム: $missingContentsColumns');
        AppLogger.debug('[GeoPackageFile] ⚠️ このファイルは破損している可能性があります。');
      }

      // フィーチャテーブルの存在チェック（正常時はログ不要）
      // 異常がなければ検証完了
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] ⚠️ 警告: GeoPackage構造の検証中にエラーが発生しました: $e');
      AppLogger.debug('[GeoPackageFile] ⚠️ このファイルは標準的なGeoPackage形式ではない可能性があります。');
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
    // 正常なdisposeはログ不要
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
    AppLogger.debug('データベースをバージョン $oldVersion から $newVersion にアップグレード');
  }

  /// データベース接続取得（初期化を含む）
  Future<Database> _getDatabase() async {
    await _initializeDatabase();
    if (_database == null) {
      throw Exception('データベースの初期化に失敗しました');
    }
    return _database!;
  }

  /// PRIMARY KEYカラム名を動的に取得（キャッシュ機能付き）
  /// 
  /// K-MAPS標準形式（新規作成）: fid INTEGER PRIMARY KEY AUTOINCREMENT（QGIS互換）
  /// 旧K-MAPS形式: id INTEGER PRIMARY KEY AUTOINCREMENT（後方互換性のため対応）
  /// PRIMARY KEYがない外部ファイル: fid を自動追加、または rowid フォールバック
  Future<String> getPrimaryKeyColumn(String tableName) async {
    // キャッシュをチェック
    if (_primaryKeyCache.containsKey(tableName)) {
      return _primaryKeyCache[tableName]!;
    }

    final db = await _getDatabase();
    
    // PRAGMA table_infoでカラム情報を取得
    final columns = await db.rawQuery('PRAGMA table_info("$tableName");');
    
    // PRIMARY KEYカラムを検索（pk列が1のもの）
    String? primaryKeyColumn;
    for (final column in columns) {
      final pk = column['pk'] as int?;
      if (pk != null && pk > 0) {
        primaryKeyColumn = column['name'] as String;
        break;
      }
    }

    // PRIMARY KEYが見つかった場合
    if (primaryKeyColumn != null) {
      // QGIS標準形式（fid PRIMARY KEY）以外の場合は情報ログ出力
      if (primaryKeyColumn != 'fid') {
        if (primaryKeyColumn == 'id') {
          AppLogger.debug('[GeoPackageFile] ℹ️ 旧形式PRIMARY KEY検出: テーブル "$tableName" は "id" を使用（現在のK-MAPS標準は "fid"）');
        } else {
          AppLogger.debug('[GeoPackageFile] ℹ️ 非標準PRIMARY KEY検出: テーブル "$tableName" は "$primaryKeyColumn" を使用');
        }
      }
      _primaryKeyCache[tableName] = primaryKeyColumn;
      return primaryKeyColumn;
    }

    // PRIMARY KEYがない場合の処理
    AppLogger.debug('[GeoPackageFile] ⚠️ 警告: テーブル "$tableName" にPRIMARY KEYが見つかりません！');
    AppLogger.debug('[GeoPackageFile] ⚠️ データが破損している可能性があります。');
    
    try {
      // テーブルのレコード数をチェック（大きなテーブルの進行状況表示のため）
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM "$tableName";');
      final rowCount = countResult.first['count'] as int? ?? 0;
      
      // fid または id カラムが既に存在するかチェック
      final hasFidColumn = columns.any((col) => col['name'] == 'fid');
      final hasIdColumn = columns.any((col) => col['name'] == 'id');
      
      // QGIS互換性のため、fid カラムを優先的に使用・追加
      if (!hasFidColumn && !hasIdColumn) {
        // 大容量テーブルの場合は進行状況を表示
        if (rowCount > 10000) {
          AppLogger.debug('[GeoPackageFile] 🔧 fidカラムを自動追加します（$rowCount行のデータ、処理に時間がかかる場合があります）...');
        } else {
          AppLogger.debug('[GeoPackageFile] 🔧 fidカラムを自動追加します（$rowCount行のデータ）...');
        }
        
        // fidカラムを追加（QGIS標準）
        await db.execute(
          'ALTER TABLE "$tableName" ADD COLUMN fid INTEGER;',
        );
        
        // rowidから値をコピー（大きなテーブルでは時間がかかる）
        await db.execute(
          'UPDATE "$tableName" SET fid = rowid;',
        );
        
        AppLogger.debug('[GeoPackageFile] ✓ fidカラムを追加し、rowidから値をコピーしました。');
        _primaryKeyCache[tableName] = 'fid';
        return 'fid';
      } else if (hasFidColumn) {
        // fidカラムは存在するが、PRIMARY KEYではない場合
        AppLogger.debug('[GeoPackageFile] ℹ️ fidカラムは存在しますが、PRIMARY KEYとして定義されていません。');
        _primaryKeyCache[tableName] = 'fid';
        return 'fid';
      } else {
        // idカラムが存在する場合（旧形式）
        AppLogger.debug('[GeoPackageFile] ℹ️ idカラムは存在しますが、PRIMARY KEYとして定義されていません。');
        _primaryKeyCache[tableName] = 'id';
        return 'id';
      }
    } catch (e, stackTrace) {
      AppLogger.debug('[GeoPackageFile] ❌ エラー: PRIMARY KEY処理中に問題が発生しました: $e');
      AppLogger.debug('[GeoPackageFile] スタックトレース: $stackTrace');
      
      // フォールバック: fid > id > rowid の優先順位
      final hasFidColumn = columns.any((col) => col['name'] == 'fid');
      final hasIdColumn = columns.any((col) => col['name'] == 'id');
      
      if (hasFidColumn) {
        _primaryKeyCache[tableName] = 'fid';
        return 'fid';
      } else if (hasIdColumn) {
        _primaryKeyCache[tableName] = 'id';
        return 'id';
      } else {
        AppLogger.debug('[GeoPackageFile] ⚠️ 緊急フォールバック: rowidを使用します。このファイルは読み込み専用としてのみ使用してください。');
        _primaryKeyCache[tableName] = 'rowid';
        return 'rowid';
      }
    }
  }

  /// 空のGeoPackageファイルを明示的に作成（即座に初期化）
  /// GeoPackageNode作成時に呼び出す
  Future<bool> createEmptyDatabase() async {
    try {
      await _initializeDatabase();
      if (_database != null && _isInitialized) {
        return true;
      } else {
        AppLogger.debug('[GeoPackageFile] 空のGeoPackageファイル作成失敗: 初期化未完了');
        return false;
      }
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] 空のGeoPackageファイル作成エラー: $e');
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
      AppLogger.debug('[ERROR] GeoPackageFile: addPoint failed: $e');
      return null;
    }
  }

  /// 指定IDのフィーチャを削除
  Future<void> removeFeature(String tableName, int id) async {
    try {
      final db = await _getDatabase();
      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
      await db.delete(tableName, where: whereClause, whereArgs: [id]);
    } catch (e) {
      AppLogger.debug('removeFeature: エラー発生 - $e');
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
      AppLogger.debug('getGeometryType: エラー発生 - $e');
      return null;
    }
  }

  /// 単一フィーチャを取得（geom列をgeometry typeに応じて変換）
  /// PRIMARY KEYカラム（fid, id, rowid等）の値を内部的に'id'として正規化
  /// これにより、FeatureNodeは常にrow['id']でPRIMARY KEYにアクセスできる
  Future<Map<String, dynamic>?> getFeature(String tableName, int rowId) async {
    try {
      final db = await _getDatabase();
      final geomType = await getGeometryType(tableName);
      final pkColumn = await getPrimaryKeyColumn(tableName);

      // rowidを使用する場合は明示的にSELECTに含める
      final selectClause = pkColumn == 'rowid'
          ? 'SELECT rowid, * FROM "$tableName" WHERE rowid = ?'
          : 'SELECT * FROM "$tableName" WHERE "$pkColumn" = ?';
      
      final rows = await db.rawQuery(selectClause, [rowId]);

      if (rows.isEmpty) return null;

      final row = Map<String, dynamic>.from(rows.first);
      
      // PRIMARY KEYカラムが'id'以外の場合、必ず正規化が必要
      // FeatureNodeのコンストラクタは常にrow['id']を参照するため
      if (pkColumn != 'id') {
        if (row.containsKey(pkColumn)) {
          row['id'] = row[pkColumn];
        } else {
          // PRIMARY KEYカラムが存在しない場合（異常事態）
          AppLogger.debug('[GeoPackageFile] ⚠️ 警告: PRIMARY KEYカラム "$pkColumn" が見つかりません！');
          row['id'] = 0; // フォールバック値
        }
      }
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
            
            // 座標値の妥当性チェック
            if (lat >= -90.0 && lat <= 90.0 && 
                lon >= -180.0 && lon <= 180.0 &&
                !lat.isNaN && !lon.isNaN &&
                !lat.isInfinite && !lon.isInfinite) {
              row['geometry'] = [LatLng(lat, lon)];
            } else {
              AppLogger.debug('[GeoPackageFile] ⚠️ 警告: 無効なPoint座標値を検出: lat=$lat, lon=$lon (rowId=$rowId)');
              AppLogger.debug('[GeoPackageFile] ⚠️ このフィーチャは破損している可能性があります。');
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

      // kmaps_metadataをパース
      final metadataStr = row['kmaps_metadata'] as String?;
      if (metadataStr != null && metadataStr.isNotEmpty) {
        try {
          row['kmaps_metadata'] =
              jsonDecode(metadataStr) as Map<String, dynamic>;
        } catch (e) {
          AppLogger.debug('getFeature: メタデータのJSONパースエラー - $e');
        }
      }

      return row;
    } catch (e) {
      AppLogger.debug('getFeature: エラー発生 - $e');
      return null;
    }
  }

  /// 指定レイヤの全フィーチャ（rawデータを取得し、内部形式に正規化）
  /// PRIMARY KEYカラム（fid, id, rowid等）の値を内部的に'id'として正規化
  /// これにより、FeatureNodeは常にrow['id']でPRIMARY KEYにアクセスできる
  Future<List<Map<String, dynamic>>> getFeatures(String tableName) async {
    try {
      final db = await _getDatabase();
      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidを使用する場合は明示的にSELECTに含める
      final selectClause = pkColumn == 'rowid' 
          ? 'SELECT rowid, * FROM "$tableName"' 
          : 'SELECT * FROM "$tableName"';
      
      final rows = await db.rawQuery(selectClause);

      // すべてのケースで正規化処理を実行（一貫性のため）
      return rows.map((row) {
        final normalizedRow = Map<String, dynamic>.from(row);
        
        // PRIMARY KEYカラムが'id'以外の場合、必ず正規化が必要
        // FeatureNodeのコンストラクタは常にrow['id']を参照するため
        if (pkColumn != 'id') {
          if (row.containsKey(pkColumn)) {
            normalizedRow['id'] = row[pkColumn];
          } else {
            // PRIMARY KEYカラムが存在しない場合（異常事態）
            AppLogger.debug('[GeoPackageFile] ⚠️ 警告: PRIMARY KEYカラム "$pkColumn" が見つかりません！');
            normalizedRow['id'] = 0; // フォールバック値
          }
        }
        
        return normalizedRow;
      }).toList();
    } catch (e) {
      AppLogger.debug('getFeatures: エラー発生 - $e');
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
      AppLogger.debug('getLayerNames: エラー発生 - $e');
      return [];
    }
  }

  /// レイヤ追加（DBにテーブル作成）
  /// QGIS互換性のため、PRIMARY KEYは fid を使用
  Future<void> addLayer(String name, GeometryType geomType) async {
    try {
      final db = await _getDatabase();

      // フィーチャテーブル作成（必須カラムのみ：fid と geom）
      // QGIS標準に準拠して fid をPRIMARY KEYとして使用
      await db.execute('''
				CREATE TABLE IF NOT EXISTS "$name" (
					fid INTEGER PRIMARY KEY AUTOINCREMENT,
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
      AppLogger.debug('addLayer: エラー発生 - $e');
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
      AppLogger.debug('[ERROR] GeoPackageFile._createSpatialIndex: $e');
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

      // 正常時のログは不要（異常時のみ出力）
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] エンベロープ更新エラー: $e');
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
      AppLogger.debug('removeLayer: エラー発生 - $e');
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
  /// 注意: geom（ジオメトリ）は常に除外される
  Future<List<String>> getColumnNames(
    String tableName, {
    bool getAll = false,
  }) async {
    try {
      final db = await _getDatabase();
      final result = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columns = result.map((row) => row['name'] as String).toList();

      // geom は属性データではないため常に除外（idは表示する）
      final filteredColumns = columns.where((c) => c != 'geom').toList();

      if (getAll) return filteredColumns;
      // supportedAttributesに含まれるものだけ返す
      return filteredColumns.where((c) => supportedAttributes.contains(c)).toList();
    } catch (e) {
      AppLogger.debug('getColumnNames: エラー発生 - $e');
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
      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
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
      AppLogger.debug('getFeatureAttribute: エラー発生 - $e');
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
      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
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
      AppLogger.debug('getFeatureAttributes: エラー発生 - $e');
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
      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
      final rowsUpdated = await db.rawUpdate(
        'UPDATE "$tableName" SET "$attributeName" = ? WHERE $whereClause',
        [newValue, rowId],
      );
      return rowsUpdated > 0;
    } catch (e) {
      AppLogger.debug('updateFeatureAttribute: エラー発生 - $e');
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

      // カラム名の安全性チェック（QGIS準拠 - 日本語・スペース・数字始まりも許可）
      // SQLインジェクション対策として最小限の危険文字のみ禁止
      final sanitizedName = _sanitizeColumnName(columnName);
      if (sanitizedName.isEmpty) {
        throw Exception('無効なカラム名です: $columnName');
      }

      // 既存カラムのチェック
      final result = await db.rawQuery('PRAGMA table_info("$tableName");');
      final columns = result.map((row) => row['name'] as String).toList();

      if (!columns.contains(sanitizedName)) {
        await db.execute(
          'ALTER TABLE "$tableName" ADD COLUMN "$sanitizedName" $columnType;',
        );
      }
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] addAttributeColumn エラー発生 - $e');
      rethrow;
    }
  }

  /// カラム名をQGIS準拠でサニタイズ（SQLインジェクション対策）
  /// 日本語・スペース・数字始まりを許可、危険な文字のみ置換
  String _sanitizeColumnName(String name) {
    if (name.isEmpty) return '';
    // SQLインジェクションに使われる危険な文字を除去/置換
    return name
        .replaceAll('"', '')      // ダブルクォート
        .replaceAll("'", '')      // シングルクォート
        .replaceAll(';', '_')     // セミコロン
        .replaceAll('--', '_')    // SQLコメント
        .replaceAll('\n', ' ')    // 改行
        .replaceAll('\r', ' ')    // 復帰
        .trim();
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
      AppLogger.debug('[GeoPackageFile] addAttributeColumns エラー発生 - $e');
      rethrow;
    }
  }

  /// テーブルのカラム名リストを取得
  Future<List<String>> getTableColumns(String tableName) async {
    try {
      final db = await _getDatabase();
      final result = await db.rawQuery('PRAGMA table_info("$tableName");');
      return result.map((row) => row['name'] as String).toList();
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] getTableColumns エラー: $e');
      return [];
    }
  }

  /// レイヤー間でフィーチャをコピー（同一カラム構造が前提）
  /// [sourceTable] コピー元テーブル名
  /// [targetTable] コピー先テーブル名
  /// 戻り値: コピーされたフィーチャ数
  Future<int> copyFeaturesBetweenLayers(String sourceTable, String targetTable) async {
    try {
      final db = await _getDatabase();

      // ソーステーブルのカラムを取得（idとROWIDを除く）
      final sourceColumns = await getTableColumns(sourceTable);
      final columnsToInsert = sourceColumns
          .where((c) => c.toLowerCase() != 'id' && c.toLowerCase() != 'fid')
          .toList();

      if (columnsToInsert.isEmpty) {
        AppLogger.debug('[GeoPackageFile] コピー可能なカラムがありません');
        return 0;
      }

      // カラムリストを作成
      final columnList = columnsToInsert.map((c) => '"$c"').join(', ');

      // INSERT INTO ... SELECT文でフィーチャをコピー
      final sql = '''
        INSERT INTO "$targetTable" ($columnList)
        SELECT $columnList FROM "$sourceTable"
      ''';

      await db.execute(sql);

      // コピーされた行数を取得（INSERT後の変更行数）
      final countResult = await db.rawQuery('SELECT changes() as count');
      final copiedCount = (countResult.first['count'] as int?) ?? 0;

      AppLogger.debug('[GeoPackageFile] フィーチャコピー完了: $sourceTable -> $targetTable ($copiedCount件)');
      return copiedCount;
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] copyFeaturesBetweenLayers エラー: $e');
      return 0;
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
      AppLogger.debug('[GeoPackageFile] addFeatureWithAttributes エラー発生 - $e');
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
      AppLogger.debug('[GeoPackageFile] getAttributeColumnInfo エラー発生 - $e');
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
        AppLogger.debug('[GeoPackageFile] deleteFile: projectRootDirが未設定');
        return false;
      }

      final absPath = p.joinAll([baseDir, ...pathList]);
      final file = File(absPath);

      if (!file.existsSync()) {
        AppLogger.debug('[GeoPackageFile] deleteFile: ファイルが存在しません - $absPath');
        return true; // 既に存在しないので成功とみなす
      }

      await file.delete();
      AppLogger.debug('[GeoPackageFile] deleteFile: ファイル削除完了 - $absPath');
      return true;
    } catch (e, stack) {
      AppLogger.debug('[GeoPackageFile] deleteFile: ファイル削除エラー - $e');
      AppLogger.debug('スタックトレース: $stack');
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
        AppLogger.debug('[GeoPackageFile] 警告: 無効なWKBデータが生成されました');
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

      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug('updatePoint: エラー発生 - $e');
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

      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug('updateLine: エラー発生 - $e');
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

      final pkColumn = await getPrimaryKeyColumn(tableName);
      
      // rowidの場合はクォートなし、それ以外はクォート付き
      final whereClause = pkColumn == 'rowid' 
          ? 'rowid = ?' 
          : '"$pkColumn" = ?';
      
      final sql = 'UPDATE "$tableName" SET ${updateColumns.join(', ')} WHERE $whereClause';
      final affectedRows = await db.rawUpdate(sql, updateValues);

      return affectedRows > 0;
    } catch (e) {
      AppLogger.debug('updatePolygon: エラー発生 - $e');
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
    // 予約済みカラム名（INSERT時に除外する）
    const reservedColumns = {'fid', 'geom', 'id', 'rowid', 'geometry', 'rings'};
    
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
        
        // insertData を構築（予約済みカラムを除く全ての属性を含める）
        final insertData = <String, dynamic>{'geom': wkb};
        
        // dataから全ての属性をコピー（予約済みカラムは除外、カラム名をサニタイズ）
        data.forEach((key, value) {
          if (!reservedColumns.contains(key.toLowerCase())) {
            // カラム名をサニタイズ（addAttributeColumnと同じ処理）
            final sanitizedKey = _sanitizeColumnName(key);
            if (sanitizedKey.isNotEmpty) {
              insertData[sanitizedKey] = value;
            }
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
      AppLogger.debug('[ERROR] GeoPackageFile.addPolygonsBatch: $e');
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
    // 予約済みカラム名（INSERT時に除外する）
    const reservedColumns = {'fid', 'geom', 'id', 'rowid', 'geometry', 'point'};
    
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
        
        // insertData を構築（予約済みカラムを除く全ての属性を含める）
        final insertData = <String, dynamic>{'geom': wkb};
        
        // dataから全ての属性をコピー（予約済みカラムは除外、カラム名をサニタイズ）
        data.forEach((key, value) {
          if (!reservedColumns.contains(key.toLowerCase())) {
            // カラム名をサニタイズ（addAttributeColumnと同じ処理）
            final sanitizedKey = _sanitizeColumnName(key);
            if (sanitizedKey.isNotEmpty) {
              insertData[sanitizedKey] = value;
            }
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
      AppLogger.debug('[ERROR] GeoPackageFile.addPointsBatch: $e');
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
    // 予約済みカラム名（INSERT時に除外する）
    const reservedColumns = {'fid', 'geom', 'id', 'rowid', 'geometry', 'line'};
    
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
        
        // insertData を構築（予約済みカラムを除く全ての属性を含める）
        final insertData = <String, dynamic>{'geom': wkb};
        
        // dataから全ての属性をコピー（予約済みカラムは除外、カラム名をサニタイズ）
        data.forEach((key, value) {
          if (!reservedColumns.contains(key.toLowerCase())) {
            // カラム名をサニタイズ（addAttributeColumnと同じ処理）
            final sanitizedKey = _sanitizeColumnName(key);
            if (sanitizedKey.isNotEmpty) {
              insertData[sanitizedKey] = value;
            }
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
      AppLogger.debug('[ERROR] GeoPackageFile.addLinesBatch: $e');
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
      final pkColumn = await getPrimaryKeyColumn(tableName);

      // カラム指定がある場合は指定されたカラムのみ、ない場合は全カラム
      final columnList = columns?.join(', ') ?? '*';

      // ORDER BYで動的PRIMARY KEYカラムを使用
      // rowidの場合はクォートなし、それ以外はクォート付き
      final orderByClause = pkColumn == 'rowid' 
          ? 'ORDER BY rowid' 
          : 'ORDER BY "$pkColumn"';

      final result = await db.rawQuery(
        'SELECT $columnList FROM "$tableName" $orderByClause',
      );

      // 正常時のログは不要（異常時のみ出力）
      return result;
    } catch (e) {
      AppLogger.debug('[GeoPackageFile] getAllFeatureAttributes エラー発生 - $e');
      return [];
    }
  }
}

