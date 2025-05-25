// K-MAPS: フィーチャ計算ユーティリティ
// 点・線・面の重心、距離、長さ、面積、最近傍feature取得など
//
// 本ファイルの関数は全て静的関数として利用可能
//
// 依存: latlong2

import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../models/layer_tree_node.dart'; // FeatureNode型利用のため

/// degree・metre変換系
class DegreeMeterConverter {
  /// 緯度1度あたりの距離（メートル）
  static double metersPerDegreeLat() {
    // 地球半径R=6378137m, 1度=π/180ラジアン
    const double degToRad = math.pi / 180.0;
    const double R = 6378137.0;
    return degToRad * R;
  }

  /// 経度1度あたりの距離（メートル）
  /// [lat]: 緯度（degree）
  static double metersPerDegreeLng(double lat) {
    const double degToRad = math.pi / 180.0;
    const double R = 6378137.0;
    final double latRad = lat * degToRad;
    return degToRad * R * math.cos(latRad);
  }

  /// 緯度方向の距離（メートル）→度変換
  /// [meters]: 距離（m）
  static double metersToDegreesLat(double meters) {
    return meters / metersPerDegreeLat();
  }

  /// 経度方向の距離（メートル）→度変換
  /// [meters]: 距離（m）
  /// [lat]: 緯度（degree）
  static double metersToDegreesLng(double meters, double lat) {
    return meters / metersPerDegreeLng(lat);
  }

  /// 緯度方向の距離（度）→メートル変換
  /// [degrees]: 距離（度）
  static double degreesToMetersLat(double degrees) {
    return degrees * metersPerDegreeLat();
  }

  /// 経度方向の距離（度）→メートル変換
  /// [degrees]: 距離（度）
  /// [lat]: 緯度（degree）
  static double degreesToMetersLng(double degrees, double lat) {
    return degrees * metersPerDegreeLng(lat);
  }

  /// 緯度経度平面の面積（degree^2）をメートル単位（m^2）に変換
  /// [area]: degree^2単位の面積
  /// [lat]: ポリゴン中心緯度（degree）
  /// 戻り値: 面積（m^2）
  static double convertAreaToMeters2(double area, double lat) {
    final double mPerDegLat = metersPerDegreeLat();
    final double mPerDegLng = metersPerDegreeLng(lat);
    return area * mPerDegLat * mPerDegLng;
  }
}

/// 距離・長さ・面積・重心計算
class GeometryCalc {
  /// 2点間の距離（メートル）を計算
  /// [a], [b]: LatLng
  /// 戻り値: 距離（m）
  static double calcDistance(LatLng a, LatLng b) {
    final Distance distance = const Distance();
    return distance(a, b);
  }

  /// 線分（List<LatLng>）の長さ（メートル）を計算
  /// [line]: 線分の座標リスト
  /// 戻り値: 総距離（m）
  static double calcLineLength(List<LatLng> line) {
    double sum = 0.0;
    for (int i = 1; i < line.length; i++) {
      sum += calcDistance(line[i - 1], line[i]);
    }
    return sum;
  }

  /// ポリゴン（外環＋穴リスト）の面積（degree^2, 穴も加算）
  /// [polygon]: 外環＋穴リスト（List<List<LatLng>>）
  /// 戻り値: 面積（degree^2）
  static double calcPolygonArea(List<List<LatLng>> polygon) {
    if (polygon.isEmpty || polygon[0].length < 3) return 0.0;
    double area = _ringArea(polygon[0]);
    for (final ring in polygon.skip(1)) {
      area -= _ringArea(ring);
    }
    return area;
  }

  /// 線分（List<LatLng>）の重心（中点）を計算
  /// [line]: 線分の座標リスト
  /// 戻り値: 重心座標（LatLng）
  static LatLng calcLineCentroid(List<LatLng> line) {
    if (line.isEmpty) return LatLng(0, 0);
    double sumLat = 0.0, sumLng = 0.0;
    for (final pt in line) {
      sumLat += pt.latitude;
      sumLng += pt.longitude;
    }
    return LatLng(sumLat / line.length, sumLng / line.length);
  }

  /// ポリゴン（外環＋穴リスト）の重心を計算
  /// [polygon]: 外環＋穴リスト（List<List<LatLng>>）
  /// 戻り値: 重心座標（LatLng）
  static LatLng calcPolygonCentroid(List<List<LatLng>> polygon) {
    // 全ての頂点（外環＋穴）を合算して重心を計算
    int count = 0;
    double sumLat = 0.0, sumLng = 0.0;
    for (final ring in polygon) {
      for (final pt in ring) {
        sumLat += pt.latitude;
        sumLng += pt.longitude;
        count++;
      }
    }
    if (count == 0) return LatLng(0, 0);
    return LatLng(sumLat / count, sumLng / count);
  }

  /// 点集合（List<LatLng>）の重心を計算
  static LatLng calcPointsCentroid(List<LatLng> points) {
    if (points.isEmpty) return LatLng(0, 0);
    double sumLat = 0.0, sumLng = 0.0;
    for (final pt in points) {
      sumLat += pt.latitude;
      sumLng += pt.longitude;
    }
    return LatLng(sumLat / points.length, sumLng / points.length);
  }

