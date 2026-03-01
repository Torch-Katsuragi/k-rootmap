import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';

import '../address_converter.dart';
import '../coordinate_converter.dart';

/// 座標系の選択・変換を扱うユーティリティクラス
class MetadataCoordinateUtils {
  /// 座標系選択肢を生成
  static Future<Map<String, String>> generateCoordinateSystemOptions(
    LatLng point,
  ) async {
    final options = <String, String>{};

    AppLogger.debug(
      '[MetadataParser] 座標系選択肢生成開始: (${point.latitude}, ${point.longitude})',
    );

    final zoneNumber = CoordinateConverter.calculateUTMZone(point.longitude);
    final utmEpsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
    final utmName = 'UTM Zone ${zoneNumber}N';
    options[utmEpsg] = utmName;

    AppLogger.debug('[MetadataParser] UTM座標系選択肢追加: $utmName ($utmEpsg)');

    try {
      AppLogger.debug('[MetadataParser] 住所取得開始...');
      final address = await AddressConverter.getAddressFromLatLng(point);
      AppLogger.debug(
        '[MetadataParser] 住所取得結果: ${address?.displayName ?? "null"}',
      );

      if (address != null) {
        final isJapan = _isJapanAddress(address);
        AppLogger.debug('[MetadataParser] 日本住所判定: $isJapan');

        if (isJapan) {
          AppLogger.debug('[MetadataParser] JGD2011座標系取得開始...');
          final jgd2011System =
              await CoordinateConverter.getBestCoordinateSystem(point);
          AppLogger.debug(
            '[MetadataParser] JGD2011座標系取得結果: ${jgd2011System?.name} (${jgd2011System?.epsgCode})',
          );

          if (jgd2011System != null && jgd2011System.epsgCode != utmEpsg) {
            options[jgd2011System.epsgCode] = jgd2011System.name;
            AppLogger.debug(
              '[MetadataParser] JGD2011座標系選択肢追加: ${jgd2011System.name} (${jgd2011System.epsgCode})',
            );
          } else {
            AppLogger.debug(
              '[MetadataParser] JGD2011座標系が追加されませんでした - システム: ${jgd2011System?.epsgCode}, UTM: $utmEpsg',
            );
          }
        }
      } else {
        AppLogger.debug('[MetadataParser] 住所がnullのため、JGD2011座標系をスキップ');
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] 住所取得エラー: $e');
    }

    AppLogger.debug('[MetadataParser] 最終的な座標系選択肢: $options');
    return options;
  }

  /// 住所が日本かどうかを判定
  static bool _isJapanAddress(Address address) {
    return address.country?.toLowerCase() == 'japan' ||
        address.countryCode?.toLowerCase() == 'jp' ||
        address.displayName.contains('日本') ||
        address.displayName.contains('Japan');
  }

