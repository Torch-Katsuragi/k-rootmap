// Root Maps: ジオメトリタイプenumクラス
// 文字列リテラルの代わりに型安全な定数として使用

/// OGC Simple Features仕様に基づくジオメトリタイプ
/// デフォルトは MULTI 系（Single も透過的に扱う）
enum GeometryType {
  point('MULTIPOINT'),
  linestring('MULTILINESTRING'),
  polygon('MULTIPOLYGON');

  const GeometryType(this.value);

  /// 文字列値
  final String value;

  /// 文字列からGeometryTypeを取得（Single/Multi両方を受理）
  static GeometryType? fromString(String value) {
    switch (value.toUpperCase()) {
      case 'POINT':
      case 'MULTIPOINT':
        return GeometryType.point;
      case 'LINESTRING':
      case 'MULTILINESTRING':
        return GeometryType.linestring;
      case 'POLYGON':
      case 'MULTIPOLYGON':
        return GeometryType.polygon;
      default:
        return null;
    }
  }

  /// 日本語表示名
  String get displayName {
    switch (this) {
      case GeometryType.point:
        return 'ポイント';
      case GeometryType.linestring:
        return 'ライン';
      case GeometryType.polygon:
        return 'ポリゴン';
    }
  }

  /// デフォルトレイヤ名を取得
  String get defaultLayerName {
    switch (this) {
      case GeometryType.point:
        return 'point';
      case GeometryType.linestring:
        return 'line';
      case GeometryType.polygon:
        return 'polygon';
    }
  }
}
