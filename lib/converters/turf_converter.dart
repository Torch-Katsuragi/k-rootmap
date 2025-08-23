// K-MAPS: turf_dartオブジェクトとGeoPackageデータ間の変換ユーティリティ
// turf_dartのFeature/FeatureCollectionとLatLng座標データ間の相互変換を行う

import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' as turf;

/// turf_dartオブジェクトとK-MAPSのデータ形式間の変換を行うユーティリティクラス
class TurfConverter {
  /// LatLng座標をturf_dartのPosition形式に変換
  /// LatLng(latitude, longitude) → [longitude, latitude]
  static List<double> latlngToPosition(LatLng latlng) {
    return [latlng.longitude, latlng.latitude];
  }

  /// turf_dartのPosition形式をLatLng座標に変換
  /// [longitude, latitude] → LatLng(latitude, longitude)
  static LatLng positionToLatlng(List<num> position) {
    if (position.length < 2) {
      throw ArgumentError('Position must have at least 2 elements (lon, lat)');
    }
    return LatLng(position[1].toDouble(), position[0].toDouble()); // lat, lon
  }

  /// LatLngリストをPositionリストに変換
  static List<List<double>> latlngsToPositions(List<LatLng> latlngs) {
    return latlngs.map(latlngToPosition).toList();
  }

  /// PositionリストをLatLngリストに変換
  static List<LatLng> positionsToLatlngs(List<List<num>> positions) {
    return positions.map(positionToLatlng).toList();
  }

  /// LatLngからturf_dartのPointを作成
  static turf.Point createPoint(
    LatLng latlng, {
    Map<String, dynamic>? properties,
  }) {
    return turf.Point(coordinates: turf.Position.of(latlngToPosition(latlng)));
  }

  /// LatLngリストからturf_dartのLineStringを作成
  static turf.LineString createLineString(
    List<LatLng> line, {
    Map<String, dynamic>? properties,
  }) {
    final positions = latlngsToPositions(line);
    return turf.LineString(
      coordinates: positions.map((pos) => turf.Position.of(pos)).toList(),
    );
  }

  /// LatLngリストのリストからturf_dartのPolygonを作成
  static turf.Polygon createPolygon(
    List<List<LatLng>> rings, {
    Map<String, dynamic>? properties,
  }) {
    final positionRings =
        rings
            .map(
              (ring) =>
                  latlngsToPositions(
                    ring,
                  ).map((pos) => turf.Position.of(pos)).toList(),
            )
            .toList();

    return turf.Polygon(coordinates: positionRings);
  }

  /// turf_dartのPointからLatLngを抽出
  static LatLng pointToLatlng(turf.Point point) {
    final coords = point.coordinates;
    return LatLng(coords.lat.toDouble(), coords.lng.toDouble());
  }

  /// turf_dartのLineStringからLatLngリストを抽出
  static List<LatLng> lineStringToLatlngs(turf.LineString lineString) {
    return lineString.coordinates
        .map((pos) => LatLng(pos.lat.toDouble(), pos.lng.toDouble()))
        .toList();
  }

  /// turf_dartのPolygonからLatLngリストのリストを抽出
  static List<List<LatLng>> polygonToLatlngs(turf.Polygon polygon) {
    return polygon.coordinates
        .map(
          (ring) =>
              ring
                  .map((pos) => LatLng(pos.lat.toDouble(), pos.lng.toDouble()))
                  .toList(),
        )
        .toList();
  }

