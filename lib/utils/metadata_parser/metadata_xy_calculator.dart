import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';

import 'metadata_coordinate_utils.dart';
import 'metadata_gps_data_parser.dart';
import 'metadata_table_data.dart';

/// XY座標の計算・集約を扱うクラス
class MetadataXYCalculator {
  /// 元データから直接最初・最後・平均のXY座標をすべて計算
  static Future<Map<String, String>> calculateAllXYCoordinatesFromOriginalData(
    MetadataTableData baseData,
    Map<String, String> avgXYCoordinates,
    String epsgCode,
  ) async {
    try {
      List<dynamic>? usedGpsData;

      if (baseData.type == 'measurement_log') {
        int? originalDataColumnIndex;
        for (int i = 0; i < baseData.headers.length; i++) {
          if (baseData.headers[i] == '元データ') {
            originalDataColumnIndex = i;
            break;
          }
        }

        AppLogger.debug(
          '[MetadataParser] 元データ列検索: インデックス=$originalDataColumnIndex',
        );

        if (originalDataColumnIndex != null && baseData.rows.isNotEmpty) {
          final firstRow = baseData.rows[0];
          if (originalDataColumnIndex < firstRow.length) {
            final usedGpsDataString = firstRow[originalDataColumnIndex];
            AppLogger.debug(
              '[MetadataParser] 元データ文字列取得成功: 長さ=${usedGpsDataString.length}',
            );
            usedGpsData =
                MetadataGpsDataParser.parseUsedGpsDataString(usedGpsDataString);
          }
        }
      }

      if (usedGpsData != null && usedGpsData.isNotEmpty) {
        AppLogger.debug(
          '[MetadataParser] usedGpsData取得成功: ${usedGpsData.length}件',
        );

        final firstGps = usedGpsData.first as Map<String, dynamic>;
        final lastGps = usedGpsData.last as Map<String, dynamic>;

        final firstPoint = LatLng(
          (firstGps['latitude'] as num).toDouble(),
          (firstGps['longitude'] as num).toDouble(),
        );
        final lastPoint = LatLng(
          (lastGps['latitude'] as num).toDouble(),
          (lastGps['longitude'] as num).toDouble(),
        );

        final firstXY = await MetadataCoordinateUtils.calculateXYCoordinates(
          firstPoint,
          epsgCode,
        );
        final lastXY = await MetadataCoordinateUtils.calculateXYCoordinates(
          lastPoint,
          epsgCode,
        );

        return {
          'x_first': firstXY['x'] ?? 'N/A',
          'y_first': firstXY['y'] ?? 'N/A',
          'x_last': lastXY['x'] ?? 'N/A',
          'y_last': lastXY['y'] ?? 'N/A',
          'x_avg': avgXYCoordinates['x'] ?? 'N/A',
          'y_avg': avgXYCoordinates['y'] ?? 'N/A',
        };
      } else {
        AppLogger.debug(
          '[MetadataParser] usedGpsDataが取得できないため平均値のみ使用',
        );
        return {
          'x_first': avgXYCoordinates['x'] ?? 'N/A',
          'y_first': avgXYCoordinates['y'] ?? 'N/A',
          'x_last': avgXYCoordinates['x'] ?? 'N/A',
          'y_last': avgXYCoordinates['y'] ?? 'N/A',
          'x_avg': avgXYCoordinates['x'] ?? 'N/A',
          'y_avg': avgXYCoordinates['y'] ?? 'N/A',
        };
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標計算エラー: $e');
      return {
        'x_first': 'N/A',
        'y_first': 'N/A',
        'x_last': 'N/A',
        'y_last': 'N/A',
        'x_avg': avgXYCoordinates['x'] ?? 'N/A',
        'y_avg': avgXYCoordinates['y'] ?? 'N/A',
      };
    }
  }

  /// 最初・最後・平均のXY座標をすべて計算
  static Future<Map<String, String>> calculateAllXYCoordinates(
    MetadataTableData baseData,
    Map<String, String> avgXYCoordinates,
    String epsgCode,
  ) async {
    try {
      List<dynamic>? usedGpsData;

      if (baseData.type == 'measurement_log') {
        usedGpsData =
            MetadataGpsDataParser.extractUsedGpsDataFromOriginalMetadata(
              baseData,
            );

        if (usedGpsData != null && usedGpsData.isNotEmpty) {
          AppLogger.debug(
            '[MetadataParser] 元のメタデータからusedGpsDataを直接取得成功: ${usedGpsData.length}件',
          );
        }
      }

      if (usedGpsData == null || usedGpsData.isEmpty) {
        String? usedGpsDataString;
        for (final row in baseData.rows) {
          if (row.length >= 2 && row[0] == '元データ') {
            usedGpsDataString = row[1];
            break;
          }
        }

        if (usedGpsDataString == null ||
            usedGpsDataString == 'null' ||
            usedGpsDataString.isEmpty) {
          AppLogger.debug(
            '[MetadataParser] usedGpsDataが見つからないため平均値のみ使用',
          );
          return {
            'x_first': avgXYCoordinates['x'] ?? 'N/A',
            'y_first': avgXYCoordinates['y'] ?? 'N/A',
            'x_last': avgXYCoordinates['x'] ?? 'N/A',
            'y_last': avgXYCoordinates['y'] ?? 'N/A',
            'x_avg': avgXYCoordinates['x'] ?? 'N/A',
            'y_avg': avgXYCoordinates['y'] ?? 'N/A',
          };
        }

        try {
          final cleaned = usedGpsDataString.replaceAll('null', 'null');
          usedGpsData =
              MetadataGpsDataParser.parseUsedGpsDataString(cleaned);
        } catch (e) {
          AppLogger.debug('[MetadataParser] usedGpsDataパースエラー: $e');
          usedGpsData = null;
        }

        if (usedGpsData == null || usedGpsData.isEmpty) {
          AppLogger.debug(
            '[MetadataParser] usedGpsDataが空のため平均値のみ使用',
          );
          return {
            'x_first': avgXYCoordinates['x'] ?? 'N/A',
            'y_first': avgXYCoordinates['y'] ?? 'N/A',
            'x_last': avgXYCoordinates['x'] ?? 'N/A',
            'y_last': avgXYCoordinates['y'] ?? 'N/A',
            'x_avg': avgXYCoordinates['x'] ?? 'N/A',
            'y_avg': avgXYCoordinates['y'] ?? 'N/A',
          };
        }
      }

      final firstGps = usedGpsData.first as Map<String, dynamic>;
      final lastGps = usedGpsData.last as Map<String, dynamic>;

      AppLogger.debug(
        '[MetadataParser] 最初のGPS: ${firstGps['latitude']}, ${firstGps['longitude']}',
      );
      AppLogger.debug(
        '[MetadataParser] 最後のGPS: ${lastGps['latitude']}, ${lastGps['longitude']}',
      );

      final firstPoint = LatLng(
        (firstGps['latitude'] as num).toDouble(),
        (firstGps['longitude'] as num).toDouble(),
      );
      final lastPoint = LatLng(
        (lastGps['latitude'] as num).toDouble(),
        (lastGps['longitude'] as num).toDouble(),
      );

      final firstXY = await MetadataCoordinateUtils.calculateXYCoordinates(
        firstPoint,
        epsgCode,
      );
      final lastXY = await MetadataCoordinateUtils.calculateXYCoordinates(
        lastPoint,
        epsgCode,
      );

      return {
        'x_first': firstXY['x'] ?? 'N/A',
        'y_first': firstXY['y'] ?? 'N/A',
        'x_last': lastXY['x'] ?? 'N/A',
        'y_last': lastXY['y'] ?? 'N/A',
        'x_avg': avgXYCoordinates['x'] ?? 'N/A',
        'y_avg': avgXYCoordinates['y'] ?? 'N/A',
      };
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標計算エラー: $e');
      return {
        'x_first': 'N/A',
        'y_first': 'N/A',
        'x_last': 'N/A',
        'y_last': 'N/A',
        'x_avg': avgXYCoordinates['x'] ?? 'N/A',
        'y_avg': avgXYCoordinates['y'] ?? 'N/A',
      };
    }
  }

  /// キー・値形式のデータにXY座標を追加
  static Future<MetadataTableData> addXYCoordinatesToKeyValueFormat(
    MetadataTableData baseData,
    Map<String, String> xyCoordinates,
    Map<String, String> coordinateOptions,
    String defaultEpsg,
  ) async {
    AppLogger.debug('[MetadataParser] キー・値形式でXY座標追加開始');

    final newRows = <List<String>>[];
    newRows.addAll(baseData.rows);

    final allXYCoordinates = await calculateAllXYCoordinates(
      baseData,
      xyCoordinates,
      defaultEpsg,
    );

    int latitudeIndex = -1;
    int longitudeIndex = -1;
    for (int i = 0; i < baseData.rows.length; i++) {
      if (baseData.rows[i][0] == '緯度') {
        latitudeIndex = i;
      } else if (baseData.rows[i][0] == '経度') {
        longitudeIndex = i;
      }
    }

    int insertIndex = 0;

    if (longitudeIndex >= 0) {
      insertIndex = longitudeIndex + 1;
    } else if (latitudeIndex >= 0) {
      insertIndex = latitudeIndex + 1;
    } else {
      insertIndex = newRows.length;
    }

    newRows.insert(insertIndex++, [
      'X座標（最初）',
      allXYCoordinates['x_first'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'Y座標（最初）',
      allXYCoordinates['y_first'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'X座標（最後）',
      allXYCoordinates['x_last'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'Y座標（最後）',
      allXYCoordinates['y_last'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'X座標（平均）',
      allXYCoordinates['x_avg'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'Y座標（平均）',
      allXYCoordinates['y_avg'] ?? 'N/A',
    ]);

    AppLogger.debug(
      '[MetadataParser] キー・値形式でXY座標追加完了: 行数=${newRows.length}',
    );

    return MetadataTableData(
      headers: baseData.headers,
      rows: newRows,
      type: baseData.type,
      title: '${baseData.title} (${coordinateOptions[defaultEpsg]})',
      coordinateSystemOptions: coordinateOptions,
      selectedCoordinateSystem: defaultEpsg,
    );
  }

  /// キー・値形式の行データのXY座標をすべて更新
  static List<List<String>> updateXYInKeyValueRows(
    List<List<String>> originalRows,
    Map<String, String> allXYCoordinates,
  ) {
    final newRows = <List<String>>[];

    for (final row in originalRows) {
      if (row.length >= 2) {
        if (row[0] == 'X座標（最初）') {
          newRows.add([row[0], allXYCoordinates['x_first'] ?? 'N/A']);
        } else if (row[0] == 'Y座標（最初）') {
          newRows.add([row[0], allXYCoordinates['y_first'] ?? 'N/A']);
        } else if (row[0] == 'X座標（最後）') {
          newRows.add([row[0], allXYCoordinates['x_last'] ?? 'N/A']);
        } else if (row[0] == 'Y座標（最後）') {
          newRows.add([row[0], allXYCoordinates['y_last'] ?? 'N/A']);
        } else if (row[0] == 'X座標（平均）') {
          newRows.add([row[0], allXYCoordinates['x_avg'] ?? 'N/A']);
        } else if (row[0] == 'Y座標（平均）') {
          newRows.add([row[0], allXYCoordinates['y_avg'] ?? 'N/A']);
        } else {
          newRows.add(List.from(row));
        }
      } else {
        newRows.add(List.from(row));
      }
    }

    return newRows;
  }
}
