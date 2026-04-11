import 'package:root_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';

import '../address_converter.dart';
import '../coordinate_converter.dart';
import 'metadata_coordinate_utils.dart';
import 'metadata_gps_data_parser.dart';
import 'metadata_table_data.dart';
import 'metadata_xy_calculator.dart';
import '../../i18n/strings.g.dart';

/// テーブル形式データへのXY座標追加・更新を扱うクラス
class MetadataXYTableHandler {
  /// 通常の表形式のデータにXY座標を追加
  static Future<MetadataTableData> addXYCoordinatesToTableFormat(
    MetadataTableData baseData,
    Map<String, String> xyCoordinates,
    Map<String, String> coordinateOptions,
    String defaultEpsg,
  ) async {
    AppLogger.debug('[MetadataParser] 表形式でXY座標追加開始');

    int? latIndex, lngIndex;
    for (int i = 0; i < baseData.headers.length; i++) {
      if (baseData.headers[i] == t.metadata.latitude) {
        latIndex = i;
      } else if (baseData.headers[i] == t.metadata.longitude) {
        lngIndex = i;
      }
    }

    final newHeaders = <String>[];
    final newRows = <List<String>>[];

    for (int i = 0; i < baseData.headers.length; i++) {
      newHeaders.add(baseData.headers[i]);

      if (baseData.headers[i] == t.metadata.longitude) {
        newHeaders.addAll([
          'X座標（最初）',
          'Y座標（最初）',
          'X座標（最後）',
          'Y座標（最後）',
          'X座標（平均）',
          'Y座標（平均）',
        ]);
      }
    }

    AppLogger.debug('[MetadataParser] 新しいヘッダー: $newHeaders');

    final allXYCoordinates =
        await MetadataXYCalculator.calculateAllXYCoordinatesFromOriginalData(
          baseData,
          xyCoordinates,
          defaultEpsg,
        );

    String? cachedState;
    if (latIndex != null && lngIndex != null && baseData.rows.isNotEmpty) {
      try {
        final firstRow = baseData.rows[0];
        if (latIndex < firstRow.length && lngIndex < firstRow.length) {
          final lat = double.parse(firstRow[latIndex]);
          final lng = double.parse(firstRow[lngIndex]);
          final firstPoint = LatLng(lat, lng);

          AppLogger.debug(
            '[MetadataParser] 最初の座標でstate取得: ($lat, $lng)',
          );
          final address = await AddressConverter.getAddressFromLatLng(
            firstPoint,
          );
          if (address != null) {
            cachedState = CoordinateConverter.getStateFromAddress(address);
            AppLogger.debug(
              '[MetadataParser] キャッシュされたstate: $cachedState',
            );
          }
        }
      } catch (e) {
        AppLogger.debug('[MetadataParser] state取得エラー: $e');
      }
    }

    int? originalDataColumnIndex;
    for (int i = 0; i < baseData.headers.length; i++) {
      if (baseData.headers[i] == t.metadata.rawData) {
        originalDataColumnIndex = i;
        break;
      }
    }

    for (int rowIndex = 0; rowIndex < baseData.rows.length; rowIndex++) {
      final originalRow = baseData.rows[rowIndex];
      final newRow = <String>[];

      String xFirstCoord = allXYCoordinates['x_first'] ?? 'N/A';
      String yFirstCoord = allXYCoordinates['y_first'] ?? 'N/A';
      String xLastCoord = allXYCoordinates['x_last'] ?? 'N/A';
      String yLastCoord = allXYCoordinates['y_last'] ?? 'N/A';
      String xAvgCoord = allXYCoordinates['x_avg'] ?? 'N/A';
      String yAvgCoord = allXYCoordinates['y_avg'] ?? 'N/A';

      if (originalDataColumnIndex != null &&
          originalDataColumnIndex < originalRow.length) {
        try {
          final rowUsedGpsDataString = originalRow[originalDataColumnIndex];
          final rowUsedGpsData =
              MetadataGpsDataParser.parseUsedGpsDataString(rowUsedGpsDataString);

          if (rowUsedGpsData != null && rowUsedGpsData.isNotEmpty) {
            AppLogger.debug(
              '[MetadataParser] 行${rowIndex + 1}: 個別GPS データ${rowUsedGpsData.length}件',
            );

            final rowFirstGps = rowUsedGpsData.first as Map<String, dynamic>;
            final rowLastGps = rowUsedGpsData.last as Map<String, dynamic>;

            final rowFirstPoint = LatLng(
              (rowFirstGps['latitude'] as num).toDouble(),
              (rowFirstGps['longitude'] as num).toDouble(),
            );
            final rowLastPoint = LatLng(
              (rowLastGps['latitude'] as num).toDouble(),
              (rowLastGps['longitude'] as num).toDouble(),
            );

            final rowFirstXY =
                await MetadataCoordinateUtils.calculateXYCoordinates(
                  rowFirstPoint,
                  defaultEpsg,
                  cachedState: cachedState,
                );
            final rowLastXY =
                await MetadataCoordinateUtils.calculateXYCoordinates(
                  rowLastPoint,
                  defaultEpsg,
                  cachedState: cachedState,
                );

            xFirstCoord = rowFirstXY['x'] ?? 'N/A';
            yFirstCoord = rowFirstXY['y'] ?? 'N/A';
            xLastCoord = rowLastXY['x'] ?? 'N/A';
            yLastCoord = rowLastXY['y'] ?? 'N/A';

            AppLogger.debug(
              '[MetadataParser] 行${rowIndex + 1}: 最初XY=($xFirstCoord, $yFirstCoord), 最後XY=($xLastCoord, $yLastCoord)',
            );
          }
        } catch (e) {
          AppLogger.debug(
            '[MetadataParser] 行${rowIndex + 1}: 個別GPS解析エラー: $e',
          );
        }
      }

      if (latIndex != null &&
          lngIndex != null &&
          latIndex < originalRow.length &&
          lngIndex < originalRow.length) {
        try {
          final latStr = originalRow[latIndex];
          final lngStr = originalRow[lngIndex];
          final lat = double.parse(latStr);
          final lng = double.parse(lngStr);

          final rowPoint = LatLng(lat, lng);
          final rowXY = await MetadataCoordinateUtils.calculateXYCoordinates(
            rowPoint,
            defaultEpsg,
            cachedState: cachedState,
          );
          xAvgCoord = rowXY['x'] ?? 'N/A';
          yAvgCoord = rowXY['y'] ?? 'N/A';

          AppLogger.debug(
            '[MetadataParser] 行${rowIndex + 1}: 平均XY=($xAvgCoord, $yAvgCoord)',
          );
        } catch (e) {
          AppLogger.debug(
            '[MetadataParser] 行${rowIndex + 1}: 平均座標計算エラー: $e',
          );
        }
      }

      for (int i = 0; i < originalRow.length; i++) {
        newRow.add(originalRow[i]);

        if (i == lngIndex) {
          newRow.addAll([
            xFirstCoord,
            yFirstCoord,
            xLastCoord,
            yLastCoord,
            xAvgCoord,
            yAvgCoord,
          ]);
        }
      }

      newRows.add(newRow);
    }

    AppLogger.debug(
      '[MetadataParser] 表形式でXY座標追加完了: 行数=${newRows.length}',
    );

    return MetadataTableData(
      headers: newHeaders,
      rows: newRows,
      type: baseData.type,
      title: '${baseData.title} (${coordinateOptions[defaultEpsg]})',
      coordinateSystemOptions: coordinateOptions,
      selectedCoordinateSystem: defaultEpsg,
    );
  }

