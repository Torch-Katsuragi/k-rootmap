// QGIS/GDAL との相互運用テスト
//
// RootMap は「ユーザーの .gpkg をそのまま読み書きする」ことを identity にしているので、
// **編集して返したファイルが QGIS で普通に開けること**が要件になる。
//
// 検証するのは3点:
//   1. 書き込みのために落とした SpatiaLiteトリガーが、クローズ時に復元されること
//      （落としたまま返すと、その後QGISで編集しても空間インデックスが更新されない）
//   2. gpkg_contents の範囲が実データに合っていること（QGISの「レイヤにズーム」用）
//   3. gpkg_ogr_contents の件数が実データに合っていること（GDALの件数キャッシュ）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:root_maps/models/geopackage/geopackage_file.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// QGIS/GDAL が作る GeoPackage を模したファイルを用意する。
///
/// 本物のGDAL出力に合わせて、RTree自動更新トリガー（ST_ 関数を使う）と
/// gpkg_ogr_contents（件数キャッシュ）を持たせる。
Future<void> _createGdalStyleGpkg(String path, String table) async {
  final db = await databaseFactoryFfi.openDatabase(path);

  await db.execute('PRAGMA application_id = 1196444487');
  // ⚠ 実物のGeoPackage（GDAL製）は user_version=1。これを立てないと
  //    sqflite が「新規DB」とみなして onCreate を走らせ、既存テーブルと衝突する。
  await db.execute('PRAGMA user_version = 1');
  await db.execute('''
    CREATE TABLE gpkg_contents (
      table_name TEXT NOT NULL PRIMARY KEY, data_type TEXT NOT NULL,
      identifier TEXT UNIQUE, description TEXT DEFAULT '',
      last_change DATETIME NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
      min_x DOUBLE, min_y DOUBLE, max_x DOUBLE, max_y DOUBLE, srs_id INTEGER)
  ''');
  await db.execute('''
    CREATE TABLE gpkg_geometry_columns (
      table_name TEXT NOT NULL, column_name TEXT NOT NULL,
      geometry_type_name TEXT NOT NULL, srs_id INTEGER NOT NULL,
      z TINYINT NOT NULL, m TINYINT NOT NULL)
  ''');
  await db.execute('''
    CREATE TABLE gpkg_spatial_ref_sys (
      srs_name TEXT NOT NULL, srs_id INTEGER NOT NULL PRIMARY KEY,
      organization TEXT NOT NULL, organization_coordsys_id INTEGER NOT NULL,
      definition TEXT NOT NULL, description TEXT)
  ''');
  await db.insert('gpkg_spatial_ref_sys', {
    'srs_name': 'WGS 84',
    'srs_id': 4326,
    'organization': 'EPSG',
    'organization_coordsys_id': 4326,
    'definition': 'GEOGCS["WGS 84"]',
  });

  await db.execute('''
    CREATE TABLE "$table" (
      fid INTEGER PRIMARY KEY AUTOINCREMENT, geom BLOB, name TEXT, description TEXT)
  ''');
  await db.insert('gpkg_contents', {
    'table_name': table,
    'data_type': 'features',
    'identifier': table,
    'srs_id': 4326,
    // GDALは範囲を入れるが、ここでは「RootMapが更新できるか」を見たいので空にしておく
    'min_x': null, 'min_y': null, 'max_x': null, 'max_y': null,
  });
  await db.insert('gpkg_geometry_columns', {
    'table_name': table,
    'column_name': 'geom',
    'geometry_type_name': 'MULTIPOINT',
    'srs_id': 4326,
    'z': 0,
    'm': 0,
  });

  // RTree本体（rtree仮想テーブルはsqflite_ffiでも作れる）
  await db.execute(
    'CREATE VIRTUAL TABLE "rtree_${table}_geom" USING rtree(id, minx, maxx, miny, maxy)',
  );

  // ⚠ ST_ 関数に依存するGDAL製トリガー。素のSQLiteでは実行できない
  await db.execute('''
    CREATE TRIGGER "rtree_${table}_geom_insert" AFTER INSERT ON "$table"
    WHEN (new."geom" NOT NULL AND NOT ST_IsEmpty(NEW."geom"))
    BEGIN
      INSERT OR REPLACE INTO "rtree_${table}_geom" VALUES (
        NEW."fid", ST_MinX(NEW."geom"), ST_MaxX(NEW."geom"),
        ST_MinY(NEW."geom"), ST_MaxY(NEW."geom"));
    END
  ''');
  await db.execute('''
    CREATE TRIGGER "rtree_${table}_geom_delete" AFTER DELETE ON "$table"
    WHEN old."geom" NOT NULL
    BEGIN
      DELETE FROM "rtree_${table}_geom" WHERE id = OLD."fid";
    END
  ''');

  // GDALの件数キャッシュ
  await db.execute('''
    CREATE TABLE gpkg_ogr_contents (
      table_name TEXT NOT NULL PRIMARY KEY, feature_count INTEGER DEFAULT NULL)
  ''');
  await db.insert('gpkg_ogr_contents', {
    'table_name': table,
    'feature_count': 999, // わざと実態とズラしておく
  });

  await db.close();
}

