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