  /// 行データのXY座標をすべて更新
  static Future<List<List<String>>> updateXYInRows(
    List<List<String>> originalRows,
    List<String> headers,
    Map<String, String> allXYCoordinates,
    LatLng point,
    String epsgCode,
  ) async {
    final newRows = <List<String>>[];

    int? latIndex, lngIndex;

    for (int i = 0; i < headers.length; i++) {
      if (headers[i] == t.metadata.latitude) {
        latIndex = i;
      } else if (headers[i] == t.metadata.longitude) {
        lngIndex = i;
      }
    }

    String? cachedState;
    if (latIndex != null && lngIndex != null && originalRows.isNotEmpty) {
      try {
        final firstRow = originalRows[0];
        if (latIndex < firstRow.length && lngIndex < firstRow.length) {
          final lat = double.parse(firstRow[latIndex]);
          final lng = double.parse(firstRow[lngIndex]);
          final firstPoint = LatLng(lat, lng);

          AppLogger.debug(
            '[MetadataParser] 更新時の最初の座標でstate取得: ($lat, $lng)',
          );
          final address = await AddressConverter.getAddressFromLatLng(
            firstPoint,
          );
          if (address != null) {
            cachedState = CoordinateConverter.getStateFromAddress(address);
            AppLogger.debug(
              '[MetadataParser] 更新時のキャッシュされたstate: $cachedState',
            );
          }
        }
      } catch (e) {
        AppLogger.debug('[MetadataParser] 更新時のstate取得エラー: $e');
      }
    }

    for (int rowIndex = 0; rowIndex < originalRows.length; rowIndex++) {
      final row = originalRows[rowIndex];
      final newRow = <String>[];

      Map<String, String> rowXYCoordinates = Map.from(allXYCoordinates);

      if (latIndex != null &&
          lngIndex != null &&
          latIndex < row.length &&
          lngIndex < row.length) {
        try {
          final latStr = row[latIndex];
          final lngStr = row[lngIndex];
          final lat = double.parse(latStr);
          final lng = double.parse(lngStr);

          final rowPoint = LatLng(lat, lng);
          final rowXY = await MetadataCoordinateUtils.calculateXYCoordinates(
            rowPoint,
            epsgCode,
            cachedState: cachedState,
          );

          rowXYCoordinates['x_avg'] = rowXY['x'] ?? 'N/A';
          rowXYCoordinates['y_avg'] = rowXY['y'] ?? 'N/A';

          AppLogger.debug(
            '[MetadataParser] 行${rowIndex + 1}更新: 緯度=$lat, 経度=$lng -> 平均XY=${rowXYCoordinates['x_avg']}, ${rowXYCoordinates['y_avg']}',
          );
        } catch (e) {
          AppLogger.debug('[MetadataParser] 行${rowIndex + 1}更新エラー: $e');
        }
      }

      for (int i = 0; i < headers.length; i++) {
        if (headers[i] == 'X座標（最初）') {
          newRow.add(rowXYCoordinates['x_first'] ?? 'N/A');
        } else if (headers[i] == 'Y座標（最初）') {
          newRow.add(rowXYCoordinates['y_first'] ?? 'N/A');
        } else if (headers[i] == 'X座標（最後）') {
          newRow.add(rowXYCoordinates['x_last'] ?? 'N/A');
        } else if (headers[i] == 'Y座標（最後）') {
          newRow.add(rowXYCoordinates['y_last'] ?? 'N/A');
        } else if (headers[i] == 'X座標（平均）') {
          newRow.add(rowXYCoordinates['x_avg'] ?? 'N/A');
        } else if (headers[i] == 'Y座標（平均）') {
          newRow.add(rowXYCoordinates['y_avg'] ?? 'N/A');
        } else {
          newRow.add(row[i]);
        }
      }

      newRows.add(newRow);
    }

    return newRows;
  }
}
