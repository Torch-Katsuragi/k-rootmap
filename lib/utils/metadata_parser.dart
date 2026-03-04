// K-MAPS: メタデータパーサーユーティリティ
// kmaps_metadataカラムの内容をパースして表形式データに変換

export 'metadata_parser/metadata_table_data.dart';
export 'metadata_parser/metadata_content_parser.dart';
export 'metadata_parser/metadata_coordinate_utils.dart';
export 'metadata_parser/metadata_gps_data_parser.dart';
export 'metadata_parser/metadata_xy_calculator.dart';
export 'metadata_parser/metadata_xy_table_handler.dart';

import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';

import 'metadata_parser/metadata_content_parser.dart';
import 'metadata_parser/metadata_coordinate_utils.dart';
import 'metadata_parser/metadata_table_data.dart';
import 'metadata_parser/metadata_xy_calculator.dart';
import 'metadata_parser/metadata_xy_table_handler.dart';

/// メタデータパーサークラス
class MetadataParser {
  /// メタデータをパースして表形式データに変換（XY座標自動追加機能付き）
  static Future<MetadataTableData?> parseMetadataWithCoordinates(
    Map<String, dynamic> metadata,
    LatLng? featureLatLng, {
    String? selectedEpsgCode,
  }) async {
    try {
      final baseData = MetadataContentParser.parseMetadata(metadata);
      if (baseData == null || featureLatLng == null) {
        return baseData;
      }

      AppLogger.debug(
        '[MetadataParser] 基本データ: ヘッダー=${baseData.headers}, 行数=${baseData.rows.length}',
      );

      final coordinateOptions =
          await MetadataCoordinateUtils.generateCoordinateSystemOptions(
            featureLatLng,
          );
      final defaultEpsg = selectedEpsgCode ?? coordinateOptions.keys.first;

      final xyCoordinates =
          await MetadataCoordinateUtils.calculateXYCoordinates(
            featureLatLng,
            defaultEpsg,
          );

      AppLogger.debug(
        '[MetadataParser] XY座標計算結果: X=${xyCoordinates['x']}, Y=${xyCoordinates['y']}',
      );

      if (baseData.headers.length == 2 &&
          baseData.headers[0] == 'キー' &&
          baseData.headers[1] == '値') {
        return await MetadataXYCalculator.addXYCoordinatesToKeyValueFormat(
          baseData,
          xyCoordinates,
          coordinateOptions,
          defaultEpsg,
        );
      } else {
        return await MetadataXYTableHandler.addXYCoordinatesToTableFormat(
          baseData,
          xyCoordinates,
          coordinateOptions,
          defaultEpsg,
        );
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標追加エラー: $e');
      return MetadataContentParser.parseMetadata(metadata);
    }
  }

  /// メタデータをパースして表形式データに変換
  static MetadataTableData? parseMetadata(Map<String, dynamic> metadata) {
    return MetadataContentParser.parseMetadata(metadata);
  }

  /// XY座標を再計算
  static Future<MetadataTableData> recalculateXYCoordinates(
    MetadataTableData originalData,
    LatLng point,
    String newEpsgCode,
  ) async {
    AppLogger.debug('[MetadataParser] XY座標再計算開始');
    AppLogger.debug(
      '[MetadataParser] 元のEPSG: ${originalData.selectedCoordinateSystem}',
    );
    AppLogger.debug('[MetadataParser] 新しいEPSG: $newEpsgCode');
    AppLogger.debug(
      '[MetadataParser] 座標: (${point.latitude}, ${point.longitude})',
    );

    final newXY = await MetadataCoordinateUtils.calculateXYCoordinates(
      point,
      newEpsgCode,
    );
    AppLogger.debug(
      '[MetadataParser] 新しいXY座標: X=${newXY['x']}, Y=${newXY['y']}',
    );

    final newCoordinateSystemName =
        originalData.coordinateSystemOptions?[newEpsgCode] ?? 'Unknown';
    AppLogger.debug('[MetadataParser] 新しい座標系名: $newCoordinateSystemName');

    final allNewXYCoordinates =
        await MetadataXYCalculator.calculateAllXYCoordinates(
          originalData,
          newXY,
          newEpsgCode,
        );

    List<List<String>> updatedRows;
    if (originalData.headers.length == 2 &&
        originalData.headers[0] == 'キー' &&
        originalData.headers[1] == '値') {
      updatedRows = MetadataXYCalculator.updateXYInKeyValueRows(
        originalData.rows,
        allNewXYCoordinates,
      );
      AppLogger.debug('[MetadataParser] キー・値形式でXY座標更新完了');
    } else {
      updatedRows = await MetadataXYTableHandler.updateXYInRows(
        originalData.rows,
        originalData.headers,
        allNewXYCoordinates,
        point,
        newEpsgCode,
      );
      AppLogger.debug('[MetadataParser] 表形式でXY座標更新完了');
    }

    final updatedData = MetadataTableData(
      title:
          '${originalData.type == 'measurement_log' ? 'GPS測量ログ' : 'メタデータ'} ($newCoordinateSystemName)',
      headers: originalData.headers,
      rows: updatedRows,
      type: originalData.type,
      selectedCoordinateSystem: newEpsgCode,
      coordinateSystemOptions: originalData.coordinateSystemOptions,
    );

    AppLogger.debug('[MetadataParser] XY座標再計算完了');
    return updatedData;
  }
}



