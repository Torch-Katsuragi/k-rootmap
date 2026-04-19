// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
import 'package:root_maps/utils/app_logger.dart';
import 'package:proj4dart/proj4dart.dart';
import 'package:latlong2/latlong.dart';
import 'address_converter.dart';
import '../i18n/strings.g.dart';

/// 緯度経度の範囲を表すクラス
class LatLngBounds {
  final LatLng southwest;
  final LatLng northeast;

  const LatLngBounds(this.southwest, this.northeast);

  /// 指定された点がこの範囲内にあるかどうかを判定
  bool contains(LatLng point) {
    return point.latitude >= southwest.latitude &&
        point.latitude <= northeast.latitude &&
        point.longitude >= southwest.longitude &&
        point.longitude <= northeast.longitude;
  }
}

/// 座標系の定義を管理するクラス
class CoordinateSystem {
  final String name;
  final String epsgCode;
  final String proj4String;
  final LatLngBounds? bounds;

  const CoordinateSystem({
    required this.name,
    required this.epsgCode,
    required this.proj4String,
    this.bounds,
  });

  /// この座標系が指定された緯度経度を含むかどうかを判定
  bool contains(LatLng point) {
    if (bounds == null) return true;
    return bounds!.contains(point);
  }
}

/// 座標変換を管理するクラス
class CoordinateConverter {
  static final List<CoordinateSystem> _coordinateSystems = [
    // UTM座標系（北半球）
    CoordinateSystem(
      name: 'UTM Zone 54N',
      epsgCode: 'EPSG:32654',
      proj4String: '+proj=utm +zone=54 +datum=WGS84 +units=m +no_defs',
      bounds: LatLngBounds(
        const LatLng(0, 138), // 南西
        const LatLng(84, 144), // 北東
      ),
    ),
    // 他の座標系も同様に追加可能
  ];

  /// 都道府県名から平面直角座標系のゾーンを取得
  static CoordinateSystem? getJGD2011ZoneFromAddress(Address address) {
    // まず直接的なstateフィールドをチェック
    String? prefecture = address.state;
    AppLogger.debug('[CoordinateConverter] 住所情報: state=$prefecture');

    // stateがnullの場合、他のフィールドから都道府県を推定
    if (prefecture == null) {
      prefecture = _extractPrefectureFromAddress(address);
      AppLogger.debug('[CoordinateConverter] 推定された都道府県: $prefecture');
    }

    if (prefecture == null) return null;

    // 都道府県名からゾーンを判定し、EPSGコードのみで座標系を生成
    switch (prefecture) {
      case '長崎県':
      case '佐賀県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS I',
          epsgCode: 'EPSG:6669',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=129.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '福岡県':
      case '熊本県':
      case '大分県':
      case '宮崎県':
      case '鹿児島県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS II',
          epsgCode: 'EPSG:6670',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '山口県':
      case '島根県':
      case '広島県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS III',
          epsgCode: 'EPSG:6671',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=132.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '香川県':
      case '愛媛県':
      case '徳島県':
      case '高知県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IV',
          epsgCode: 'EPSG:6672',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '兵庫県':
      case '鳥取県':
      case '岡山県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS V',
          epsgCode: 'EPSG:6673',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '京都府':
      case '大阪府':
      case '福井県':
      case '滋賀県':
      case '三重県':
      case '奈良県':
      case '和歌山県':
        AppLogger.debug('[CoordinateConverter] JGD2011 CS VI を選択 (和歌山県)');
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VI',
          epsgCode: 'EPSG:6674',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '石川県':
      case '富山県':
      case '岐阜県':
      case '愛知県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VII',
          epsgCode: 'EPSG:6675',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '新潟県':
      case '長野県':
      case '山梨県':
      case '静岡県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VIII',
          epsgCode: 'EPSG:6676',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '東京都':
      case '福島県':
      case '栃木県':
      case '茨城県':
      case '埼玉県':
      case '千葉県':
      case '群馬県':
      case '神奈川県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IX',
          epsgCode: 'EPSG:6677',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '青森県':
      case '秋田県':
      case '山形県':
      case '岩手県':
      case '宮城県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS X',
          epsgCode: 'EPSG:6678',
          proj4String:
              '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '北海道':
        // 北海道は複数のゾーンがあるが、とりあえず第XI系を使用
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS XI',
          epsgCode: 'EPSG:6679',
          proj4String:
              '+proj=tmerc +lat_0=44 +lon_0=140.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case '沖縄県':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS XV',
          epsgCode: 'EPSG:6683',
          proj4String:
              '+proj=tmerc +lat_0=26 +lon_0=127.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      default:
        AppLogger.debug('[CoordinateConverter] 未対応の都道府県: $prefecture');
        return null;
    }
  }

