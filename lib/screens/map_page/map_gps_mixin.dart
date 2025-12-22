// K-MAPS: GPS追跡関連のmixin
// map_page.dartからGPS追跡機能を分離して保守性を向上
//
// TODO: map_page.dartへの統合時に完全実装する
// このファイルは将来のリファクタリング用のプレースホルダーです

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../../models/nodes/layer_node.dart';
import '../../services/gps_manager_service.dart';
import '../../services/foreground_service.dart';

/// GPS追跡に必要な状態へのアクセスを提供するインターフェース
/// mixinがホストクラスの状態にアクセスするために使用
mixin MapGpsMixinState {
  // 必須プロパティ（ホストクラスで実装）
  GpsManagerService get gpsManager;
  ForegroundServiceManager get serviceManager;
  bool get isGpsTrackingServiceRunning;
  set isGpsTrackingServiceRunning(bool value);
  LatLng? get lastTrackedPosition;
  set lastTrackedPosition(LatLng? value);
  PointLayerNode? get trackingTargetPointLayer;
  set trackingTargetPointLayer(PointLayerNode? value);
  int get trackedPointCount;
  set trackedPointCount(int value);
  int get trackingSaveIntervalSeconds;
  set trackingSaveIntervalSeconds(int value);
  int get trackingMinDistanceCm;
  set trackingMinDistanceCm(int value);
  DateTime? get lastTrackingSaveTime;
  set lastTrackingSaveTime(DateTime? value);
  LatLng? get lastSavedTrackingPosition;
  set lastSavedTrackingPosition(LatLng? value);
  bool get isMainIsolateTracking;
  set isMainIsolateTracking(bool value);
  StreamSubscription<dynamic>? get trackPointSubscription;
  set trackPointSubscription(StreamSubscription<dynamic>? value);
  AnimationController get trackingAnimationController;
  LatLng? get currentLocation;
  bool get mounted;
  BuildContext get context;
  
  /// setStateの代理メソッド
  void triggerSetState(VoidCallback fn);
}

/// GPS追跡関連のmixin
/// GPS追跡サービスの開始/停止、ポイント保存などの機能を提供
/// 
/// 使用方法（将来の統合時）:
/// ```dart
/// class _MapPageState extends State<MapPage>
///     with MapGpsMixinState, MapGpsMixin {
///   // ...
/// }
/// ```
mixin MapGpsMixin on MapGpsMixinState {
  /// GPS追跡サービス状態を更新（画面表示に影響がある変化のみUIを更新）
  /// 
  /// 実装ロジック:
  /// 1. サービス開始/停止を検出
  /// 2. 追跡位置の変化を検出（約10m以上の移動のみ）
  /// 3. アニメーション制御
  void updateGpsTrackingServiceStatus() {
    final wasRunning = isGpsTrackingServiceRunning;
    final isRunning = serviceManager.isServiceRunning;
    final previousTrackedPosition = lastTrackedPosition;

    bool hasVisualChanges = false;

    // サービス開始/停止は地図上のボタン表示に影響するため更新が必要
    if (wasRunning != isRunning) {
      hasVisualChanges = true;
    }

    // サービスが動作中で現在位置がある場合、追跡位置を更新
    LatLng? newTrackedPosition = lastTrackedPosition;
    if (isRunning && currentLocation != null) {
      newTrackedPosition = currentLocation;
      // 座標の大きな変化（約10m以上）のみ更新
      if (previousTrackedPosition == null ||
          (newTrackedPosition!.latitude - previousTrackedPosition.latitude)
                  .abs() >
              0.0001 ||
          (newTrackedPosition.longitude - previousTrackedPosition.longitude)
                  .abs() >
              0.0001) {
        hasVisualChanges = true;
      }
    }

    // サービスが停止した場合、追跡位置をクリア
    if (!isRunning && wasRunning) {
      newTrackedPosition = null;
      hasVisualChanges = true;
    }

    // 実際の状態は常に更新
    isGpsTrackingServiceRunning = isRunning;
    lastTrackedPosition = newTrackedPosition;

    // 視覚的変化がある場合のみsetState()を呼ぶ
    if (hasVisualChanges && mounted) {
      triggerSetState(() {});
    }

    // アニメーション制御
    if (isRunning && !wasRunning) {
      trackingAnimationController.repeat();
    } else if (!isRunning && wasRunning) {
      trackingAnimationController.stop();
      trackingAnimationController.reset();
    }
  }

  /// 2点間の距離を計算（メートル単位）
  double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // メートル
    final lat1 = point1.latitude * math.pi / 180;
    final lat2 = point2.latitude * math.pi / 180;
    final dLat = (point2.latitude - point1.latitude) * math.pi / 180;
    final dLon = (point2.longitude - point1.longitude) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }
}


