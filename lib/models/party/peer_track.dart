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
/// パーティ位置共有: ピアの圏外区間軌跡（gap backfill の受信側）
///
/// RTDBの `/rooms/{code}/tracks/{uid}/{pushId}` 1件に対応する。
/// 「ブラックアウト中どこを通ったか」を仲間の地図に描くための揮発データで、
/// GeoPackage には保存しない。
library;

import 'package:latlong2/latlong.dart';

import '../../services/party/polyline_codec.dart';

/// ピア1人の圏外区間軌跡1本
class PeerTrack {
  /// メンバーのuid
  final String uid;

  /// デコード済みの座標列
  final List<LatLng> points;

  /// 圏外区間の開始（epoch ms）
  final int fromMs;

  /// 圏外区間の終了（epoch ms）
  final int toMs;

  const PeerTrack({
    required this.uid,
    required this.points,
    required this.fromMs,
    required this.toMs,
  });

  /// RTDBのMap（`/tracks/{uid}/{pushId}` の値）からの変換。
  ///
  /// 欠損・デコード不能なら null（読むときは寛容に）。
  static PeerTrack? fromMap(String uid, Map<dynamic, dynamic> map) {
    final pts = map['pts'];
    final from = map['from'];
    final to = map['to'];
    if (pts is! String || from is! num || to is! num) return null;
    final List<LatLng> points;
    try {
      points = PolylineCodec.decode(pts);
    } catch (_) {
      return null;
    }
    if (points.length < 2) return null;
    return PeerTrack(
      uid: uid,
      points: points,
      fromMs: from.toInt(),
      toMs: to.toInt(),
    );
  }
}
