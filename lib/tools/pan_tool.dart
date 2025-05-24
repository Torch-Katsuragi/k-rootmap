// lib/tools/pan_tool.dart
// てのひらツール（地図パン専用）
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'map_tool.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show CustomPoint;

/// 地図パン（移動）専用ツール
class PanTool extends MapTool {
  @override
  String get name => 'てのひら';

  @override
  IconData get icon => Icons.pan_tool_alt;

  Offset? _lastFocalPoint;

  /// タップイベント
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    // パンツールでは特に何もしない
  }

  /// スケール開始イベント
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    // 最初の指位置を記録
    _lastFocalPoint = details.localFocalPoint;
  }

  /// スケール更新イベント
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    if (_lastFocalPoint == null) return;
    final delta = details.localFocalPoint - _lastFocalPoint!;
    _lastFocalPoint = details.localFocalPoint;

    // mapStateはKMapsHomePageのState。_mapControllerとcenter取得
    final mapController = mapState.mapController;
    final center = mapController.center;
    final zoom = mapController.zoom;

    // 現在の中心をピクセル座標に変換
    final centerPx = mapState.latLngToOffset(center);
    // 移動量を加算（Y軸は画面座標系に注意）
    final newCenterPx = centerPx - delta;
    // 新しいピクセル座標を地図座標に変換
    final newCenter = mapController.pointToLatLng(
      CustomPoint(newCenterPx.dx, newCenterPx.dy),
    );
    if (newCenter != null) {
      mapController.move(newCenter, zoom);
    }
  }

  /// スケール終了イベント
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    _lastFocalPoint = null;
  }
}
