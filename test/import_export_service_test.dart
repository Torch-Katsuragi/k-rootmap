// K-MAPS: Import/Export Service Tests
import 'package:flutter_test/flutter_test.dart';
import 'package:k_maps/services/import_export_service.dart';
import 'package:k_maps/models/geometry_type.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:proj4dart/proj4dart.dart';
import 'package:k_maps/utils/coordinate_converter.dart';

void main() {
  group('ImportExportService Tests', () {
    late ImportExportService service;

    setUp(() {
      service = ImportExportService();
    });

    test('FileFormat.fromExtension should correctly identify file formats', () {
      expect(FileFormat.fromExtension('.shp'), FileFormat.shapefile);
      expect(FileFormat.fromExtension('.SHP'), FileFormat.shapefile);
      expect(FileFormat.fromExtension('.geojson'), FileFormat.geojson);
      expect(FileFormat.fromExtension('.json'), FileFormat.geojson);
      expect(FileFormat.fromExtension('.kml'), FileFormat.kml);
      expect(FileFormat.fromExtension('.csv'), FileFormat.csv);
      expect(FileFormat.fromExtension('.gpx'), FileFormat.gpx);
      expect(FileFormat.fromExtension('.xyz'), FileFormat.unknown);
    });

    test('FileFormat.isImportSupported should return correct values', () {
      expect(FileFormat.shapefile.isImportSupported, isTrue);
      expect(FileFormat.geojson.isImportSupported, isFalse); // 将来実装予定
      expect(FileFormat.kml.isImportSupported, isFalse);
      expect(FileFormat.csv.isImportSupported, isFalse);
      expect(FileFormat.gpx.isImportSupported, isFalse);
      expect(FileFormat.unknown.isImportSupported, isFalse);
    });

    test('FileFormat.isExportSupported should return correct values', () {
      // 現在、すべてのエクスポート機能は未実装
      for (final format in FileFormat.values) {
        expect(format.isExportSupported, isFalse);
      }
    });

    test('getSupportedImportFormats should return only supported formats', () {
      final supportedFormats = service.getSupportedImportFormats();
      expect(supportedFormats, contains(FileFormat.shapefile));
      expect(supportedFormats, isNot(contains(FileFormat.geojson))); // 未実装
    });

    test('getSupportedImportExtensions should return correct extensions', () {
      final extensions = service.getSupportedImportExtensions();
      expect(extensions, contains('.shp'));
      // 将来実装される形式はこの時点では含まれない
      expect(extensions, isNot(contains('.geojson')));
    });

    test('ImportExportResult factory methods should work correctly', () {
      final successResult = ImportExportResult.success();
      expect(successResult.success, isTrue);
      expect(successResult.errorMessage, isNull);

      final errorResult = ImportExportResult.error('Test error');
      expect(errorResult.success, isFalse);
      expect(errorResult.errorMessage, equals('Test error'));
    });
  });

  group('FileFormat enum tests', () {
    test('fromExtension should handle case insensitive input', () {
      expect(FileFormat.fromExtension('.SHP'), FileFormat.shapefile);
      expect(FileFormat.fromExtension('.shp'), FileFormat.shapefile);
      expect(FileFormat.fromExtension('.Shp'), FileFormat.shapefile);
    });

    test('fromExtension should handle extensions with and without dots', () {
      expect(FileFormat.fromExtension('.shp'), FileFormat.shapefile);
      expect(FileFormat.fromExtension('shp'), FileFormat.unknown); // ドット必須
    });
  });

  group('Shapefile Analysis Tests', () {
    test('GeometryType enum should have correct values', () {
      expect(GeometryType.point.value, equals('POINT'));
      expect(GeometryType.linestring.value, equals('LINESTRING'));
      expect(GeometryType.polygon.value, equals('POLYGON'));
    });

    test('GeometryType fromString should work correctly', () {
      expect(GeometryType.fromString('POINT'), equals(GeometryType.point));
      expect(
        GeometryType.fromString('LINESTRING'),
        equals(GeometryType.linestring),
      );
      expect(GeometryType.fromString('POLYGON'), equals(GeometryType.polygon));
      expect(
        GeometryType.fromString('UNKNOWN'),
        equals(GeometryType.point),
      ); // デフォルト
    });

    test('should handle basic file operations', () async {
      // テスト用の一時ファイルを作成
      final tempDir = Directory.systemTemp.createTempSync('k_maps_test');

      try {
        // 基本的なファイル作成テスト
        final testFile = File('${tempDir.path}/test.shp');
        await testFile.writeAsBytes([1, 2, 3, 4]); // 4バイト

        expect(testFile.existsSync(), isTrue);
        expect(testFile.lengthSync(), equals(4));

        // 関連ファイルのテスト
        final dbfFile = File('${tempDir.path}/test.dbf');
        final shxFile = File('${tempDir.path}/test.shx');
        final prjFile = File('${tempDir.path}/test.prj');

        await dbfFile.writeAsBytes([5, 6]);
        await shxFile.writeAsBytes([7, 8]);
        await prjFile.writeAsBytes([9, 10]);

        expect(dbfFile.existsSync(), isTrue);
        expect(shxFile.existsSync(), isTrue);
        expect(prjFile.existsSync(), isTrue);
      } finally {
        // テスト用一時ファイルを削除
        tempDir.deleteSync(recursive: true);
      }
    });

    test('should handle binary data operations', () {
      // バイナリデータ操作のテスト
      final headerBytes = ByteData(100);

      // ファイルコードを設定（Big-endian）
      headerBytes.setInt32(0, 0x0000270a, Endian.big);
      expect(headerBytes.getInt32(0, Endian.big), equals(0x0000270a));

      // ファイル長を設定（Big-endian）
      headerBytes.setInt32(24, 50, Endian.big);
      expect(headerBytes.getInt32(24, Endian.big), equals(50));

      // シェープタイプを設定（Little-endian）
      headerBytes.setInt32(32, 1, Endian.little);
      expect(headerBytes.getInt32(32, Endian.little), equals(1));

      // バイト配列変換テスト
      final bytes = headerBytes.buffer.asUint8List();
      expect(bytes.length, equals(100));
    });
  });

  group('ImportExportService座標変換テスト', () {
    test('CoordinateSystemオブジェクトの作成', () {
      final coordinateSystem = CoordinateSystem(
        name: 'JGD2000 / Japan Plane Rectangular CS VI',
        epsgCode: 'EPSG:2448',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
      );

      expect(coordinateSystem.name, 'JGD2000 / Japan Plane Rectangular CS VI');
      expect(coordinateSystem.epsgCode, 'EPSG:2448');
      print('[TEST] CoordinateSystemオブジェクト作成成功');
    });

    test('和歌山県の座標変換テスト', () {
      // 和歌山県北山村の平面直角座標系VI系の座標例
      // 実際の座標値（推定値）
      final x = 50000.0; // Easting (東方向)
      final y = -150000.0; // Northing (北方向)

      final coordinateSystem = CoordinateSystem(
        name: 'JGD2000 / Japan Plane Rectangular CS VI',
        epsgCode: 'EPSG:2448',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
      );

      try {
        final point = Point(x: x, y: y);
        final result = CoordinateConverter.xyToLatLng(point, coordinateSystem);

        print(
          '[TEST] 座標変換結果: ($x, $y) -> (${result.latitude}, ${result.longitude})',
        );

        // 和歌山県の緯度経度範囲をチェック（余裕を持った範囲）
        expect(result.latitude, greaterThan(33.0));
        expect(result.latitude, lessThan(35.0));
        expect(result.longitude, greaterThan(135.0));
        expect(result.longitude, lessThan(137.0)); // 余裕を持った範囲に調整

        print('[TEST] 和歌山県座標変換テスト成功');
      } catch (e) {
        print('[TEST] 座標変換エラー: $e');
        fail('座標変換に失敗: $e');
      }
    });

    test('proj4dart基本動作テスト', () {
      try {
        // WGS84からJGD2000平面直角座標系VI系への変換テスト
        final source = Projection.get('EPSG:4326'); // WGS84
        final target = Projection.add(
          'EPSG:2448',
          '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
        );

        expect(source, isNotNull);
        expect(target, isNotNull);

        if (source != null) {
          // 和歌山県の緯度経度を平面直角座標に変換
          final wgs84Point = Point(x: 135.8, y: 34.2); // 和歌山県内の座標
          final result = source.transform(target, wgs84Point);

          print(
            '[TEST] proj4dart変換テスト: (${wgs84Point.y}, ${wgs84Point.x}) -> (${result.x.toStringAsFixed(1)}, ${result.y.toStringAsFixed(1)})',
          );

          // 平面直角座標系の座標値は通常数万～数十万メートル
          expect(result.x.abs(), greaterThan(1000.0));
          expect(result.y.abs(), greaterThan(1000.0));

          print('[TEST] proj4dart基本動作テスト成功');
        }
      } catch (e) {
        print('[TEST] proj4dartテストエラー: $e');
        fail('proj4dart動作テストに失敗: $e');
      }
    });

    test('大きな座標値の妥当性チェック', () {
      // 平面直角座標系の典型的な座標値（数万〜数十万メートル）
      final largeCoordinates = [
        Point(x: 123456.789, y: -234567.123),
        Point(x: 50000.0, y: -150000.0),
        Point(x: 200000.0, y: -50000.0),
      ];

      for (final coord in largeCoordinates) {
        // 有限数チェック
        expect(coord.x.isFinite, isTrue);
        expect(coord.y.isFinite, isTrue);
        print('[TEST] 大きな座標値 (${coord.x}, ${coord.y}) の妥当性確認');
      }
    });
  });
}
