import 'dart:io';
import 'package:test/test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/utils/metadata_parser.dart';

/// テスト結果をログファイルに出力するヘルパークラス
class MetadataTestLogger {
  static final File _logFile = File('metadata_test_results.log');

  static Future<void> init() async {
    if (await _logFile.exists()) {
      await _logFile.delete();
    }
    await _logFile.create();
    await log('=== メタデータパーサーテスト開始 ===');
  }

  static Future<void> log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message\n';
    await _logFile.writeAsString(logMessage, mode: FileMode.append);
    print(logMessage.trim()); // コンソールにも出力
  }

  static Future<void> logTableData(String label, MetadataTableData data) async {
    await log('$label:');
    await log('  タイトル: ${data.title}');
    await log('  タイプ: ${data.type}');
    await log('  ヘッダー: ${data.headers}');
    await log('  行数: ${data.rows.length}');
    await log('  選択座標系: ${data.selectedCoordinateSystem}');
    await log('  座標系選択肢: ${data.coordinateSystemOptions}');

    for (int i = 0; i < data.rows.length; i++) {
      await log('  行${i + 1}: ${data.rows[i]}');
    }
    await log('');
  }
}

void main() {
  group('メタデータパーサーテスト', () {
    setUpAll(() async {
      await MetadataTestLogger.init();
    });

    test('基本的なメタデータパーステスト', () async {
      await MetadataTestLogger.log('=== 基本的なメタデータパーステスト ===');

      // テスト用メタデータ（parseMetadataが期待する形式）
      final testMetadata = {
        'type': 'test_data',
        'contents': {
          '名前': 'テスト地点',
          '緯度': '35.6762',
          '経度': '139.6503',
          '標高': '10m',
          '備考': 'テストデータ',
        },
      };

      // 基本パース（座標なし）
      final basicResult = MetadataParser.parseMetadata(testMetadata);
      if (basicResult != null) {
        await MetadataTestLogger.logTableData('基本パース結果', basicResult);

        // ヘッダーに緯度経度が含まれることを確認
        expect(basicResult.headers, contains('キー'));
        expect(basicResult.headers, contains('値'));

        // 行データに緯度経度が含まれることを確認
        final hasLatitude = basicResult.rows.any((row) => row.contains('緯度'));
        final hasLongitude = basicResult.rows.any((row) => row.contains('経度'));

        expect(hasLatitude, isTrue, reason: '緯度データが見つかりません');
        expect(hasLongitude, isTrue, reason: '経度データが見つかりません');

        await MetadataTestLogger.log('✓ 基本パーステスト成功');
      } else {
        await MetadataTestLogger.log('✗ 基本パースに失敗');
        fail('基本パースに失敗しました');
      }
    });

    test('XY座標追加テスト - 東京駅', () async {
      await MetadataTestLogger.log('=== XY座標追加テスト - 東京駅 ===');

      final testPoint = LatLng(35.6762, 139.6503);
      final testMetadata = {
        'type': 'test_data',
        'contents': {
          '名前': '東京駅',
          '緯度': '35.6762',
          '経度': '139.6503',
          '標高': '10m',
        },
      };

      final result = await MetadataParser.parseMetadataWithCoordinates(
        testMetadata,
        testPoint,
      );

      if (result != null) {
        await MetadataTestLogger.logTableData('東京駅 XY座標追加結果', result);

        // X座標とY座標が行データに含まれることを確認（キー・値形式）
        bool hasXCoordinate = false;
        bool hasYCoordinate = false;

        for (final row in result.rows) {
          if (row.length >= 2) {
            if (row[0] == 'X座標') hasXCoordinate = true;
            if (row[0] == 'Y座標') hasYCoordinate = true;
          }
        }

        expect(hasXCoordinate, isTrue, reason: 'X座標が見つかりません');
        expect(hasYCoordinate, isTrue, reason: 'Y座標が見つかりません');

        // X座標とY座標のインデックスを取得（キー・値形式の場合）
        int? xIndex, yIndex;
        for (int i = 0; i < result.rows.length; i++) {
          if (result.rows[i].length >= 2) {
            if (result.rows[i][0] == 'X座標') {
              xIndex = i;
            } else if (result.rows[i][0] == 'Y座標') {
              yIndex = i;
            }
          }
        }

        expect(xIndex, isNotNull, reason: 'X座標のインデックスが見つかりません');
        expect(yIndex, isNotNull, reason: 'Y座標のインデックスが見つかりません');

        if (xIndex != null && yIndex != null) {
          final xValue = result.rows[xIndex][1]; // 値は2列目
          final yValue = result.rows[yIndex][1]; // 値は2列目

          await MetadataTestLogger.log('X座標値: $xValue');
          await MetadataTestLogger.log('Y座標値: $yValue');

          // X座標とY座標が異なることを確認
          expect(
            xValue,
            isNot(equals(yValue)),
            reason: 'X座標($xValue)とY座標($yValue)が同じです',
          );

          // N/Aでないことを確認
          expect(xValue, isNot(equals('N/A')), reason: 'X座標がN/Aです');
          expect(yValue, isNot(equals('N/A')), reason: 'Y座標がN/Aです');

          // 数値として解析できることを確認
          final xNum = double.tryParse(xValue);
          final yNum = double.tryParse(yValue);

          expect(xNum, isNotNull, reason: 'X座標が数値として解析できません: $xValue');
          expect(yNum, isNotNull, reason: 'Y座標が数値として解析できません: $yValue');

          await MetadataTestLogger.log('✓ 東京駅 XY座標追加テスト成功');
        }
      } else {
        await MetadataTestLogger.log('✗ 東京駅 XY座標追加に失敗');
        fail('東京駅のXY座標追加に失敗しました');
      }
    });

    test('複数地点でのXY座標追加テスト', () async {
      await MetadataTestLogger.log('=== 複数地点でのXY座標追加テスト ===');

      final testCases = [
        {'name': '東京駅', 'lat': 35.6762, 'lng': 139.6503},
        {'name': '大阪駅', 'lat': 34.6937, 'lng': 135.5023},
        {'name': '札幌駅', 'lat': 43.0642, 'lng': 141.3469},
        {'name': '福岡駅', 'lat': 33.5904, 'lng': 130.4017},
      ];

      final results = <String, Map<String, String>>{};

      for (final testCase in testCases) {
        final name = testCase['name'] as String;
        final lat = testCase['lat'] as double;
        final lng = testCase['lng'] as double;
        final point = LatLng(lat, lng);

        await MetadataTestLogger.log('--- $name のテスト ---');

        final testMetadata = {
          'type': 'test_data',
          'contents': {
            '名前': name,
            '緯度': lat.toString(),
            '経度': lng.toString(),
            '標高': '10m',
          },
        };

        final result = await MetadataParser.parseMetadataWithCoordinates(
          testMetadata,
          point,
        );

        if (result != null) {
          // X座標とY座標のインデックスを取得（キー・値形式の場合）
          int? xIndex, yIndex;

          // キー・値形式の場合、行データから検索
          for (int i = 0; i < result.rows.length; i++) {
            if (result.rows[i].length >= 2) {
              if (result.rows[i][0] == 'X座標') {
                xIndex = i;
              } else if (result.rows[i][0] == 'Y座標') {
                yIndex = i;
              }
            }
          }

          if (xIndex != null && yIndex != null) {
            final xValue = result.rows[xIndex][1]; // 値は2列目
            final yValue = result.rows[yIndex][1]; // 値は2列目

            await MetadataTestLogger.log('$name - X座標: $xValue, Y座標: $yValue');
            await MetadataTestLogger.log(
              '$name - 座標系: ${result.selectedCoordinateSystem}',
            );

            results[name] = {
              'x': xValue,
              'y': yValue,
              'epsg': result.selectedCoordinateSystem ?? 'N/A',
            };

            // X座標とY座標が異なることを確認
            expect(
              xValue,
              isNot(equals(yValue)),
              reason: '$name でX座標($xValue)とY座標($yValue)が同じです',
            );

            // N/Aでないことを確認
            expect(xValue, isNot(equals('N/A')), reason: '$name のX座標がN/Aです');
            expect(yValue, isNot(equals('N/A')), reason: '$name のY座標がN/Aです');

            await MetadataTestLogger.log('✓ $name のテスト成功');
          } else {
            await MetadataTestLogger.log('✗ $name でX座標またはY座標のインデックスが見つかりません');
            await MetadataTestLogger.log(
              '  利用可能な行キー: ${result.rows.map((row) => row.isNotEmpty ? row[0] : 'empty').toList()}',
            );
            fail('$name でX座標またはY座標のインデックスが見つかりません');
          }
        } else {
          await MetadataTestLogger.log('✗ $name のメタデータパースに失敗');
          fail('$name のメタデータパースに失敗しました');
        }

        await MetadataTestLogger.log('');
      }

      // 異なる地点で異なる座標が得られることを確認
      await MetadataTestLogger.log('--- 地点間の座標差異確認 ---');
      final locations = results.keys.toList();
      for (int i = 0; i < locations.length - 1; i++) {
        for (int j = i + 1; j < locations.length; j++) {
          final loc1 = locations[i];
          final loc2 = locations[j];
          final result1 = results[loc1]!;
          final result2 = results[loc2]!;

          await MetadataTestLogger.log('$loc1 vs $loc2:');
          await MetadataTestLogger.log(
            '  $loc1: X=${result1['x']}, Y=${result1['y']}',
          );
          await MetadataTestLogger.log(
            '  $loc2: X=${result2['x']}, Y=${result2['y']}',
          );

          // 異なる地点で異なる座標が得られることを確認
          final sameX = result1['x'] == result2['x'];
          final sameY = result1['y'] == result2['y'];

          if (sameX && sameY) {
            await MetadataTestLogger.log('  ⚠️ 警告: $loc1 と $loc2 で同じ座標が得られました');
            fail(
              '$loc1 と $loc2 で同じ座標が得られました: X=${result1['x']}, Y=${result1['y']}',
            );
          } else {
            await MetadataTestLogger.log('  ✓ 異なる座標が得られました');
          }
        }
      }
    });

    test('座標系変更テスト', () async {
      await MetadataTestLogger.log('=== 座標系変更テスト ===');

      final testPoint = LatLng(35.6762, 139.6503); // 東京駅
      final testMetadata = {
        'type': 'test_data',
        'contents': {'名前': '東京駅', '緯度': '35.6762', '経度': '139.6503'},
      };

      // 初期データを取得
      final initialResult = await MetadataParser.parseMetadataWithCoordinates(
        testMetadata,
        testPoint,
      );

      if (initialResult != null &&
          initialResult.coordinateSystemOptions != null) {
        await MetadataTestLogger.logTableData('初期結果', initialResult);

        final availableSystems =
            initialResult.coordinateSystemOptions!.keys.toList();
        await MetadataTestLogger.log('利用可能な座標系: $availableSystems');

        // 各座標系でテスト
        for (final epsgCode in availableSystems) {
          if (epsgCode != initialResult.selectedCoordinateSystem) {
            await MetadataTestLogger.log('--- 座標系変更: $epsgCode ---');

            final recalculatedResult =
                await MetadataParser.recalculateXYCoordinates(
                  initialResult,
                  testPoint,
                  epsgCode,
                );

            // X座標とY座標のインデックスを取得（キー・値形式の場合）
            int? xIndex, yIndex;
            for (int i = 0; i < recalculatedResult.rows.length; i++) {
              if (recalculatedResult.rows[i].length >= 2) {
                if (recalculatedResult.rows[i][0] == 'X座標') {
                  xIndex = i;
                } else if (recalculatedResult.rows[i][0] == 'Y座標') {
                  yIndex = i;
                }
              }
            }

            if (xIndex != null && yIndex != null) {
              final xValue = recalculatedResult.rows[xIndex][1]; // 値は2列目
              final yValue = recalculatedResult.rows[yIndex][1]; // 値は2列目

              await MetadataTestLogger.log('座標系: $epsgCode');
              await MetadataTestLogger.log('X座標: $xValue');
              await MetadataTestLogger.log('Y座標: $yValue');

              // X座標とY座標が異なることを確認
              expect(
                xValue,
                isNot(equals(yValue)),
                reason: '座標系$epsgCode でX座標($xValue)とY座標($yValue)が同じです',
              );

              // N/Aでないことを確認
              expect(
                xValue,
                isNot(equals('N/A')),
                reason: '座標系$epsgCode のX座標がN/Aです',
              );
              expect(
                yValue,
                isNot(equals('N/A')),
                reason: '座標系$epsgCode のY座標がN/Aです',
              );

              await MetadataTestLogger.log('✓ 座標系$epsgCode のテスト成功');
            }

            await MetadataTestLogger.log('');
          }
        }
      } else {
        await MetadataTestLogger.log('✗ 初期データの取得に失敗');
        fail('初期データの取得に失敗しました');
      }
    });

    test('複数データポイント（表形式）でのXY座標追加テスト', () async {
      await MetadataTestLogger.log('=== 複数データポイント（表形式）でのXY座標追加テスト ===');

      // 複数地点のテーブル形式データを作成
      final testMetadata = {
        'type': 'measurement_points',
        'contents': [
          {'名前': '東京駅', '緯度': '35.6762', '経度': '139.6503', '標高': '10m'},
          {'名前': '大阪駅', '緯度': '34.6937', '経度': '135.5023', '標高': '15m'},
          {'名前': '札幌駅', '緯度': '43.0642', '経度': '141.3469', '標高': '8m'},
        ],
      };

      // 最初の地点の座標を代表座標として使用
      final representativePoint = LatLng(35.6762, 139.6503);

      final result = await MetadataParser.parseMetadataWithCoordinates(
        testMetadata,
        representativePoint,
      );

      expect(result, isNotNull);
      await MetadataTestLogger.log('複数データポイント結果:');
      await MetadataTestLogger.log('  タイトル: ${result!.title}');
      await MetadataTestLogger.log('  タイプ: ${result.type}');
      await MetadataTestLogger.log('  ヘッダー: ${result.headers}');
      await MetadataTestLogger.log('  行数: ${result.rows.length}');
      await MetadataTestLogger.log(
        '  選択座標系: ${result.selectedCoordinateSystem}',
      );

      // 各行のデータをログ出力
      for (int rowIndex = 0; rowIndex < result.rows.length; rowIndex++) {
        await MetadataTestLogger.log(
          '  行${rowIndex + 1}: ${result.rows[rowIndex]}',
        );
      }

      // X座標とY座標の列インデックスを探す
      int? xIndex, yIndex;
      for (int colIndex = 0; colIndex < result.headers.length; colIndex++) {
        if (result.headers[colIndex] == 'X座標') {
          xIndex = colIndex;
        } else if (result.headers[colIndex] == 'Y座標') {
          yIndex = colIndex;
        }
      }

      expect(xIndex, isNotNull, reason: 'X座標列が見つかりません');
      expect(yIndex, isNotNull, reason: 'Y座標列が見つかりません');

      if (xIndex != null && yIndex != null) {
        // 各行のX座標とY座標が異なることを確認
        final coordinates = <String, Map<String, String>>{};

        for (int rowIndex = 0; rowIndex < result.rows.length; rowIndex++) {
          final row = result.rows[rowIndex];
          if (xIndex < row.length && yIndex < row.length) {
            final name = row[0]; // 名前は最初の列
            final xValue = row[xIndex];
            final yValue = row[yIndex];

            coordinates[name] = {'x': xValue, 'y': yValue};

            await MetadataTestLogger.log('$name - X座標: $xValue, Y座標: $yValue');

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

        // 地点間で座標が異なることを確認
        final names = coordinates.keys.toList();
        for (int i = 0; i < names.length; i++) {
          for (int j = i + 1; j < names.length; j++) {
            final name1 = names[i];
            final name2 = names[j];
            final coord1 = coordinates[name1]!;
            final coord2 = coordinates[name2]!;

            await MetadataTestLogger.log('$name1 vs $name2:');
            await MetadataTestLogger.log(
              '  $name1: X=${coord1['x']}, Y=${coord1['y']}',
            );
            await MetadataTestLogger.log(
              '  $name2: X=${coord2['x']}, Y=${coord2['y']}',
            );

            // 異なる地点で異なる座標が得られることを確認
            final sameX = coord1['x'] == coord2['x'];
            final sameY = coord1['y'] == coord2['y'];

            expect(
              sameX && sameY,
              isFalse,
              reason:
                  '$name1 と $name2 で同じ座標が得られました: X=${coord1['x']}, Y=${coord1['y']}',
            );

            if (!sameX || !sameY) {
              await MetadataTestLogger.log('  ✓ 異なる座標が得られました');
            }
          }
        }
      }

      await MetadataTestLogger.log('✓ 複数データポイント（表形式）テスト成功');
    });

    tearDownAll(() async {
      await MetadataTestLogger.log('=== メタデータパーサーテスト終了 ===');
    });
  });
}
