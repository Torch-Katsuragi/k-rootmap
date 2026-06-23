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
/// パーティ位置共有: エンコード済みポリライン（Google Encoded Polyline Algorithm）
///
/// gap backfill の軌跡を小さな文字列で送るために使う（RTDBのペイロード極小化）。
/// 精度は 1e5（約1m）。RTDBルールの `pts` 長さ上限（8000文字）に収まるよう、
/// 送信側で Douglas-Peucker 等の間引きを先に行う前提。
library;

import 'package:latlong2/latlong.dart';

/// エンコード済みポリラインの相互変換
class PolylineCodec {
  static const int _precision = 100000; // 1e5

  /// 座標列をエンコード済みポリライン文字列に変換
  static String encode(List<LatLng> points) {
    final sb = StringBuffer();
    int lastLat = 0;
    int lastLng = 0;
    for (final p in points) {
      final lat = (p.latitude * _precision).round();
      final lng = (p.longitude * _precision).round();
      _encodeValue(lat - lastLat, sb);
      _encodeValue(lng - lastLng, sb);
      lastLat = lat;
      lastLng = lng;
    }
    return sb.toString();
  }

  /// エンコード済みポリライン文字列を座標列に変換
  static List<LatLng> decode(String encoded) {
    final points = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lng = 0;
    final len = encoded.length;
    while (index < len) {
      final dLat = _decodeValue(encoded, index);
      index = dLat.nextIndex;
      lat += dLat.value;
      final dLng = _decodeValue(encoded, index);
      index = dLng.nextIndex;
      lng += dLng.value;
      points.add(LatLng(lat / _precision, lng / _precision));
    }
    return points;
  }

  static void _encodeValue(int value, StringBuffer sb) {
    int v = value < 0 ? ~(value << 1) : (value << 1);
    while (v >= 0x20) {
      sb.writeCharCode((0x20 | (v & 0x1f)) + 63);
      v >>= 5;
    }
    sb.writeCharCode(v + 63);
  }

  static _DecodeResult _decodeValue(String encoded, int startIndex) {
    int index = startIndex;
    int shift = 0;
    int result = 0;
    int b;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    final value = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    return _DecodeResult(value, index);
  }
}

class _DecodeResult {
  final int value;
  final int nextIndex;
  const _DecodeResult(this.value, this.nextIndex);
}
