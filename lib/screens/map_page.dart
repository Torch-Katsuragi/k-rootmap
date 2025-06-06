// K-MAPS: Map and edit screen
// Main UI for map display and layer/feature editing
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/wkb_utils.dart';
import '../models/layer_tree_node.dart';
import '../widgets/inline_edit.dart';
import '../widgets/layer_drawer.dart';
import '../utils/global_config.dart';
// import 'package:sqlite3/sqlite3.dart' as sql; // sqflite移行により削除
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../utils/global_config.dart' show LayerTreeNodeUtils;
import '../utils/feature_calc_utils.dart';
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
enum ToolType { pen, eraser }

// --- Drawer use: Name edit state management ---
class _EditState {
  String? editingFolderPath;
  String? editingGpkgPath;
  int? editingLayerGpIndex;
  int? editingLayerIndex;
}

class _KMapsHomePageState extends State<KMapsHomePage> {
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

    // プロジェクトフォルダ内をスキャンして子ノード（サブフォルダ・.gpkgファイル）を更新
    _initializeProjectTree();

    // GPS権限チェックと初期化
    _initializeGps();

    // GPS追跡サービス状態の初期化
    _updateGpsTrackingServiceStatus();

    // 定期的にサービス状態を更新（1秒間隔）
    _serviceStatusUpdateTimer = Timer.periodic(Duration(seconds: 1), (timer) {
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
    super.dispose();
  }

  void _moveToCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
    }
  }

  /// GPS追跡サービス状態を更新
  void _updateGpsTrackingServiceStatus() {
    final wasRunning = _isGpsTrackingServiceRunning;
    final isRunning = _serviceManager.isServiceRunning;

    setState(() {
      _isGpsTrackingServiceRunning = isRunning;

      // サービスが動作中で現在位置がある場合、追跡位置を更新
      if (isRunning && _currentLocation != null) {
        _lastTrackedPosition = _currentLocation;
      }

      // サービスが停止した場合、追跡位置をクリア
      if (!isRunning && wasRunning) {
        _lastTrackedPosition = null;
      }
    });
  }

  /// GPS追跡フォアグラウンドサービス開始
  Future<void> _startGpsTrackingService() async {
    await _serviceManager.startService();
    _updateGpsTrackingServiceStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS追跡フォアグラウンドサービスを開始しました'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// GPS追跡フォアグラウンドサービス停止
  Future<void> _stopGpsTrackingService() async {
    await _serviceManager.stopService();
    _updateGpsTrackingServiceStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GPS追跡フォアグラウンドサービスを停止しました'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
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
        ],
      );
      if (selected != null) {
        setState(() {
          _selectedTool = selected;
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
      if (layer is PointLayerNode) {
        final features = await layer.features;
        print(
          '[DEBUG] _updateFeatures: found ${features.length} point features in ${layer.name}',
        );
        pointFeatures.addAll(features.whereType<PointFeatureNode>());
      } else if (layer is LineLayerNode) {
        final features = await layer.features;
        print(
          '[DEBUG] _updateFeatures: found ${features.length} line features in ${layer.name}',
        );
        lineFeatures.addAll(features.whereType<LineFeatureNode>());
      } else if (layer is PolygonLayerNode) {
        final features = await layer.features;
        print(
          '[DEBUG] _updateFeatures: found ${features.length} polygon features in ${layer.name}',
        );
        polygonFeatures.addAll(features.whereType<PolygonFeatureNode>());
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
                        // --- GPS追跡サービスの位置マーカー ---
                        if (_isGpsTrackingServiceRunning &&
                            _lastTrackedPosition != null)
                          Marker(
                            point: _lastTrackedPosition!,
                            width: 56,
                            height: 56,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red.withOpacity(0.3),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.track_changes,
                                color: Colors.white,
                                size: 28,
                              ),
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
          // --- Left bottom floating button (placed next to toolbar) ---
          Positioned(
            left: 56, // Toolbar width(44) + margin(12)
            bottom: 24,
            child: _LeftBottomFab(),
          ),
        ],
      ),
      floatingActionButton:
          (() {
            final selected = GlobalConfig.instance.selectedLayerNode;
            final isLineDrawing =
                selected is LineLayerNode &&
                GlobalConfig.instance.currentTool is PenTool &&
                (GlobalConfig.instance.currentTool as PenTool)
                    .drawingLine
                    .isNotEmpty;
            final isPolygonDrawing =
                selected is PolygonLayerNode &&
                GlobalConfig.instance.currentTool is PenTool &&
                (GlobalConfig.instance.currentTool as PenTool)
                    .drawingPolygon
                    .isNotEmpty;
            if (isLineDrawing || isPolygonDrawing) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Undo button
                  FloatingActionButton(
                    heroTag: 'undo',
                    onPressed: () {
                      setState(() {
                        if (isLineDrawing &&
                            GlobalConfig.instance.currentTool is PenTool) {
                          (GlobalConfig.instance.currentTool as PenTool)
                              .drawingLine
                              .removeLast();
                        } else if (isPolygonDrawing &&
                            GlobalConfig.instance.currentTool is PenTool) {
                          (GlobalConfig.instance.currentTool as PenTool)
                              .drawingPolygon
                              .removeLast();
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
                        if (isLineDrawing &&
                            GlobalConfig.instance.currentTool is PenTool) {
                          (GlobalConfig.instance.currentTool as PenTool)
                              .drawingLine
                              .clear();
                        } else if (isPolygonDrawing &&
                            GlobalConfig.instance.currentTool is PenTool) {
                          (GlobalConfig.instance.currentTool as PenTool)
                              .drawingPolygon
                              .clear();
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
              SizedBox(width: 16),
              _buildGpsTrackingButton(),
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
            SizedBox(width: 16),
            _buildGpsTrackingButton(),
          ],
        ),
      ),
    );
  }

  /// GPS追跡サービスのコントロールボタン
  Widget _buildGpsTrackingButton() {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton.icon(
        onPressed:
            _isGpsTrackingServiceRunning
                ? _stopGpsTrackingService
                : _startGpsTrackingService,
        icon: Icon(
          _isGpsTrackingServiceRunning ? Icons.stop : Icons.track_changes,
          size: 16,
        ),
        label: Text(
          _isGpsTrackingServiceRunning ? '追跡停止' : '追跡開始',
          style: TextStyle(fontSize: 12),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              _isGpsTrackingServiceRunning ? Colors.red : Colors.green,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size(80, 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
