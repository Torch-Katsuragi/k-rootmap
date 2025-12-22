// K-MAPS: Map and edit screen
// Main UI for map display and layer/feature editing
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // PointerScrollEvent用
// マウスボタン定数用
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_compass/flutter_compass.dart'; // コンパス機能用
import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/folder_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../models/nodes/image_node.dart';
import '../widgets/layer_drawer/layer_drawer.dart';
import '../widgets/resizable_side_panel.dart';
import '../widgets/dynamic_attribute_table_widget.dart';
import '../widgets/cached_tile_layer.dart'; // キャッシュ機能を有効化
import '../widgets/compass_fan_painter.dart'; // コンパス扇形描画用
import '../utils/global_config.dart';
// import 'package:k_maps/utils/app_logger.dart';
// sqflite移行により削除
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../tools/gps_tool.dart';
import '../utils/feature_calc_utils.dart';
import '../models/gps_track.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../widgets/gps_tracking_dialogs.dart'; // GPS追跡ダイアログ
import '../widgets/feature_detail_panel.dart'; // フィーチャ詳細パネル
import '../widgets/left_bottom_fab.dart'; // 左下FAB
import '../widgets/map_toolbar.dart'; // 地図ツールバー
import '../widgets/map_appbar_actions.dart'; // AppBarアクション
import '../services/foreground_service.dart'; // GPS追跡フォアグラウンドサービス
import 'layer_style_settings_screen.dart'; // レイヤ描画設定
import '../services/gps_manager_service.dart'; // 統合GPS管理サービス
import '../services/geometry_conversion_service.dart';
import '../utils/global_drawing_state.dart'; // GlobalDrawingState
import '../utils/keyboard_handler.dart'; // キーボードショートカット
import '../interfaces/map_state_interface.dart'; // 型安全なマップ状態インターフェース

/// Map and edit screen (main structure)
class KMapsHomePage extends StatefulWidget {
  const KMapsHomePage({super.key});
  @override
  State<KMapsHomePage> createState() => _KMapsHomePageState();
}

/// Tool types
enum ToolType { pen, eraser, gps }