  /// 点と線分（List<LatLng>）の最短距離（メートル）を計算
  /// [pt]: 判定点
  /// [line]: 線分
  /// 戻り値: 最短距離（m）
  static double calcPointToLineDistance(LatLng pt, List<LatLng> line) {
    double minDist = double.infinity;
    for (int i = 1; i < line.length; i++) {
      final d = _distancePointToSegment(pt, line[i - 1], line[i]);
      if (d < minDist) minDist = d;
    }
    return minDist;
  }

  /// 点とポリゴン（外環＋穴リスト）の最短距離（メートル）を計算
  /// [pt]: 判定点
  /// [polygon]: 外環＋穴リスト
  /// 戻り値: 最短距離（m）（ポリゴン内なら0）
  static double calcPointToPolygonDistance(
    LatLng pt,
    List<List<LatLng>> polygon,
  ) {
    if (polygon.isEmpty) return double.infinity;
    // 外環・穴すべてのリングとの最短距離
    double minDist = double.infinity;
    for (final ring in polygon) {
      for (int i = 1; i < ring.length; i++) {
        final d = _distancePointToSegment(pt, ring[i - 1], ring[i]);
        if (d < minDist) minDist = d;
      }
    }
    // 外環内かつどの穴にも含まれなければ距離0
    if (_pointInPolygonWithHoles(pt, polygon)) return 0.0;
    return minDist;
  }

  /// 点が外環＋穴リストのポリゴン内にあるか判定
  static bool _pointInPolygonWithHoles(LatLng pt, List<List<LatLng>> polygon) {
    if (polygon.isEmpty) return false;
    if (!_pointInRing(pt, polygon[0])) return false; // 外環外
    for (int i = 1; i < polygon.length; i++) {
      if (_pointInRing(pt, polygon[i])) return false; // 穴内
    }
    return true;
  }

  // 1つのリング内判定
  static bool _pointInRing(LatLng pt, List<LatLng> ring) {
    int cnt = 0;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      if (((ring[i].latitude > pt.latitude) !=
              (ring[j].latitude > pt.latitude)) &&
          (pt.longitude <
              (ring[j].longitude - ring[i].longitude) *
                      (pt.latitude - ring[i].latitude) /
                      (ring[j].latitude - ring[i].latitude) +
                  ring[i].longitude)) {
        cnt++;
      }
    }
    return cnt % 2 == 1;
  }

  /// 点と線分の最短距離（メートル）
  static double _distancePointToSegment(LatLng p, LatLng a, LatLng b) {
    // 緯度経度を平面直交座標に近似
    final x0 = p.longitude, y0 = p.latitude;
    final x1 = a.longitude, y1 = a.latitude;
    final x2 = b.longitude, y2 = b.latitude;
    final dx = x2 - x1, dy = y2 - y1;
    if (dx == 0 && dy == 0) return calcDistance(p, a);
    final t = ((x0 - x1) * dx + (y0 - y1) * dy) / (dx * dx + dy * dy);
    if (t < 0) return calcDistance(p, a);
    if (t > 1) return calcDistance(p, b);
    final proj = LatLng(y1 + t * dy, x1 + t * dx);
    return calcDistance(p, proj);
  }

  /// Shoelace formula for a single ring（絶対値で返す）
  /// [ring]: List<LatLng>
  static double _ringArea(List<LatLng> ring) {
    double area = 0.0;
    for (int i = 0; i < ring.length; i++) {
      final j = (i + 1) % ring.length;
      area += ring[i].longitude * ring[j].latitude;
      area -= ring[j].longitude * ring[i].latitude;
    }
    return area.abs() / 2.0;
  }
}

/// feature距離・最近傍feature検索
class FeatureSearch {
  /// 点とfeature（点・線・面）の最短距離（メートル）を計算
  /// featureType: 'point'|'line'|'polygon'
  static double calcPointToFeatureDistance(
    LatLng pt,
    Object geometry,
    String featureType,
  ) {
    if (featureType == 'point') {
      if (geometry is List<LatLng> && geometry.isNotEmpty) {
        return GeometryCalc.calcDistance(pt, geometry.first);
      }
    } else if (featureType == 'line') {
      if (geometry is List<List<LatLng>>) {
        double minDist = double.infinity;
        for (final line in geometry) {
          final d = GeometryCalc.calcPointToLineDistance(pt, line);
          if (d < minDist) minDist = d;
        }
        return minDist;
      }
    } else if (featureType == 'polygon') {
      if (geometry is List<List<LatLng>>) {
        return GeometryCalc.calcPointToPolygonDistance(pt, geometry);
      }
    }
    return double.infinity;
  }

  /// 点とfeatureリストの中で最も近いfeatureを取得
  /// [pt]: 判定点
  /// [features]: FeatureNodeリスト
  /// [featureType]: 'point'|'line'|'polygon'
  /// 戻り値: 最近傍FeatureNodeと距離のMapEntry（なければnull）
  static MapEntry<FeatureNode, double>? findNearestFeature(
    LatLng pt,
    List<FeatureNode> features,
    String featureType,
  ) {
    FeatureNode? nearest;
    double minDist = double.infinity;
    for (final f in features) {
      final d = calcPointToFeatureDistance(pt, f.geometry, featureType);
      if (d < minDist) {
        minDist = d;
        nearest = f;
      }
    }
    if (nearest == null) return null;
    return MapEntry(nearest, minDist);
  }
}
