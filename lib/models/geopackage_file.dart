// K-MAPS: GeoPackageファイル管理クラス（最小構成）
// DB操作ラッパー。点レイヤのみ対応。
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:latlong2/latlong.dart';
import '../utils/wkb_utils.dart'; // WKBユーティリティをインポート
import 'package:path/path.dart' as p;
import '../utils/global_config.dart';

/// GeoPackageファイルを管理する最小クラス
class GeoPackageFile {
  /// ルートからのパスリスト
  final List<String> pathList;

  /// サポートする属性カラム名リスト（属性テーブルで表示するカラム）
  final List<String> supportedAttributes = [
    "id",
    "geom",
    "name",
    "description",
  ];

  /// コンストラクタ
  /// pathList: ルートからのサブディレクトリ＋ファイル名のリスト
  GeoPackageFile(this.pathList) {
    createIfNotExists();
  }

  /// ファイルがなければGeoPackageファイルを新規作成（OGC仕様準拠、最小構成）
  void createIfNotExists() {
    final baseDir = GlobalConfig.instance.projectRootDir;
    if (baseDir == null) {
      print('GeoPackageファイル作成失敗: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([baseDir, ...pathList]);
    final file = File(absPath);
    final dir = file.parent;
    if (!file.existsSync()) {
      if (!dir.existsSync()) {
        print('GeoPackageファイル作成失敗: 親ディレクトリが存在しません (${dir.path})');
        return;
      }
      try {
        // GeoPackage初期化SQL（OGC仕様準拠、最小構成）
        final db = sql.sqlite3.open(absPath);
        db.execute('''
          CREATE TABLE gpkg_spatial_ref_sys (
            srs_name TEXT NOT NULL,
            srs_id INTEGER NOT NULL PRIMARY KEY,
            organization TEXT NOT NULL,
            organization_coordsys_id INTEGER NOT NULL,
            definition  TEXT NOT NULL,
            description TEXT
          );
        ''');
        db.execute('''
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
        db.execute('''
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
        db.execute('''
          INSERT INTO gpkg_spatial_ref_sys (srs_name, srs_id, organization, organization_coordsys_id, definition, description) VALUES
          ('WGS 84 geodetic', 4326, 'EPSG', 4326, 'GEOGCS["WGS 84",DATUM["WGS_1984",SPHEROID["WGS 84",6378137,298.257223563]],PRIMEM["Greenwich",0],UNIT["degree",0.0174532925199433]]', 'longitude/latitude coordinates in decimal degrees on the WGS 84 spheroid'),
          ('Undefined geographic SRS', 0, 'NONE', 0, 'undefined', 'undefined geographic coordinate reference system'),
          ('Undefined cartesian SRS', -1, 'NONE', -1, 'undefined', 'undefined cartesian coordinate reference system');
        ''');
        db.dispose();
      } catch (e, stack) {
        print('GeoPackageファイル作成時にエラー発生:');
        print(e);
        print(stack);
      }
    }
  }

  /// DBからレイヤ（フィーチャテーブル）名一覧を取得
  List<String> getLayerNames() {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('getLayerNames: projectRootDirが未設定');
      return [];
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final contents = db.select(
      'SELECT table_name FROM gpkg_contents WHERE data_type = "features"',
    );
    final tableNames =
        contents.map((row) => row['table_name'] as String).toList();
    db.dispose();
    return tableNames;
  }

  /// DBから指定レイヤの点フィーチャ一覧を取得
  List<LatLng> getPoints(String tableName) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('getPoints: projectRootDirが未設定');
      return [];
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final rows = db.select('SELECT geom FROM "$tableName"');
    final points = <LatLng>[];
    for (final r in rows) {
      final geom = r['geom'] as Uint8List;
      if (geom.length >= 21 && geom[0] == 1 && geom[1] == 1) {
        final lon = ByteData.sublistView(
          geom,
          5,
          13,
        ).getFloat64(0, Endian.little);
        final lat = ByteData.sublistView(
          geom,
          13,
          21,
        ).getFloat64(0, Endian.little);
        points.add(LatLng(lat, lon));
      }
    }
    db.dispose();
    return points;
  }

  /// 点フィーチャを追加（属性付き）
  void addPoint(
    String tableName,
    LatLng pt, {
    String name = '',
    String description = '',
  }) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('addPoint: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final wkb = createWkbPoint(pt.longitude, pt.latitude);
    db.execute(
      'INSERT INTO "$tableName" (geom, name, description) VALUES (?, ?, ?);',
      [wkb, name, description],
    );
    db.dispose();
  }

  /// 指定座標の点フィーチャを削除
  void removePoint(String tableName, LatLng pt) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('removePoint: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final wkb = createWkbPoint(pt.longitude, pt.latitude);
    db.execute('DELETE FROM "$tableName" WHERE geom = ?;', [wkb]);
    db.dispose();
  }

  /// 指定レイヤのジオメトリタイプ（POINT/LINESTRING/POLYGON等）を取得
  String? getGeometryType(String tableName) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('getGeometryType: projectRootDirが未設定');
      return null;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    // テーブル存在チェック
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='gpkg_geometry_columns'",
    );
    if (tables.isEmpty) {
      print('[WARN] gpkg_geometry_columnsテーブルが存在しません: $absPath');
      db.dispose();
      return null;
    }
    final rows = db.select(
      'SELECT geometry_type_name FROM gpkg_geometry_columns WHERE table_name = ?',
      [tableName],
    );
    db.dispose();
    if (rows.isEmpty) return null;
    return rows.first['geometry_type_name'] as String?;
  }

