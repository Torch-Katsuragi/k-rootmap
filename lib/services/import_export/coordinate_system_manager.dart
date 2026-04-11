// Root Maps: Coordinate System Manager
// 高度な座標系管理クラス（proj4dartとEPSGデータベースを活用）
import 'package:root_maps/utils/app_logger.dart';
import 'package:proj4dart/proj4dart.dart';
import '../../utils/coordinate_converter.dart';

/// 高度な座標系管理クラス
/// proj4dartとEPSGデータベースを活用したスマートな座標系解析
class SmartCoordinateSystemManager {
  /// シングルトンインスタンス
  static final SmartCoordinateSystemManager _instance =
      SmartCoordinateSystemManager._internal();
  factory SmartCoordinateSystemManager() => _instance;
  SmartCoordinateSystemManager._internal();

  /// 予め定義された座標系のキャッシュ
  final Map<String, Projection> _projectionCache = {};

  /// よく使われるEPSGコードとProj4定義のマップ
  static const Map<String, String> commonEpsgDefinitions = {
    // WGS84系
    'EPSG:4326': '+proj=longlat +datum=WGS84 +no_defs',
    'EPSG:3857':
        '+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs',

    // JGD2000平面直角座標系 (EPSG:2443-2461)
    'EPSG:2443':
        '+proj=tmerc +lat_0=33 +lon_0=129.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2444':
        '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2445':
        '+proj=tmerc +lat_0=36 +lon_0=132.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2446':
        '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2447':
        '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2448':
        '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2449':
        '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2450':
        '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2451':
        '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',
    'EPSG:2452':
        '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +units=m +no_defs',

    // UTM座標系（日本周辺）
    'EPSG:32654': '+proj=utm +zone=54 +datum=WGS84 +units=m +no_defs',
    'EPSG:32655': '+proj=utm +zone=55 +datum=WGS84 +units=m +no_defs',
    'EPSG:32656': '+proj=utm +zone=56 +datum=WGS84 +units=m +no_defs',
  };

  /// WKT文字列から座標系を解析（proj4dartを最大限活用）
  Future<CoordinateSystem?> parseWktToCoordinateSystem(String wkt) async {
    try {
      AppLogger.debug('[SmartCRS] WKT座標系解析開始');
      AppLogger.debug('[SmartCRS] WKT文字列長: ${wkt.length}文字');

      // Step 1: WKT文字列からEPSGコードを直接抽出
      final epsgCode = _extractEpsgCodeFromWkt(wkt);
      if (epsgCode != null) {
        AppLogger.debug('[SmartCRS] WKTからEPSGコード抽出成功: $epsgCode');

        // 既知のEPSG定義を使用
        if (commonEpsgDefinitions.containsKey(epsgCode)) {
          final proj4String = commonEpsgDefinitions[epsgCode]!;
          AppLogger.debug('[SmartCRS] 既知のEPSG定義を使用: $epsgCode');

          return CoordinateSystem(
            name: _getEpsgName(epsgCode),
            epsgCode: epsgCode,
            proj4String: proj4String,
          );
        }
      }

      // Step 2: proj4dartのWKT解析機能を使用
      try {
        AppLogger.debug('[SmartCRS] proj4dartでWKT直接解析を試行');
        Projection.parse(wkt);
        AppLogger.debug('[SmartCRS] proj4dartWKT解析成功');

        return CoordinateSystem(
          name: epsgCode != null ? _getEpsgName(epsgCode) : 'WKT Projection',
          epsgCode: epsgCode ?? 'WKT',
          proj4String: wkt,
        );
      } catch (e) {
        AppLogger.debug('[SmartCRS] proj4dartでのWKT解析失敗: $e');
      }

      // Step 3: WKTからProj4文字列への変換を試行（フォールバック）
      final proj4String = await _convertWktToProj4String(wkt);
      if (proj4String != null) {
        AppLogger.debug('[SmartCRS] WKT→Proj4変換成功');

        try {
          Projection.parse(proj4String);
          return CoordinateSystem(
            name:
                epsgCode != null
                    ? _getEpsgName(epsgCode)
                    : 'Converted Projection',
            epsgCode: epsgCode ?? 'CONVERTED',
            proj4String: proj4String,
          );
        } catch (e) {
          AppLogger.debug('[SmartCRS] 変換されたProj4文字列の解析失敗: $e');
        }
      }

      // Step 4: 最後の手段として投影法タイプから推定
      final projectionInfo = _inferProjectionFromWkt(wkt);
      if (projectionInfo != null) {
        AppLogger.debug('[SmartCRS] 投影法推定による座標系生成');
        return projectionInfo;
      }

      AppLogger.debug('[SmartCRS] 全ての解析手法が失敗');
      return null;
    } catch (e, stack) {
      AppLogger.debug('[SmartCRS] WKT解析エラー: $e');
      AppLogger.debug('[SmartCRS] スタックトレース: $stack');
      return null;
    }
  }