  /// 住所データから都道府県を推定
  static String? _extractPrefectureFromAddress(Address address) {
    // displayNameから都道府県を抽出
    final displayName = address.displayName;
    AppLogger.debug('[CoordinateConverter] displayName解析: $displayName');

    // 東京都の特別区を判定
    final tokyoWards = [
      '千代田区',
      '中央区',
      '港区',
      '新宿区',
      '文京区',
      '台東区',
      '墨田区',
      '江東区',
      '品川区',
      '目黒区',
      '大田区',
      '世田谷区',
      '渋谷区',
      '中野区',
      '杉並区',
      '豊島区',
      '北区',
      '荒川区',
      '板橋区',
      '練馬区',
      '足立区',
      '葛飾区',
      '江戸川区',
    ];

    for (final ward in tokyoWards) {
      if (displayName.contains(ward)) {
        AppLogger.debug('[CoordinateConverter] 東京都の特別区を検出: $ward');
        return '東京都';
      }
    }

    // 一般的な都道府県名パターンをチェック
    final prefecturePatterns = [
      '北海道',
      '青森県',
      '岩手県',
      '宮城県',
      '秋田県',
      '山形県',
      '福島県',
      '茨城県',
      '栃木県',
      '群馬県',
      '埼玉県',
      '千葉県',
      '東京都',
      '神奈川県',
      '新潟県',
      '富山県',
      '石川県',
      '福井県',
      '山梨県',
      '長野県',
      '岐阜県',
      '静岡県',
      '愛知県',
      '三重県',
      '滋賀県',
      '京都府',
      '大阪府',
      '兵庫県',
      '奈良県',
      '和歌山県',
      '鳥取県',
      '島根県',
      '岡山県',
      '広島県',
      '山口県',
      '徳島県',
      '香川県',
      '愛媛県',
      '高知県',
      '福岡県',
      '佐賀県',
      '長崎県',
      '熊本県',
      '大分県',
      '宮崎県',
      '鹿児島県',
      '沖縄県',
    ];

    for (final prefecture in prefecturePatterns) {
      if (displayName.contains(prefecture)) {
        AppLogger.debug('[CoordinateConverter] 都道府県を検出: $prefecture');
        return prefecture;
      }
    }

    // cityフィールドから推定
    final city = address.city;
    if (city != null) {
      AppLogger.debug('[CoordinateConverter] city解析: $city');

      // 東京都の特別区をチェック
      for (final ward in tokyoWards) {
        if (city.contains(ward)) {
          AppLogger.debug('[CoordinateConverter] cityから東京都の特別区を検出: $ward');
          return '東京都';
        }
      }

      // 政令指定都市から都道府県を推定
      final cityToPrefecture = {
        '札幌市': '北海道',
        '仙台市': '宮城県',
        'さいたま市': '埼玉県',
        '千葉市': '千葉県',
        '横浜市': '神奈川県',
        '川崎市': '神奈川県',
        '相模原市': '神奈川県',
        '新潟市': '新潟県',
        '静岡市': '静岡県',
        '浜松市': '静岡県',
        '名古屋市': '愛知県',
        '京都市': '京都府',
        '大阪市': '大阪府',
        '堺市': '大阪府',
        '神戸市': '兵庫県',
        '岡山市': '岡山県',
        '広島市': '広島県',
        '北九州市': '福岡県',
        '福岡市': '福岡県',
        '熊本市': '熊本県',
      };

      for (final entry in cityToPrefecture.entries) {
        if (city.contains(entry.key)) {
          AppLogger.debug(
            '[CoordinateConverter] 政令指定都市から都道府県を推定: ${entry.key} -> ${entry.value}',
          );
          return entry.value;
        }
      }
    }

    AppLogger.debug('[CoordinateConverter] 都道府県の推定に失敗');
    return null;
  }

