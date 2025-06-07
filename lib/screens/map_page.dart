// K-MAPS: Map and edit screen
// Main UI for map display and layer/feature editing
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../utils/wkb_utils.dart';
import '../models/layer_tree_node.dart';
import '../models/geometry_type.dart'; // ジオメトリタイプenumをインポート
import '../widgets/inline_edit.dart';
import '../widgets/layer_drawer.dart';
import '../utils/global_config.dart';
// import 'package:sqlite3/sqlite3.dart' as sql; // sqflite移行により削除
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../tools/gps_tool.dart';
import '../utils/global_config.dart' show LayerTreeNodeUtils;
import '../utils/feature_calc_utils.dart';
import '../models/gps_track.dart';
import '../widgets/track_save_dialog.dart';
import '../tools/gps_utils.dart'; // Added GPS utility
import '../screens/bluetooth_gnss_screen.dart'; // Bluetooth GNSS screen import
import '../services/foreground_service.dart'; // GPS追跡フォアグラウンドサービス

/// Map and edit screen (main structure)
class KMapsHomePage extends StatefulWidget {
  const KMapsHomePage({super.key});
  @override
  State<KMapsHomePage> createState() => _KMapsHomePageState();
}

/// Tool types
enum ToolType { pen, eraser, gps }

// --- Drawer use: Name edit state management ---
class _EditState {
  String? editingFolderPath;
  String? editingGpkgPath;
  int? editingLayerGpIndex;
  int? editingLayerIndex;
}

