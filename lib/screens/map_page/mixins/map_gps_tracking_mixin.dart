// K-MAPS: GPS追跡サービスMixin
// GPS追跡サービスの開始/停止、ポイント保存などの機能を提供
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:latlong2/latlong.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/global_config.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../services/geometry_conversion_service.dart';
import '../../../widgets/gps_tracking_dialogs.dart';
import '../map_page_state_base.dart';

/// GPS追跡サービスMixin
/// フォアグラウンドサービスを使用したGPS追跡機能を提供
mixin MapGpsTrackingMixin<T extends StatefulWidget> on MapPageStateBase<T> {
  
  // =============================================
  // GPS追跡サービス状態管理
  // =============================================
  
  /// GPS追跡サービス状態を更新（画面表示に影響がある変化のみUIを更新）
  @override
  void updateGpsTrackingServiceStatus() {
    final wasRunning = isGpsTrackingServiceRunning;
    final isRunning = serviceManager.isServiceRunning;
    final previousTrackedPosition = lastTrackedPosition;
    
    // 状態に変化がない場合は何もしない（UIの不必要な再描画を防止）
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
          (newTrackedPosition!.latitude - previousTrackedPosition.latitude).abs() > 0.0001 ||
          (newTrackedPosition.longitude - previousTrackedPosition.longitude).abs() > 0.0001) {
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
    
    // アニメーション制御: サービス開始時に回転開始、停止時に回転停止
    if (isRunning && !wasRunning) {
      trackingAnimationController.repeat();
    } else if (!isRunning && wasRunning) {
      trackingAnimationController.stop();
      trackingAnimationController.reset();
    }
  }
  
  // =============================================
  // GPS追跡サービス操作
  // =============================================
  
  /// GPS追跡フォアグラウンドサービス開始
  Future<void> startGpsTrackingService() async {
    // 保存先PointLayerNodeと保存オプションを選択
    final result = await showSelectPointLayerDialog();
    if (result == null) {
      // ユーザーがキャンセルした
      return;
    }
    
    trackingTargetPointLayer = result['layer'] as PointLayerNode;
    trackingSaveIntervalSeconds = result['intervalSeconds'] as int;
    trackingMinDistanceCm = result['minDistanceCm'] as int;
    final useExternalGnss = result['useExternalGnss'] as bool? ?? false;
    trackedPointCount = 0;
    lastTrackingSaveTime = null;
    lastSavedTrackingPosition = null;
    
    // 外部GNSS使用フラグを設定
    isMainIsolateTracking = useExternalGnss && gpsManager.isExternalGnssConnected;
    
    try {
      AppLogger.debug(
        '[MapGpsTrackingMixin] GPS追跡開始: ${isMainIsolateTracking ? "外部GNSS" : "内蔵GPS"}',
      );
      
      // 外部GNSS使用時はGPS測量モードを開始
      if (isMainIsolateTracking) {
        await gpsManager.startGpsSurveyWithWait();
        AppLogger.debug(
          '[MapGpsTrackingMixin] GPS測量モード開始: 外部GNSS機器 (${gpsManager.selectedGnssDevice?.name})',
        );
      }
      
      // バックグラウンドサービスからのポイント受信設定
      trackPointSubscription?.cancel();
      trackPointSubscription = FlutterBackgroundService()
          .on('addTrackPoint')
          .listen((event) {
            if (event != null) {
              handleTrackPointForSaving(event);
            }
          });
      
      try {
        await serviceManager.startService();
      } catch (e) {
        AppLogger.debug('[MapGpsTrackingMixin] GPS追跡サービス開始エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'GPS追跡サービスの開始に失敗しました。\n'
                'アプリを再起動してから再度お試しください。',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        // エラー時はクリーンアップして終了
        trackPointSubscription?.cancel();
        trackPointSubscription = null;
        if (isMainIsolateTracking) {
          await gpsManager.stopGpsSurvey();
        }
        return;
      }
      
      updateGpsTrackingServiceStatus();
      
      // アニメーション開始
      trackingAnimationController.repeat();
      
      if (mounted) {
        final sourceType = isMainIsolateTracking ? '外部GNSS' : '内蔵GPS';
        final deviceInfo = isMainIsolateTracking
            ? ' (${gpsManager.selectedGnssDevice?.name})'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$sourceType追跡を開始しました。ポイントを「${trackingTargetPointLayer!.name}」に$trackingSaveIntervalSeconds秒間隔で保存します$deviceInfo',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[MapGpsTrackingMixin] GPS追跡開始エラー: $e');
      isMainIsolateTracking = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS追跡の開始に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
  
  /// GPS追跡フォアグラウンドサービス停止
  Future<void> stopGpsTrackingService() async {
    AppLogger.debug(
      '[MapGpsTrackingMixin] GPS追跡停止: ${isMainIsolateTracking ? "外部GNSS" : "内蔵GPS"}',
    );
    
    // 外部GNSS使用時はGPS測量モードを停止
    if (isMainIsolateTracking) {
      await gpsManager.stopGpsSurvey();
      isMainIsolateTracking = false;
    }
    
    // ポイント受信リスナーをキャンセル
    trackPointSubscription?.cancel();
    trackPointSubscription = null;
    
    // フォアグラウンドサービスを停止
    await serviceManager.stopService();
    updateGpsTrackingServiceStatus();
    
    final savedCount = trackedPointCount;
    final savedPointLayer = trackingTargetPointLayer;
    
    // 保存されたポイントがある場合、処理方法を選択するダイアログを表示
    if (savedCount > 0 && savedPointLayer != null && mounted) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => TrackingStopDialog(
          pointLayer: savedPointLayer,
          pointCount: savedCount,
        ),
      );
      
      if (result != null) {
        await handleTrackingStopOption(result, savedPointLayer);
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS追跡を停止しました（保存されたポイントなし）'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    // 保存先レイヤー情報をクリア
    trackingTargetPointLayer = null;
    trackedPointCount = 0;
    lastTrackingSaveTime = null;
    lastSavedTrackingPosition = null;
  }
  
  // =============================================
  // ポイント保存処理
  // =============================================
  
  /// GPS追跡ポイントを都度保存
  Future<void> handleTrackPointForSaving(Map<String, dynamic> event) async {
    // 保存先レイヤーの存在チェック
    if (trackingTargetPointLayer == null) {
      AppLogger.debug('[MapGpsTrackingMixin] GPS追跡: 保存先レイヤーがnullです');
      return;
    }
    
    // レイヤーが削除されていないかチェック
    final parent = trackingTargetPointLayer!.parent;
    if (parent == null || !parent.children.contains(trackingTargetPointLayer)) {
      AppLogger.debug('[MapGpsTrackingMixin] GPS追跡: 保存先レイヤーが削除されています');
      // 追跡を停止
      await stopGpsTrackingService();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存先レイヤーが削除されました。GPS追跡を停止します。'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    
    // 時間間隔チェック
    final now = DateTime.now();
    if (lastTrackingSaveTime != null) {
      final elapsedSeconds = now.difference(lastTrackingSaveTime!).inSeconds;
      if (elapsedSeconds < trackingSaveIntervalSeconds) {
        return;
      }
    }
    
    try {
      Map<String, dynamic> pointData;
      LatLng position;
      
      if (isMainIsolateTracking) {
        // 外部GNSS使用時：メインisolateから外部GNSSデータを取得
        final gpsInfo = gpsManager.getCurrentGpsInfo();
        
        if (gpsInfo['isActive'] != true ||
            gpsInfo['latitude'] == null ||
            gpsInfo['longitude'] == null) {
          return;
        }
        
        final latitude = gpsInfo['latitude'] as double;
        final longitude = gpsInfo['longitude'] as double;
        position = LatLng(latitude, longitude);
        
        pointData = {
          'latitude': latitude,
          'longitude': longitude,
          'altitude': gpsInfo['altitude'],
          'accuracy': gpsInfo['accuracy'],
          'speed': gpsInfo['speed'],
          'bearing': gpsInfo['bearing'],
          'sourceType': gpsInfo['sourceType'] ?? 'GNSS',
        };
      } else {
        // 内蔵GPS使用時：フォアグラウンドサービスのデータを使用
        pointData = Map<String, dynamic>.from(event);
        final latitude = pointData['latitude'].toDouble();
        final longitude = pointData['longitude'].toDouble();
        position = LatLng(latitude, longitude);
      }
      
      // 移動距離チェック（最小移動距離が0より大きい場合のみ）
      if (trackingMinDistanceCm > 0 && lastSavedTrackingPosition != null) {
        final distanceMeters = calculateDistance(lastSavedTrackingPosition!, position);
        final distanceCm = distanceMeters * 100;
        if (distanceCm < trackingMinDistanceCm) {
          return;
        }
      }
      
      // PointFeatureNodeを作成
      final pointFeature = await PointFeatureNode.createIn(
        trackingTargetPointLayer!,
        position,
        '',
        '',
      );
      
      if (pointFeature != null) {
        // GPS属性を設定
        final attributes = <String, dynamic>{};
        
        if (pointData['altitude'] != null) {
          attributes['altitude'] = (pointData['altitude'] as num).toDouble();
        }
        if (pointData['accuracy'] != null) {
          attributes['accuracy'] = (pointData['accuracy'] as num).toDouble();
        }
        if (pointData['speed'] != null) {
          attributes['speed'] = (pointData['speed'] as num).toDouble();
        }
        if (pointData['bearing'] != null) {
          attributes['bearing'] = (pointData['bearing'] as num).toDouble();
        }
        
        attributes['source_type'] = pointData['sourceType'] ?? 'GPS';
        attributes['timestamp'] = DateTime.now().toIso8601String();
        
        if (attributes.isNotEmpty) {
          await pointFeature.setAttributeValues(attributes);
        }
        
        trackedPointCount++;
        lastTrackingSaveTime = DateTime.now();
        lastSavedTrackingPosition = position;
        
        AppLogger.debug(
          '[MapGpsTrackingMixin] GPS追跡ポイント保存: $trackedPointCount ポイント目',
        );
        
        // UI更新
        triggerSetState(() {
          lastTrackedPosition = position;
        });
        refreshFeatures();
      } else {
        AppLogger.debug('[ERROR] GPS追跡ポイントの作成に失敗しました');
      }
    } catch (e) {
      AppLogger.debug('[MapGpsTrackingMixin] GPS追跡ポイント保存エラー: $e');
    }
  }
  
  /// GPS追跡停止時の処理オプションを実行
  Future<void> handleTrackingStopOption(
    Map<String, dynamic> result,
    PointLayerNode pointLayer,
  ) async {
    final targetLayer = result['targetLayer'] as LayerNode?;
    final deletePoint = result['deletePoint'] as bool? ?? false;
    
    if (targetLayer == null) {
      // ポイントのみ保持
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS追跡を停止しました。ポイントは「${pointLayer.name}」に保存されています'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      // ライン/ポリゴンに変換
      try {
        final createdFeature = await GeometryConversionService.convertPointsToGeometry(
          sourceLayer: pointLayer,
          targetLayer: targetLayer,
          name: 'GPS追跡軌跡',
        );
        
        if (createdFeature != null) {
          if (deletePoint) {
            await pointLayer.dispose();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'GPS軌跡を「${targetLayer.name}」に変換し、ポイントレイヤーを削除しました',
                  ),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('GPS軌跡を「${targetLayer.name}」に変換しました'),
                  backgroundColor: Colors.green,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
          
          // UI更新
          await updateFeatures();
          triggerSetState(() {});
        }
      } catch (e) {
        AppLogger.debug('[MapGpsTrackingMixin] GPS追跡ポイント変換エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('変換エラー: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }
  
  // =============================================
  // ダイアログ
  // =============================================
  
  /// 保存先PointLayerNode選択ダイアログを表示
  Future<Map<String, dynamic>?> showSelectPointLayerDialog() async {
    final rootNode = GlobalConfig.instance.folderTree;
    if (rootNode == null) return null;
    
    // ポイントレイヤーを検索
    final pointLayers = <PointLayerNode>[];
    void searchPointLayers(LayerTreeNode node) {
      if (node is PointLayerNode) {
        pointLayers.add(node);
      }
      if (node is! FeatureNode) {
        for (final child in node.children) {
          searchPointLayers(child);
        }
      }
    }
    
    searchPointLayers(rootNode);
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SelectPointLayerDialog(pointLayers: pointLayers),
    );
  }
  
  // =============================================
  // ユーティリティ
  // =============================================
  
  /// 2点間の距離を計算（メートル）
  double calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000;
    
    final lat1Rad = point1.latitude * pi / 180;
    final lat2Rad = point2.latitude * pi / 180;
    final dLat = (point2.latitude - point1.latitude) * pi / 180;
    final dLon = (point2.longitude - point1.longitude) * pi / 180;
    
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }
  
  // =============================================
  // 抽象メソッド（サブクラスで実装）
  // =============================================
  
  /// フィーチャデータを更新
  Future<void> updateFeatures();
}