  /// GeoPackageのrowデータからturf_dartのFeatureを作成
  /// [rowData] GeoPackageから取得したフィーチャデータ（geometry変換済み）
  /// [geometryType] ジオメトリの種別（'Point', 'LineString', 'Polygon'）
  static turf.Feature? createFeatureFromRow(
    Map<String, dynamic> rowData,
    String geometryType,
  ) {
    try {
      // ジオメトリデータを取得
      final geometryData = rowData['geometry'];
      if (geometryData == null) return null;

      // プロパティを準備（id, geom, geometryを除く全ての属性）
      final properties = Map<String, dynamic>.from(rowData);
      properties.remove('geom');
      properties.remove('geometry');

      turf.GeometryObject? geometry;

      switch (geometryType.toLowerCase()) {
        case 'point':
          if (geometryData is List<LatLng> && geometryData.isNotEmpty) {
            geometry = createPoint(geometryData.first);
          }
          break;
        case 'linestring':
          if (geometryData is List<LatLng>) {
            geometry = createLineString(geometryData);
          }
          break;
        case 'polygon':
          if (geometryData is List<List<LatLng>>) {
            geometry = createPolygon(geometryData);
          }
          break;
      }

      if (geometry == null) return null;

      return turf.Feature(geometry: geometry, properties: properties);
    } catch (e) {
      print('[ERROR] TurfConverter.createFeatureFromRow: $e');
      return null;
    }
  }

  /// turf_dartのFeatureからGeoPackage保存用のデータを生成
  /// [feature] turf_dartのFeatureオブジェクト
  /// 戻り値: GeoPackage保存用のMap（geometry, properties含む）
  static Map<String, dynamic>? featureToRowData(turf.Feature feature) {
    try {
      final rowData = <String, dynamic>{};

      // プロパティをコピー
      if (feature.properties != null) {
        rowData.addAll(feature.properties!);
      }

      // ジオメトリデータを変換
      final geometry = feature.geometry;
      if (geometry is turf.Point) {
        rowData['geometry'] = [pointToLatlng(geometry)];
      } else if (geometry is turf.LineString) {
        rowData['geometry'] = lineStringToLatlngs(geometry);
      } else if (geometry is turf.Polygon) {
        rowData['geometry'] = polygonToLatlngs(geometry);
      } else {
        print(
          '[WARNING] TurfConverter.featureToRowData: Unsupported geometry type: ${geometry.runtimeType}',
        );
        return null;
      }

      return rowData;
    } catch (e) {
      print('[ERROR] TurfConverter.featureToRowData: $e');
      return null;
    }
  }

  /// turf_dartのFeatureCollectionを作成
  static turf.FeatureCollection createFeatureCollection(
    List<turf.Feature> features,
  ) {
    return turf.FeatureCollection(features: features);
  }

  /// FeatureCollectionからFeatureリストを取得
  static List<turf.Feature> getFeatures(turf.FeatureCollection collection) {
    return collection.features;
  }

  /// ジオメトリタイプを判定
  static String? getGeometryType(turf.Feature feature) {
    final geometry = feature.geometry;
    if (geometry is turf.Point) return 'Point';
    if (geometry is turf.LineString) return 'LineString';
    if (geometry is turf.Polygon) return 'Polygon';
    return null;
  }

  /// Featureの重心を計算
  static LatLng? calculateCentroid(turf.Feature feature) {
    try {
      final centroid = turf.centroid(feature);
      if (centroid.geometry is turf.Point) {
        return pointToLatlng(centroid.geometry as turf.Point);
      }
      return null;
    } catch (e) {
      print('[ERROR] TurfConverter.calculateCentroid: $e');
      return null;
    }
  }

  /// Featureの面積を計算（Polygon用）
  static double? calculateArea(turf.Feature feature) {
    try {
      if (feature.geometry is turf.Polygon) {
        final result = turf.area(feature);
        return result?.toDouble();
      }
      return null;
    } catch (e) {
      print('[ERROR] TurfConverter.calculateArea: $e');
      return null;
    }
  }

  /// Featureの長さを計算（LineString用）
  static double? calculateLength(turf.Feature feature) {
    try {
      if (feature.geometry is turf.LineString) {
        final lineString = feature.geometry as turf.LineString;
        final lineFeature = turf.Feature(
          geometry: lineString,
          properties: feature.properties,
        );
        final result = turf.length(lineFeature, turf.Unit.meters);
        return result.toDouble();
      }
      return null;
    } catch (e) {
      print('[ERROR] TurfConverter.calculateLength: $e');
      return null;
    }
  }

  /// position型のgetterヘルパー（LatLngから）
  static List<double> get positionFromLatLng =>
      throw UnsupportedError('Use latlngToPosition(LatLng latlng) instead');
}
