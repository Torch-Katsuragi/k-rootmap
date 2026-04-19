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
/// flutter_map互換のMapControllerラッパー
///
/// maplibreのMapControllerを内包し、既存コードが使う
/// flutter_map風のAPIを提供する。座標はLatLng(latlong2)を維持。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import '../utils/geo_converter.dart';

/// flutter_map互換のカメラ情報
class KMapCamera {
  final ml.MapController _controller;

  KMapCamera(this._controller);

  double get zoom => _controller.getCamera().zoom;
  LatLng get center => _controller.getCamera().center.toLatLng();

  /// bearing (maplibre) = rotation (flutter_map) として扱う
  double get rotation => _controller.getCamera().bearing;
  double get bearing => _controller.getCamera().bearing;
  double get pitch => _controller.getCamera().pitch;

  /// 画面座標 → 地図座標
  LatLng offsetToCrs(Offset offset) =>
      _controller.toLngLat(offset).toLatLng();

  /// 地図座標 → 画面座標
  Offset latLngToScreenOffset(LatLng latlng) =>
      _controller.toScreenLocation(latlng.toGeographic());
}

/// maplibreのMapControllerをラップし、flutter_map互換APIを提供
class RMapController {
  ml.MapController? _controller;
  ml.StyleController? _styleController;

  /// カメラアニメーション排他制御用
  Timer? _fitDebounceTimer;
  bool _isCameraAnimating = false;

  /// maplibreのMapControllerをセット
  void attach(ml.MapController controller) {
    _controller = controller;
  }

  /// StyleControllerをセット
  void attachStyle(ml.StyleController style) {
    _styleController = style;
  }

  /// 生のmaplibreコントローラ（maplibre固有API用）
  ml.MapController? get raw => _controller;

  /// StyleController（ソース・レイヤ管理用）
  ml.StyleController? get style => _styleController;

  /// カメラ情報
  KMapCamera get camera {
    assert(_controller != null, 'MapController is not attached');
    return KMapCamera(_controller!);
  }

  /// カメラ移動（同期的にfire-and-forget）
  void move(LatLng center, double zoom) {
    _controller?.moveCamera(
      center: center.toGeographic(),
      zoom: zoom,
    );
  }

  /// カメラ移動 + 回転
  void moveAndRotate(LatLng center, double zoom, double rotation) {
    _controller?.moveCamera(
      center: center.toGeographic(),
      zoom: zoom,
      bearing: rotation,
    );
  }

  /// アニメーション付きカメラ移動
  ///
  /// 進行中のアニメーションがあれば即キャンセルしてから開始する。
  Future<void> animateTo({
    LatLng? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) async {
    _fitDebounceTimer?.cancel();
    _cancelOngoingAnimation();

    _isCameraAnimating = true;
    try {
      await _controller?.animateCamera(
        center: center?.toGeographic(),
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
      );
    } on Exception catch (_) {
      // moveCamera によるキャンセル時に "Map camera movement cancelled." が
      // スローされるが、意図的なキャンセルなので無視する
    } finally {
      _isCameraAnimating = false;
    }
  }

  /// 座標リストに合わせてカメラをフィット
  ///
  /// 短時間の連続呼び出しはデバウンスし、最後の呼び出しのみ実行する。
  /// 進行中のアニメーションがあれば即キャンセルしてから開始する。
  void fitCoordinates(List<LatLng> coordinates, {EdgeInsets padding = EdgeInsets.zero}) {
    if (_controller == null || coordinates.isEmpty) return;

    // デバウンス: 短時間の連続ダブルタップをまとめて最後の1つだけ実行
    _fitDebounceTimer?.cancel();
    _fitDebounceTimer = Timer(const Duration(milliseconds: 150), () {
      _executeFitBounds(coordinates, padding);
    });
  }

  /// 実際の fitBounds 実行（排他制御付き）
  Future<void> _executeFitBounds(
    List<LatLng> coordinates,
    EdgeInsets padding,
  ) async {
    if (_controller == null) return;

    // 進行中のアニメーションをキャンセル
    _cancelOngoingAnimation();

    // 座標からバウンディングボックスを計算
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;
    for (final c in coordinates) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    _isCameraAnimating = true;
    try {
      await _controller!.fitBounds(
        bounds: ml.LngLatBounds(
          longitudeWest: minLon,
          longitudeEast: maxLon,
          latitudeSouth: minLat,
          latitudeNorth: maxLat,
        ),
        padding: padding,
      );
    } on Exception catch (_) {
      // moveCamera によるキャンセル時に "Map camera movement cancelled." が
      // スローされるが、意図的なキャンセルなので無視する
    } finally {
      _isCameraAnimating = false;
    }
  }

  /// 進行中のカメラアニメーションを即座にキャンセル
  ///
  /// moveCamera（瞬時移動）で現在位置にスナップすることで
  /// ネイティブ側のアニメーションを中断する。
  void _cancelOngoingAnimation() {
    if (!_isCameraAnimating || _controller == null) return;
    final cam = _controller!.getCamera();
    _controller!.moveCamera(
      center: cam.center,
      zoom: cam.zoom,
      bearing: cam.bearing,
      pitch: cam.pitch,
    );
    _isCameraAnimating = false;
  }

  /// 画面座標 → 地図座標
  LatLng toLngLat(Offset offset) {
    assert(_controller != null, 'MapController is not attached');
    return _controller!.toLngLat(offset).toLatLng();
  }

  /// 地図座標 → 画面座標
  Offset toScreenLocation(LatLng latlng) {
    assert(_controller != null, 'MapController is not attached');
    return _controller!.toScreenLocation(latlng.toGeographic());
  }

  void dispose() {
    _fitDebounceTimer?.cancel();
    _controller = null;
    _styleController = null;
  }
}
