// K-MAPS: レイヤ・フィーチャモデル定義
// レイヤ種別・フィーチャ基底・各ジオメトリ型フィーチャ
import 'package:latlong2/latlong.dart';

/// レイヤ種別
enum LayerType { point, line, polygon }

/// フィーチャ基底クラス
abstract class Feature {
  /// 属性値
  String attr;
  Feature(this.attr);
}

/// MultiPointフィーチャ
class MultiPointFeature extends Feature {
  /// 座標リスト
  List<LatLng> points;
  MultiPointFeature(this.points, String attr) : super(attr);
}

/// MultiLineStringフィーチャ（複数LineString＋属性）
class MultiLineStringFeature extends Feature {
  /// 複数線分
  List<List<LatLng>> lines;
  MultiLineStringFeature(this.lines, String attr) : super(attr);
}

/// MultiPolygonフィーチャ（複数Polygon＋属性）
class MultiPolygonFeature extends Feature {
  /// 複数ポリゴン（外環＋穴）
  List<List<List<LatLng>>> polygons;
  MultiPolygonFeature(this.polygons, String attr) : super(attr);
}
