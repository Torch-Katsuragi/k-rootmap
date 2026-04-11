// Root Maps: GeoPackage DB接続管理クラス
// DB接続の初期化、クローズ、バリデーションを担当
import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import '../../utils/app_logger.dart';
import '../../i18n/strings.g.dart';

/// GeoPackage DB接続を管理するクラス
/// 責務: DB接続の初期化、クローズ、構造検証
class GeoPackageConnection {
  /// ルートからのパスリスト
  final List<String> pathList;

  /// 絶対パス（指定時はpathListを無視）
  /// グローバルフォルダ内のGeoPackageで使用
  final String? absolutePath;

  /// プロジェクトルートディレクトリ（相対パスモード時に使用）
  final String? projectRootDir;

  /// データベース接続インスタンス
  Database? _database;

  /// 初期化の排他制御用Completer（進行中のみ非null）
  Completer<void>? _initCompleter;

  /// データベース初期化完了フラグ
  bool _isInitialized = false;

  /// 初期化完了かどうか
  bool get isInitialized => _isInitialized;

  /// コンストラクタ
  GeoPackageConnection(this.pathList, {this.absolutePath, this.projectRootDir});

  /// データベース接続取得（初期化を含む）
  Future<Database> getDatabase() async {
    await _initializeDatabase();
    if (_database == null) {
      throw Exception(t.services.dbInitFailed);
    }
    return _database!;
  }

  /// データベース初期化（遅延初期化・Completerで二重実行防止）
  Future<void> _initializeDatabase() async {
    if (_isInitialized && _database != null) {
      return;
    }

    // 別の呼び出しが初期化中なら、その完了を待つ
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      await _initializeDatabaseImpl();
      _initCompleter!.complete();
    } catch (e, stack) {
      _initCompleter!.completeError(e, stack);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// データベース初期化の実体
  Future<void> _initializeDatabaseImpl() async {

    // 絶対パスが指定されている場合はそれを使用（グローバルフォルダ用）
    final String absPath;
    if (absolutePath != null) {
      absPath = absolutePath!;
    } else {
      if (projectRootDir == null) {
        AppLogger.debug('[GeoPackageConnection] 初期化失敗: projectRootDirが未設定');
        return;
      }
      absPath = p.joinAll([projectRootDir!, ...pathList]);
    }

    final file = File(absPath);
    final dir = file.parent;

    if (!dir.existsSync()) {
      AppLogger.debug('[GeoPackageConnection] 親ディレクトリを作成: ${dir.path}');
      try {
        dir.createSync(recursive: true);
      } catch (e) {
        AppLogger.debug('[GeoPackageConnection] 初期化失敗: 親ディレクトリ作成エラー - $e');
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
    } catch (e, stack) {
      AppLogger.debug('[GeoPackageConnection] 初期化時にエラー発生:');
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
    AppLogger.debug('データベースをバージョン $oldVersion から $newVersion にアップグレード');
  }

  /// GeoPackageファイルの基本構造を検証
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
        AppLogger.debug('[GeoPackageConnection] ⚠️ 警告: GeoPackage標準テーブルが不足しています: $missingTables');
        AppLogger.debug('[GeoPackageConnection] ⚠️ これはRoot Maps標準形式ではない可能性があります。');
        return;
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
        AppLogger.debug('[GeoPackageConnection] ⚠️ 警告: gpkg_contentsテーブルの構造が不正です。不足カラム: $missingContentsColumns');
        AppLogger.debug('[GeoPackageConnection] ⚠️ このファイルは破損している可能性があります。');
      }
    } catch (e) {
      AppLogger.debug('[GeoPackageConnection] ⚠️ 警告: GeoPackage構造の検証中にエラーが発生しました: $e');
      AppLogger.debug('[GeoPackageConnection] ⚠️ このファイルは標準的なGeoPackage形式ではない可能性があります。');
    }
  }

  /// 空のGeoPackageファイルを明示的に作成（即座に初期化）
  Future<bool> createEmptyDatabase() async {
    try {
      await _initializeDatabase();
      if (_database != null && _isInitialized) {
        return true;
      } else {
        AppLogger.debug('[GeoPackageConnection] 空のGeoPackageファイル作成失敗: 初期化未完了');
        return false;
      }
    } catch (e) {
      AppLogger.debug('[GeoPackageConnection] 空のGeoPackageファイル作成エラー: $e');
      return false;
    }
  }

  /// データベースのクローズ処理
  Future<void> dispose() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    _isInitialized = false;
    _initCompleter = null;
  }

  /// ファイル自体を削除（物理削除）
  Future<bool> deleteFile() async {
    try {
      // まずデータベース接続を閉じる
      await dispose();

      // 絶対パスが指定されている場合はそれを使用（グローバルフォルダ用）
      final String absPath;
      if (absolutePath != null) {
        absPath = absolutePath!;
      } else {
        if (projectRootDir == null) {
          AppLogger.debug('[GeoPackageConnection] deleteFile: projectRootDirが未設定');
          return false;
        }
        absPath = p.joinAll([projectRootDir!, ...pathList]);
      }
      final file = File(absPath);

      if (!file.existsSync()) {
        AppLogger.debug('[GeoPackageConnection] deleteFile: ファイルが存在しません - $absPath');
        return true; // 既に存在しないので成功とみなす
      }

      await file.delete();
      AppLogger.debug('[GeoPackageConnection] deleteFile: ファイル削除完了 - $absPath');
      return true;
    } catch (e, stack) {
      AppLogger.debug('[GeoPackageConnection] deleteFile: ファイル削除エラー - $e');
      AppLogger.debug('スタックトレース: $stack');
      return false;
    }
  }
}