  /// XY座標を計算
  static Future<Map<String, String>> calculateXYCoordinates(
    LatLng point,
    String epsgCode, {
    String? cachedState,
  }) async {
    AppLogger.debug('[MetadataParser] XY座標計算開始: EPSG=$epsgCode');

    try {
      CoordinateSystem? coordinateSystem;

      if (epsgCode.startsWith('326') || epsgCode.startsWith('327')) {
        final zoneNumber = CoordinateConverter.calculateUTMZone(
          point.longitude,
        );
        final expectedEpsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
        final proj4String =
            '+proj=utm +zone=$zoneNumber +datum=WGS84 +units=m +no_defs';

        coordinateSystem = CoordinateSystem(
          name: 'UTM Zone ${zoneNumber}N',
          epsgCode: expectedEpsg,
          proj4String: proj4String,
        );

        AppLogger.debug(
          '[MetadataParser] UTM座標系使用: ${coordinateSystem.name} (${coordinateSystem.epsgCode})',
        );
      } else if (epsgCode.startsWith('667')) {
        AppLogger.debug('[MetadataParser] JGD2011座標系処理開始: $epsgCode');
        coordinateSystem = await _getJGD2011CoordinateSystem(
          epsgCode,
          point,
          cachedState: cachedState,
        );
        AppLogger.debug(
          '[MetadataParser] JGD2011座標系取得結果: ${coordinateSystem?.name} (${coordinateSystem?.epsgCode})',
        );

        if (coordinateSystem == null) {
          AppLogger.debug(
            '[MetadataParser] JGD2011座標系がnullです - EPSGコードから直接作成を試行',
          );
          coordinateSystem = createJGD2011CoordinateSystemFromEpsg(epsgCode);
          AppLogger.debug(
            '[MetadataParser] EPSGコードから作成結果: ${coordinateSystem?.name}',
          );
        }
      } else {
        AppLogger.debug('[MetadataParser] その他の座標系 - 自動判定開始');
        coordinateSystem = await CoordinateConverter.getBestCoordinateSystem(
          point,
          cachedState: cachedState,
        );
        AppLogger.debug(
          '[MetadataParser] 自動判定座標系使用: ${coordinateSystem?.name} (${coordinateSystem?.epsgCode})',
        );
      }

      if (coordinateSystem != null) {
        AppLogger.debug(
          '[MetadataParser] 座標変換開始: ${coordinateSystem.epsgCode}',
        );
        final xy = CoordinateConverter.latLngToXY(
          point,
          coordinateSystem: coordinateSystem,
        );

        AppLogger.debug(
          '[MetadataParser] XY座標計算成功: X=${xy.x.toStringAsFixed(3)}, Y=${xy.y.toStringAsFixed(3)}',
        );
        return {'x': xy.x.toStringAsFixed(3), 'y': xy.y.toStringAsFixed(3)};
      } else {
        AppLogger.debug('[MetadataParser] 座標系がnullです');
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標計算エラー: $e');
    }

    return {'x': 'N/A', 'y': 'N/A'};
  }

  /// JGD2011座標系を取得
  static Future<CoordinateSystem?> _getJGD2011CoordinateSystem(
    String epsgCode,
    LatLng point, {
    String? cachedState,
  }) async {
    if (cachedState != null) {
      AppLogger.debug('[MetadataParser] キャッシュされたstate使用: $cachedState');
      final jgd2011Zone = CoordinateConverter.getJGD2011ZoneFromState(
        cachedState,
      );
      if (jgd2011Zone != null && jgd2011Zone.epsgCode == epsgCode) {
        return jgd2011Zone;
      }
    }

    final address = await AddressConverter.getAddressFromLatLng(point);
    if (address != null) {
      final jgd2011Zone = CoordinateConverter.getJGD2011ZoneFromAddress(
        address,
      );
      if (jgd2011Zone != null && jgd2011Zone.epsgCode == epsgCode) {
        return jgd2011Zone;
      }
    }

    return createJGD2011CoordinateSystemFromEpsg(epsgCode);
  }

  /// EPSGコードからJGD2011座標系を作成
  static CoordinateSystem? createJGD2011CoordinateSystemFromEpsg(
    String epsgCode,
  ) {
    switch (epsgCode) {
      case 'EPSG:6669':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS I',
          epsgCode: 'EPSG:6669',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=129.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6670':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS II',
          epsgCode: 'EPSG:6670',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6671':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS III',
          epsgCode: 'EPSG:6671',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=132.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6672':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IV',
          epsgCode: 'EPSG:6672',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6673':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS V',
          epsgCode: 'EPSG:6673',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6674':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VI',
          epsgCode: 'EPSG:6674',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=crs',
        );
      case 'EPSG:6675':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VII',
          epsgCode: 'EPSG:6675',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6676':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VIII',
          epsgCode: 'EPSG:6676',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6677':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IX',
          epsgCode: 'EPSG:6677',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6678':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS X',
          epsgCode: 'EPSG:6678',
          proj4String:
              '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6679':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS XI',
          epsgCode: 'EPSG:6679',
          proj4String:
              '+proj=tmerc +lat_0=44 +lon_0=140.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6683':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS XV',
          epsgCode: 'EPSG:6683',
          proj4String:
              '+proj=tmerc +lat_0=26 +lon_0=127.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      default:
        return null;
    }
  }
}
