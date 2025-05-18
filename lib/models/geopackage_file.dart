// K-MAPS: GeoPackageファイル管理クラス（最小構成）
// DB操作ラッパー。点レイヤのみ対応。
import 'dart:io';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:latlong2/latlong.dart';
import '../utils/wkb_utils.dart'; // WKBユーティリティをインポート
import 'layer.dart';

/// GeoPackageファイルを管理する最小クラス
class GeoPackageFile {
  /// GeoPackageファイルの絶対パス
  final String path;

  /// コンストラクタ
  /// 指定パスにGeoPackageファイルが存在しない場合、親ディレクトリが存在すれば最小構成で新規作成を試みる。
  GeoPackageFile(this.path) {
    final file = File(path);
    if (!file.existsSync()) {
      final dir = file.parent;
      if (dir.existsSync()) {
        // GeoPackage初期化SQL（OGC仕様準拠、最小構成）
        final db = sql.sqlite3.open(path);
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
      }
    }
  }

  /// DBからレイヤ（フィーチャテーブル）名一覧を取得
  List<String> getLayerNames() {
    final db = sql.sqlite3.open(path);
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
    final db = sql.sqlite3.open(path);
    final rows = db.select('SELECT geom FROM "$tableName"');
    final points = <LatLng>[];
    for (final r in rows) {
      final geom = r['geom'] as Uint8List;
      // WKBユーティリティでデコード
      if (geom.length >= 21 && geom[0] == 1 && geom[1] == 1) {
        // 旧実装: 手書きデコード
        // 新実装: createWkbPointはエンコード用なので、ここはparseWkbLineString等を使う
        // ただし点は専用デコードがないので直接デコード
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
  void addPoint(String tableName, LatLng pt, [String attr = '']) {
    final db = sql.sqlite3.open(path);
    // WKBユーティリティでエンコード
    final wkb = createWkbPoint(pt.longitude, pt.latitude);
    db.execute('INSERT INTO "$tableName" (geom, attr) VALUES (?, ?);', [
      wkb,
      attr,
    ]);
    db.dispose();
  }

  /// 指定座標の点フィーチャを削除
  void removePoint(String tableName, LatLng pt) {
    final db = sql.sqlite3.open(path);
    // WKBユーティリティでエンコード
    final wkb = createWkbPoint(pt.longitude, pt.latitude);
    db.execute('DELETE FROM "$tableName" WHERE geom = ?;', [wkb]);
    db.dispose();
  }

  /// 指定レイヤのジオメトリタイプ（POINT/LINESTRING/POLYGON等）を取得
  String? getGeometryType(String tableName) {
    final db = sql.sqlite3.open(path);
    final rows = db.select(
      'SELECT geometry_type_name FROM gpkg_geometry_columns WHERE table_name = ?',
      [tableName],
    );
    db.dispose();
    if (rows.isEmpty) return null;
    return rows.first['geometry_type_name'] as String?;
  }

  /// 指定レイヤの全フィーチャ（点のみ対応、属性も取得）
  List<Feature> getFeatures(String tableName) {
    final db = sql.sqlite3.open(path);
    final rows = db.select('SELECT geom, attr FROM "$tableName"');
    final features = <Feature>[];
    for (final r in rows) {
      final geom = r['geom'] as Uint8List;
      final attr = r['attr'] as String? ?? '';
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
        features.add(MultiPointFeature([LatLng(lat, lon)], attr));
      }
    }
    db.dispose();
    return features;
  }

  /// レイヤ追加（DBにテーブル作成）
  void addLayer(String name, String geomType) {
    final db = sql.sqlite3.open(path);
    db.execute('''
      CREATE TABLE IF NOT EXISTS "$name" (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        geom BLOB NOT NULL,
        attr TEXT
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
    final db = sql.sqlite3.open(path);
    db.execute('DROP TABLE IF EXISTS "$name";');
    db.execute('DELETE FROM gpkg_contents WHERE table_name = ?;', [name]);
    db.execute('DELETE FROM gpkg_geometry_columns WHERE table_name = ?;', [
      name,
    ]);
    db.dispose();
  }

  /// 線フィーチャを追加（属性付き）
  void addLine(String tableName, List<LatLng> line, [String attr = '']) {
    final db = sql.sqlite3.open(path);
    // WKBユーティリティでエンコード
    final wkb = createWkbLineString(line);
    db.execute('INSERT INTO "$tableName" (geom, attr) VALUES (?, ?);', [
      wkb,
      attr,
    ]);
    db.dispose();
  }

  /// ポリゴンフィーチャを追加（属性付き）
  void addPolygon(String tableName, List<LatLng> polygon, [String attr = '']) {
    final db = sql.sqlite3.open(path);
    // WKBユーティリティでエンコード（外環のみ対応）
    final wkb = createWkbPolygon([polygon]);
    db.execute('INSERT INTO "$tableName" (geom, attr) VALUES (?, ?);', [
      wkb,
      attr,
    ]);
    db.dispose();
  }
}
