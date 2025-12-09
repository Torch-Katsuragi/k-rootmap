// lib/tools/pan_tool.dart
// てのひらツール（地図パン専用）
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // PointerScrollEvent用
// pointerEvents用
import 'map_tool.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import '../utils/global_config.dart'; // SelectToolアクセス用

/// 地図パン（移動）専用ツール
class PanTool extends MapTool {
  @override
  String get name => 'Pan';

  @override
  IconData get icon => Icons.pan_tool_alt;

  // マウスホイールズームの最大倍率設定
  static const double maxZoom = 25.0;

  // ピンチ・回転用状態
  Offset? _lastFocalPoint;
  double? _startZoom, _startRotation;

  // 中ボタンドラッグ用状態
  bool _isMiddleButtonDragging = false;

  /// 中ボタンドラッグ状態の取得（他のツールから参照可能）
  bool get isMiddleButtonDragging => _isMiddleButtonDragging;

  /// タップイベント - SelectToolのonTapを呼び出す
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    // パンツールでのシングルタップは選択動作として動作
    GlobalConfig.instance.selectTool.onTap(details, mapState);
  }

  /// スケール開始イベント
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    // 中ボタンドラッグ中は通常のスケール処理をスキップ
    if (_isMiddleButtonDragging) return;

    _lastFocalPoint = details.localFocalPoint;
    _startZoom = mapState.mapController.camera.zoom;
    _startRotation = mapState.mapController.camera.rotation;
  }

  /// スケール更新イベント
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    // 中ボタンドラッグ中は通常のスケール処理をスキップ
    if (_isMiddleButtonDragging) return;

    if (_lastFocalPoint == null) return;
    final delta = details.localFocalPoint - _lastFocalPoint!;
    _lastFocalPoint = details.localFocalPoint;
    final mapController = mapState.mapController;
    final center = mapController.camera.center;
    final zoom = _startZoom! + log(details.scale) / ln2;
    // mapcontrollerはdegreeであるが、details.rotationはラジアンなので変換する必要がある
    final rotation = _startRotation! + details.rotation * 180 / pi;

    // Flutter Map v8の正しい座標変換を使用
    final centerPx = mapState.latLngToOffset(center);
    final newCenterPx = centerPx - delta;
    final newCenter = mapState.offsetToLatLng(newCenterPx);

    mapController.moveAndRotate(newCenter, zoom, rotation);
  }

  /// スケール終了イベント
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    // 中ボタンドラッグ中は通常のスケール処理をスキップ
    if (_isMiddleButtonDragging) return;

    _lastFocalPoint = null;
    _startZoom = null;
    _startRotation = null;
  }

  /// マウスホイールズーム処理（他のツールからも呼び出し可能）
  void handleMouseWheelZoom(PointerScrollEvent event, dynamic mapState) {
    // スクロール量を基にズーム量を計算
    const double zoomSpeed = 0.01; // ズーム感度調整（より細かいズーム操作）
    final double zoomDelta = -event.scrollDelta.dy * zoomSpeed;

    final mapController = mapState.mapController;
    final double currentZoom = mapController.camera.zoom;
    final double newZoom = (currentZoom + zoomDelta).clamp(1.0, maxZoom);

    if (newZoom != currentZoom) {
      // マウス位置を中心にズーム
      final LatLng cursorLatLng = mapState.offsetToLatLng(event.localPosition);
      mapController.moveAndRotate(
        cursorLatLng,
        newZoom,
        mapController.camera.rotation,
      );
    }
  }

  /// マウスホイールスクロールイベント（ズーム機能）
  @override
  void onPointerSignal(PointerEvent event, dynamic mapState) {
    if (event is PointerScrollEvent) {
      handleMouseWheelZoom(event, mapState);
    }
  }

  /// 中ボタンドラッグ開始（パン処理用の初期化）
  @override
  void onMiddleButtonDown(PointerDownEvent event, dynamic mapState) {
    _isMiddleButtonDragging = true;
    _lastFocalPoint = event.localPosition;
  }

  /// 中ボタンドラッグ移動（パン処理のみ）
  @override
  void onMiddleButtonMove(PointerMoveEvent event, dynamic mapState) {
    if (!_isMiddleButtonDragging || _lastFocalPoint == null) return;

    // 前回位置からの移動量を計算
    final delta = event.localPosition - _lastFocalPoint!;
    _lastFocalPoint = event.localPosition;

    final mapController = mapState.mapController;
    final center = mapController.camera.center;

    // パン処理（Flutter Map v8の正しい座標変換を使用）
    final centerPx = mapState.latLngToOffset(center);
    final newCenterPx = centerPx - delta;
    final newCenter = mapState.offsetToLatLng(newCenterPx);

    // パンのみ適用（ズームと回転は現在の値を維持）
    mapController.moveAndRotate(
      newCenter,
      mapController.camera.zoom,
      mapController.camera.rotation,
    );
  }

  /// 中ボタンドラッグ終了
  @override
  void onMiddleButtonUp(PointerUpEvent event, dynamic mapState) {
    _isMiddleButtonDragging = false;
    _lastFocalPoint = null;
  }
}
