// K-MAPS: 初期化処理Mixin
// MapPageの各種サービス初期化処理を分離
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/global_config.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../map_page_state_base.dart';
import '../../layer_style_settings_screen.dart';

/// 初期化処理Mixin
/// プロジェクトツリー、GPS、背景地図、コンパスの初期化を担当
mixin MapInitializationMixin<T extends StatefulWidget> on MapPageStateBase<T> {
  
  // =============================================
  // 初期化処理
  // =============================================
  
  /// 全サービスの初期化を実行
  Future<void> initializeAllServices() async {
    AppLogger.debug('[DEBUG] initializeAllServices: start');
    
    // ルートノード設定（既に存在する場合は再作成しない）
    // home_screen.dartでグローバルフォルダ付きで作成済みの場合を考慮
    if (GlobalConfig.instance.folderTree == null) {
      GlobalConfig.instance.folderTree = FolderNode("rootNode", visible: true);
    }
    currentNode = GlobalConfig.instance.folderTree;
    GlobalConfig.instance.mapState = this;
    
    // レイヤ描画設定を読み込み＆変更リスナー登録
    LayerStyleConfig().load();
    LayerStyleConfig().addListener(onLayerStyleChanged);
    
    // 追跡アニメーション初期化
    initializeTrackingAnimation();
    
    // プロジェクトツリー初期化
    await initializeProjectTree();
    
    // GPS管理サービス初期化
    await initializeGpsManager();
    
    // GPS追跡サービス状態の初期化
    updateGpsTrackingServiceStatus();
    
    // 背景地図サービス初期化
    await initializeBaseMapService();
    
    // コンパス機能の初期化
    await initializeCompass();
    
    // 定期的にサービス状態を更新（10秒間隔）
    serviceStatusUpdateTimer = Timer.periodic(
      const Duration(seconds: 10),
      (timer) => updateGpsTrackingServiceStatus(),
    );
    
    AppLogger.debug('[DEBUG] initializeAllServices: complete');
  }
  
  /// 追跡アニメーション初期化
  void initializeTrackingAnimation() {
    trackingAnimationController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    trackingRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * 3.14159, // 2π（360度）
    ).animate(
      CurvedAnimation(
        parent: trackingAnimationController,
        curve: Curves.linear,
      ),
    );
  }
  
  /// プロジェクトツリーの初期化（非同期）
  Future<void> initializeProjectTree() async {
    AppLogger.debug('[DEBUG] initializeProjectTree: start');
    final rootNode = GlobalConfig.instance.folderTree;
    if (rootNode != null) {
      await updateNodeRecursively(rootNode);
      // フィーチャデータを更新（サブクラスで実装）
      await updateFeatures();
      // UI更新
      triggerSetState(() {});
    }
    AppLogger.debug('[DEBUG] initializeProjectTree: complete');
  }
  
  /// ノードを再帰的に更新（サブフォルダ・GeoPackage・レイヤすべて）
  Future<void> updateNodeRecursively(LayerTreeNode node) async {
    // まず明示的に初期化を実行
    await node.ensureInitialized();
    
    // 子ノードも再帰的に更新
    for (final child in node.children) {
      if (child is FolderNode || child is GeoPackageNode) {
        await updateNodeRecursively(child);
      }
    }
  }
  
  /// 背景地図サービス初期化
  Future<void> initializeBaseMapService() async {
    try {
      AppLogger.debug('[DEBUG] BaseMapService: 初期化開始');
      await GlobalConfig.instance.baseMapService.initialize();
      
      // 背景地図サービスの変更を監視
      GlobalConfig.instance.baseMapService.addListener(onBaseMapServiceUpdate);
      
      AppLogger.debug('[DEBUG] BaseMapService: 初期化完了');
    } catch (e) {
      AppLogger.debug('[ERROR] BaseMapService: 初期化エラー: $e');
    }
  }
  
  /// コンパス機能初期化
  Future<void> initializeCompass() async {
    try {
      AppLogger.debug('[DEBUG] Compass: 初期化開始');
      
      // コンパスストリームが利用可能かチェック
      final compassStream = FlutterCompass.events;
      if (compassStream == null) {
        AppLogger.debug('[DEBUG] Compass: コンパスストリームが利用できません');
        return;
      }
      
      // コンパスストリームの監視を開始
      compassSubscription = compassStream.listen((event) {
        if (mounted && event.heading != null) {
          triggerSetState(() {
            currentHeading = event.heading;
          });
        }
      });
      
      AppLogger.debug('[DEBUG] Compass: 初期化完了');
    } catch (e) {
      AppLogger.debug('[ERROR] Compass: 初期化エラー: $e');
    }
  }
  
  /// GPS管理サービス初期化
  Future<void> initializeGpsManager() async {
    AppLogger.debug('[DEBUG] GPS: GPS管理サービス初期化開始');
    
    try {
      // GPS管理サービスを初期化
      if (!gpsManager.isInitialized) {
        await gpsManager.initialize();
      }
      
      // GPS管理サービスの更新を監視
      gpsManager.addListener(onGpsManagerUpdate);
      
      // 外部GNSS機器をスキャン（バックグラウンドで実行）
      scanGnssDevicesBackground();
      
      // GPS位置情報取得を開始
      await gpsManager.startGps();
      
      // 初期GPS情報を取得
      updateCurrentGpsInfo();
      
      // 標準のGeolocatorストリーム（マップ中心移動用）
      positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      positionSubscription = positionStream!.listen(
        (pos) {
          triggerSetState(() {
            currentLocation = LatLng(pos.latitude, pos.longitude);
            if (!movedToCurrentLocationOnce && currentLocation != null) {
              mapController.move(currentLocation!, 16.0);
              movedToCurrentLocationOnce = true;
            }
          });
        },
        onError: (error) {
          AppLogger.debug('[DEBUG] GPS: Geolocator stream error: $error');
        },
      );
      
      // GPS待機タイマー開始
      gpsWaitSeconds = 0;
      gpsWaitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        triggerSetState(() {
          gpsWaitSeconds++;
        });
      });
      
      AppLogger.debug('[DEBUG] GPS: GPS管理サービス初期化完了');
    } catch (e) {
      AppLogger.debug('[DEBUG] GPS: GPS管理サービス初期化エラー: $e');
    }
  }
  
  /// 外部GNSS機器をバックグラウンドでスキャン
  Future<void> scanGnssDevicesBackground() async {
    try {
      AppLogger.debug('[DEBUG] GPS: 外部GNSS機器バックグラウンドスキャン開始');
      await gpsManager.scanExternalGnssDevices();
      AppLogger.debug(
        '[DEBUG] GPS: 外部GNSS機器スキャン完了: ${gpsManager.availableGnssDevices.length}件',
      );
    } catch (e) {
      AppLogger.debug('[DEBUG] GPS: 外部GNSS機器スキャンエラー: $e');
      // エラーでもマップ画面の表示は継続
    }
  }
  
  // =============================================
  // 破棄処理
  // =============================================
  
  /// 全サービスの破棄処理
  void disposeAllServices() {
    gpsManager.removeListener(onGpsManagerUpdate);
    GlobalConfig.instance.baseMapService.removeListener(onBaseMapServiceUpdate);
    LayerStyleConfig().removeListener(onLayerStyleChanged);
    
    // GPS取得を停止（測量モードでない場合のみ）
    if (gpsManager.isGpsActive && !gpsManager.isSurveyMode) {
      gpsManager.stopGps();
    }
    
    positionSubscription?.cancel();
    compassSubscription?.cancel();
    gpsWaitTimer?.cancel();
    serviceStatusUpdateTimer?.cancel();
    longPressCountUpdateTimer?.cancel();
    trackPointSubscription?.cancel();
    trackingAnimationController.dispose();
  }
  
  // =============================================
  // 抽象メソッド（サブクラスで実装）
  // =============================================
  
  /// フィーチャデータを更新
  Future<void> updateFeatures();
}