  /// 緯度経度から最適な座標系を取得
  static Future<CoordinateSystem?> getBestCoordinateSystem(
    LatLng point, {
    String? cachedState,
  }) async {
    try {
      // キャッシュされたstateがある場合はそれを使用
      if (cachedState != null) {
        AppLogger.debug('[CoordinateConverter] キャッシュされたstate使用: $cachedState');
        final jgd2011Zone = getJGD2011ZoneFromState(cachedState);
        if (jgd2011Zone != null) {
          AppLogger.debug(
            '[CoordinateConverter] キャッシュからJGD2011座標系: ${jgd2011Zone.name} (${jgd2011Zone.epsgCode})',
          );
          return Future.value(jgd2011Zone);
        }
      }

      // キャッシュがない場合は住所を取得
      final address = await AddressConverter.getAddressFromLatLng(point);
      if (address != null) {
        // 住所から平面直角座標系を判定
        final jgd2011Zone = getJGD2011ZoneFromAddress(address);
        AppLogger.debug(
          '[CoordinateConverter] JGD2011座標系: ${jgd2011Zone?.name} (${jgd2011Zone?.epsgCode})',
        );
        if (jgd2011Zone != null) {
          return Future.value(jgd2011Zone);
        }
      }

      // 住所が取得できない場合は、緯度経度からUTMゾーンを動的に生成
      final zoneNumber = calculateUTMZone(point.longitude);
      final epsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
      final proj4String =
          '+proj=utm +zone=$zoneNumber +datum=WGS84 +units=m +no_defs';

      final utmSystem = CoordinateSystem(
        name: 'UTM Zone ${zoneNumber}N',
        epsgCode: epsg,
        proj4String: proj4String,
      );

      AppLogger.debug(
        '[CoordinateConverter] UTM座標系を動的生成: ${utmSystem.name} (${utmSystem.epsgCode})',
      );
      return Future.value(utmSystem);
    } catch (e) {
      AppLogger.debug('座標系判定エラー: $e');
      return Future.value(null);
    }
  }

  /// stateからJGD2011座標系を取得
  static CoordinateSystem? getJGD2011ZoneFromState(String state) {
    AppLogger.debug('[CoordinateConverter] state情報: $state');

    // 都道府県名からJGD2011座標系を判定
    if (state.contains('北海道')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS XI',
        epsgCode: 'EPSG:6679',
        proj4String:
            '+proj=tmerc +lat_0=44 +lon_0=140.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('青森') ||
        state.contains('秋田') ||
        state.contains('岩手')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS X',
        epsgCode: 'EPSG:6678',
        proj4String:
            '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('宮城') ||
        state.contains('福島') ||
        state.contains('山形')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS IX',
        epsgCode: 'EPSG:6677',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('茨城') ||
        state.contains('栃木') ||
        state.contains('群馬') ||
        state.contains('埼玉')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS IX',
        epsgCode: 'EPSG:6677',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('千葉') ||
        state.contains('東京') ||
        state.contains('神奈川')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS IX',
        epsgCode: 'EPSG:6677',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('新潟') || state.contains('長野')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS VIII',
        epsgCode: 'EPSG:6676',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('山梨') || state.contains('静岡')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS VIII',
        epsgCode: 'EPSG:6676',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('富山') ||
        state.contains('石川') ||
        state.contains('福井') ||
        state.contains('岐阜')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS VII',
        epsgCode: 'EPSG:6675',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('愛知') || state.contains('三重')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS VII',
        epsgCode: 'EPSG:6675',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('滋賀') ||
        state.contains('京都') ||
        state.contains('大阪') ||
        state.contains('兵庫') ||
        state.contains('奈良') ||
        state.contains('和歌山')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS VI',
        epsgCode: 'EPSG:6674',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=crs',
      );
    } else if (state.contains('鳥取') ||
        state.contains('島根') ||
        state.contains('岡山') ||
        state.contains('広島') ||
        state.contains('山口')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS V',
        epsgCode: 'EPSG:6673',
        proj4String:
            '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('香川') ||
        state.contains('愛媛') ||
        state.contains('徳島') ||
        state.contains('高知')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS IV',
        epsgCode: 'EPSG:6672',
        proj4String:
            '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('福岡') ||
        state.contains('佐賀') ||
        state.contains('長崎') ||
        state.contains('熊本') ||
        state.contains('大分') ||
        state.contains('宮崎') ||
        state.contains('鹿児島')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS II',
        epsgCode: 'EPSG:6670',
        proj4String:
            '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    } else if (state.contains('沖縄')) {
      return CoordinateSystem(
        name: 'JGD2011 / Japan Plane Rectangular CS XV',
        epsgCode: 'EPSG:6683',
        proj4String:
            '+proj=tmerc +lat_0=26 +lon_0=127.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );
    }

    AppLogger.debug('[CoordinateConverter] 該当するJGD2011座標系が見つかりませんでした: $state');
    return null;
  }

