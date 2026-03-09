/// flutter_map互換のMapControllerラッパー
///
/// maplibreのMapControllerを内包し、既存コードが使う
/// flutter_map風のAPIを提供する。座標はLatLng(latlong2)を維持。
library;

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
class KMapController {
  ml.MapController? _controller;
  ml.StyleController? _styleController;

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
  Future<void> animateTo({
    LatLng? center,
    double? zoom,
    double? bearing,
    double? pitch,
  }) async {
    await _controller?.animateCamera(
      center: center?.toGeographic(),
      zoom: zoom,
      bearing: bearing,
      pitch: pitch,
    );
  }

  /// 座標リストに合わせてカメラをフィット
  void fitCoordinates(List<LatLng> coordinates, {EdgeInsets padding = EdgeInsets.zero}) {
    if (_controller == null || coordinates.isEmpty) return;

    // 座標からバウンディングボックスを計算
    double minLat = double.infinity, maxLat = -double.infinity;
    double minLon = double.infinity, maxLon = -double.infinity;
    for (final c in coordinates) {
      if (c.latitude < minLat) minLat = c.latitude;
      if (c.latitude > maxLat) maxLat = c.latitude;
      if (c.longitude < minLon) minLon = c.longitude;
      if (c.longitude > maxLon) maxLon = c.longitude;
    }

    _controller!.fitBounds(
      bounds: ml.LngLatBounds(
        longitudeWest: minLon,
        longitudeEast: maxLon,
        latitudeSouth: minLat,
        latitudeNorth: maxLat,
      ),
      padding: padding,
    );
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
    _controller = null;
    _styleController = null;
  }
}