Future<List<String>> _triggerNames(String path) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='trigger'",
  );
  await db.close();
  return rows.map((r) => r['name'] as String).toList();
}

Future<Map<String, Object?>> _contentsRow(String path, String table) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  final rows = await db.rawQuery(
    'SELECT * FROM gpkg_contents WHERE table_name = ?',
    [table],
  );
  await db.close();
  return rows.first;
}

Future<int?> _ogrCount(String path, String table) async {
  final db = await databaseFactoryFfi.openDatabase(path);
  final rows = await db.rawQuery(
    'SELECT feature_count FROM gpkg_ogr_contents WHERE table_name = ?',
    [table],
  );
  await db.close();
  return rows.first['feature_count'] as int?;
}

void main() {
  const table = 'shinrin';
  late Directory tempDir;
  late String gpkgPath;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('qgis_interop');
    gpkgPath = '${tempDir.path}/qgis_made.gpkg';
    await _createGdalStyleGpkg(gpkgPath, table);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('前提: QGIS製gpkgは ST_ 関数を使うトリガーを持つ', () async {
    final names = await _triggerNames(gpkgPath);
    expect(names, contains('rtree_${table}_geom_insert'));
    expect(names, contains('rtree_${table}_geom_delete'));
  });

  test('編集して閉じると SpatiaLiteトリガーが復元される', () async {
    final file = GeoPackageFile([], absolutePath: gpkgPath);

    // 書き込み（この過程で ST_ 依存トリガーが落とされる）
    await file.addPoint(table, const LatLng(33.97, 135.85), name: 'A');
    await file.dispose();

    final names = await _triggerNames(gpkgPath);
    expect(
      names,
      contains('rtree_${table}_geom_insert'),
      reason: '落としたまま返すと、その後QGISで編集しても空間インデックスが更新されない',
    );
    expect(names, contains('rtree_${table}_geom_delete'));
  });

  test('gpkg_contents の範囲が実データに合わせて更新される', () async {
    final before = await _contentsRow(gpkgPath, table);
    expect(before['min_x'], isNull, reason: '前提: 最初は空');

    final file = GeoPackageFile([], absolutePath: gpkgPath);
    await file.addPoint(table, const LatLng(33.90, 135.80), name: 'A');
    await file.addPoint(table, const LatLng(34.00, 135.90), name: 'B');
    await file.dispose();

    final after = await _contentsRow(gpkgPath, table);
    expect(after['min_x'], isNotNull, reason: 'QGISの「レイヤにズーム」で使われる');
    expect((after['min_x']! as num).toDouble(), closeTo(135.80, 0.01));
    expect((after['max_x']! as num).toDouble(), closeTo(135.90, 0.01));
    expect((after['min_y']! as num).toDouble(), closeTo(33.90, 0.01));
    expect((after['max_y']! as num).toDouble(), closeTo(34.00, 0.01));
  });

  test('gpkg_ogr_contents の件数が実データに合わせて同期される', () async {
    expect(await _ogrCount(gpkgPath, table), 999, reason: '前提: わざとズラしてある');

    final file = GeoPackageFile([], absolutePath: gpkgPath);
    await file.addPoint(table, const LatLng(33.97, 135.85), name: 'A');
    await file.addPoint(table, const LatLng(33.98, 135.86), name: 'B');
    await file.dispose();

    expect(await _ogrCount(gpkgPath, table), 2);
  });
}
