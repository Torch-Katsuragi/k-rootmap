// K-MAPS: ジオメトリタイプenumクラス
// 文字列リテラルの代わりに型安全な定数として使用

/// OGC Simple Features仕様に基づくジオメトリタイプ
/// MULTI系を削除し、単一系のみサポート
enum GeometryType {
  point('POINT'),
  linestring('LINESTRING'),
  polygon('POLYGON');

  const GeometryType(this.value);

  /// 文字列値
  final String value;

  /// 文字列からGeometryTypeを取得
  static GeometryType? fromString(String value) {
    final valueUpper = value.toUpperCase();
    switch (valueUpper) {
      case 'POINT':
      case 'MULTIPOINT': // 後方互換のため一時的に対応
        return GeometryType.point;
      case 'LINESTRING':
      case 'MULTILINESTRING': // 後方互換のため一時的に対応
        return GeometryType.linestring;
      case 'POLYGON':
      case 'MULTIPOLYGON': // 後方互換のため一時的に対応
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