class _KMapsHomePageState extends State<KMapsHomePage>
    with TickerProviderStateMixin
    implements IMapState {
  final LatLng _center = const LatLng(35.681236, 139.767125); // Tokyo Station
  LatLng? _currentLocation;
  Stream<Position>? _positionStream;
  StreamSubscription<Position>? _positionSubscription;

  // コンパス（端末の向き）関連
  double? _currentHeading; // 現在の方角（度数）
  StreamSubscription<CompassEvent>? _compassSubscription;
  final MapController _mapController = MapController();
  late LayerTreeNode? _currentNode;
  bool _movedToCurrentLocationOnce = false;

  // GPS長押し測量用状態変数
  bool _isLongPressing = false;
  int _longPressGpsCount = 0;
  Timer? _longPressCountUpdateTimer;
  double drawerWidth = 320;
  bool drawerOpen = true;
  final double minDrawerWidth = 200;

  // 統合GPS管理サービス
  final GpsManagerService _gpsManager = GpsManagerService();
  Map<String, dynamic>? _currentGpsInfo;
  int _gpsWaitSeconds = 0; // GPS acquisition wait seconds
  Timer? _gpsWaitTimer;

  // GPS追跡フォアグラウンドサービス管理
  final ForegroundServiceManager _serviceManager = ForegroundServiceManager();
  bool _isGpsTrackingServiceRunning = false;
  LatLng? _lastTrackedPosition; // フォアグラウンドサービスからの最新位置

  // GPS追跡ポイント都度保存用
  PointLayerNode? _trackingTargetPointLayer;
  int _trackedPointCount = 0;
  StreamSubscription<dynamic>? _trackPointSubscription;
  int _trackingSaveIntervalSeconds = 10; // 保存間隔（秒）
  int _trackingMinDistanceCm = 0; // 最小移動距離（cm）
  DateTime? _lastTrackingSaveTime; // 最後に保存した時刻
  LatLng? _lastSavedTrackingPosition; // 最後に保存した位置

  // メインisolateでのGPS追跡（外部GNSS用）
  bool _isMainIsolateTracking = false;

  // 属性テーブル表示状態
  bool _showAttributeTable = false;
  double _attributeTableWidth = 400;
  LayerNode? _attributeTableLayer;
  Timer? _serviceStatusUpdateTimer;

  // GPS追跡アニメーション用変数
  late AnimationController _trackingAnimationController;
  late Animation<double> _trackingRotationAnimation;

  // フィーチャデータキャッシュ用変数（非同期データを管理）
  List<PointFeatureNode> _pointFeatures = [];
  List<LineFeatureNode> _lineFeatures = [];
  List<PolygonFeatureNode> _polygonFeatures = [];
  List<ImageNode> _photoNodes = []; // ImageNode用キャッシュ追加

  // Public getter added (implements IMapState.mapController)
  @override
  MapController get mapController => _mapController;

  @override
  void initState() {
    super.initState();
    AppLogger.debug('[DEBUG] initState: KMapsHomePage start');
    GlobalConfig.instance.folderTree = FolderNode("rootNode", visible: true);
    _currentNode = GlobalConfig.instance.folderTree; // Reference root node
    AppLogger.debug('[DEBUG] initState: folderTree=${GlobalConfig.instance.folderTree}');
    GlobalConfig.instance.mapState = this;

    // レイヤ描画設定を読み込み＆変更リスナー登録
    LayerStyleConfig().load();
    LayerStyleConfig().addListener(_onLayerStyleChanged);

    // GPS追跡アニメーション初期化
    _trackingAnimationController = AnimationController(
      duration: const Duration(seconds: 3), // 3秒で1回転
      vsync: this,
    );
    _trackingRotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * 3.14159, // 2π（360度）
    ).animate(
      CurvedAnimation(
        parent: _trackingAnimationController,
        curve: Curves.linear, // 等速回転
      ),
    );

    // プロジェクトフォルダ内をスキャンして子ノード（サブフォルダ・.gpkgファイル）を更新
    _initializeProjectTree();

    // GPS管理サービス初期化と権限チェック
    _initializeGpsManager();

    // GPS追跡サービス状態の初期化
    _updateGpsTrackingServiceStatus();

    // 背景地図サービス初期化
    _initializeBaseMapService();

    // コンパス機能の初期化
    _initializeCompass();

    // 定期的にサービス状態を更新（10秒間隔に変更、かつ変化がある時のみ更新）
    // LayerDrawerに影響を与えないよう、更新頻度を最小限に抑制
    _serviceStatusUpdateTimer = Timer.periodic(Duration(seconds: 10), (timer) {
      _updateGpsTrackingServiceStatus();
    });

    // フィーチャデータの初期ロード（非同期）は_initializeProjectTree()内で実行
    // _updateFeatures();
  }

  /// プロジェクトツリーの初期化（非同期）
  Future<void> _initializeProjectTree() async {
    AppLogger.debug('[DEBUG] _initializeProjectTree: start');
    final rootNode = GlobalConfig.instance.folderTree;
    if (rootNode != null) {
      await _updateNodeRecursively(rootNode);
      // フィーチャデータを更新
      await _updateFeatures();
      // UI更新
      if (mounted) {
        setState(() {});
      }
    }
    AppLogger.debug('[DEBUG] _initializeProjectTree: complete');
  }

  /// ノードを再帰的に更新（サブフォルダ・GeoPackage・レイヤすべて）
  Future<void> _updateNodeRecursively(LayerTreeNode node) async {
    // まず明示的に初期化を実行
    await node.ensureInitialized();

    // 子ノードも再帰的に更新
    for (final child in node.children) {
      if (child is FolderNode || child is GeoPackageNode) {
        await _updateNodeRecursively(child);
      }
    }
  }

  /// 背景地図サービス初期化
  Future<void> _initializeBaseMapService() async {
    try {
      AppLogger.debug('[DEBUG] BaseMapService: 初期化開始');
      await GlobalConfig.instance.baseMapService.initialize();

      // 背景地図サービスの変更を監視
      GlobalConfig.instance.baseMapService.addListener(_onBaseMapServiceUpdate);

      AppLogger.debug('[DEBUG] BaseMapService: 初期化完了');
    } catch (e) {
      AppLogger.debug('[ERROR] BaseMapService: 初期化エラー: $e');
    }
  }

  /// コンパス機能初期化
  Future<void> _initializeCompass() async {
    try {
      AppLogger.debug('[DEBUG] Compass: 初期化開始');

      // コンパスストリームが利用可能かチェック
      final compassStream = FlutterCompass.events;
      if (compassStream == null) {
        AppLogger.debug('[DEBUG] Compass: コンパスストリームが利用できません');
        return;
      }

      // コンパスストリームの監視を開始
      _compassSubscription = compassStream.listen((CompassEvent event) {
        if (mounted && event.heading != null) {
          setState(() {
            _currentHeading = event.heading;
          });
        }
      });

      AppLogger.debug('[DEBUG] Compass: 初期化完了');
    } catch (e) {
      AppLogger.debug('[ERROR] Compass: 初期化エラー: $e');
    }
  }

  /// 背景地図サービス更新コールバック
  void _onBaseMapServiceUpdate() {
    if (mounted) {
      setState(() {}); // 背景地図が変更された時にUIを更新
    }
  }

  /// レイヤスタイル設定変更コールバック
  void _onLayerStyleChanged() {
    if (mounted) {
      setState(() {}); // スタイル変更時にマップを再描画
    }
  }

  /// GPS管理サービス初期化
  Future<void> _initializeGpsManager() async {
    AppLogger.debug('[DEBUG] GPS: GPS管理サービス初期化開始');

    try {
      // GPS管理サービスを初期化
      if (!_gpsManager.isInitialized) {
        await _gpsManager.initialize();
      }

      // GPS管理サービスの更新を監視
      _gpsManager.addListener(_onGpsManagerUpdate);

      // 外部GNSS機器をスキャン（バックグラウンドで実行）
      _scanGnssDevicesBackground();

      // GPS位置情報取得を開始
      await _gpsManager.startGps();

      // 初期GPS情報を取得
      _updateCurrentGpsInfo();

      // 標準のGeolocatorストリーム（マップ中心移動用）
      _positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _positionSubscription = _positionStream!.listen(
        (pos) {
          setState(() {
            _currentLocation = LatLng(pos.latitude, pos.longitude);
            if (!_movedToCurrentLocationOnce && _currentLocation != null) {
              _mapController.move(_currentLocation!, 16.0);
              _movedToCurrentLocationOnce = true;
            }
          });
        },
        onError: (error) {
          AppLogger.debug('[DEBUG] GPS: Geolocator stream error: $error');
        },
      );

      // GPS待機タイマー開始
      _gpsWaitSeconds = 0;
      _gpsWaitTimer = Timer.periodic(Duration(seconds: 1), (timer) {
        setState(() {
          _gpsWaitSeconds++;
        });
      });

      AppLogger.debug('[DEBUG] GPS: GPS管理サービス初期化完了');
    } catch (e) {
      AppLogger.debug('[DEBUG] GPS: GPS管理サービス初期化エラー: $e');
    }
  }

  /// 外部GNSS機器をバックグラウンドでスキャン
  Future<void> _scanGnssDevicesBackground() async {
    try {
      AppLogger.debug('[DEBUG] GPS: 外部GNSS機器バックグラウンドスキャン開始');
      await _gpsManager.scanExternalGnssDevices();
      AppLogger.debug(
        '[DEBUG] GPS: 外部GNSS機器スキャン完了: ${_gpsManager.availableGnssDevices.length}件',
      );
    } catch (e) {
      AppLogger.debug('[DEBUG] GPS: 外部GNSS機器スキャンエラー: $e');
      // エラーでもマップ画面の表示は継続
    }
  }

  /// GPS管理サービス更新コールバック
  void _onGpsManagerUpdate() {
    if (mounted) {
      _updateCurrentGpsInfo();
    }
  }

  /// 現在のGPS情報を更新
  void _updateCurrentGpsInfo() {
    setState(() {
      _currentGpsInfo = _gpsManager.getCurrentGpsInfo();
      // GPS情報が取得できた場合はタイマーを停止
      if (_currentGpsInfo != null && _currentGpsInfo!['isActive'] == true) {
        _gpsWaitTimer?.cancel();
      }
    });
  }

  @override
  void dispose() {
    _gpsManager.removeListener(_onGpsManagerUpdate);
    GlobalConfig.instance.baseMapService.removeListener(
      _onBaseMapServiceUpdate,
    );
    LayerStyleConfig().removeListener(_onLayerStyleChanged); // レイヤスタイル変更リスナー解除
    // GPS取得を停止（測量モードでない場合のみ）
    if (_gpsManager.isGpsActive && !_gpsManager.isSurveyMode) {
      _gpsManager.stopGps();
    }
    _positionSubscription?.cancel();
    _compassSubscription?.cancel(); // コンパス監視を停止
    _gpsWaitTimer?.cancel();
    _serviceStatusUpdateTimer?.cancel();
    _longPressCountUpdateTimer?.cancel(); // 長押しカウンタータイマーも破棄
    _trackPointSubscription?.cancel(); // GPS追跡ポイント受信リスナーを破棄
    _trackingAnimationController.dispose(); // アニメーションコントローラーを破棄
    super.dispose();
  }

  /// GPS追跡サービス状態を更新（画面表示に影響がある変化のみUIを更新）
  void _updateGpsTrackingServiceStatus() {
    final wasRunning = _isGpsTrackingServiceRunning;
    final isRunning = _serviceManager.isServiceRunning;
    final previousTrackedPosition = _lastTrackedPosition;

    // 状態に変化がない場合は何もしない（UIの不必要な再描画を防止）
    bool hasVisualChanges = false;

    // サービス開始/停止は地図上のボタン表示に影響するため更新が必要
    if (wasRunning != isRunning) {
      hasVisualChanges = true;
    }

    // サービスが動作中で現在位置がある場合、追跡位置を更新
    LatLng? newTrackedPosition = _lastTrackedPosition;
    if (isRunning && _currentLocation != null) {
      newTrackedPosition = _currentLocation;
      // 追跡位置の変更は地図上のアニメーション表示に影響する場合のみ更新
      // （座標の微細な変化は無視して、大きな移動のみ更新）
      if (previousTrackedPosition == null ||
          (newTrackedPosition!.latitude - previousTrackedPosition.latitude)
                  .abs() >
              0.0001 ||
          (newTrackedPosition.longitude - previousTrackedPosition.longitude)
                  .abs() >
              0.0001) {
        // 座標の大きな変化（約10m以上）のみ更新
        hasVisualChanges = true;
      }
    }

    // サービスが停止した場合、追跡位置をクリア
    if (!isRunning && wasRunning) {
      newTrackedPosition = null;
      hasVisualChanges = true;
    }

    // 実際の状態は常に更新（setStateは視覚的変化がある場合のみ）
    _isGpsTrackingServiceRunning = isRunning;
    _lastTrackedPosition = newTrackedPosition;

    // 視覚的変化がある場合のみsetState()を呼ぶ
    if (hasVisualChanges && mounted) {
      setState(() {}); // 状態は既に更新済みなので空のsetState
    }

    // アニメーション制御: サービス開始時に回転開始、停止時に回転停止
    if (isRunning && !wasRunning) {
      _trackingAnimationController.repeat(); // 無限回転開始
    } else if (!isRunning && wasRunning) {
      _trackingAnimationController.stop(); // 回転停止
      _trackingAnimationController.reset(); // 位置をリセット
    }
  }

  /// GPS追跡フォアグラウンドサービス開始
  Future<void> _startGpsTrackingService() async {
    // 保存先PointLayerNodeと保存オプションを選択
    final result = await _showSelectPointLayerDialog();
    if (result == null) {
      // ユーザーがキャンセルした
      return;
    }

    _trackingTargetPointLayer = result['layer'] as PointLayerNode;
    _trackingSaveIntervalSeconds = result['intervalSeconds'] as int;
    _trackingMinDistanceCm = result['minDistanceCm'] as int;
    final useExternalGnss = result['useExternalGnss'] as bool? ?? false;
    _trackedPointCount = 0;
    _lastTrackingSaveTime = null;
    _lastSavedTrackingPosition = null;

    // 外部GNSS使用フラグを設定
    _isMainIsolateTracking =
        useExternalGnss && _gpsManager.isExternalGnssConnected;

    try {
      AppLogger.debug(
        '[MapPage] GPS追跡開始: ${_isMainIsolateTracking ? "外部GNSS" : "内蔵GPS"}',
      );

      // 外部GNSS使用時はGPS測量モードを開始
      if (_isMainIsolateTracking) {
        await _gpsManager.startGpsSurveyWithWait();
        AppLogger.debug(
          '[MapPage] GPS測量モード開始: 外部GNSS機器 (${_gpsManager.selectedGnssDevice?.name})',
        );
      }

      // フォアグラウンドサービスは常に起動（内蔵GPSで動作）
      // バックグラウンドサービスからのポイント受信設定
      _trackPointSubscription?.cancel();
      _trackPointSubscription = FlutterBackgroundService()
          .on('addTrackPoint')
          .listen((event) {
            if (event != null) {
              _handleTrackPointForSaving(event);
            }
          });

      try {
        await _serviceManager.startService();
      } catch (e) {
        // Android 12以降でフォアグラウンドサービス開始が失敗する場合
        AppLogger.debug('[MapPage] GPS追跡サービス開始エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'GPS追跡サービスの開始に失敗しました。\n'
                'アプリを再起動してから再度お試しください。',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
        // エラー時はクリーンアップして終了
        _trackPointSubscription?.cancel();
        _trackPointSubscription = null;
        if (_isMainIsolateTracking) {
          await _gpsManager.stopGpsSurvey();
        }
        return;
      }
      
      _updateGpsTrackingServiceStatus();

      // アニメーション開始
      _trackingAnimationController.repeat();

      if (mounted) {
        final sourceType = _isMainIsolateTracking ? '外部GNSS' : '内蔵GPS';
        final deviceInfo =
            _isMainIsolateTracking
                ? ' (${_gpsManager.selectedGnssDevice?.name})'
                : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$sourceType追跡を開始しました。ポイントを「${_trackingTargetPointLayer!.name}」に$_trackingSaveIntervalSeconds秒間隔で保存します$deviceInfo',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[MapPage] GPS追跡開始エラー: $e');
      _isMainIsolateTracking = false;
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

  /// GPS追跡ポイントを都度保存
  Future<void> _handleTrackPointForSaving(Map<String, dynamic> event) async {
    // 保存先レイヤーの存在チェック
    if (_trackingTargetPointLayer == null) {
      AppLogger.debug('[MapPage] GPS追跡: 保存先レイヤーがnullです');
      return;
    }

    // レイヤーが削除されていないかチェック
    final parent = _trackingTargetPointLayer!.parent;
    if (parent == null ||
        !parent.children.contains(_trackingTargetPointLayer)) {
      AppLogger.debug('[MapPage] GPS追跡: 保存先レイヤーが削除されています');
      // 追跡を停止
      await _stopGpsTrackingService();
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
    if (_lastTrackingSaveTime != null) {
      final elapsedSeconds = now.difference(_lastTrackingSaveTime!).inSeconds;
      if (elapsedSeconds < _trackingSaveIntervalSeconds) {
        // まだ保存間隔に達していない
        return;
      }
    }

    try {
      // 外部GNSS使用時は外部GNSSデータを取得、内蔵GPS使用時はフォアグラウンドサービスのデータを使用
      Map<String, dynamic> pointData;
      LatLng position;

      if (_isMainIsolateTracking) {
        // 外部GNSS使用時：メインisolateから外部GNSSデータを取得
        final gpsInfo = _gpsManager.getCurrentGpsInfo();

        if (gpsInfo['isActive'] != true ||
            gpsInfo['latitude'] == null ||
            gpsInfo['longitude'] == null) {
          // 外部GNSS位置情報が利用できない（エラーログは出力しない）
          return;
        }

        final latitude = gpsInfo['latitude'] as double;
        final longitude = gpsInfo['longitude'] as double;
        position = LatLng(latitude, longitude);

        // 外部GNSSデータを使用
        pointData = {
          'latitude': latitude,
          'longitude': longitude,
          'altitude': gpsInfo['altitude'],
          'accuracy': gpsInfo['accuracy'],
          'speed': gpsInfo['speed'],
          'bearing': gpsInfo['bearing'],
          'sourceType': gpsInfo['sourceType'] ?? 'GNSS',
        };

        // 外部GNSSデータを使用（ログ削減）
      } else {
        // 内蔵GPS使用時：フォアグラウンドサービスのデータを使用
        pointData = Map<String, dynamic>.from(event);
        final latitude = pointData['latitude'].toDouble();
        final longitude = pointData['longitude'].toDouble();
        position = LatLng(latitude, longitude);
        // 内蔵GPSデータを使用（ログ削減）
      }

      // 移動距離チェック（最小移動距離が0より大きい場合のみ）
      if (_trackingMinDistanceCm > 0 && _lastSavedTrackingPosition != null) {
        final distanceMeters = _calculateDistance(
          _lastSavedTrackingPosition!,
          position,
        );
        final distanceCm = distanceMeters * 100;
        if (distanceCm < _trackingMinDistanceCm) {
          // 移動距離が閾値未満なので保存をスキップ
          // 移動距離不足でスキップ（ログ削減）
          return;
        }
      }

      // PointFeatureNodeを作成（メタデータなし、nameも空）
      final pointFeature = await PointFeatureNode.createIn(
        _trackingTargetPointLayer!,
        position,
        '', // nameは空（NULL相当）
        '',
      );

      if (pointFeature != null) {
        // GPS属性を個別カラムとして設定（geomと重複しないもののみ）
        final attributes = <String, dynamic>{};

        // 高度、精度、速度、方位など、geomに含まれない情報のみ保存
        if (pointData['altitude'] != null) {
          attributes['altitude'] =
              pointData['altitude'] is double
                  ? pointData['altitude']
                  : (pointData['altitude'] as num).toDouble();
        }
        if (pointData['accuracy'] != null) {
          attributes['accuracy'] =
              pointData['accuracy'] is double
                  ? pointData['accuracy']
                  : (pointData['accuracy'] as num).toDouble();
        }
        if (pointData['speed'] != null) {
          attributes['speed'] =
              pointData['speed'] is double
                  ? pointData['speed']
                  : (pointData['speed'] as num).toDouble();
        }
        if (pointData['bearing'] != null) {
          attributes['bearing'] =
              pointData['bearing'] is double
                  ? pointData['bearing']
                  : (pointData['bearing'] as num).toDouble();
        }

        // 重要：source_typeを設定（外部GNSS使用時は'GNSS'、内蔵GPS使用時は'GPS'）
        attributes['source_type'] = pointData['sourceType'] ?? 'GPS';
        attributes['timestamp'] = DateTime.now().toIso8601String();

        // 属性値を設定（カラムが存在しない場合は自動作成される）
        if (attributes.isNotEmpty) {
          await pointFeature.setAttributeValues(attributes);
        }

        _trackedPointCount++;
        _lastTrackingSaveTime = DateTime.now();
        _lastSavedTrackingPosition = position;
        AppLogger.debug(
          '[MapPage] GPS追跡ポイント保存: $_trackedPointCount ポイント目 (source_type: ${attributes['source_type']})',
        );

        // UI更新
        setState(() {
          _lastTrackedPosition = position;
        });
        refreshFeatures();
      } else {
        AppLogger.debug('[ERROR] GPS追跡ポイントの作成に失敗しました');
      }
    } catch (e) {
      AppLogger.debug('[MapPage] GPS追跡ポイント保存エラー: $e');
    }
  }

  /// 2点間の距離を計算（メートル）
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // 地球の半径（メートル）

    final lat1Rad = point1.latitude * pi / 180;
    final lat2Rad = point2.latitude * pi / 180;
    final dLat = (point2.latitude - point1.latitude) * pi / 180;
    final dLon = (point2.longitude - point1.longitude) * pi / 180;

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
  }

  /// 保存先PointLayerNode選択ダイアログを表示（GPS追跡用）
  Future<Map<String, dynamic>?> _showSelectPointLayerDialog() async {
    // カレントディレクトリからポイントレイヤーを検索
    final rootNode = GlobalConfig.instance.folderTree;
    if (rootNode == null) return null;

    // ポイントレイヤーを検索（空でもOK、新規作成できるので）
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

    // ダイアログで選択（保存オプション付き）
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => SelectPointLayerDialog(pointLayers: pointLayers),
    );
  }

  /// GPS測量（現在位置を記録）
  Future<void> _recordGpsPosition() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) {
        AppLogger.debug('[MapPage] GPS測量: 現在のツールがGpsToolではありません');
        return;
      }

      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('レイヤーが選択されていません'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      if (!selected.isVisibleRecursive()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('このレイヤは不可視のため編集できません'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // GPS位置情報取得開始のスナックバーを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS位置情報を取得中...'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }

      // GPS位置を記録
      final success = await currentTool.recordCurrentGpsPosition();
      if (success) {
        setState(() {}); // プレビュー更新

        if (mounted) {
          final totalPoints =
              GlobalConfig.instance.drawingState.drawingLine.length +
              GlobalConfig.instance.drawingState.drawingPolygon.length;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('GPS位置を記録しました ($totalPointsポイント目)'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS位置情報が取得できません。位置情報の許可と設定を確認してください。'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.debug('[MapPage] GPS測量エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GPS測量エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// GPS長押し測量開始
  Future<void> _startLongPressGpsSurvey() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) {
        AppLogger.debug('[MapPage] GPS長押し測量: 現在のツールがGpsToolではありません');
        return;
      }

      setState(() {
        _isLongPressing = true;
        _longPressGpsCount = 0;
      });

      AppLogger.debug('[MapPage] GPS長押し測量開始');
      currentTool.startLongPressGpsSurvey();

      // 長押し中の個数更新タイマーを開始（0.5秒間隔で更新）
      _longPressCountUpdateTimer = Timer.periodic(
        const Duration(milliseconds: 500),
        (timer) {
          // currentToolは既にGpsTool型として確定している（行808でガード済み）
          final newCount = currentTool.longPressGpsCount;
          if (_longPressGpsCount != newCount) {
            setState(() {
              _longPressGpsCount = newCount;
            });
          }
        },
      );

      // 長押し中のフィードバック用のスナックバーを表示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS長押し測量中... 離すと平均位置を記録します'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[MapPage] GPS長押し測量開始エラー: $e');
      _longPressCountUpdateTimer?.cancel();
      _longPressCountUpdateTimer = null;
      setState(() {
        _isLongPressing = false;
        _longPressGpsCount = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS長押し測量開始エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// GPS長押し測量停止と平均化処理
  Future<void> _stopLongPressGpsSurvey() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) {
        AppLogger.debug('[MapPage] GPS長押し測量停止: 現在のツールがGpsToolではありません');
        return;
      }

      AppLogger.debug('[MapPage] GPS長押し測量停止 - 平均化処理開始');
      final success = await currentTool.stopLongPressGpsSurvey();

      if (!success) {
        throw Exception('GPS長押し測量データが不十分です');
      }

      setState(() {
        _isLongPressing = false;
        _longPressGpsCount = 0;
      });

      // 長押しカウンタータイマーを停止
      _longPressCountUpdateTimer?.cancel();
      _longPressCountUpdateTimer = null;

      if (mounted) {
        // 成功のフィードバック
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS長押し測量完了 - 平均位置でポイントを作成しました'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[MapPage] GPS長押し測量停止エラー: $e');
      _longPressCountUpdateTimer?.cancel();
      _longPressCountUpdateTimer = null;
      setState(() {
        _isLongPressing = false;
        _longPressGpsCount = 0;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS長押し測量エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// GPS追跡フォアグラウンドサービス停止
  Future<void> _stopGpsTrackingService() async {
    AppLogger.debug(
      '[MapPage] GPS追跡停止: ${_isMainIsolateTracking ? "外部GNSS" : "内蔵GPS"}',
    );

    // 外部GNSS使用時はGPS測量モードを停止
    if (_isMainIsolateTracking) {
      await _gpsManager.stopGpsSurvey();
      _isMainIsolateTracking = false;
    }

    // ポイント受信リスナーをキャンセル
    _trackPointSubscription?.cancel();
    _trackPointSubscription = null;

    // フォアグラウンドサービスを停止
    await _serviceManager.stopService();
    _updateGpsTrackingServiceStatus();

    final savedCount = _trackedPointCount;
    final savedPointLayer = _trackingTargetPointLayer;

    // 保存されたポイントがある場合、処理方法を選択するダイアログを表示
    if (savedCount > 0 && savedPointLayer != null && mounted) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder:
            (context) => TrackingStopDialog(
              pointLayer: savedPointLayer,
              pointCount: savedCount,
            ),
      );

      if (result != null) {
        await _handleTrackingStopOption(result, savedPointLayer);
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
    _trackingTargetPointLayer = null;
    _trackedPointCount = 0;
    _lastTrackingSaveTime = null;
    _lastSavedTrackingPosition = null;
  }

  /// GPS追跡停止時の処理オプションを実行
  Future<void> _handleTrackingStopOption(
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
        final createdFeature =
            await GeometryConversionService.convertPointsToGeometry(
              sourceLayer: pointLayer,
              targetLayer: targetLayer,
              name: 'GPS追跡軌跡',
            );

        if (createdFeature != null) {
          // 変換後にポイントレイヤーを削除するか
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
          await _updateFeatures();
          setState(() {});
        }
      } catch (e) {
        AppLogger.debug('[MapPage] GPS追跡ポイント変換エラー: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('変換エラー: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // --- Utility to automatically close polygon rings ---
  @override
  List<LatLng> closeRing(List<LatLng> pts) {
    if (pts.length < 3) return [];
    final first = pts.first;
    final last = pts.last;
    bool isClosed =
        (first.latitude == last.latitude) &&
        (first.longitude == last.longitude);
    if (!isClosed) {
      return List<LatLng>.from(pts)..add(first);
    }
    return pts;
  }

  /// GPS測量確定処理
  Future<void> _onConfirmGpsSurvey() async {
    try {
      final currentTool = GlobalConfig.instance.currentTool;
      if (currentTool is! GpsTool) return;

      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) return;

      // 属性入力ダイアログを表示
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) {
          String name = '';
          String description = '';
          return AlertDialog(
            title: const Text('GPS測量フィーチャの属性入力'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '名前'),
                  onChanged: (v) => name = v,
                ),
                const SizedBox(height: 12),
                TextField(
                  decoration: const InputDecoration(labelText: '説明（任意）'),
                  maxLines: 3,
                  onChanged: (v) => description = v,
                ),
                const SizedBox(height: 12),
                Text(
                  'GPS測量データ（${GlobalConfig.instance.drawingState.drawingLine.length + GlobalConfig.instance.drawingState.drawingPolygon.length}ポイント）が自動的に記録されます',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.pop(context, {
                      'name': name,
                      'description': description,
                    }),
                child: const Text('作成'),
              ),
            ],
          );
        },
      );

      if (result == null) return;

      // GlobalDrawingStateの統一確定処理を使用（GPS測量メタデータ付き）
      final drawingState = GlobalDrawingState.instance;

      // GPS測量データを追加メタデータとして準備
      final surveyGpsData =
          drawingState.isLineDrawing
              ? drawingState.getLineWithMetadata()
              : drawingState.getPolygonWithMetadata();
      final additionalMetadata = {
        'type': 'measurement_log',
        'contents': List<Map<String, dynamic>>.from(
          surveyGpsData.map((e) => Map<String, dynamic>.from(e)),
        ),
      };

      final success = await drawingState.confirmCurrentFeature(
        layerNode: selected,
        name:
            result['name']?.isNotEmpty == true ? result['name']! : 'GPS測量フィーチャ',
        description: result['description'] ?? '',
        closeRing: closeRing,
        additionalMetadata: additionalMetadata,
        refreshCallback: () {
          // フィーチャ表示を更新（pen_toolと同じ処理を使用）
          _refreshMapUI();
        },
      );

      // GPS測量成功時はGPS停止（map_pageの_gpsManagerを使用）
      // currentToolは既にGpsTool型として確定している（行1062でガード済み）
      if (success) {
        await _gpsManager.stopGpsSurvey();
      }

      if (success) {
        // フィーチャ表示を更新
        await _updateFeatures();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS測量フィーチャを作成しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('GPS測量フィーチャの作成に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.debug('[MapPage] GPS測量確定エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS測量確定エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- Line/polygon confirmation processing ---
  Future<void> _onConfirmDrawing() async {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return;

    final drawingState = GlobalDrawingState.instance;

    // 描画データがあるかチェック
    if (!drawingState.isDrawing) {
      AppLogger.debug('[MAP] 確定処理: 描画データがありません');
      return;
    }

    // 属性入力ダイアログを表示
    String? name = await showDialog<String>(
      context: context,
      builder: (context) {
        String text = '';
        return AlertDialog(
          title: const Text('Attribute Input'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Attribute (Text)'),
            onChanged: (v) => text = v,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, text),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (name == null) return;

    // GlobalDrawingStateの統一確定処理を使用
    final success = await drawingState.confirmCurrentFeature(
      layerNode: selected,
      name: name.isNotEmpty ? name : '新規フィーチャ',
      description: '',
      closeRing: closeRing,
      refreshCallback: () {
        // フィーチャ表示を更新
        _refreshMapUI();
      },
    );

    if (success) {
      AppLogger.debug('[MAP] フィーチャ確定成功: $name');
    } else {
      AppLogger.debug('[MAP] フィーチャ確定失敗: $name');
    }
  }

  // --- Screen coordinates to map coordinates conversion ---
  @override
  LatLng offsetToLatLng(Offset offset) {
    // Flutter Map v8での正しい座標変換API
    try {
      final camera = _mapController.camera;
      return camera.offsetToCrs(offset);
    } catch (e) {
      AppLogger.debug('[ERROR] offsetToLatLng failed: $e');
      return _mapController.camera.center;
    }
  }

  // --- Map coordinates to screen pixel conversion ---
  @override
  Offset latLngToOffset(LatLng latlng) {
    // Flutter Map v8での正しい座標変換API
    try {
      final camera = _mapController.camera;
      return camera.latLngToScreenOffset(latlng);
    } catch (e) {
      AppLogger.debug('[ERROR] latLngToOffset failed: $e');
      final size = MediaQuery.of(context).size;
      return Offset(size.width / 2, size.height / 2);
    }
  }

  /// フィーチャデータを非同期で更新（キャッシュに保存）
  /// LayerNodeが管理するFeatureNodeを直接参照し、DBアクセスを最小限に抑制
  Future<void> _updateFeatures() async {
    AppLogger.debug('[DEBUG] _updateFeatures: start');
    final folderTree = GlobalConfig.instance.folderTree;
    AppLogger.debug('[DEBUG] _updateFeatures: folderTree=$folderTree');

    final visibleLayers =
        folderTree != null ? folderTree.getVisibleLayerNodes() : <LayerNode>[];
    AppLogger.debug(
      '[DEBUG] _updateFeatures: found ${visibleLayers.length} visible layers',
    );

    final pointFeatures = <PointFeatureNode>[];
    final lineFeatures = <LineFeatureNode>[];
    final polygonFeatures = <PolygonFeatureNode>[];
    final photoNodes = <ImageNode>[]; // ImageNode収集用リスト追加

    // ImageNodeを収集（FolderNode配下を再帰的に検索）
    if (folderTree != null) {
      _collectImageNodesRecursive(folderTree, photoNodes);
    }
    AppLogger.debug(
      '[DEBUG] _updateFeatures: collected ${photoNodes.length} photo nodes',
    );

    for (final node in visibleLayers) {
      // LayerNode以外はスキップ
      if (node is! LayerNode) continue;
      final layer = node;

      AppLogger.debug(
        '[DEBUG] _updateFeatures: processing layer ${layer.name} (${layer.runtimeType})',
      );

      // KMetaスタイルを事前読み込み（描画時に同期アクセスするため）
      if (!layer.isKmetaStyleLoaded) {
        await layer.getKmetaStyle();
      }

      // LayerNodeのchildrenから直接FeatureNodeを取得（dispose済みを除外）
      final layerFeatures =
          layer.children
              .whereType<FeatureNode>()
              .where((f) => !f.isDisposed)
              .toList();

      if (layer is PointLayerNode) {
        final layerPointFeatures =
            layerFeatures.whereType<PointFeatureNode>().toList();
        AppLogger.debug(
          '[DEBUG] _updateFeatures: found ${layerPointFeatures.length} point features in ${layer.name} (from children)',
        );
        pointFeatures.addAll(layerPointFeatures);

        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          await layer.updateChildren(); // DBから読み込んでchildrenに追加
          final dbPointFeatures =
              layer.features.whereType<PointFeatureNode>().toList();
          AppLogger.debug(
            '[DEBUG] _updateFeatures: loaded ${dbPointFeatures.length} point features from DB for ${layer.name}',
          );
          pointFeatures.addAll(dbPointFeatures);
        }
      } else if (layer is LineLayerNode) {
        final layerLineFeatures =
            layerFeatures.whereType<LineFeatureNode>().toList();
        AppLogger.debug(
          '[DEBUG] _updateFeatures: found ${layerLineFeatures.length} line features in ${layer.name} (from children)',
        );
        lineFeatures.addAll(layerLineFeatures);

        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          await layer.updateChildren(); // DBから読み込んでchildrenに追加
          final dbLineFeatures =
              layer.features.whereType<LineFeatureNode>().toList();
          AppLogger.debug(
            '[DEBUG] _updateFeatures: loaded ${dbLineFeatures.length} line features from DB for ${layer.name}',
          );
          lineFeatures.addAll(dbLineFeatures);
        }
      } else if (layer is PolygonLayerNode) {
        final layerPolygonFeatures =
            layerFeatures.whereType<PolygonFeatureNode>().toList();
        AppLogger.debug(
          '[DEBUG] _updateFeatures: found ${layerPolygonFeatures.length} polygon features in ${layer.name} (from children)',
        );
        polygonFeatures.addAll(layerPolygonFeatures);

        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          await layer.updateChildren(); // DBから読み込んでchildrenに追加
          final dbPolygonFeatures =
              layer.features.whereType<PolygonFeatureNode>().toList();
          AppLogger.debug(
            '[DEBUG] _updateFeatures: loaded ${dbPolygonFeatures.length} polygon features from DB for ${layer.name}',
          );
          polygonFeatures.addAll(dbPolygonFeatures);
        }
      }
    }

    AppLogger.debug(
      '[DEBUG] _updateFeatures: total features - points:${pointFeatures.length}, lines:${lineFeatures.length}, polygons:${polygonFeatures.length}, photos:${photoNodes.length}',
    );

    if (mounted) {
      setState(() {
        _pointFeatures = pointFeatures;
        _lineFeatures = lineFeatures;
        _polygonFeatures = polygonFeatures;
        _photoNodes = photoNodes; // ImageNodeキャッシュを更新
      });
      AppLogger.debug('[DEBUG] _updateFeatures: state updated successfully');
    } else {
      AppLogger.debug(
        '[DEBUG] _updateFeatures: widget not mounted, skipping state update',
      );
    }
  }

  /// ImageNodeを再帰的に収集する補助メソッド
  void _collectImageNodesRecursive(
    LayerTreeNode node,
    List<ImageNode> photoNodes,
  ) {
    // 現在のノードがImageNodeなら追加
    if (node is ImageNode && node.visible && node.isVisibleRecursive()) {
      photoNodes.add(node);
    }

    // 子ノードを再帰的に処理
    for (final child in node.children) {
      _collectImageNodesRecursive(child, photoNodes);
    }
  }

  /// フィーチャデータの公開更新メソッド（外部から呼び出し可能）
  @override
  void refreshFeatures() {
    _updateFeatures();
  }

  /// マップの強制更新処理（外部から呼び出し可能）
  /// フィーチャの追加・更新・削除後にマップ表示を更新
  @override
  void forceMapRefresh() {
    _refreshMapUI();
  }

  /// コンパス方向付きの現在位置マーカーを構築
  Widget _buildLocationMarkerWithCompass() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 方向を示す扇形（背景）
        if (_currentHeading != null)
          Transform.rotate(
            angle: (_currentHeading! * pi / 180) - (pi / 2), // 北を上に調整
            child: SizedBox(
              width: 60,
              height: 60,
              child: CustomPaint(painter: CompassFanPainter()),
            ),
          ),
        // 現在位置の中心円
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 追記モード開始処理
  /// [feature] - 追記対象のFeatureNode
  void _startAppendMode(FeatureNode feature) {
    AppLogger.debug('[MAP] 追記モード開始: ${feature.name} (${feature.runtimeType})');

    // 1. ツールをPenToolに切り替え
    setState(() {
      GlobalConfig.instance.currentTool = GlobalConfig.instance.penTool;
    });

    // 2. 選択レイヤーを該当フィーチャのレイヤーに設定
    LayerNode? targetLayer;
    if (feature is LineFeatureNode) {
      targetLayer = feature.parent as LayerNode?;
    } else if (feature is PolygonFeatureNode) {
      targetLayer = feature.parent as LayerNode?;
    }

    if (targetLayer != null) {
      setState(() {
        GlobalConfig.instance.selectedLayerNode = targetLayer;
      });
      AppLogger.debug('[MAP] 選択レイヤーを設定: ${targetLayer.name}');
    }

    // 3. UI状態を更新してツール変更とレイヤー選択を反映
    setState(() {});

    AppLogger.debug('[MAP] 追記モード開始完了');
  }

  /// マップUI更新処理
  /// フィーチャの追加・更新・削除後にマップ表示を更新
  /// 【重要】childrenはクリアせず、メモリ上のインスタンスから読み込む（DBアクセスなし）
  void _refreshMapUI() {
    AppLogger.debug('[MAP] マップUI更新開始（インスタンスベース）');

    // 1. フィーチャデータのキャッシュをクリア
    _pointFeatures.clear();
    _lineFeatures.clear();
    _polygonFeatures.clear();
    _photoNodes.clear();

    // 2. 【重要】LayerNodeのchildrenはクリアしない（メモリ上のインスタンスを維持）
    //    DBからの再読み込みは行わず、既存のchildrenから読み込む

    // 3. フィーチャデータを再読み込み（childrenが空の場合のみDBから読み込む）
    _updateFeatures()
        .then((_) {
          // 4. UI全体を更新
          if (mounted) {
            setState(() {});
            AppLogger.debug('[MAP] マップUI更新完了');
          }
        })
        .catchError((error) {
          AppLogger.debug('[ERROR] マップUI更新エラー: $error');
        });
  }

  /// 属性テーブルを開く
  Future<void> _openAttributeTable([LayerNode? targetLayer]) async {
    try {
      // ターゲットレイヤーが指定されていない場合は選択中のレイヤーを使用
      final layer = targetLayer ?? GlobalConfig.instance.selectedLayerNode;

      if (layer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('レイヤーが選択されていません'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      AppLogger.debug('[MAP] 属性テーブルを開く: ${layer.name}');

      setState(() {
        _attributeTableLayer = layer;
        _showAttributeTable = true;
        // レイヤドロワーを閉じる（属性テーブルと併用しない）
        drawerOpen = false;
      });

      AppLogger.debug('[MAP] 属性テーブル表示開始');
    } catch (e) {
      AppLogger.debug('[MAP] 属性テーブル表示エラー: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('属性テーブルの表示に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 属性テーブルを閉じる
  void _closeAttributeTable() {
    setState(() {
      _showAttributeTable = false;
      _attributeTableLayer = null;
    });
    AppLogger.debug('[MAP] 属性テーブル表示終了');
  }

  /// 属性テーブルでフィーチャが選択されたときの処理
  void _onAttributeTableFeatureSelected(FeatureNode feature) {
    try {
      AppLogger.debug('[MAP] 属性テーブルでフィーチャ選択: ${feature.rowId}');

      // 地図上でフィーチャを選択状態にする
      GlobalConfig.instance.selectedFeatures = [feature];

      // 地図を更新
      setState(() {});

      // 地図をフィーチャの位置にジャンプ
      _mapController.move(feature.centroid, _mapController.camera.zoom);

      AppLogger.debug('[MAP] フィーチャ選択とマップジャンプ完了');
    } catch (e) {
      AppLogger.debug('[MAP] フィーチャ選択処理エラー: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // キャッシュされたフィーチャデータを使用（非同期処理は _updateFeatures で実行）
    final pointFeatures = _pointFeatures;
    final lineFeatures = _lineFeatures;
    final polygonFeatures = _polygonFeatures;
    final photoNodes = _photoNodes; // ImageNodeキャッシュを取得

    final currentTool = GlobalConfig.instance.currentTool;
    final isPanTool = currentTool.name == 'Pan';

    // キーボードショートカット対応（Deleteキーなど）
    return KeyboardShortcutWrapper(
      mapState: this,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('K-MAPS GIS'),
          actions: buildMapAppBarActions(
            context: context,
            showAttributeTable: _showAttributeTable,
            drawerOpen: drawerOpen,
            onAttributeTableToggle: () {
              if (_showAttributeTable) {
                _closeAttributeTable();
              } else {
                _openAttributeTable();
              }
            },
            onDrawerToggle: () {
              setState(() {
                if (drawerOpen) {
                  drawerOpen = false;
                } else {
                  drawerOpen = true;
                  drawerWidth = 320;
                  // 属性テーブルを閉じる（layer drawerと併用しない）
                  _showAttributeTable = false;
                  _attributeTableLayer = null;
                }
              });
            },
          ),
          bottom: PreferredSize(
            preferredSize: Size.fromHeight(36),
            child: _buildGpsInfoBar(),
          ),
        ),
        body: Stack(
          children: [
            // 左側ツールバー
            MapToolbar(
              onToolChanged: () => setState(() {}),
              currentFolder:
                  _currentNode is FolderNode ? _currentNode as FolderNode : null,
            ),
            // --- Main map ---
            Positioned.fill(
              left: 44, // Move map to right of toolbar
              child: Stack(
                children: [
                  FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: _center,
                      initialZoom: 16.0,
                      // マウスホイール拡大制限をPanToolの設定に合わせる
                      maxZoom: PanTool.maxZoom,
                      interactionOptions: InteractionOptions(
                        flags:
                            isPanTool
                                ? InteractiveFlag.all
                                : (InteractiveFlag.pinchZoom |
                                    InteractiveFlag.scrollWheelZoom),
                      ),
                      // Windows環境での安定性向上設定
                      keepAlive: true,
                    ),
                    children: [
                      // キャッシュ機能付き地図タイルレイヤー
                      CachedTileLayer(
                        provider:
                            GlobalConfig
                                .instance
                                .baseMapService
                                .currentProvider,
                        baseMapService: GlobalConfig.instance.baseMapService,
                      ),
                      PolylineLayer(
                        polylines: [
                          for (final f in lineFeatures)
                            if (f.geometry != null)
                              (() {
                                final styleConfig = LayerStyleConfig();
                                // 親レイヤーのKMetaスタイルを取得
                                final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
                                final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
                                final lineColor = styleConfig.getLineColor(kmetaStyle);
                                final lineWidth = styleConfig.getLineWidth(kmetaStyle);
                                return Polyline(
                                  points: f.geometry as List<LatLng>,
                                  color: isSelected
                                      ? styleConfig.selectedColor
                                      : lineColor,
                                  strokeWidth: isSelected
                                      ? lineWidth * styleConfig.selectedMultiplier
                                      : lineWidth,
                                );
                              })(),
                          // --- GPS survey line preview ---
                          if (GlobalConfig.instance.currentTool is GpsTool &&
                              GlobalConfig
                                  .instance
                                  .drawingState
                                  .drawingLine
                                  .isNotEmpty)
                            Polyline(
                              points:
                                  GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingLine,
                              color: Colors.purple,
                              strokeWidth: 2.0,
                            ),
                          // --- Pen tool line preview ---
                          if (GlobalConfig.instance.currentTool is PenTool &&
                              GlobalConfig
                                  .instance
                                  .drawingState
                                  .drawingLine
                                  .isNotEmpty)
                            Polyline(
                              points:
                                  GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingLine,
                              color: Colors.orange,
                              strokeWidth: 1.5,
                            ),
                          // --- GPS survey polygon line preview (2点の場合) ---
                          if (GlobalConfig.instance.currentTool is GpsTool &&
                              GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingPolygon
                                      .length ==
                                  2)
                            Polyline(
                              points:
                                  GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingPolygon,
                              color: Colors.purple,
                              strokeWidth: 2.0,
                            ),
                          // --- Pen tool polygon line preview (2点の場合) ---
                          if (GlobalConfig.instance.currentTool is PenTool)
                            ...((() {
                              final drawingState = GlobalDrawingState.instance;
                              // 2点の場合は線として表示
                              if (drawingState.drawingPolygon.length == 2) {
                                return [
                                  Polyline(
                                    points: drawingState.drawingPolygon,
                                    color: Colors.orange,
                                    strokeWidth: 1.5,
                                  ),
                                ];
                              }
                              return <Polyline>[];
                            })()),
                          // --- GPS追跡中の軌跡プレビュー ---
                          if (_isGpsTrackingServiceRunning &&
                              GpsTrackManager().currentTrack != null &&
                              GpsTrackManager().currentTrack!.points.length >=
                                  2)
                            Polyline(
                              points:
                                  GpsTrackManager().currentTrack!
                                      .toLatLngList(),
                              color: Colors.cyan,
                              strokeWidth: 2.0,
                            ),
                        ],
                      ),
                      PolygonLayer(
                        polygons: [
                          for (final f in polygonFeatures)
                            if (f.geometry != null)
                              (() {
                                final styleConfig = LayerStyleConfig();
                                // 親レイヤーのKMetaスタイルを取得
                                final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
                                final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
                                final fillColor = styleConfig.getPolygonFillColor(kmetaStyle);
                                final fillOpacity = styleConfig.getPolygonFillOpacity(kmetaStyle);
                                final borderColor = styleConfig.getPolygonBorderColor(kmetaStyle);
                                final borderOpacity = styleConfig.getPolygonBorderOpacity(kmetaStyle);
                                final borderWidth = styleConfig.getPolygonBorderWidth(kmetaStyle);
                                return Polygon(
                                  points: (f.geometry as List<List<LatLng>>).first,
                                  holePointsList: (f.geometry as List<List<LatLng>>)
                                      .skip(1)
                                      .toList(),
                                  color: isSelected
                                      ? styleConfig.selectedColor.withValues(alpha: 0.5)
                                      : fillColor.withValues(alpha: fillOpacity),
                                  borderStrokeWidth: isSelected
                                      ? borderWidth * styleConfig.selectedMultiplier
                                      : borderWidth,
                                  borderColor: isSelected
                                      ? styleConfig.selectedColor
                                      : borderColor.withValues(alpha: borderOpacity),
                                );
                              })(),
                          // --- GPS survey polygon preview ---
                          if (GlobalConfig.instance.currentTool is GpsTool &&
                              GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingPolygon
                                      .length >=
                                  3) // 3点以上でのみポリゴンプレビューを表示
                            Polygon(
                              points: closeRing(
                                GlobalConfig
                                    .instance
                                    .drawingState
                                    .drawingPolygon,
                              ),
                              color: Colors.purple.withValues(alpha: 0.4),
                              borderStrokeWidth: 2.0,
                              borderColor: Colors.purple,
                            ),
                          // --- Pen tool polygon preview (3点以上の場合) ---
                          if (GlobalConfig.instance.currentTool is PenTool)
                            ...((() {
                              final drawingState = GlobalDrawingState.instance;
                              // 3点以上の場合のみポリゴンプレビューを表示
                              if (drawingState.drawingPolygon.length >= 3) {
                                final previewPoints = closeRing(
                                  drawingState.drawingPolygon,
                                );
                                if (previewPoints.isNotEmpty) {
                                  return [
                                    Polygon(
                                      points: previewPoints,
                                      color: Colors.orange.withValues(alpha: 0.4),
                                      borderStrokeWidth: 1.5,
                                      borderColor: Colors.orange,
                                    ),
                                  ];
                                }
                              }
                              return <Polygon>[];
                            })()),
                          // --- SelectTool lasso preview ---
                          if (GlobalConfig.instance.currentTool is SelectTool &&
                              (GlobalConfig.instance.currentTool as SelectTool)
                                      .lassoPoints
                                      .length >=
                                  3)
                            Polygon(
                              points: closeRing(
                                (GlobalConfig.instance.currentTool
                                        as SelectTool)
                                    .lassoPoints
                                    .map((offset) => offsetToLatLng(offset))
                                    .toList(),
                              ),
                              color: Colors.white.withValues(alpha: 0.2),
                              borderStrokeWidth: 1.0,
                              borderColor: Colors.black,
                            ),
                        ],
                      ),
                      // MarkerLayerを最後に移動（線・ポリゴンの上に点を表示）
                      MarkerLayer(
                        markers: [
                          // --- Current location marker with compass direction ---
                          if (_currentLocation != null)
                            Marker(
                              point: _currentLocation!,
                              width: 64,
                              height: 64,
                              child: _buildLocationMarkerWithCompass(),
                            ),

                          // --- GPS survey line/polygon point markers ---
                          if (GlobalConfig.instance.currentTool is GpsTool) ...[
                            // Line survey points
                            for (
                              int i = 0;
                              i <
                                  GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingLine
                                      .length;
                              i++
                            )
                              Marker(
                                point:
                                    GlobalConfig
                                        .instance
                                        .drawingState
                                        .drawingLine[i],
                                width: 32,
                                height: 32,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.purple,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${(() {
                                        try {
                                          final drawingState = GlobalConfig.instance.drawingState;
                                          final metadataList = drawingState.lineMetadata;
                                          if (i >= metadataList.length) return i + 1;
                                          final metadata = metadataList[i];
                                          if (metadata == null) return 1;
                                          if (metadata.containsKey('point_count')) {
                                            return metadata['point_count'] as int? ?? 1;
                                          }
                                          if (metadata.containsKey('collected_points') && metadata['collected_points'] is List) {
                                            return (metadata['collected_points'] as List).length;
                                          }
                                          return 1;
                                        } catch (e) {
                                          return i + 1;
                                        }
                                      })()}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Polygon survey points
                            for (
                              int i = 0;
                              i <
                                  GlobalConfig
                                      .instance
                                      .drawingState
                                      .drawingPolygon
                                      .length;
                              i++
                            )
                              Marker(
                                point:
                                    GlobalConfig
                                        .instance
                                        .drawingState
                                        .drawingPolygon[i],
                                width: 32,
                                height: 32,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: Colors.purple,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${(() {
                                        try {
                                          final drawingState = GlobalConfig.instance.drawingState;
                                          final metadataList = drawingState.polygonMetadata;
                                          if (i >= metadataList.length) return i + 1;
                                          final metadata = metadataList[i];
                                          if (metadata == null) return 1;
                                          if (metadata.containsKey('point_count')) {
                                            return metadata['point_count'] as int? ?? 1;
                                          }
                                          if (metadata.containsKey('collected_points') && metadata['collected_points'] is List) {
                                            return (metadata['collected_points'] as List).length;
                                          }
                                          return 1;
                                        } catch (e) {
                                          return i + 1;
                                        }
                                      })()}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],

                          // --- Line/Polygon vertex points (optional) ---
                          ...((() {
                            final style = LayerStyleConfig();
                            final markers = <Marker>[];

                            if (style.lineVertexPointsEnabled) {
                              for (final f in lineFeatures) {
                                if (f.geometry == null) continue;
                                final pts = f.geometry as List<LatLng>;
                                if (pts.isEmpty) continue;

                                final isSelected =
                                    GlobalConfig.instance.selectedFeatures.contains(f);
                                final color =
                                    isSelected ? style.selectedColor : style.lineColor;
                                final strokeWidth = isSelected
                                    ? style.lineWidth * style.selectedMultiplier
                                    : style.lineWidth;
                                final size = (strokeWidth * style.lineVertexPointSizeFactor)
                                    .clamp(4.0, 48.0);

                                for (final pt in pts) {
                                  markers.add(
                                    Marker(
                                      point: pt,
                                      width: size + 4,
                                      height: size + 4,
                                      child: Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: size > 10 ? 1.5 : 1.0,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 1,
                                              offset: Offset(0, 0.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              }
                            }

                            if (style.polygonVertexPointsEnabled) {
                              for (final f in polygonFeatures) {
                                if (f.geometry == null) continue;
                                final rings = f.geometry as List<List<LatLng>>;
                                if (rings.isEmpty) continue;

                                final isSelected =
                                    GlobalConfig.instance.selectedFeatures.contains(f);
                                final color = isSelected
                                    ? style.selectedColor
                                    : style.polygonBorderColor.withValues(
                                        alpha: style.polygonBorderOpacity,
                                      );
                                final strokeWidth = isSelected
                                    ? style.polygonBorderWidth * style.selectedMultiplier
                                    : style.polygonBorderWidth;
                                final size = (strokeWidth * style.polygonVertexPointSizeFactor)
                                    .clamp(4.0, 48.0);

                                for (final ring in rings) {
                                  if (ring.isEmpty) continue;
                                  final pts = List<LatLng>.from(ring);
                                  if (pts.length >= 2 && pts.first == pts.last) {
                                    pts.removeLast(); // 閉路の重複点は除外
                                  }
                                  for (final pt in pts) {
                                    markers.add(
                                      Marker(
                                        point: pt,
                                        width: size + 4,
                                        height: size + 4,
                                        child: Container(
                                          width: size,
                                          height: size,
                                          decoration: BoxDecoration(
                                            color: color,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: size > 10 ? 1.5 : 1.0,
                                            ),
                                            boxShadow: const [
                                              BoxShadow(
                                                color: Colors.black26,
                                                blurRadius: 1,
                                                offset: Offset(0, 0.5),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            }

                            return markers;
                          })()),

                          // --- Existing point feature markers ---
                          for (final f in pointFeatures)
                            if (f.geometry != null)
                              ...((f.geometry as List<LatLng>).map(
                                (pt) {
                                  final styleConfig = LayerStyleConfig();
                                  // 親レイヤーのKMetaスタイルを取得
                                  final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
                                  final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
                                  final pointSize = styleConfig.getPointSize(kmetaStyle);
                                  final pointColor = styleConfig.getPointColor(kmetaStyle);
                                  final size = isSelected
                                      ? pointSize * styleConfig.selectedMultiplier
                                      : pointSize;
                                  return Marker(
                                    point: pt,
                                    width: size + 4, // マージン考慮
                                    height: size + 4,
                                    child: Tooltip(
                                      message: f.name,
                                      child: Container(
                                        width: size,
                                        height: size,
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? styleConfig.selectedColor
                                              : pointColor,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: size > 8 ? 1.5 : 0.5,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black26,
                                              blurRadius: 1,
                                              offset: Offset(0, 0.5),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              )),

                          // --- ImageNode markers (写真アイコン) ---
                          for (final photo in photoNodes)
                            Marker(
                              point: photo.location,
                              width: 20,
                              height: 20,
                              child: GestureDetector(
                                onTap: () {
                                  // ImageNode選択処理
                                  setState(() {
                                    GlobalConfig.instance.selectedFeatures
                                        .clear();
                                    GlobalConfig.instance.selectedFeatures.add(
                                      photo,
                                    );
                                  });
                                },
                                child: Tooltip(
                                  message:
                                      '📸 ${photo.name}\n撮影位置: ${photo.location.latitude.toStringAsFixed(6)}, ${photo.location.longitude.toStringAsFixed(6)}',
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color:
                                          GlobalConfig.instance.selectedFeatures
                                                  .contains(photo)
                                              ? Colors.yellow[100]
                                              : Colors.white,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color:
                                            GlobalConfig
                                                    .instance
                                                    .selectedFeatures
                                                    .contains(photo)
                                                ? Colors.orange
                                                : Colors.purple,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 2,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                    child: Icon(
                                      Icons.photo_camera,
                                      color:
                                          GlobalConfig.instance.selectedFeatures
                                                  .contains(photo)
                                              ? Colors.orange
                                              : Colors.purple,
                                      size:
                                          GlobalConfig.instance.selectedFeatures
                                                  .contains(photo)
                                              ? 14
                                              : 12,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  Positioned.fill(
                    child: Listener(
                      onPointerMove: (event) {
                        // 中ボタンドラッグ中の場合は中ボタン移動処理を呼び出し
                        if (event.buttons == kMiddleMouseButton) {
                          GlobalConfig.instance.currentTool.onMiddleButtonMove(
                            event,
                            this,
                          );
                        } else {
                          GlobalConfig.instance.currentTool.addPointerToBuffer(
                            event.localPosition,
                          );
                        }
                      },
                      onPointerDown: (event) {
                        // 中ボタンが押下された場合は中ボタンダウン処理を呼び出し
                        if (event.buttons == kMiddleMouseButton) {
                          GlobalConfig.instance.currentTool.onMiddleButtonDown(
                            event,
                            this,
                          );
                        } else {
                          GlobalConfig.instance.currentTool.addPointerToBuffer(
                            event.localPosition,
                          );
                        }
                      },
                      onPointerUp: (event) {
                        // 中ボタンが離された場合は中ボタンアップ処理を呼び出し
                        if (event.buttons == 0) {
                          // ボタンが離された状態
                          GlobalConfig.instance.currentTool.onMiddleButtonUp(
                            event,
                            this,
                          );
                        }
                        GlobalConfig.instance.currentTool.clearPointerBuffer();
                      },
                      onPointerSignal: (event) {
                        // 現在のツールのonPointerSignalメソッドを呼び出し
                        GlobalConfig.instance.currentTool.onPointerSignal(
                          event,
                          this,
                        );
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTapUp: (details) {
                          GlobalConfig.instance.currentTool.onTap(
                            details,
                            this,
                          );
                        },
                        onScaleStart: (details) {
                          GlobalConfig.instance.currentTool.onScaleStart(
                            details,
                            this,
                          );
                        },
                        onScaleUpdate: (details) {
                          GlobalConfig.instance.currentTool.onScaleUpdate(
                            details,
                            this,
                          );
                        },
                        onScaleEnd: (details) {
                          GlobalConfig.instance.currentTool.onScaleEnd(
                            details,
                            this,
                          );
                        },
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                  // --- Pen tool drawing preview information ---
                  if (GlobalConfig.instance.currentTool is PenTool)
                    Builder(
                      builder: (context) {
                        final selected =
                            GlobalConfig.instance.selectedLayerNode;
                        final penTool =
                            GlobalConfig.instance.currentTool as PenTool;
                        String? previewText;
                        Offset? previewOffset;
                        // Point layer
                        if (selected is PointLayerNode &&
                            penTool.pointPreview != null) {
                          final pt = penTool.pointPreview!;
                          previewText =
                              'Coordinates: (${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)})';
                          previewOffset = latLngToOffset(pt);
                        }
                        // Line layer
                        else if (selected is LineLayerNode &&
                            GlobalDrawingState.instance.drawingLine.length >=
                                2) {
                          final len = GeometryCalc.calcLineLength(
                            GlobalDrawingState.instance.drawingLine,
                          );
                          final centroid = GeometryCalc.calcLineCentroid(
                            GlobalDrawingState.instance.drawingLine,
                          );
                          if (len >= 10000) {
                            previewText =
                                'Length: ${(len / 1000).toStringAsFixed(1)} km';
                          } else {
                            previewText = 'Length: ${len.toStringAsFixed(2)} m';
                          }
                          previewOffset = latLngToOffset(centroid);
                        }
                        // Polygon layer
                        else if (selected is PolygonLayerNode &&
                            GlobalDrawingState.instance.drawingPolygon.length >=
                                3) {
                          final closed = closeRing(
                            GlobalDrawingState.instance.drawingPolygon,
                          );
                          final areaDeg2 = GeometryCalc.calcPolygonArea([
                            closed,
                          ]);
                          final centroid = GeometryCalc.calcPolygonCentroid([
                            closed,
                          ]);
                          final areaM2 =
                              DegreeMeterConverter.convertAreaToMeters2(
                                areaDeg2,
                                centroid.latitude,
                              );
                          if (areaM2 >= 10000) {
                            previewText =
                                'Area: ${(areaM2 / 10000).toStringAsFixed(3)} ha';
                          } else {
                            previewText =
                                'Area: ${areaM2.toStringAsFixed(3)} m?';
                          }
                          previewOffset = latLngToOffset(centroid);
                        }
                        if (previewText != null && previewOffset != null) {
                          return Positioned(
                            left: previewOffset.dx + 10,
                            top: previewOffset.dy - 30,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                previewText,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  // --- GPS追跡サービスの回転する光エフェクト ---
                  if (_isGpsTrackingServiceRunning && _currentLocation != null)
                    AnimatedBuilder(
                      animation: _trackingRotationAnimation,
                      builder: (context, child) {
                        final screenPos = latLngToOffset(_currentLocation!);
                        return Positioned(
                          left: screenPos.dx - 40, // 中心を基準に調整
                          top: screenPos.dy - 40,
                          child: SizedBox(
                            width: 80,
                            height: 80,
                            child: Stack(
                              children: [
                                // 外側の薄い円 (軌跡)
                                Positioned.fill(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.orange.withValues(alpha: 0.3),
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                ),
                                // 回転する光点
                                Positioned(
                                  left:
                                      40 +
                                      30 *
                                          cos(
                                            _trackingRotationAnimation.value,
                                          ) -
                                      4, // 中心から30px離れた位置
                                  top:
                                      40 +
                                      30 *
                                          sin(
                                            _trackingRotationAnimation.value,
                                          ) -
                                      4,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: Colors.orange,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.orange.withValues(alpha: 0.8),
                                          blurRadius: 4,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                // さらに内側の小さな回転光点（逆回転で複雑な動き）
                                Positioned(
                                  left:
                                      40 +
                                      20 *
                                          cos(
                                            -_trackingRotationAnimation.value *
                                                1.5,
                                          ) -
                                      3, // 中心から20px離れた位置
                                  top:
                                      40 +
                                      20 *
                                          sin(
                                            -_trackingRotationAnimation.value *
                                                1.5,
                                          ) -
                                      3,
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: Colors.amber,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.amber.withValues(alpha: 0.6),
                                          blurRadius: 3,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
            // --- Custom Drawer ---
            // Layer Drawer Panel
            if (drawerOpen)
              ResizableSidePanel(
                initialWidth: drawerWidth,
                minWidth: minDrawerWidth,
                maxWidthRatio: 0.67,
                initiallyOpen: drawerOpen,
                onOpenChanged: (isOpen) {
                  setState(() {
                    drawerOpen = isOpen;
                  });
                },
                onWidthChanged: (width) {
                  setState(() {
                    drawerWidth = width;
                  });
                },
                child: LayerDrawer(
                  currentNode: _currentNode,
                  onDirChanged: (node) {
                    setState(() {
                      _currentNode = node;
                    });
                  },
                  setStateCallback: (fn) => setState(fn),
                  onJumpTo: (latLng) {
                    // Maintain current zoom level and move center
                    _mapController.move(latLng, _mapController.camera.zoom);
                  },
                  onStartAppendMode: (feature) {
                    // 追記モード開始処理
                    _startAppendMode(feature);
                  },
                ),
              ),

            // Attribute Table Panel
            if (_showAttributeTable && _attributeTableLayer != null)
              ResizableSidePanel(
                initialWidth: _attributeTableWidth,
                minWidth: 300,
                maxWidthRatio: 0.8,
                initiallyOpen: _showAttributeTable,
                onOpenChanged: (isOpen) {
                  if (!isOpen) {
                    _closeAttributeTable();
                  }
                },
                onWidthChanged: (width) {
                  setState(() {
                    _attributeTableWidth = width;
                  });
                },
                child: DynamicAttributeTableWidget(
                  layer: _attributeTableLayer!,
                  onFeatureSelected: _onAttributeTableFeatureSelected,
                  onFeatureDeleted: (feature) async {
                    // フィーチャ削除時の処理
                    try {
                      final layerNode = _attributeTableLayer!;

                      // フィーチャを削除（データベースからも削除される）
                      await feature.dispose();

                      // レイヤーノードから削除
                      layerNode.children.remove(feature);

                      // 成功メッセージ
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('フィーチャが削除されました: ID ${feature.rowId}'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }

                      // マップを更新
                      _refreshMapUI();

                      AppLogger.debug('[MAP] フィーチャ削除完了: ${feature.rowId}');
                    } catch (e) {
                      AppLogger.debug('[MAP] フィーチャ削除エラー: $e');
                    }
                  },
                  onAddFeature: () {
                    // 新規フィーチャ追加時の処理（将来実装）
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('新規フィーチャ追加機能は開発中です')),
                      );
                    }
                  },
                ),
              ),
            // --- Feature detail panel ---
            if (GlobalConfig.instance.selectedFeatures.length == 1)
              Positioned(
                left: 60,
                top: 20,
                child: FeatureDetailPanel(
                  feature: GlobalConfig.instance.selectedFeatures.first,
                ),
              ),
            // --- Left bottom floating buttons (placed next to toolbar) ---
            Positioned(
              left: 56, // Toolbar width(44) + margin(12)
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // GPS関連ボタン群（GPSツール選択時のみ表示）
                  if (GlobalConfig.instance.currentTool.name == 'GPS') ...[
                    // GPS測量ボタン（長押し対応）
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 長押し中のデータ個数表示
                          if (_isLongPressing)
                            Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4.0,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                '$_longPressGpsCount点',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          // GPS測量ボタン
                          GestureDetector(
                            onTap: _recordGpsPosition,
                            onLongPress: _startLongPressGpsSurvey,
                            onLongPressEnd: (_) => _stopLongPressGpsSurvey(),
                            child: Container(
                              width: 56.0,
                              height: 56.0,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 8.0,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  // 長押し進行状況を示すプログレスインジケーター
                                  if (_isLongPressing)
                                    SizedBox(
                                      width: 56.0,
                                      height: 56.0,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3.0,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                        backgroundColor: Colors.white
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                  // メインアイコン
                                  Icon(
                                    Icons.add_location,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // GPS追跡ボタン（Windows以外の環境でのみ表示）
                    if (!Platform.isWindows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FloatingActionButton(
                          heroTag: 'gps_tracking_left',
                          onPressed:
                              _isGpsTrackingServiceRunning
                                  ? _stopGpsTrackingService
                                  : _startGpsTrackingService,
                          backgroundColor:
                              _isGpsTrackingServiceRunning
                                  ? Colors.red
                                  : Colors.green,
                          foregroundColor: Colors.white,
                          tooltip:
                              _isGpsTrackingServiceRunning
                                  ? 'GPS追跡停止'
                                  : 'GPS追跡開始',
                          child: Icon(
                            _isGpsTrackingServiceRunning
                                ? Icons.stop
                                : Icons.pets, // 足跡アイコン（paw print）
                            // 他の選択肢: Icons.hiking, Icons.nordic_walking, Icons.accessibility_new
                            size: 28,
                          ),
                        ),
                      ),
                  ],
                  // 既存の左下フローティングボタン
                  const LeftBottomFab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton:
            (() {
              final selected = GlobalConfig.instance.selectedLayerNode;
              final currentTool = GlobalConfig.instance.currentTool;
              final gpsTool = currentTool is GpsTool ? currentTool : null;

              // GPS測量中のボタン表示
              final isGpsSurveyLine =
                  selected is LineLayerNode &&
                  gpsTool != null &&
                  gpsTool.surveyLine.isNotEmpty;
              final isGpsSurveyPolygon =
                  selected is PolygonLayerNode &&
                  gpsTool != null &&
                  gpsTool.surveyPolygon.isNotEmpty;

              // ペンツールでの描画中のボタン表示
              final isLineDrawing =
                  selected is LineLayerNode &&
                  currentTool is PenTool &&
                  GlobalConfig.instance.drawingState.drawingLine.isNotEmpty;
              final isPolygonDrawing =
                  selected is PolygonLayerNode &&
                  currentTool is PenTool &&
                  GlobalConfig.instance.drawingState.drawingPolygon.isNotEmpty;

              // GPS測量中は専用のボタンを表示
              if (isGpsSurveyLine || isGpsSurveyPolygon) {
                // ここではgpsToolはnon-nullが保証される（条件でチェック済み）
                final gps = gpsTool;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Undo button
                    FloatingActionButton(
                      heroTag: 'gps_undo',
                      onPressed: () {
                        final drawingState = GlobalDrawingState.instance;
                        final isLine = gps.surveyLine.isNotEmpty;
                        drawingState.undo(isLine: isLine);
                        setState(() {});
                      },
                      tooltip: 'GPS測量の最後のポイントを取り消し',
                      child: const Icon(Icons.undo),
                    ),
                    const SizedBox(width: 12),
                    // Cancel button
                    FloatingActionButton(
                      heroTag: 'gps_cancel',
                      onPressed: () async {
                        try {
                          await gps.cancelSurveyWithGpsStop();
                          setState(() {});
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('GPS測量をキャンセルしました'),
                                backgroundColor: Colors.orange,
                                duration: Duration(seconds: 1),
                              ),
                            );
                          }
                        } catch (e) {
                          AppLogger.debug('[MapPage] GPS測量キャンセルエラー: $e');
                        }
                      },
                      tooltip: 'GPS測量をキャンセル',
                      child: const Icon(Icons.clear),
                    ),
                    const SizedBox(width: 12),
                    // Confirm button
                    FloatingActionButton.extended(
                      heroTag: 'gps_confirm',
                      onPressed: _onConfirmGpsSurvey,
                      icon: const Icon(Icons.check),
                      label: const Text('GPS測量確定'),
                    ),
                  ],
                );
              }
              // ペンツールでの描画中は従来のボタンを表示
              else if (isLineDrawing || isPolygonDrawing) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Undo button
                    FloatingActionButton(
                      heroTag: 'undo',
                      onPressed: () {
                        final drawingState = GlobalDrawingState.instance;
                        if (isLineDrawing) {
                          drawingState.undo(isLine: true);
                          setState(() {}); // UI更新
                        } else if (isPolygonDrawing) {
                          drawingState.undo(isLine: false);
                          setState(() {}); // UI更新
                        }
                      },
                      tooltip: 'Undo',
                      child: const Icon(Icons.undo),
                    ),
                    const SizedBox(width: 12),
                    // Cancel button
                    FloatingActionButton(
                      heroTag: 'cancel',
                      onPressed: () {
                        final drawingState = GlobalDrawingState.instance;
                        if (isLineDrawing) {
                          drawingState.cancel(isLine: true);
                          setState(() {}); // UI更新
                        } else if (isPolygonDrawing) {
                          drawingState.cancel(isLine: false);
                          setState(() {}); // UI更新
                        }
                      },
                      tooltip: 'Cancel',
                      child: const Icon(Icons.clear),
                    ),
                    const SizedBox(width: 12),
                    // Confirm button
                    FloatingActionButton.extended(
                      heroTag: 'confirm',
                      onPressed: _onConfirmDrawing,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                    ),
                  ],
                );
              }
              return null;
            })(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    ); // KeyboardShortcutWrapper
  }

  /// GPS information bar widget
  Widget _buildGpsInfoBar() {
    if (_currentGpsInfo == null || _currentGpsInfo!['isActive'] != true) {
      return Container(
        height: 48,
        color: Colors.grey[200],
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.gps_off, size: 18, color: Colors.grey),
              SizedBox(width: 8),
              Text('GPS: 取得中...'),
              SizedBox(width: 12),
              Text(
                '($_gpsWaitSeconds秒経過)',
                style: TextStyle(color: Colors.grey),
              ),
              SizedBox(width: 16),
              Text('ソース: ${_currentGpsInfo?['sourceName'] ?? '不明'}'),
            ],
          ),
        ),
      );
    }

    final latitude = _currentGpsInfo!['latitude'];
    final longitude = _currentGpsInfo!['longitude'];
    final accuracy = _currentGpsInfo!['accuracy'];
    final satelliteCount = _currentGpsInfo!['satelliteCount'];
    final hdop = _currentGpsInfo!['hdop'];
    final sourceName = _currentGpsInfo!['sourceName'] ?? 'GPS';
    final sourceType = _currentGpsInfo!['sourceType'];
    final isExternalGnss = sourceType == 'GNSS';

    return Container(
      height: 48,
      color: Colors.lightBlue[50],
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              isExternalGnss ? Icons.bluetooth : Icons.gps_fixed,
              size: 18,
              color: Colors.blue,
            ),
            SizedBox(width: 8),
            Text(
              'Lat: ${latitude?.toStringAsFixed(6) ?? "取得中"} Lon: ${longitude?.toStringAsFixed(6) ?? "取得中"}',
              style: TextStyle(fontSize: 14),
            ),
            if (accuracy != null) ...[
              SizedBox(width: 16),
              Text('精度: ±${accuracy.toStringAsFixed(1)}m'),
            ],
            // 外部GNSS機器の場合のみ衛星情報とHDOPを表示
            if (isExternalGnss) ...[
              if (satelliteCount != null) ...[
                SizedBox(width: 16),
                Text('衛星数: $satelliteCount基'),
              ],
              if (hdop != null) ...[
                SizedBox(width: 16),
                Text('HDOP: ${hdop.toStringAsFixed(2)}'),
              ],
            ],
            SizedBox(width: 16),
            Text('ソース: $sourceName'),
            // コンパス情報を表示
            if (_currentHeading != null) ...[
              SizedBox(width: 16),
              Text('方角: ${_currentHeading!.toStringAsFixed(0)}°'),
            ],
          ],
        ),
      ),
    );
  }
}


