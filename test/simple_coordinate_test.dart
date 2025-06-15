import 'dart:io';
import 'package:test/test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/utils/coordinate_converter.dart';

/// テスト結果をログファイルに出力するヘルパークラス
class TestLogger {
  static final File _logFile = File('coordinate_test_results.log');

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
}

void main() {
  group('座標変換基本テスト', () {
    setUpAll(() async {
      await TestLogger.init();
    });

    test('UTM座標変換テスト', () async {
      await TestLogger.log('=== UTM座標変換テスト開始 ===');

      // テスト用の地点
      final testPoints = [
        {'name': '東京駅', 'lat': 35.6762, 'lng': 139.6503},
        {'name': '大阪駅', 'lat': 34.6937, 'lng': 135.5023},
        {'name': '札幌駅', 'lat': 43.0642, 'lng': 141.3469},
      ];

      for (final pointData in testPoints) {
        final name = pointData['name'] as String;
        final lat = pointData['lat'] as double;
        final lng = pointData['lng'] as double;
        final point = LatLng(lat, lng);

        await TestLogger.log('--- $name の座標変換 ---');
        await TestLogger.log('緯度経度: ($lat, $lng)');

        // UTM座標系での変換
        final utmZone = CoordinateConverter.calculateUTMZone(lng);
        await TestLogger.log('UTMゾーン: $utmZone');

        final utmEpsg = 'EPSG:326${utmZone.toString().padLeft(2, '0')}';
        await TestLogger.log('UTM EPSG: $utmEpsg');

        final utmSystem = CoordinateSystem(
          name: 'UTM Zone ${utmZone}N',
          epsgCode: utmEpsg,
          proj4String:
              '+proj=utm +zone=$utmZone +datum=WGS84 +units=m +no_defs',
        );

        try {
          final utmXY = CoordinateConverter.latLngToXY(
            point,
            coordinateSystem: utmSystem,
          );

          await TestLogger.log('X座標: ${utmXY.x.toStringAsFixed(3)}');
          await TestLogger.log('Y座標: ${utmXY.y.toStringAsFixed(3)}');

          // X座標とY座標が同じでないことを確認
          expect(
            utmXY.x,
            isNot(equals(utmXY.y)),
            reason: '$name のUTM座標でX座標(${utmXY.x})とY座標(${utmXY.y})が同じです',
          );

          // 座標が有効な値であることを確認
          expect(utmXY.x, isNot(equals(0.0)), reason: '$name のX座標が0です');
          expect(utmXY.y, isNot(equals(0.0)), reason: '$name のY座標が0です');

          await TestLogger.log('✓ $name の座標変換成功');
        } catch (e) {
          await TestLogger.log('✗ $name の座標変換エラー: $e');
          fail('$name の座標変換に失敗: $e');
        }

        await TestLogger.log('');
      }
    });

    test('同一地点での複数座標系テスト', () async {
      await TestLogger.log('=== 同一地点での複数座標系テスト ===');

      final testPoint = LatLng(35.6762, 139.6503); // 東京駅
      await TestLogger.log('テスト地点: 東京駅 (35.6762, 139.6503)');

      // 複数の座標系で変換
      final coordinateSystems = [
        CoordinateSystem(
          name: 'UTM Zone 54N',
          epsgCode: 'EPSG:32654',
          proj4String: '+proj=utm +zone=54 +datum=WGS84 +units=m +no_defs',
        ),
        CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IX',
          epsgCode: 'EPSG:6677',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        ),
      ];

      final results = <String, Map<String, double>>{};

      for (final system in coordinateSystems) {
        await TestLogger.log('--- ${system.name} での変換 ---');

        try {
          final xy = CoordinateConverter.latLngToXY(
            testPoint,
            coordinateSystem: system,
          );

          await TestLogger.log('座標系: ${system.epsgCode}');
          await TestLogger.log('X座標: ${xy.x.toStringAsFixed(3)}');
          await TestLogger.log('Y座標: ${xy.y.toStringAsFixed(3)}');

          results[system.epsgCode] = {'x': xy.x, 'y': xy.y};

          // X座標とY座標が同じでないことを確認
          expect(
            xy.x,
            isNot(equals(xy.y)),
            reason: '${system.name} でX座標(${xy.x})とY座標(${xy.y})が同じです',
          );

          await TestLogger.log('✓ ${system.name} の変換成功');
        } catch (e) {
          await TestLogger.log('✗ ${system.name} の変換エラー: $e');
          fail('${system.name} の変換に失敗: $e');
        }

        await TestLogger.log('');
      }

      // 異なる座標系で異なる結果が得られることを確認
      if (results.length >= 2) {
        final systems = results.keys.toList();
        final result1 = results[systems[0]]!;
        final result2 = results[systems[1]]!;

        await TestLogger.log('--- 座標系間の差異確認 ---');
        await TestLogger.log(
          '${systems[0]}: X=${result1['x']}, Y=${result1['y']}',
        );
        await TestLogger.log(
          '${systems[1]}: X=${result2['x']}, Y=${result2['y']}',
        );

        expect(
          result1['x'],
          isNot(equals(result2['x'])),
          reason: '異なる座標系で同じX座標が得られました',
        );
        expect(
          result1['y'],
          isNot(equals(result2['y'])),
          reason: '異なる座標系で同じY座標が得られました',
        );

        await TestLogger.log('✓ 座標系間で異なる結果が得られました');
      }
    });

    tearDownAll(() async {
      await TestLogger.log('=== 座標変換テスト終了 ===');
    });
  });
}