  /// WKT文字列からEPSGコードを抽出
  String? _extractEpsgCodeFromWkt(String wkt) {
    // AUTHORITY["EPSG","XXXX"] パターン
    final authorityPattern = RegExp(r'AUTHORITY\["EPSG","(\d+)"\]');
    final match = authorityPattern.firstMatch(wkt);
    if (match != null) {
      return 'EPSG:${match.group(1)}';
    }

    // EPSG:XXXX 直接パターン
    final directPattern = RegExp(r'EPSG[:\s]*(\d+)');
    final directMatch = directPattern.firstMatch(wkt);
    if (directMatch != null) {
      return 'EPSG:${directMatch.group(1)}';
    }

    return null;
  }

  /// EPSGコードから名前を取得
  String _getEpsgName(String epsgCode) {
    switch (epsgCode) {
      case 'EPSG:4326':
        return 'WGS 84';
      case 'EPSG:3857':
        return 'WGS 84 / Pseudo-Mercator';
      case 'EPSG:2443':
        return 'JGD2000 / Japan Plane Rectangular CS I';
      case 'EPSG:2444':
        return 'JGD2000 / Japan Plane Rectangular CS II';
      case 'EPSG:2445':
        return 'JGD2000 / Japan Plane Rectangular CS III';
      case 'EPSG:2446':
        return 'JGD2000 / Japan Plane Rectangular CS IV';
      case 'EPSG:2447':
        return 'JGD2000 / Japan Plane Rectangular CS V';
      case 'EPSG:2448':
        return 'JGD2000 / Japan Plane Rectangular CS VI';
      case 'EPSG:2449':
        return 'JGD2000 / Japan Plane Rectangular CS VII';
      case 'EPSG:2450':
        return 'JGD2000 / Japan Plane Rectangular CS VIII';
      case 'EPSG:2451':
        return 'JGD2000 / Japan Plane Rectangular CS IX';
      case 'EPSG:2452':
        return 'JGD2000 / Japan Plane Rectangular CS X';
      case 'EPSG:32654':
        return 'WGS 84 / UTM zone 54N';
      case 'EPSG:32655':
        return 'WGS 84 / UTM zone 55N';
      case 'EPSG:32656':
        return 'WGS 84 / UTM zone 56N';
      default:
        return epsgCode;
    }
  }