  /// 指定レイヤの全フィーチャ（点・線・面すべて対応、属性も取得）
  List<Map<String, dynamic>> getFeatures(String tableName) {
    // name/descriptionカラムがなければ自動追加
    ensureNameDescriptionColumns(tableName);
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('getFeatures: projectRootDirが未設定');
      return [];
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    // テーブル存在チェック
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='gpkg_geometry_columns'",
    );
    if (tables.isEmpty) {
      print('[WARN] gpkg_geometry_columnsテーブルが存在しません: $absPath');
      db.dispose();
      return [];
    }
    final typeRows = db.select(
      'SELECT geometry_type_name FROM gpkg_geometry_columns WHERE table_name = ?',
      [tableName],
    );
    final geomType =
        typeRows.isNotEmpty
            ? (typeRows.first['geometry_type_name'] as String).toUpperCase()
            : '';
    final rows = db.select(
      'SELECT id, geom, name, description FROM "$tableName"',
    );
    final features = <Map<String, dynamic>>[];
    for (final r in rows) {
      final id = r['id'] as int? ?? 0;
      final geom = r['geom'] as Uint8List;
      final name = r['name'] as String? ?? '';
      final description = r['description'] as String? ?? '';
      if (geomType == 'MULTIPOINT' || geomType == 'POINT') {
        if (geom.length >= 21 && geom[0] == 1 && geom[1] == 1) {
          final lon = ByteData.sublistView(
            geom,
            5,
            13,
          ).getFloat64(0, Endian.little);
          final lat = ByteData.sublistView(
            geom,
            13,
            21,
          ).getFloat64(0, Endian.little);
          features.add({
            'id': id,
            'points': [LatLng(lat, lon)],
            'name': name,
            'description': description,
          });
        }
      } else if (geomType == 'MULTILINESTRING' || geomType == 'LINESTRING') {
        final lines = parseWkbLineString(geom);
        if (lines.isNotEmpty) {
          features.add({
            'id': id,
            'lines': lines,
            'name': name,
            'description': description,
          });
        }
      } else if (geomType == 'MULTIPOLYGON' || geomType == 'POLYGON') {
        final polygons = parseWkbPolygon(geom);
        if (polygons.isNotEmpty) {
          features.add({
            'id': id,
            'polygons': polygons,
            'name': name,
            'description': description,
          });
        }
      }
    }
    db.dispose();
    return features;
  }

  /// レイヤ追加（DBにテーブル作成）
  void addLayer(String name, String geomType) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('addLayer: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    db.execute('''
      CREATE TABLE IF NOT EXISTS "$name" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        geom BLOB NOT NULL,
        name TEXT,
        description TEXT
      );
    ''');
    db.execute(
      '''
      INSERT OR IGNORE INTO gpkg_contents (table_name, data_type, identifier, description, srs_id)
      VALUES (?, 'features', ?, '', 4326);
      ''',
      [name, name],
    );
    db.execute(
      '''
      INSERT OR IGNORE INTO gpkg_geometry_columns (table_name, column_name, geometry_type_name, srs_id, z, m)
      VALUES (?, 'geom', ?, 4326, 0, 0);
      ''',
      [name, geomType],
    );
    db.dispose();
  }

  /// レイヤ削除（DBからテーブル・メタ情報削除）
  void removeLayer(String name) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('removeLayer: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    db.execute('DROP TABLE IF EXISTS "$name";');
    db.execute('DELETE FROM gpkg_contents WHERE table_name = ?;', [name]);
    db.execute('DELETE FROM gpkg_geometry_columns WHERE table_name = ?;', [
      name,
    ]);
    db.dispose();
  }

  /// 線フィーチャを追加（属性付き）
  void addLine(
    String tableName,
    List<LatLng> line, {
    String name = '',
    String description = '',
  }) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('addLine: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final wkb = createWkbLineString(line);
    db.execute(
      'INSERT INTO "$tableName" (geom, name, description) VALUES (?, ?, ?);',
      [wkb, name, description],
    );
    db.dispose();
  }

  /// ポリゴンフィーチャを追加（属性付き、外環＋穴リスト対応）
  void addPolygon(
    String tableName,
    List<List<LatLng>> rings, {
    String name = '',
    String description = '',
  }) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('addPolygon: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final wkb = createWkbPolygon(rings);
    db.execute(
      'INSERT INTO "$tableName" (geom, name, description) VALUES (?, ?, ?);',
      [wkb, name, description],
    );
    db.dispose();
  }

  /// 指定テーブルのカラム名一覧を返す（getAll=trueなら全カラム、falseならsupportedAttributesのみ）
  List<String> getColumnNames(String tableName, {bool getAll = false}) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('getColumnNames: projectRootDirが未設定');
      return [];
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final result = db.select('PRAGMA table_info("$tableName");');
    final columns = result.map((row) => row['name'] as String).toList();
    db.dispose();
    if (getAll) return columns;
    // supportedAttributesに含まれるものだけ返す
    return columns.where((c) => supportedAttributes.contains(c)).toList();
  }

  /// 指定テーブル・rowId・カラム名から値を取得
  dynamic getFeatureAttribute(
    String tableName,
    int rowId,
    String attributeName,
  ) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('getFeatureAttribute: projectRootDirが未設定');
      return null;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    try {
      final result = db.select(
        'SELECT "$attributeName" FROM "$tableName" WHERE id = ?;',
        [rowId],
      );
      if (result.isNotEmpty) {
        return result.first[attributeName];
      }
      return null;
    } finally {
      db.dispose();
    }
  }

  /// 指定テーブル・rowId・カラム名の属性値を更新
  void updateFeatureAttribute(
    String tableName,
    int rowId,
    String attributeName,
    dynamic newValue,
  ) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('updateFeatureAttribute: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    try {
      db.execute('UPDATE "$tableName" SET "$attributeName" = ? WHERE id = ?;', [
        newValue,
        rowId,
      ]);
    } finally {
      db.dispose();
    }
  }

  /// レイヤのカラム追加（name/descriptionがなければ追加）
  void ensureNameDescriptionColumns(String tableName) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) return;
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    final result = db.select('PRAGMA table_info("$tableName");');
    final columns = result.map((row) => row['name'] as String).toList();
    if (!columns.contains('name')) {
      db.execute('ALTER TABLE "$tableName" ADD COLUMN name TEXT;');
    }
    if (!columns.contains('description')) {
      db.execute('ALTER TABLE "$tableName" ADD COLUMN description TEXT;');
    }
    db.dispose();
  }

  /// 線フィーチャをidで削除
  void removeLine(String tableName, int id) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('removeLine: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    db.execute('DELETE FROM "$tableName" WHERE id = ?;', [id]);
    db.dispose();
  }

  /// ポリゴンフィーチャをidで削除
  void removePolygon(String tableName, int id) {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) {
      print('removePolygon: projectRootDirが未設定');
      return;
    }
    final absPath = p.joinAll([root, ...pathList]);
    final db = sql.sqlite3.open(absPath);
    db.execute('DELETE FROM "$tableName" WHERE id = ?;', [id]);
    db.dispose();
  }
}
