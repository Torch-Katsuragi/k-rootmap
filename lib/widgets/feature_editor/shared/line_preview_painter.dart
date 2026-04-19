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
/// LatLng座標リストの描画用CustomPainter
///
/// 背景ライン（灰色）と前景ライン（黒）、頂点マーカー（赤）を描画する。
/// LineSimplificationやTrackExtractionなど、ライン系プレビューで共通利用。
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class LinePreviewPainter extends CustomPainter {
  /// 背景に薄く表示するライン（元のライン全体など）
  final List<LatLng> backgroundLine;

  /// 前景に強調表示するライン（簡略化後・選択範囲など）
  final List<LatLng> foregroundLine;

  /// 前景ライン上に赤点で描画する頂点リスト（nullなら foregroundLine を使用）
  final List<LatLng>? vertices;

  /// 背景ラインの色
  final Color backgroundColor;

  /// 前景ラインの色
  final Color foregroundColor;

  /// 頂点マーカーの色
  final Color vertexColor;

  const LinePreviewPainter({
    required this.backgroundLine,
    required this.foregroundLine,
    this.vertices,
    this.backgroundColor = const Color(0xFFBDBDBD), // Colors.grey.shade400
    this.foregroundColor = Colors.black,
    this.vertexColor = Colors.red,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final allPoints = backgroundLine.isNotEmpty ? backgroundLine : foregroundLine;
    if (allPoints.isEmpty) return;

    final bounds = _calcBounds(allPoints);
    Offset toOffset(LatLng point) => _latLngToOffset(point, bounds, size);

    // 背景ライン
    if (backgroundLine.length >= 2) {
      final paint = Paint()
        ..color = backgroundColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      _drawPath(canvas, backgroundLine, toOffset, paint);
    }

    // 前景ライン
    if (foregroundLine.length >= 2) {
      final paint = Paint()
        ..color = foregroundColor
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      _drawPath(canvas, foregroundLine, toOffset, paint);
    }

    // 頂点マーカー（多すぎる場合は間引いて描画）
    final verts = vertices ?? foregroundLine;
    if (verts.isNotEmpty) {
      final paint = Paint()
        ..color = vertexColor
        ..style = PaintingStyle.fill;
      const maxVertices = 200;
      final step = verts.length > maxVertices ? verts.length ~/ maxVertices : 1;
      for (int i = 0; i < verts.length; i += step) {
        canvas.drawCircle(toOffset(verts[i]), 2.5, paint);
      }
      // 最後の点は必ず描画
      if (step > 1) {
        canvas.drawCircle(toOffset(verts.last), 2.5, paint);
      }
    }
  }

  /// 座標リストのバウンディングボックスを計算（マージン付き）
  _Bounds _calcBounds(List<LatLng> points) {
    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;

    for (final p in points) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }

    final latMargin = (maxLat - minLat) * 0.1 + 0.0001;
    final lngMargin = (maxLng - minLng) * 0.1 + 0.0001;
    return _Bounds(
      minLat - latMargin,
      maxLat + latMargin,
      minLng - lngMargin,
      maxLng + lngMargin,
    );
  }

  Offset _latLngToOffset(LatLng point, _Bounds b, Size size) {
    final x = (point.longitude - b.minLng) / (b.maxLng - b.minLng) * size.width;
    final y = (b.maxLat - point.latitude) / (b.maxLat - b.minLat) * size.height;
    return Offset(x, y);
  }

  void _drawPath(
    Canvas canvas,
    List<LatLng> line,
    Offset Function(LatLng) transform,
    Paint paint,
  ) {
    final path = ui.Path();
    final start = transform(line.first);
    path.moveTo(start.dx, start.dy);
    for (int i = 1; i < line.length; i++) {
      final p = transform(line[i]);
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant LinePreviewPainter old) =>
      old.backgroundLine != backgroundLine ||
      old.foregroundLine != foregroundLine ||
      old.vertices != vertices;
}

class _Bounds {
  final double minLat, maxLat, minLng, maxLng;
  const _Bounds(this.minLat, this.maxLat, this.minLng, this.maxLng);
}