class _KMapsHomePageState extends State<KMapsHomePage>
    with TickerProviderStateMixin {
  final LatLng _center = const LatLng(35.681236, 139.767125); // Tokyo Station
  LatLng? _currentLocation;
  Stream<Position>? _positionStream;
  StreamSubscription<Position>? _positionSubscription;
  final MapController _mapController = MapController();
  ToolType _selectedTool = ToolType.pen;
  int _selectedBottomIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late LayerTreeNode? _currentNode;
  bool _movedToCurrentLocationOnce = false;
  int? _editingLayerIndex;
  String? _editingFolderPath;
  String? _editingGpkgPath;
  final _editState = _EditState();
  double drawerWidth = 320;
  bool drawerOpen = true;
  final double minDrawerWidth = 200;
  GpsPosition? _gpsPosition; // GPS information storage
  int? _satelliteCount; // Satellite count
  double? _hdop; // HDOP
  StreamSubscription? _gpsStreamSub;
  int _gpsWaitSeconds = 0; // GPS acquisition wait seconds
  Timer? _gpsWaitTimer;

  // GPS追跡フォアグラウンドサービス管理
  final ForegroundServiceManager _serviceManager = ForegroundServiceManager();
  bool _isGpsTrackingServiceRunning = false;
  LatLng? _lastTrackedPosition; // フォアグラウンドサービスからの最新位置
  Timer? _serviceStatusUpdateTimer;

  // GPS追跡アニメーション用変数
  late AnimationController _trackingAnimationController;
  late Animation<double> _trackingRotationAnimation;

  // フィーチャデータキャッシュ用変数（非同期データを管理）
  List<PointFeatureNode> _pointFeatures = [];
  List<LineFeatureNode> _lineFeatures = [];
  List<PolygonFeatureNode> _polygonFeatures = [];

  // Public getter added
  MapController get mapController => _mapController;

  @override
  void initState() {
    super.initState();
    print('[DEBUG] initState: KMapsHomePage start');
    GlobalConfig.instance.folderTree = FolderNode("rootNode", visible: true);
    _currentNode = GlobalConfig.instance.folderTree; // Reference root node
    print('[DEBUG] initState: folderTree=${GlobalConfig.instance.folderTree}');
    GlobalConfig.instance.mapState = this;

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

    // GPS権限チェックと初期化
    _initializeGps();

    // GPS追跡サービス状態の初期化
    _updateGpsTrackingServiceStatus();

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
    print('[DEBUG] _initializeProjectTree: start');
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
    print('[DEBUG] _initializeProjectTree: complete');
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

  /// GPS初期化処理（権限チェック・ストリーム購読）
  Future<void> _initializeGps() async {
    print('[DEBUG] GPS: Starting GPS initialization');

    // 権限チェック・リクエスト
    bool hasPermission = await GpsUtils.instance.checkAndRequestPermission();
    if (!hasPermission) {
      print('[DEBUG] GPS: Permission denied, GPS features disabled');
      return;
    }

    // 位置情報サービス確認
    bool serviceEnabled = await GpsUtils.instance.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('[DEBUG] GPS: Location service disabled, GPS features disabled');
      return;
    }

    print('[DEBUG] GPS: Permission and service OK, starting streams');

    // 標準のGeolocatorストリーム（現在位置表示用）
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
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
        print('[DEBUG] GPS: Geolocator stream error: $error');
      },
    );

    // Start GPS acquisition wait timer
    _gpsWaitSeconds = 0;
    _gpsWaitTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _gpsWaitSeconds++;
      });
    });

    // Subscribe to GPS information stream (詳細GPS情報用)
    _gpsStreamSub = GpsUtils.instance.getPositionStream().listen(
      (pos) {
        if (pos is GpsPosition) {
          setState(() {
            _gpsPosition = pos;
            _satelliteCount = pos.satellites;
            _hdop = pos.hdop;
            _gpsWaitTimer?.cancel(); // Stop timer when acquired
          });
        }
      },
      onError: (error) {
        print('[DEBUG] GPS: GpsUtils stream error: $error');
      },
    );
  }

  @override
  void dispose() {
    _gpsStreamSub?.cancel();
    _positionSubscription?.cancel();
    _gpsWaitTimer?.cancel();
    _serviceStatusUpdateTimer?.cancel();
    _trackingAnimationController.dispose(); // アニメーションコントローラーを破棄
    super.dispose();
  }

  void _moveToCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
    }
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
    // 外部GNSS設定確認
    final gnssDevice = ForegroundServiceManager.getGnssDevice();
    String sourceType = gnssDevice['address'] != null ? '外部GNSS' : '内蔵GPS';
    String deviceInfo =
        gnssDevice['name'] != null ? ' (${gnssDevice['name']})' : '';

    await _serviceManager.startService();
    _updateGpsTrackingServiceStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$sourceType追跡フォアグラウンドサービスを開始しました$deviceInfo'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// GPS追跡フォアグラウンドサービス停止
  Future<void> _stopGpsTrackingService() async {
    // 軌跡データを取得
    final track = _serviceManager.stopTrackingAndGetTrack();

    await _serviceManager.stopService();
    _updateGpsTrackingServiceStatus();

    // 軌跡保存ダイアログを表示
    if (track != null && track.pointCount > 0) {
      _showTrackSaveDialog(track);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('位置追跡フォアグラウンドサービスを停止しました（軌跡データなし）'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 軌跡保存ダイアログを表示
  Future<void> _showTrackSaveDialog(GpsTrack track) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (context) => TrackSaveDialog(
            track: track,
            rootNode: GlobalConfig.instance.folderTree,
          ),
    );

    if (result != null) {
      final savedTrack = result['track'] as GpsTrack;
      final geoPackage = result['geoPackage'] as GeoPackageNode;
      await _saveTrackToGeoPackage(savedTrack, geoPackage);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('位置追跡フォアグラウンドサービスを停止しました（軌跡は保存されませんでした）'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 軌跡をGeoPackageに保存
  Future<void> _saveTrackToGeoPackage(
    GpsTrack track,
    GeoPackageNode geoPackage,
  ) async {
    try {
      print('[DEBUG] GPS軌跡保存開始: ${track.trackName} -> ${geoPackage.name}');
      print('[DEBUG] 軌跡ポイント数: ${track.pointCount}');
      print('[DEBUG] 軌跡座標リスト長: ${track.toLatLngList().length}');

      // GPS軌跡レイヤー名を生成（通常の線レイヤーとして保存）
      const layerName = 'gps_tracks';

      // GeoPackageファイルを取得
      final gpkgFile = geoPackage.geoPackageFile;
      print('[DEBUG] GeoPackageファイル取得成功: ${gpkgFile.pathList}');

      // GPS軌跡レイヤーを作成（通常の線レイヤーとして）
      print('[DEBUG] GPS軌跡レイヤー作成開始: $layerName');
      await gpkgFile.addLayer(layerName, GeometryType.linestring);
      print('[DEBUG] GPS軌跡レイヤー作成完了: $layerName');

      // 軌跡の統計情報を取得
      final stats = track.getStatistics();
      print('[DEBUG] 軌跡統計: $stats');

      // 軌跡をLineStringとして保存（pen_toolと同じ方式）
      print('[DEBUG] LineString保存開始: $layerName');
      final coordinates = track.toLatLngList();
      if (coordinates.isEmpty) {
        throw Exception('軌跡座標が空です');
      }

      await gpkgFile.addLine(
        layerName,
        coordinates,
        name: track.trackName,
        description:
            '${stats['pointCount']}ポイント、${(stats['totalDistance'] / 1000).toStringAsFixed(2)}km',
      );
      print('[DEBUG] LineString保存完了');

      // UI更新
      print('[DEBUG] UI更新開始');
      await _updateFeatures();
      print('[DEBUG] UI更新完了');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'GPS軌跡「${track.trackName}」を${geoPackage.name}に保存しました',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      print('[DEBUG] GPS軌跡保存完了: ${track.trackName} -> ${geoPackage.name}');
    } catch (e, stackTrace) {
      print('[ERROR] GPS軌跡保存エラー: $e');
      print('[ERROR] スタックトレース: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS軌跡の保存に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // --- Utility to automatically close polygon rings ---
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

  // --- Line/polygon confirmation processing ---
  Future<void> _onConfirmDrawing() async {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return;
    final penTool = GlobalConfig.instance.currentTool as PenTool;
    if (selected is LineLayerNode && penTool.drawingLine.length >= 2) {
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
      penTool.confirm(
        selected: selected,
        name: name,
        description: '',
        setState: setState,
        closeRing: closeRing,
      );
    } else if (selected is PolygonLayerNode &&
        penTool.drawingPolygon.length >= 3) {
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
      penTool.confirm(
        selected: selected,
        name: name,
        description: '',
        setState: setState,
        closeRing: closeRing,
      );
    }
  }

  void _onBottomNavTapped(int index) async {
    setState(() {
      _selectedBottomIndex = index;
    });
    if (index == 0) {
      final selected = await showMenu<ToolType>(
        context: context,
        position: RelativeRect.fromLTRB(100, 600, 100, 0),
        items: [
          PopupMenuItem(
            value: ToolType.pen,
            child: Row(
              children: [
                Icon(Icons.brush, color: Colors.black),
                SizedBox(width: 8),
                Text('Pen'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ToolType.eraser,
            child: Row(
              children: [
                Icon(Icons.auto_fix_normal, color: Colors.black),
                SizedBox(width: 8),
                Text('Eraser'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ToolType.gps,
            child: Row(
              children: [
                Icon(Icons.gps_fixed, color: Colors.black),
                SizedBox(width: 8),
                Text('GPS Tool'),
              ],
            ),
          ),
        ],
      );
      if (selected != null) {
        setState(() {
          _selectedTool = selected;
          // 選択されたツールに基づいてGlobalConfigのcurrentToolを更新
          switch (selected) {
            case ToolType.pen:
              GlobalConfig.instance.currentTool = GlobalConfig.instance.penTool;
              break;
            case ToolType.eraser:
              // エラーザーは将来実装予定
              break;
            case ToolType.gps:
              GlobalConfig.instance.currentTool = GlobalConfig.instance.gpsTool;
              break;
          }
        });
      }
    } else if (index == 1) {
      // GPS icon: add something here if needed
    } else if (index == 2) {
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  // --- Screen coordinates to map coordinates conversion ---
  LatLng offsetToLatLng(Offset offset) {
    // Use FlutterMap's Pixel to LatLng conversion API
    // Reference: https://pub.dev/documentation/flutter_map/latest/flutter_map/MapController/pointToLatLng.html
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return _center;
    final local = renderBox.globalToLocal(offset);
    final point = CustomPoint(local.dx, local.dy);
    final latlng = _mapController.pointToLatLng(point);
    return latlng ?? _center;
  }

  // --- Map coordinates to screen pixel conversion ---
  Offset latLngToOffset(LatLng latlng) {
    // Use MapController's latLngToScreenPoint
    final point = _mapController.latLngToScreenPoint(latlng);
    return Offset(point.x.toDouble(), point.y.toDouble());
  }

  /// フィーチャデータを非同期で更新（キャッシュに保存）
  /// LayerNodeが管理するFeatureNodeを直接参照し、DBアクセスを最小限に抑制
  Future<void> _updateFeatures() async {
    print('[DEBUG] _updateFeatures: start');
    final folderTree = GlobalConfig.instance.folderTree;
    print('[DEBUG] _updateFeatures: folderTree=$folderTree');

    final visibleLayers =
        folderTree != null ? folderTree.getVisibleLayerNodes() : <LayerNode>[];
    print(
      '[DEBUG] _updateFeatures: found ${visibleLayers.length} visible layers',
    );

    final pointFeatures = <PointFeatureNode>[];
    final lineFeatures = <LineFeatureNode>[];
    final polygonFeatures = <PolygonFeatureNode>[];

    for (final layer in visibleLayers) {
      print(
        '[DEBUG] _updateFeatures: processing layer ${layer.name} (${layer.runtimeType})',
      );

      // LayerNodeのchildrenから直接FeatureNodeを取得（高速化）
      final layerFeatures = layer.children.whereType<FeatureNode>().toList();

      if (layer is PointLayerNode) {
        final layerPointFeatures =
            layerFeatures.whereType<PointFeatureNode>().toList();
        print(
          '[DEBUG] _updateFeatures: found ${layerPointFeatures.length} point features in ${layer.name} (from children)',
        );
        pointFeatures.addAll(layerPointFeatures);

        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          final dbFeatures = await layer.features;
          final dbPointFeatures =
              dbFeatures.whereType<PointFeatureNode>().toList();
          print(
            '[DEBUG] _updateFeatures: loaded ${dbPointFeatures.length} point features from DB for ${layer.name}',
          );
          pointFeatures.addAll(dbPointFeatures);
          // DBから読み込んだFeatureNodeをlayerのchildrenに追加
          for (final feature in dbPointFeatures) {
            layer.addChild(feature);
          }
        }
      } else if (layer is LineLayerNode) {
        final layerLineFeatures =
            layerFeatures.whereType<LineFeatureNode>().toList();
        print(
          '[DEBUG] _updateFeatures: found ${layerLineFeatures.length} line features in ${layer.name} (from children)',
        );
        lineFeatures.addAll(layerLineFeatures);

        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          final dbFeatures = await layer.features;
          final dbLineFeatures =
              dbFeatures.whereType<LineFeatureNode>().toList();
          print(
            '[DEBUG] _updateFeatures: loaded ${dbLineFeatures.length} line features from DB for ${layer.name}',
          );
          lineFeatures.addAll(dbLineFeatures);
          // DBから読み込んだFeatureNodeをlayerのchildrenに追加
          for (final feature in dbLineFeatures) {
            layer.addChild(feature);
          }
        }
      } else if (layer is PolygonLayerNode) {
        final layerPolygonFeatures =
            layerFeatures.whereType<PolygonFeatureNode>().toList();
        print(
          '[DEBUG] _updateFeatures: found ${layerPolygonFeatures.length} polygon features in ${layer.name} (from children)',
        );
        polygonFeatures.addAll(layerPolygonFeatures);

        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          final dbFeatures = await layer.features;
          final dbPolygonFeatures =
              dbFeatures.whereType<PolygonFeatureNode>().toList();
          print(
            '[DEBUG] _updateFeatures: loaded ${dbPolygonFeatures.length} polygon features from DB for ${layer.name}',
          );
          polygonFeatures.addAll(dbPolygonFeatures);
          // DBから読み込んだFeatureNodeをlayerのchildrenに追加
          for (final feature in dbPolygonFeatures) {
            layer.addChild(feature);
          }
        }
      }
    }

    print(
      '[DEBUG] _updateFeatures: total features - points:${pointFeatures.length}, lines:${lineFeatures.length}, polygons:${polygonFeatures.length}',
    );

    if (mounted) {
      setState(() {
        _pointFeatures = pointFeatures;
        _lineFeatures = lineFeatures;
        _polygonFeatures = polygonFeatures;
      });
      print('[DEBUG] _updateFeatures: state updated successfully');
    } else {
      print(
        '[DEBUG] _updateFeatures: widget not mounted, skipping state update',
      );
    }
  }

  /// フィーチャデータの公開更新メソッド（外部から呼び出し可能）
  void refreshFeatures() {
    _updateFeatures();
  }

  @override
  Widget build(BuildContext context) {
    final folderTree = GlobalConfig.instance.folderTree;
    // キャッシュされたフィーチャデータを使用（非同期処理は _updateFeatures で実行）
    final pointFeatures = _pointFeatures;
    final lineFeatures = _lineFeatures;
    final polygonFeatures = _polygonFeatures;

    final currentTool = GlobalConfig.instance.currentTool;
    final isPanTool = currentTool.name == 'Pan';
    final screenWidth = MediaQuery.of(context).size.width;
    final maxDrawerWidth = screenWidth * 2 / 3;
    return Scaffold(
      appBar: AppBar(
        title: const Text('K-MAPS GIS'),
        actions: [
          // Bluetooth GNSS接続ボタン
          IconButton(
            icon: const Icon(Icons.bluetooth),
            tooltip: 'Bluetooth GNSS',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BluetoothGnssScreen(),
                ),
              );
            },
          ),
          if (!drawerOpen)
            IconButton(
              icon: Icon(Icons.layers),
              tooltip: 'Open Layer Drawer',
              onPressed: () {
                setState(() {
                  drawerOpen = true;
                  drawerWidth = 320;
                });
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(36),
          child: _buildGpsInfoBar(),
        ),
      ),
      body: Stack(
        children: [
          // --- Toolbar (left vertical alignment) ---
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 44, // Narrow toolbar width
              color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Pan tool button with blue circle when selected
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          currentTool.name == 'Pan'
                              ? Colors.blue
                              : Colors.transparent,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.pan_tool_alt,
                        color:
                            currentTool.name == 'Pan'
                                ? Colors.white
                                : Colors.black,
                      ),
                      tooltip: 'Pan',
                      onPressed: () {
                        setState(() {
                          GlobalConfig.instance.currentTool =
                              GlobalConfig.instance.panTool;
                        });
                      },
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Pen tool button with blue circle when selected
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          currentTool.name == 'Pen'
                              ? Colors.blue
                              : Colors.transparent,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.edit,
                        color:
                            currentTool.name == 'Pen'
                                ? Colors.white
                                : Colors.black,
                      ),
                      tooltip: 'Pen',
                      onPressed: () {
                        setState(() {
                          GlobalConfig.instance.currentTool =
                              GlobalConfig.instance.penTool;
                        });
                      },
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Select tool button with blue circle when selected
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          currentTool.name == 'Select'
                              ? Colors.blue
                              : Colors.transparent,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.select_all,
                        color:
                            currentTool.name == 'Select'
                                ? Colors.white
                                : Colors.black,
                      ),
                      tooltip: 'Select',
                      onPressed: () {
                        setState(() {
                          GlobalConfig.instance.currentTool =
                              GlobalConfig.instance.selectTool;
                        });
                      },
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // GPS tool button with blue circle when selected
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color:
                          currentTool.name == 'GPS'
                              ? Colors.blue
                              : Colors.transparent,
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.gps_fixed,
                        color:
                            currentTool.name == 'GPS'
                                ? Colors.white
                                : Colors.black,
                      ),
                      tooltip: 'GPS Tool',
                      onPressed: () {
                        setState(() {
                          GlobalConfig.instance.currentTool =
                              GlobalConfig.instance.gpsTool;
                        });
                      },
                      iconSize: 24,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // --- Main map ---
          Positioned.fill(
            left: 44, // Move map to right of toolbar
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    center: _center,
                    zoom: 16.0,
                    interactiveFlags:
                        isPanTool
                            ? InteractiveFlag.all
                            : InteractiveFlag.pinchZoom,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.k_maps',
                    ),
                    MarkerLayer(
                      markers: [
                        // --- Current location marker ---
                        if (_currentLocation != null)
                          Marker(
                            point: _currentLocation!,
                            width: 44,
                            height: 44,
                            child: Icon(
                              Icons.my_location,
                              color: Colors.blue,
                              size: 36,
                            ),
                          ),

                        // --- Existing point feature markers ---
                        for (final f in pointFeatures)
                          ...((f.geometry as List<LatLng>).map(
                            (pt) => Marker(
                              point: pt,
                              width: 40,
                              height: 40,
                              child: Tooltip(
                                message: f.name,
                                child: Icon(
                                  Icons.location_on,
                                  color:
                                      GlobalConfig.instance.selectedFeatures
                                              .contains(f)
                                          ? Colors.yellow
                                          : Colors.red,
                                  size:
                                      GlobalConfig.instance.selectedFeatures
                                              .contains(f)
                                          ? 44
                                          : 36,
                                ),
                              ),
                            ),
                          )),
                      ],
                    ),
                    PolylineLayer(
                      polylines: [
                        for (final f in lineFeatures)
                          Polyline(
                            points: f.geometry as List<LatLng>,
                            color:
                                GlobalConfig.instance.selectedFeatures.contains(
                                      f,
                                    )
                                    ? Colors.yellow
                                    : Colors.blue,
                            strokeWidth:
                                GlobalConfig.instance.selectedFeatures.contains(
                                      f,
                                    )
                                    ? 5.0
                                    : 3.0,
                          ),
                        if (GlobalConfig.instance.currentTool is PenTool &&
                            (GlobalConfig.instance.currentTool as PenTool)
                                .drawingLine
                                .isNotEmpty)
                          Polyline(
                            points:
                                (GlobalConfig.instance.currentTool as PenTool)
                                    .drawingLine,
                            color: Colors.orange,
                            strokeWidth: 3.0,
                          ),
                      ],
                    ),
                    PolygonLayer(
                      polygons: [
                        for (final f in polygonFeatures)
                          Polygon(
                            points: (f.geometry as List<List<LatLng>>).first,
                            holePointsList:
                                (f.geometry as List<List<LatLng>>)
                                    .skip(1)
                                    .toList(),
                            color:
                                GlobalConfig.instance.selectedFeatures.contains(
                                      f,
                                    )
                                    ? Colors.yellow.withOpacity(0.5)
                                    : Colors.green.withOpacity(0.3),
                            borderStrokeWidth:
                                GlobalConfig.instance.selectedFeatures.contains(
                                      f,
                                    )
                                    ? 6.0
                                    : 3.0,
                            borderColor:
                                GlobalConfig.instance.selectedFeatures.contains(
                                      f,
                                    )
                                    ? Colors.yellow
                                    : Colors.green,
                            isFilled: true,
                          ),
                        if (GlobalConfig.instance.currentTool is PenTool &&
                            (GlobalConfig.instance.currentTool as PenTool)
                                    .drawingPolygon
                                    .length >=
                                2)
                          Polygon(
                            points: closeRing(
                              (GlobalConfig.instance.currentTool as PenTool)
                                  .drawingPolygon,
                            ),
                            color: Colors.orange.withOpacity(0.4),
                            borderStrokeWidth: 3.0,
                            borderColor: Colors.orange,
                            isFilled: true,
                          ),
                        // --- SelectTool lasso preview ---
                        if (GlobalConfig.instance.currentTool is SelectTool &&
                            (GlobalConfig.instance.currentTool as SelectTool)
                                    .lassoPoints
                                    .length >=
                                3)
                          Polygon(
                            points: closeRing(
                              (GlobalConfig.instance.currentTool as SelectTool)
                                  .lassoPoints
                                  .map((offset) => offsetToLatLng(offset))
                                  .toList(),
                            ),
                            color: Colors.white.withOpacity(0.2),
                            borderStrokeWidth: 2.0,
                            borderColor: Colors.black,
                            isFilled: true,
                          ),
                      ],
                    ),
                  ],
                ),
                Positioned.fill(
                  child: Listener(
                    onPointerMove: (event) {
                      GlobalConfig.instance.currentTool.addPointerToBuffer(
                        event.localPosition,
                      );
                    },
                    onPointerDown: (event) {
                      GlobalConfig.instance.currentTool.addPointerToBuffer(
                        event.localPosition,
                      );
                    },
                    onPointerUp: (event) {
                      GlobalConfig.instance.currentTool.clearPointerBuffer();
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) {
                        GlobalConfig.instance.currentTool.onTap(details, this);
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
                      final selected = GlobalConfig.instance.selectedLayerNode;
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
                          penTool.drawingLine.length >= 2) {
                        final len = GeometryCalc.calcLineLength(
                          penTool.drawingLine,
                        );
                        final centroid = GeometryCalc.calcLineCentroid(
                          penTool.drawingLine,
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
                          penTool.drawingPolygon.length >= 3) {
                        final closed = closeRing(penTool.drawingPolygon);
                        final areaDeg2 = GeometryCalc.calcPolygonArea([closed]);
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
                              'Area: ${(areaM2 / 10000).toStringAsFixed(1)} ha';
                        } else {
                          previewText = 'Area: ${areaM2.toStringAsFixed(2)} m?';
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
                              color: Colors.black.withOpacity(0.7),
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
                                      color: Colors.orange.withOpacity(0.3),
                                      width: 1,
                                    ),
                                  ),
                                ),
                              ),
                              // 回転する光点
                              Positioned(
                                left:
                                    40 +
                                    30 * cos(_trackingRotationAnimation.value) -
                                    4, // 中心から30px離れた位置
                                top:
                                    40 +
                                    30 * sin(_trackingRotationAnimation.value) -
                                    4,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.orange.withOpacity(0.8),
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
                                        color: Colors.amber.withOpacity(0.6),
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
          if (drawerOpen)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: drawerWidth.clamp(200, maxDrawerWidth),
              child: Material(
                elevation: 0,
                color: Colors.transparent,
                child: Row(
                  children: [
                    // Left drag handle (resizable)
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragUpdate: (details) {
                        setState(() {
                          drawerWidth -= details.delta.dx;
                          if (drawerWidth < minDrawerWidth) {
                            drawerOpen = false;
                          } else if (drawerWidth > maxDrawerWidth) {
                            drawerWidth = maxDrawerWidth;
                          }
                        });
                      },
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: Container(
                          width: 28,
                          color: Colors.black12, // Semi-transparent black
                          child: const Center(
                            child: VerticalDivider(width: 2, thickness: 2),
                          ),
                        ),
                      ),
                    ),
                    // Right side: LayerDrawer main body with white background
                    Expanded(
                      child: Container(
                        color: Colors.white,
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
                            _mapController.move(latLng, _mapController.zoom);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
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
                // GPS追跡ボタン（GPSツール選択時かつWindows以外の環境でのみ表示）
                if (GlobalConfig.instance.currentTool.name == 'GPS' &&
                    !Platform.isWindows)
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
                          _isGpsTrackingServiceRunning ? 'GPS追跡停止' : 'GPS追跡開始',
                      child: Icon(
                        _isGpsTrackingServiceRunning
                            ? Icons.stop
                            : Icons.pets, // 足跡アイコン（paw print）
                        // 他の選択肢: Icons.hiking, Icons.nordic_walking, Icons.accessibility_new
                        size: 28,
                      ),
                    ),
                  ),
                // 既存の左下フローティングボタン
                _LeftBottomFab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton:
          (() {
            final selected = GlobalConfig.instance.selectedLayerNode;
            final currentTool = GlobalConfig.instance.currentTool;
            final isLineDrawing =
                selected is LineLayerNode &&
                currentTool is PenTool &&
                (currentTool).drawingLine.isNotEmpty;
            final isPolygonDrawing =
                selected is PolygonLayerNode &&
                currentTool is PenTool &&
                (currentTool).drawingPolygon.isNotEmpty;

            // ペンツールでの描画中は従来のボタンを表示
            if (isLineDrawing || isPolygonDrawing) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Undo button
                  FloatingActionButton(
                    heroTag: 'undo',
                    onPressed: () {
                      setState(() {
                        if (isLineDrawing) {
                          (currentTool).drawingLine.removeLast();
                        } else if (isPolygonDrawing) {
                          (currentTool).drawingPolygon.removeLast();
                        }
                      });
                    },
                    tooltip: 'Undo',
                    child: const Icon(Icons.undo),
                  ),
                  const SizedBox(width: 12),
                  // Cancel button
                  FloatingActionButton(
                    heroTag: 'cancel',
                    onPressed: () {
                      setState(() {
                        if (isLineDrawing) {
                          (currentTool).drawingLine.clear();
                        } else if (isPolygonDrawing) {
                          (currentTool).drawingPolygon.clear();
                        }
                      });
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
    );
  }

  /// GPS information bar widget
  Widget _buildGpsInfoBar() {
    if (_gpsPosition == null) {
      return Container(
        height: 48,
        color: Colors.grey[200],
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text('GPS: Acquiring...'),
              SizedBox(width: 12),
              Text(
                '(${_gpsWaitSeconds}s elapsed)',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      height: 48,
      color: Colors.lightBlue[50],
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(Icons.gps_fixed, size: 18, color: Colors.blue),
            SizedBox(width: 8),
            Text(
              'Lat: ${_gpsPosition!.latitude.toStringAsFixed(6)} Lon: ${_gpsPosition!.longitude.toStringAsFixed(6)}',
              style: TextStyle(fontSize: 14),
            ),
            SizedBox(width: 16),
            Text('Satellites: ${_satelliteCount ?? "-"}'),
            SizedBox(width: 16),
            Text('HDOP: ${_hdop?.toStringAsFixed(2) ?? "-"}'),
          ],
        ),
      ),
    );
  }
}

/// Feature detail information panel
class FeatureDetailPanel extends StatelessWidget {
  final dynamic feature;
  const FeatureDetailPanel({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    if (feature == null) return const SizedBox.shrink();
    if (feature is FeatureNode) {
      final entries = feature.detailEntries;
      return _buildPanel(
        context,
        title: feature.runtimeType.toString(),
        children: [
          for (final e in entries)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.key}: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(child: Text(e.value)),
              ],
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildPanel(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

// --- Left bottom floating button widget ---
/// White circular floating button displayed at bottom left. Press state managed by GlobalConfig
class _LeftBottomFab extends StatefulWidget {
  @override
  State<_LeftBottomFab> createState() => _LeftBottomFabState();
}

class _LeftBottomFabState extends State<_LeftBottomFab> {
  @override
  Widget build(BuildContext context) {
    final isActive = GlobalConfig.instance.isFabActive;
    final currentTool = GlobalConfig.instance.currentTool;
    // Change center icon based on currentTool
    Widget centerIcon;
    switch (currentTool.runtimeType) {
      case PenTool:
        centerIcon = Icon(
          Icons.auto_fix_normal, // Back to eraser-style icon used initially
          color: isActive ? Colors.white : Colors.grey,
          size: 32,
        );
        break;
      // Add more cases when other tools are added
      default:
        centerIcon = Icon(
          Icons.circle,
          color: isActive ? Colors.white : Colors.grey,
          size: 32,
        );
        break;
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          GlobalConfig.instance.isFabActive = !isActive;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
          border: Border.all(
            color: isActive ? Colors.blueAccent : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: centerIcon,
      ),
    );
  }
}
