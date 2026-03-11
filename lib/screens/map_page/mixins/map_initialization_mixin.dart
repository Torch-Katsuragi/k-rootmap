// K-MAPS: 初期化処理Mixin
// MapPageの各種サービス初期化処理を分離
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/platform_capabilities.dart';
import '../../../utils/app_logger.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../services/google_drive/index.dart';
import '../../../services/google_drive/auto_sync_service.dart';
import '../../../services/tile_server.dart';
import '../map_page_state_base.dart';
import '../../../utils/geo_converter.dart';
import '../../layer_style_settings_screen.dart' show layerStyleSettings;

/// 初期化処理Mixin
/// プロジェクトツリー、GPS、背景地図、コンパスの初期化を担当
mixin MapInitializationMixin<T extends ConsumerStatefulWidget>
    on MapPageStateBase<T> {
  // =============================================
  // 初期化処理
  // =============================================

  /// 全サービスの初期化を実行
  Future<void> initializeAllServices() async {
    AppLogger.debug('[Init] start');

    if (ref.read(folderTreeProvider) == null) {
      ref
          .read(folderTreeProvider.notifier)
          .set(FolderNode("Home", visible: true));
    }
    currentNode = ref.read(folderTreeProvider);

    // 背景地図サービス初期化（TileServer起動を最優先）
    await initializeBaseMapService();

    // 設定ストアを読み込み＆変更リスナー登録
    await layerStyleSettings.load();
    layerStyleSettings.addListener(onLayerStyleChanged);

    // プロジェクトツリー初期化
    await initializeProjectTree();

    // GPS管理サービス初期化
    await initializeGpsManager();

    // GPS履歴レコーダー初期化
    await initializeGpsHistoryRecorder();

    // コンパス機能の初期化
    await initializeCompass();

    AppLogger.debug('[Init] complete');
  }

  /// プロジェクトツリーの初期化（非同期）
  Future<void> initializeProjectTree() async {
    AppLogger.debug('[Init] projectTree start');
    final rootNode = ref.read(folderTreeProvider);
    if (rootNode != null) {
      await updateNodeRecursively(rootNode);
      // フィーチャデータを更新（サブクラスで実装）
      await updateFeatures();
      // UI更新
      triggerSetState(() {});

      // AutoSyncServiceを起動（WiFi時に自動同期、conflict時はサブタイトル通知）
      if (PlatformCapabilities.supportsDriveSyncStatusCheck) {
        AutoSyncService.instance.start(
          root: rootNode,
          onStatusChanged: () => triggerSetState(() {}),
          onRefreshNeeded: (node) => _updateChildrenRecursive(node),
        );
      }
    }
    AppLogger.debug('[Init] projectTree complete');
  }

  /// 子ノードを再帰的に更新（Pull後のツリーリフレッシュ用）
  Future<void> _updateChildrenRecursive(LayerTreeNode node) async {
    await node.updateChildren();
    for (final child in node.children) {
      if (child is FolderNode) {
        await _updateChildrenRecursive(child);
      } else if (child is GeoPackageNode) {
        await child.updateChildren();
      }
    }
  }

  /// ノードを再帰的に更新（サブフォルダ・GeoPackage・レイヤすべて）
  /// 兄弟ノードは並列処理（異なる.gpkgは別DB接続なので安全）
  Future<void> updateNodeRecursively(LayerTreeNode node) async {
    await node.ensureInitialized();

    // 兄弟ノードをFuture.waitで並列初期化
    final childFutures = node.children
        .where((c) => c is FolderNode || c is GeoPackageNode)
        .map((c) => updateNodeRecursively(c));

    await Future.wait(childFutures);
  }

  /// 背景地図サービス初期化（タイルサーバーも起動）
  Future<void> initializeBaseMapService() async {
    try {
      await baseMapService.initialize();
      await tileServer.start();
      basemapStyleUri = await TileServer.ensureLocalStyle();
      baseMapService.addListener(onBaseMapServiceUpdate);
      if (mapControllerInstance.style != null) onBaseMapServiceUpdate();
      triggerSetState(() {});
      AppLogger.debug('[Init] BaseMap ready (port=${tileServer.port})');
    } catch (e) {
      AppLogger.debug('[ERROR] BaseMapService: 初期化エラー: $e');
    }
  }

  /// コンパス機能初期化
  Future<void> initializeCompass() async {
    if (!PlatformCapabilities.supportsCompass) {
      AppLogger.debug('[Init] Compass: skipped (desktop)');
      return;
    }

    try {
      final compassStream = FlutterCompass.events;
      if (compassStream == null) return;

      // コンパスストリームの監視（ValueNotifier経由、setStateなし）
      compassSubscription = compassStream.listen((event) {
        if (mounted && event.heading != null) {
          headingNotifier.value = event.heading;
        }
      });

      AppLogger.debug('[Init] Compass ready');
    } catch (e) {
      AppLogger.debug('[ERROR] Compass: 初期化エラー: $e');
    }
  }

  /// GPS管理サービス初期化
  Future<void> initializeGpsManager() async {

    try {
      // GPS管理サービスを初期化
      if (!gpsManager.isInitialized) {
        await gpsManager.initialize();
      }

      // GPS管理サービスの更新を監視
      gpsManager.addListener(onGpsManagerUpdate);

      // 外部GNSS機器をスキャン（バックグラウンドで実行）
      scanGnssDevicesBackground();

      // GPS位置情報取得を開始（InternalGpsLocationStore経由）
      await gpsManager.startGps();

      // 初期GPS情報を取得
      updateCurrentGpsInfo();

      // Store.positionStream を購読（マップマーカー・中心移動用）
      positionSubscription = locationStore.positionStream.listen(
        (record) {
          triggerSetState(() {
            currentLocation = LatLng(record.latitude, record.longitude);
            if (!movedToCurrentLocationOnce && currentLocation != null) {
              mapController.move(currentLocation!, 16.0);
              movedToCurrentLocationOnce = true;
            }
          });
        },
        onError: (error) {
          AppLogger.debug('[GPS] stream error: $error');
        },
      );

      AppLogger.debug('[Init] GPS ready');
    } catch (e) {
      AppLogger.debug('[Init] GPS error: $e');
    }
  }

  /// GPS履歴レコーダー初期化
  Future<void> initializeGpsHistoryRecorder() async {
    try {
      final globalPath = ref.read(globalFolderPathProvider);
      if (globalPath == null) return;

      // AppSupportDir（rawバッファ用、プロジェクトUIに非表示）
      final supportDir = await getApplicationSupportDirectory();

      // GpsHistoryRecorder を初期化（ハイブリッド方式）
      await gpsHistoryRecorder.initialize(globalPath, supportDir.path);

      // positionStream の購読開始（常時記録 + consolidationタイマー）
      gpsHistoryRecorder.startRecording(locationStore.positionStream);

      // 軌跡更新リスナー登録（地図上にリアルタイム表示するため）
      gpsHistoryRecorder.addListener(_onGpsHistoryUpdate);

      AppLogger.debug('[Init] GpsHistory ready');
    } catch (e) {
      AppLogger.debug('[Init] GpsHistory error: $e');
    }
  }

  /// GPS履歴更新コールバック（MapSourceManager経由でGPS軌跡ソースのみ更新）
  void _onGpsHistoryUpdate() {
    if (mounted && sourceManager.isInitialized) {
      sourceManager.updateGpsTrack(
        gpsHistoryRecorder.todayPoints.toGeographics(),
      );
    }
  }

  /// 外部GNSS機器をバックグラウンドでスキャン
  Future<void> scanGnssDevicesBackground() async {
    try {
      await gpsManager.scanExternalGnssDevices();
    } catch (e) {
      AppLogger.debug('[GPS] GNSS scan error: $e');
      // エラーでもマップ画面の表示は継続
    }
  }

  // =============================================
  // 破棄処理
  // =============================================

  /// 全サービスの破棄処理
  void disposeAllServices() {
    AutoSyncService.instance.stop();
    tileServer.stop();
    gpsManager.removeListener(onGpsManagerUpdate);
    baseMapService.removeListener(onBaseMapServiceUpdate);
    layerStyleSettings.removeListener(onLayerStyleChanged);
    gpsHistoryRecorder.removeListener(_onGpsHistoryUpdate);

    // GPS取得を停止（測量モードでない場合のみ）
    if (gpsManager.isGpsActive && !gpsManager.isSurveyMode) {
      gpsManager.stopGps();
    }

    positionSubscription?.cancel();
    compassSubscription?.cancel();
    headingNotifier.dispose();
    longPressCountUpdateTimer?.cancel();
  }

  // =============================================
  // 抽象メソッド（サブクラスで実装）
  // =============================================

  /// フィーチャデータを更新
  Future<void> updateFeatures();
}
