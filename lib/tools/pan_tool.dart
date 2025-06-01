// lib/tools/pan_tool.dart
// てのひらツール（地図パン専用）
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // pointerEvents用
import 'map_tool.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map/flutter_map.dart' show CustomPoint;
import 'dart:math';
import '../utils/global_config.dart'; // SelectToolアクセス用

/// 地図パン（移動）専用ツール
class PanTool extends MapTool {
  @override
  String get name => 'Pan';

  @override
  IconData get icon => Icons.pan_tool_alt;

  // ピンチ・回転用状態
  Offset? _lastFocalPoint;
  double? _startZoom, _startRotation;
  LatLng? _startCenter;

  /// タップイベント - SelectToolのonTapを呼び出す
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    // パンツールでのシングルタップは選択動作として動作
    GlobalConfig.instance.selectTool.onTap(details, mapState);
  }

  /// スケール開始イベント
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    _lastFocalPoint = details.localFocalPoint;
    _startZoom = mapState.mapController.zoom;
    _startRotation = mapState.mapController.rotation;
    _startCenter = mapState.mapController.center;
  }

  /// スケール更新イベント
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    if (_lastFocalPoint == null) return;
    final delta = details.localFocalPoint - _lastFocalPoint!;
    _lastFocalPoint = details.localFocalPoint;
    final mapController = mapState.mapController;
    final center = mapController.center;
    final zoom = _startZoom! + log(details.scale) / ln2;
    // mapcontrollerはdegreeであるが、details.rotationはラジアンなので変換する必要がある
    final rotation = _startRotation! + details.rotation * 180 / pi;
    final centerPx = mapState.latLngToOffset(center);
    final newCenterPx = centerPx - delta;
    final newCenter = mapController.pointToLatLng(
      CustomPoint(newCenterPx.dx, newCenterPx.dy),
    );
    if (newCenter != null) {
      mapController.moveAndRotate(newCenter, zoom, rotation);
    }
  }

  /// スケール終了イベント
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    _lastFocalPoint = null;
    _startZoom = null;
    _startRotation = null;
    _startCenter = null;
  }
}