  /// 住所からstateを取得
  static String? getStateFromAddress(Address address) {
    // 都道府県情報を取得
    String? state = address.state;

    // stateがnullの場合はdisplayNameから都道府県を抽出
    if (state == null || state.isEmpty) {
      state = _extractPrefectureFromDisplayName(address.displayName);
    }

    AppLogger.debug('[CoordinateConverter] 住所から取得したstate: $state');
    return state;
  }

  /// 住所文字列から都道府県を抽出
  static String? _extractPrefectureFromDisplayName(String displayName) {
    final prefectures = [
      '北海道',
      '青森県',
      '岩手県',
      '宮城県',
      '秋田県',
      '山形県',
      '福島県',
      '茨城県',
      '栃木県',
      '群馬県',
      '埼玉県',
      '千葉県',
      '東京都',
      '神奈川県',
      '新潟県',
      '富山県',
      '石川県',
      '福井県',
      '山梨県',
      '長野県',
      '岐阜県',
      '静岡県',
      '愛知県',
      '三重県',
      '滋賀県',
      '京都府',
      '大阪府',
      '兵庫県',
      '奈良県',
      '和歌山県',
      '鳥取県',
      '島根県',
      '岡山県',
      '広島県',
      '山口県',
      '徳島県',
      '香川県',
      '愛媛県',
      '高知県',
      '福岡県',
      '佐賀県',
      '長崎県',
      '熊本県',
      '大分県',
      '宮崎県',
      '鹿児島県',
      '沖縄県',
    ];

    for (final prefecture in prefectures) {
      if (displayName.contains(prefecture)) {
        return prefecture;
      }
    }

    return null;
  }

  /// 緯度経度からXY座標に変換
  static Point latLngToXY(LatLng point, {CoordinateSystem? coordinateSystem}) {
    try {
      // coordinateSystemが指定されていない場合はUTMゾーンを使用
      if (coordinateSystem == null) {
        final zoneNumber = calculateUTMZone(point.longitude);
        final epsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
        final proj4String =
            '+proj=utm +zone=$zoneNumber +datum=WGS84 +units=m +no_defs';

        coordinateSystem = CoordinateSystem(
          name: 'UTM Zone ${zoneNumber}N',
          epsgCode: epsg,
          proj4String: proj4String,
        );
      }

      AppLogger.debug(
        '[CoordinateConverter] 座標変換: ${coordinateSystem.epsgCode} (${coordinateSystem.proj4String})',
      );

      // WGS84 (EPSG:4326) から目標座標系への変換
      final source = Projection.get('EPSG:4326'); // WGS84
      if (source == null) {
        throw Exception('WGS84座標系の初期化に失敗');
      }

      // 目標座標系のProjectionを取得または作成
      Projection? target = Projection.get(coordinateSystem.epsgCode);
      AppLogger.debug(
        '[CoordinateConverter] 既存Projection取得: ${target != null ? "成功" : "失敗"}',
      );

      if (target == null && coordinateSystem.proj4String.isNotEmpty) {
        AppLogger.debug(
          '[CoordinateConverter] 新規Projection作成: ${coordinateSystem.epsgCode}',
        );
        AppLogger.debug(
          '[CoordinateConverter] proj4文字列: ${coordinateSystem.proj4String}',
        );
        target = Projection.add(
          coordinateSystem.epsgCode,
          coordinateSystem.proj4String,
        );
        AppLogger.debug(
          '[CoordinateConverter] 新規Projection作成結果: ${"成功"}',
        );
      }

      if (target == null) {
        throw Exception(t.services.coordSystemInitFailed(code: coordinateSystem.epsgCode));
      }

      // WGS84から目標座標系への変換
      final p = Point(x: point.longitude, y: point.latitude);
      AppLogger.debug(
        '[CoordinateConverter] 変換前座標: (${point.latitude}, ${point.longitude})',
      );

      final result = source.transform(target, p);

      AppLogger.debug(
        '[CoordinateConverter] 変換後座標: (${result.x.toStringAsFixed(3)}, ${result.y.toStringAsFixed(3)})',
      );

      // JGD2011の場合、座標軸の順序を修正
      if (coordinateSystem.epsgCode.startsWith('EPSG:667')) {
        AppLogger.debug('[CoordinateConverter] JGD2011座標系検出 - 座標軸順序修正');
        AppLogger.debug(
          '[CoordinateConverter] 変換前: X=${result.x.toStringAsFixed(3)}, Y=${result.y.toStringAsFixed(3)}',
        );

        // JGD2011では X=Northing, Y=Easting だが、
        // proj4dartの結果では順序が逆になっている可能性がある
        final correctedResult = Point(x: result.y, y: result.x);

        AppLogger.debug(
          '[CoordinateConverter] 修正後: X(Northing)=${correctedResult.x.toStringAsFixed(3)}, Y(Easting)=${correctedResult.y.toStringAsFixed(3)}',
        );
        return correctedResult;
      }

      return result;
    } catch (e) {
      AppLogger.debug('[CoordinateConverter] 座標変換エラー: $e');
      rethrow;
    }
  }