  /// WKTをProj4文字列に変換（簡易版）
  Future<String?> _convertWktToProj4String(String wkt) async {
    try {
      // 投影法を抽出
      String? projType;
      if (wkt.contains('Transverse_Mercator')) {
        projType = '+proj=tmerc';
      } else if (wkt.contains('Mercator')) {
        projType = '+proj=merc';
      } else if (wkt.contains('Lambert_Conformal_Conic')) {
        projType = '+proj=lcc';
      } else if (wkt.contains('Albers')) {
        projType = '+proj=aea';
      } else if (wkt.contains('UTM')) {
        // UTMゾーンを抽出
        final utmMatch = RegExp(r'UTM.*zone.*(\d+)').firstMatch(wkt);
        if (utmMatch != null) {
          final zone = utmMatch.group(1);
          return '+proj=utm +zone=$zone +datum=WGS84 +units=m +no_defs';
        }
      } else {
        // 地理座標系（緯度経度）
        projType = '+proj=longlat';
      }

      if (projType == null) return null;

      // 基本パラメータの構築
      final parts = <String>[projType];

      // 測地系の判定
      if (wkt.contains('WGS_1984') || wkt.contains('WGS84')) {
        parts.add('+datum=WGS84');
      } else if (wkt.contains('GRS80') || wkt.contains('JGD')) {
        parts.add('+ellps=GRS80');
      }

      // 単位
      if (wkt.contains('metre') || wkt.contains('meter')) {
        parts.add('+units=m');
      }

      parts.add('+no_defs');

      return parts.join(' ');
    } catch (e) {
      AppLogger.debug('[SmartCRS] WKT→Proj4変換エラー: $e');
      return null;
    }
  }

  /// WKTから投影法を推定
  CoordinateSystem? _inferProjectionFromWkt(String wkt) {
    // 日本の一般的な投影法パターンを推定
    if (wkt.toUpperCase().contains('JAPAN')) {
      return CoordinateSystem(
        name: 'JGD2000 / Japan Plane Rectangular CS VI (推定)',
        epsgCode: 'EPSG:2448',
        proj4String: commonEpsgDefinitions['EPSG:2448']!,
      );
    }

    // WGS84地理座標系をフォールバックとして使用
    return CoordinateSystem(
      name: 'WGS 84 (フォールバック)',
      epsgCode: 'EPSG:4326',
      proj4String: commonEpsgDefinitions['EPSG:4326']!,
    );
  }

  /// EPSGコードから座標系を取得
  Future<CoordinateSystem?> getCoordinateSystemByEpsg(String epsgCode) async {
    if (commonEpsgDefinitions.containsKey(epsgCode)) {
      return CoordinateSystem(
        name: _getEpsgName(epsgCode),
        epsgCode: epsgCode,
        proj4String: commonEpsgDefinitions[epsgCode]!,
      );
    }
    return null;
  }

  /// Proj4dartの投影オブジェクトを取得（キャッシュ付き）
  Projection? getProjection(String epsgCodeOrProj4String) {
    if (_projectionCache.containsKey(epsgCodeOrProj4String)) {
      return _projectionCache[epsgCodeOrProj4String];
    }

    try {
      Projection? projection;

      // EPSGコードの場合は既知の定義を使用
      if (epsgCodeOrProj4String.startsWith('EPSG:') &&
          commonEpsgDefinitions.containsKey(epsgCodeOrProj4String)) {
        final proj4String = commonEpsgDefinitions[epsgCodeOrProj4String]!;
        projection = Projection.parse(proj4String);
      } else {
        // Proj4文字列またはWKTとして解析
        projection = Projection.parse(epsgCodeOrProj4String);
      }

      _projectionCache[epsgCodeOrProj4String] = projection;
      return projection;
    } catch (e) {
      AppLogger.debug('[SmartCRS] 投影作成エラー: $e');
      return null;
    }
  }

  /// サポートされているEPSGコードのリストを取得
  List<String> getSupportedEpsgCodes() {
    return commonEpsgDefinitions.keys.toList()..sort();
  }

  /// 座標系情報の詳細表示
  void printCoordinateSystemInfo(CoordinateSystem coordinateSystem) {
    AppLogger.debug('[SmartCRS] =====================================');
    AppLogger.debug('[SmartCRS] 座標系情報:');
    AppLogger.debug('[SmartCRS]   名前: ${coordinateSystem.name}');
    AppLogger.debug('[SmartCRS]   EPSGコード: ${coordinateSystem.epsgCode}');
    AppLogger.debug('[SmartCRS]   Proj4文字列: ${coordinateSystem.proj4String}');
    AppLogger.debug('[SmartCRS] =====================================');
  }
}

