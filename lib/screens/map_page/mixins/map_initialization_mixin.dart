// K-MAPS: 初期化処理Mixin
// MapPageの各種サービス初期化処理を分離
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import '../../../utils/app_logger.dart';
import '../../../providers/project_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../models/nodes/drive_folder_node.dart';
import '../../../services/google_drive/index.dart';
import '../map_page_state_base.dart';
import '../../layer_style_settings_screen.dart' show layerStyleSettings;
import '../../performance_settings_screen.dart' show performanceSettings;

/// 初期化処理Mixin
/// プロジェクトツリー、GPS、背景地図、コンパスの初期化を担当
mixin MapInitializationMixin<T extends ConsumerStatefulWidget>
    on MapPageStateBase<T> {
  // =============================================
  // 初期化処理
  // =============================================

  /// 全サービスの初期化を実行
  Future<void> initializeAllServices() async {
    AppLogger.debug('[DEBUG] initializeAllServices: start');

    if (ref.read(folderTreeProvider) == null) {
      ref
          .read(folderTreeProvider.notifier)
          .set(FolderNode("rootNode", visible: true));
    }
    currentNode = ref.read(folderTreeProvider);

    // 設定ストアを読み込み＆変更リスナー登録
    await layerStyleSettings.load();
    layerStyleSettings.addListener(onLayerStyleChanged);
    await performanceSettings.load();
    performanceSettings.addListener(onLayerStyleChanged);

    // プロジェクトツリー初期化
    await initializeProjectTree();

    // GPS管理サービス初期化
    await initializeGpsManager();

    // GPS履歴レコーダー初期化
    await initializeGpsHistoryRecorder();

    // 背景地図サービス初期化
    await initializeBaseMapService();

    // コンパス機能の初期化
    await initializeCompass();

    AppLogger.debug('[DEBUG] initializeAllServices: complete');
  }

  /// プロジェクトツリーの初期化（非同期）
  Future<void> initializeProjectTree() async {
    AppLogger.debug('[DEBUG] initializeProjectTree: start');
    final rootNode = ref.read(folderTreeProvider);
    if (rootNode != null) {
      await updateNodeRecursively(rootNode);
      // フィーチャデータを更新（サブクラスで実装）
      await updateFeatures();
      // UI更新
      triggerSetState(() {});

      // Drive連携フォルダの同期状態をバックグラウンドでチェック
      _checkDriveFoldersSyncStatus(rootNode);
    }
    AppLogger.debug('[DEBUG] initializeProjectTree: complete');
  }

  /// Drive連携フォルダの同期状態をチェック（バックグラウンド実行）
  /// PC版では実行しない（Google Drive Desktop使用を想定）
  Future<void> _checkDriveFoldersSyncStatus(LayerTreeNode rootNode) async {
    // PC版ではDrive連携機能を無効化
    if (!Platform.isAndroid && !Platform.isIOS) {
      AppLogger.debug('[DEBUG] PC版のためDrive同期状態チェックをスキップ');
      return;
    }

    final driveFolders = _collectDriveFolderNodes(rootNode);
    if (driveFolders.isEmpty) return;

    AppLogger.debug('[DEBUG] Drive連携フォルダ同期状態チェック: ${driveFolders.length}件');

    // Drive認証を確認
    final driveService = GoogleDriveService();
    await driveService.initialize();
    if (!driveService.isDriveApiAvailable) {
      AppLogger.debug('[DEBUG] Drive未認証のため同期状態チェックをスキップ');
      return;
    }

    // トークンをリフレッシュ
    await driveService.refreshToken();

    final syncEngine = SyncEngine();

    for (final node in driveFolders) {
      final localPath = node.getAbsoluteFilePath();
      if (localPath == null) continue;

      try {
        final status = await syncEngine.checkSyncStatus(localPath);
        switch (status) {
          case FolderSyncStatus.synced:
            node.syncStatus = SyncStatus.synced;
            break;
          case FolderSyncStatus.localChanges:
            node.syncStatus = SyncStatus.localChanges;
            break;
          case FolderSyncStatus.remoteChanges:
            node.syncStatus = SyncStatus.remoteChanges;
            break;
          case FolderSyncStatus.conflict:
            node.syncStatus = SyncStatus.conflict;
            break;
          case FolderSyncStatus.notLinked:
          case FolderSyncStatus.error:
            node.syncStatus = SyncStatus.error;
            break;
        }
        AppLogger.debug('[DEBUG] ${node.name} 同期状態: ${node.syncStatus}');
      } catch (e) {
        AppLogger.debug('[DEBUG] ${node.name} 同期状態チェックエラー: $e');
        node.syncStatus = SyncStatus.error;
      }
    }

    // UI更新
    triggerSetState(() {});
  }

  /// ツリーからDriveFolderNodeを収集
  List<DriveFolderNode> _collectDriveFolderNodes(LayerTreeNode node) {
    final result = <DriveFolderNode>[];

    if (node is DriveFolderNode) {
      result.add(node);
    }

    for (final child in node.children) {
      result.addAll(_collectDriveFolderNodes(child));
    }

    return result;
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

  /// 背景地図サービス初期化
  Future<void> initializeBaseMapService() async {
    try {
      AppLogger.debug('[DEBUG] BaseMapService: 初期化開始');
      await baseMapService.initialize();

      baseMapService.addListener(onBaseMapServiceUpdate);

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
          AppLogger.debug('[DEBUG] GPS: Store position stream error: $error');
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

  /// GPS履歴レコーダー初期化
  Future<void> initializeGpsHistoryRecorder() async {
    AppLogger.debug('[DEBUG] GPS: GPS履歴レコーダー初期化開始');

    try {
      final globalPath = ref.read(globalFolderPathProvider);
      if (globalPath == null) {
        AppLogger.debug('[DEBUG] GPS: グローバルフォルダパスが未設定のためスキップ');
        return;
      }

      // AppSupportDir（rawバッファ用、プロジェクトUIに非表示）
      final supportDir = await getApplicationSupportDirectory();

      // GpsHistoryRecorder を初期化（ハイブリッド方式）
      await gpsHistoryRecorder.initialize(globalPath, supportDir.path);

      // positionStream の購読開始（常時記録 + consolidationタイマー）
      gpsHistoryRecorder.startRecording(locationStore.positionStream);

      // 軌跡更新リスナー登録（地図上にリアルタイム表示するため）
      gpsHistoryRecorder.addListener(_onGpsHistoryUpdate);

      AppLogger.debug('[DEBUG] GPS: GPS履歴レコーダー初期化完了');
    } catch (e) {
      AppLogger.debug('[DEBUG] GPS: GPS履歴レコーダー初期化エラー: $e');
    }
  }

  /// GPS履歴更新コールバック（軌跡ポリライン更新用）
  void _onGpsHistoryUpdate() {
    if (mounted) {
      triggerSetState(() {});
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
    baseMapService.removeListener(onBaseMapServiceUpdate);
    layerStyleSettings.removeListener(onLayerStyleChanged);
    performanceSettings.removeListener(onLayerStyleChanged);
    gpsHistoryRecorder.removeListener(_onGpsHistoryUpdate);

    // GPS取得を停止（測量モードでない場合のみ）
    if (gpsManager.isGpsActive && !gpsManager.isSurveyMode) {
      gpsManager.stopGps();
    }

    positionSubscription?.cancel();
    compassSubscription?.cancel();
    gpsWaitTimer?.cancel();
    longPressCountUpdateTimer?.cancel();
  }

  // =============================================
  // 抽象メソッド（サブクラスで実装）
  // =============================================

  /// フィーチャデータを更新
  Future<void> updateFeatures();
}