  /// XY座標から緯度経度に変換
  static LatLng xyToLatLng(Point point, CoordinateSystem coordinateSystem) {
    try {
      // 目標座標系からWGS84への変換
      Projection? source = Projection.get(coordinateSystem.epsgCode);
      if (source == null && coordinateSystem.proj4String.isNotEmpty) {
        source = Projection.add(
          coordinateSystem.epsgCode,
          coordinateSystem.proj4String,
        );
      }

      if (source == null) {
        throw Exception(t.services.coordSystemInitFailed(code: coordinateSystem.epsgCode));
      }

      final target = Projection.get('EPSG:4326'); // WGS84
      if (target == null) {
        throw Exception('WGS84座標系の初期化に失敗');
      }

      // 目標座標系からWGS84への変換
      final result = source.transform(target, point);
      return LatLng(result.y, result.x);
    } catch (e) {
      AppLogger.debug('[CoordinateConverter] 逆変換エラー: $e');
      rethrow;
    }
  }

  /// 利用可能な座標系のリストを取得
  static List<CoordinateSystem> get availableCoordinateSystems =>
      _coordinateSystems;

  /// UTMゾーン番号を計算
  static int calculateUTMZone(double longitude) {
    // 経度からUTMゾーン番号を計算（1-60）
    return ((longitude + 180) / 6).floor() + 1;
  }

  /// UTMゾーン文字を計算
  static String calculateUTMLetter(double latitude) {
    // 緯度からUTMゾーン文字を計算
    final letters = 'CDEFGHJKLMNPQRSTUVWX';
    final index = ((latitude + 80) / 8).floor();
    return letters[index];
  }

  /// 緯度経度からUTM座標に変換
  static Map<String, dynamic> latLonToUTM(LatLng latLon) {
    final zoneNumber = calculateUTMZone(latLon.longitude);
    final zoneLetter = calculateUTMLetter(latLon.latitude);
    final epsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';

    // WGS84からUTMへの変換
    final source = Projection.get('EPSG:4326')!; // WGS84
    final target = Projection.get(epsg)!;

    final point = Point(x: latLon.longitude, y: latLon.latitude);
    final transformed = source.transform(target, point);

    return {
      'easting': transformed.x,
      'northing': transformed.y,
      'zoneNumber': zoneNumber,
      'zoneLetter': zoneLetter,
      'epsg': epsg,
    };
  }

  /// UTM座標から緯度経度に変換
  static LatLng utmToLatLon({
    required double easting,
    required double northing,
    required int zoneNumber,
    required String zoneLetter,
  }) {
    final epsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';

    // UTMからWGS84への変換
    final source = Projection.get(epsg)!;
    final target = Projection.get('EPSG:4326')!; // WGS84

    final point = Point(x: easting, y: northing);
    final transformed = source.transform(target, point);

    return LatLng(transformed.y, transformed.x);
  }

  /// 緯度経度から最適なUTMゾーンを自動判定
  static Map<String, dynamic> getOptimalUTMZone(LatLng latLon) {
    final zoneNumber = calculateUTMZone(latLon.longitude);
    final zoneLetter = calculateUTMLetter(latLon.latitude);
    final epsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';

    return {'zoneNumber': zoneNumber, 'zoneLetter': zoneLetter, 'epsg': epsg};
  }

  /// 緯度経度から最適な座標系を取得（同期版）
  static CoordinateSystem? getBestCoordinateSystemSync(LatLng point) {
    try {
      // 緯度経度からUTMゾーンを判定
      return _coordinateSystems.firstWhere(
        (system) => system.bounds?.contains(point) ?? false,
      );
    } catch (e) {
      // 該当するゾーンがない場合はUTMゾーンを動的に生成
      final zoneNumber = calculateUTMZone(point.longitude);
      final epsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
      final proj4String =
          '+proj=utm +zone=$zoneNumber +datum=WGS84 +units=m +no_defs';

      return CoordinateSystem(
        name: 'UTM Zone ${zoneNumber}N',
        epsgCode: epsg,
        proj4String: proj4String,
      );
    }
  }
}

