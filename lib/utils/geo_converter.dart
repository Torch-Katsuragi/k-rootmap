/// LatLng (latlong2) ↔ Geographic (geobase) 変換ユーティリティ
/// maplibre移行で座標型が異なるため、境界で変換する
library;

import 'package:latlong2/latlong.dart';
import 'package:geobase/geobase.dart';

extension LatLngToGeographic on LatLng {
  /// LatLng → Geographic 変換
  Geographic toGeographic() =>
      Geographic(lon: longitude, lat: latitude);
}

extension GeographicToLatLng on Geographic {
  /// Geographic → LatLng 変換
  LatLng toLatLng() => LatLng(lat, lon);
}

extension LatLngListToGeographic on List<LatLng> {
  /// LatLngリスト → Geographicリスト 変換
  List<Geographic> toGeographics() =>
      map((ll) => ll.toGeographic()).toList();
}

extension GeographicListToLatLng on List<Geographic> {
  /// Geographicリスト → LatLngリスト 変換
  List<LatLng> toLatLngs() =>
      map((g) => g.toLatLng()).toList();
}
