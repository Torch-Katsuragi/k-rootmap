import 'dart:io';
import 'package:test/test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/utils/coordinate_converter.dart';
import '../lib/utils/metadata_parser.dart';
import '../lib/utils/address_converter.dart';

/// テスト結果をログファイルに出力するヘルパークラス
class TestLogger {
  static final File _logFile = File('test_results.log');

  static Future<void> init() async {
    if (await _logFile.exists()) {
      await _logFile.delete();
    }
    await _logFile.create();
    await log('=== 座標変換テスト開始 ===');
  }

  static Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message\n';
    await _logFile.writeAsString(logMessage, mode: FileMode.append);
    print(logMessage.trim()); // コンソールにも出力
  }

  static Future<void> logCoordinate(
    String label,
    LatLng coord,
    Map<String, dynamic>? xyResult,
  ) async {
    await log('$label:');
    await log('  緯度経度: (${coord.latitude}, ${coord.longitude})');
    if (xyResult != null) {
      await log('  X座標: ${xyResult['x']}');
      await log('  Y座標: ${xyResult['y']}');
      await log('  座標系: ${xyResult['epsg'] ?? 'N/A'}');
    }
    await log('');
  }
}

void main() {
  group('座標変換テスト', () {
    setUpAll(() async {
      await TestLogger.init();
    });

    test('異なる地点でのXY座標変換テスト', () async {
      await TestLogger.log('=== 異なる地点でのXY座標変換テスト ===');

      // テスト用の異なる地点
      final testPoints = [
        LatLng(35.6762, 139.6503), // 東京駅
        LatLng(34.6937, 135.5023), // 大阪駅
        LatLng(43.0642, 141.3469), // 札幌駅
        LatLng(26.2124, 127.6792), // 那覇
        LatLng(33.5904, 130.4017), // 福岡
      ];

      final pointNames = ['東京駅', '大阪駅', '札幌駅', '那覇', '福岡'];

      for (int i = 0; i < testPoints.length; i++) {
        final point = testPoints[i];
        final name = pointNames[i];

        await TestLogger.log('--- $name の座標変換テスト ---');

        // UTM座標系での変換
        final utmZone = CoordinateConverter.calculateUTMZone(point.longitude);
        final utmEpsg = 'EPSG:326${utmZone.toString().padLeft(2, '0')}';
        final utmSystem = CoordinateSystem(
          name: 'UTM Zone ${utmZone}N',
          epsgCode: utmEpsg,
          proj4String:
              '+proj=utm +zone=$utmZone +datum=WGS84 +units=m +no_defs',
        );

        final utmXY = CoordinateConverter.latLngToXY(
          point,
          coordinateSystem: utmSystem,
        );
        await TestLogger.logCoordinate('$name (UTM)', point, {
          'x': utmXY.x.toStringAsFixed(3),
          'y': utmXY.y.toStringAsFixed(3),
          'epsg': utmEpsg,
        });

        // 日本の地点の場合はJGD2011も試す
        if (i < 4) {
          // 那覇以外（那覇は特殊なので別途テスト）
          try {
            final address = await AddressConverter.getAddressFromLatLng(point);
            if (address != null) {
              final jgdSystem = CoordinateConverter.getJGD2011ZoneFromAddress(
                address,
              );
              if (jgdSystem != null) {
                final jgdXY = CoordinateConverter.latLngToXY(
                  point,
                  coordinateSystem: jgdSystem,
                );
                await TestLogger.logCoordinate('$name (JGD2011)', point, {
                  'x': jgdXY.x.toStringAsFixed(3),
                  'y': jgdXY.y.toStringAsFixed(3),
                  'epsg': jgdSystem.epsgCode,
                });
              }
            }
          } catch (e) {
            await TestLogger.log('$name のJGD2011変換でエラー: $e');
          }
        }

        // 座標が同じでないことを確認
        expect(
          utmXY.x,
          isNot(equals(utmXY.y)),
          reason: '$name のUTM座標でX座標とY座標が同じです',
        );
      }
    });

    test('メタデータパーサーのXY座標追加テスト', () async {
      await TestLogger.log('=== メタデータパーサーのXY座標追加テスト ===');

      // テスト用メタデータ
      final testMetadata = {
        'type': 'test',
        'properties': {
          '名前': 'テスト地点',
          '緯度': '35.6762',
          '経度': '139.6503',
          '標高': '10m',
        },
      };

      final testPoints = [
        LatLng(35.6762, 139.6503), // 東京駅
        LatLng(34.6937, 135.5023), // 大阪駅
        LatLng(43.0642, 141.3469), // 札幌駅
      ];

      final pointNames = ['東京駅', '大阪駅', '札幌駅'];

      for (int i = 0; i < testPoints.length; i++) {
        final point = testPoints[i];
        final name = pointNames[i];

        await TestLogger.log('--- $name のメタデータパーサーテスト ---');

        // メタデータを更新
        testMetadata['properties']!['緯度'] = point.latitude.toString();
        testMetadata['properties']!['経度'] = point.longitude.toString();
        testMetadata['properties']!['名前'] = name;

        final result = await MetadataParser.parseMetadataWithCoordinates(
          testMetadata,
          point,
        );

        if (result != null) {
          await TestLogger.log('$name のメタデータパース結果:');
          await TestLogger.log('  ヘッダー: ${result.headers}');
          await TestLogger.log('  行数: ${result.rows.length}');

          // 各行のデータをログ出力
          for (int rowIndex = 0; rowIndex < result.rows.length; rowIndex++) {
            await TestLogger.log(
              '  行${rowIndex + 1}: ${result.rows[rowIndex]}',
            );

            // X座標とY座標のインデックスを探す
            int? xIndex, yIndex;
            for (
              int colIndex = 0;
              colIndex < result.headers.length;
              colIndex++
            ) {
              if (result.headers[colIndex] == 'X座標') {
                xIndex = colIndex;
              } else if (result.headers[colIndex] == 'Y座標') {
                yIndex = colIndex;
              }
            }

            if (xIndex != null && yIndex != null) {
              final xValue = result.rows[rowIndex][xIndex];
              final yValue = result.rows[rowIndex][yIndex];

              await TestLogger.log('    X座標: $xValue');
              await TestLogger.log('    Y座標: $yValue');

              // X座標とY座標が同じでないことを確認
              expect(
                xValue,
                isNot(equals(yValue)),
                reason: '$name でX座標($xValue)とY座標($yValue)が同じです',
              );

              // N/Aでないことを確認
              expect(xValue, isNot(equals('N/A')), reason: '$name のX座標がN/Aです');
              expect(yValue, isNot(equals('N/A')), reason: '$name のY座標がN/Aです');
            }
          }

          await TestLogger.log('  座標系: ${result.selectedCoordinateSystem}');
          await TestLogger.log('  座標系選択肢: ${result.coordinateSystemOptions}');
        } else {
          await TestLogger.log('$name のメタデータパース結果がnullです');
          fail('$name のメタデータパースに失敗しました');
        }

        await TestLogger.log('');
      }
    });

    test('座標系変更テスト', () async {
      await TestLogger.log('=== 座標系変更テスト ===');

      final testPoint = LatLng(35.6762, 139.6503); // 東京駅
      final testMetadata = {
        'type': 'test',
        'properties': {'名前': '東京駅', '緯度': '35.6762', '経度': '139.6503'},
      };

      // 初期データを取得
      final initialResult = await MetadataParser.parseMetadataWithCoordinates(
        testMetadata,
        testPoint,
      );

      if (initialResult != null &&
          initialResult.coordinateSystemOptions != null) {
        await TestLogger.log(
          '初期座標系: ${initialResult.selectedCoordinateSystem}',
        );

        // 利用可能な座標系をすべてテスト
        for (final epsgCode in initialResult.coordinateSystemOptions!.keys) {
          if (epsgCode != initialResult.selectedCoordinateSystem) {
            await TestLogger.log('--- 座標系変更テスト: $epsgCode ---');

            final recalculatedResult =
                await MetadataParser.recalculateXYCoordinates(
                  initialResult,
                  testPoint,
                  epsgCode,
                );

            // X座標とY座標のインデックスを探す
            int? xIndex, yIndex;
            for (
              int colIndex = 0;
              colIndex < recalculatedResult.headers.length;
              colIndex++
            ) {
              if (recalculatedResult.headers[colIndex] == 'X座標') {
                xIndex = colIndex;
              } else if (recalculatedResult.headers[colIndex] == 'Y座標') {
                yIndex = colIndex;
              }
            }

            if (xIndex != null &&
                yIndex != null &&
                recalculatedResult.rows.isNotEmpty) {
              final xValue = recalculatedResult.rows[0][xIndex];
              final yValue = recalculatedResult.rows[0][yIndex];

              await TestLogger.log('  座標系: $epsgCode');
              await TestLogger.log('  X座標: $xValue');
              await TestLogger.log('  Y座標: $yValue');

              // X座標とY座標が同じでないことを確認
              expect(
                xValue,
                isNot(equals(yValue)),
                reason: '座標系$epsgCode でX座標($xValue)とY座標($yValue)が同じです',
              );
            }
          }
        }
      }
    });

    tearDownAll(() async {
      await TestLogger.log('=== 座標変換テスト終了 ===');
    });
  });
}
