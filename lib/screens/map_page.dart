// K-MAPS: 地図・編集画面
// 地図表示・レイヤ/フィーチャ編集UI本体
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
import 'package:sqlite3/sqlite3.dart' as sql;
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../utils/global_config.dart' show LayerTreeNodeUtils;

/// 地図・編集画面（最小構成）
class KMapsHomePage extends StatefulWidget {
  const KMapsHomePage({super.key});
  @override
  State<KMapsHomePage> createState() => _KMapsHomePageState();
}

/// ツール種別
enum ToolType { pen, eraser }

// --- Drawer用: 名前編集状態管理 ---
class _EditState {
  String? editingFolderPath;
  String? editingGpkgPath;
  int? editingLayerGpIndex;
  int? editingLayerIndex;
}

class _KMapsHomePageState extends State<KMapsHomePage> {
  final LatLng _center = const LatLng(35.681236, 139.767125); // 東京駅
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

  // パブリックgetterを追加
  MapController get mapController => _mapController;

  @override
  void initState() {
    super.initState();
    print('[DEBUG] initState: KMapsHomePage start');
    GlobalConfig.instance.folderTree = FolderNode("rootNode", visible: true);
    _currentNode = GlobalConfig.instance.folderTree; // ルートノード参照
    print('[DEBUG] initState: folderTree=${GlobalConfig.instance.folderTree}');
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    _positionSubscription = _positionStream!.listen((pos) {
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        if (!_movedToCurrentLocationOnce && _currentLocation != null) {
          _mapController.move(_currentLocation!, 16.0);
          _movedToCurrentLocationOnce = true;
        }
      });
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  void _moveToCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16.0);
    }
  }

  // --- ポリゴン点列を自動で閉じるユーティリティ ---
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

  // --- 線・ポリゴン確定処理 ---
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
            title: const Text('属性入力'),
            content: TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: '属性（テキスト）'),
              onChanged: (v) => text = v,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
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
            title: const Text('属性入力'),
            content: TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: '属性（テキスト）'),
              onChanged: (v) => text = v,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
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
                Text('ペン'),
              ],
            ),
          ),
          PopupMenuItem(
            value: ToolType.eraser,
            child: Row(
              children: [
                Icon(Icons.auto_fix_normal, color: Colors.black),
                SizedBox(width: 8),
                Text('消しゴム'),
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
      // GPSアイコン: 何か追加したい場合ここに
    } else if (index == 2) {
      _scaffoldKey.currentState?.openEndDrawer();
    }
  }

  // --- 画面座標→地図座標変換 ---
  LatLng offsetToLatLng(Offset offset) {
    // FlutterMapのPixel→LatLng変換APIを利用
    // 参考: https://pub.dev/documentation/flutter_map/latest/flutter_map/MapController/pointToLatLng.html
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return _center;
    final local = renderBox.globalToLocal(offset);
    final point = CustomPoint(local.dx, local.dy);
    final latlng = _mapController.pointToLatLng(point);
    return latlng ?? _center;
  }

  // --- 地図座標→画面ピクセル変換 ---
  Offset latLngToOffset(LatLng latlng) {
    // MapControllerのlatLngToScreenPointを利用
    final point = _mapController.latLngToScreenPoint(latlng);
    return Offset(point.x.toDouble(), point.y.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final folderTree = GlobalConfig.instance.folderTree;
    final visibleLayers =
        folderTree != null ? folderTree.getVisibleLayerNodes() : <LayerNode>[];
    // Point/Line/Polygonごとに分けてfeaturesを集約
    final pointFeatures = <PointFeatureNode>[];
    final lineFeatures = <LineFeatureNode>[];
    final polygonFeatures = <PolygonFeatureNode>[];
    for (final layer in visibleLayers) {
      if (layer is PointLayerNode) {
        pointFeatures.addAll(layer.features.whereType<PointFeatureNode>());
      } else if (layer is LineLayerNode) {
        lineFeatures.addAll(layer.features.whereType<LineFeatureNode>());
      } else if (layer is PolygonLayerNode) {
        polygonFeatures.addAll(layer.features.whereType<PolygonFeatureNode>());
      }
    }
    final currentTool = GlobalConfig.instance.currentTool;
    final isPanTool = currentTool.name == 'てのひら';
    final screenWidth = MediaQuery.of(context).size.width;
    final maxDrawerWidth = screenWidth * 2 / 3;
    return Scaffold(
      appBar: AppBar(
        title: const Text('K-MAPS 最小構成'),
        actions: [
          if (!drawerOpen)
            IconButton(
              icon: Icon(Icons.layers),
              tooltip: 'レイヤDrawerを開く',
              onPressed: () {
                setState(() {
                  drawerOpen = true;
                  drawerWidth = 320;
                });
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // --- ツールバー（左端縦並び） ---
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                IconButton(
                  icon: Icon(
                    Icons.pan_tool_alt,
                    color:
                        currentTool.name == 'てのひら' ? Colors.blue : Colors.black,
                  ),
                  tooltip: 'てのひら',
                  onPressed: () {
                    setState(() {
                      GlobalConfig.instance.currentTool =
                          GlobalConfig.instance.panTool;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    color:
                        currentTool.name == 'ペン' ? Colors.blue : Colors.black,
                  ),
                  tooltip: 'ペン',
                  onPressed: () {
                    setState(() {
                      GlobalConfig.instance.currentTool =
                          GlobalConfig.instance.penTool;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.select_all,
                    color:
                        currentTool.name == '選択' ? Colors.blue : Colors.black,
                  ),
                  tooltip: '選択',
                  onPressed: () {
                    setState(() {
                      GlobalConfig.instance.currentTool =
                          GlobalConfig.instance.selectTool;
                    });
                  },
                ),
              ],
            ),
          ),
          // --- 地図本体 ---
          Positioned.fill(
            left: 56, // ツールバー分だけ地図を右にずらす
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
                        for (final f in pointFeatures)
                          ...((f.geometry as List<LatLng>).map(
                            (pt) => Marker(
                              point: pt,
                              width: 40,
                              height: 40,
                              child: Tooltip(
                                message: f.name,
                                child: const Icon(
                                  Icons.location_on,
                                  color: Colors.red,
                                  size: 36,
                                ),
                              ),
                            ),
                          )),
                      ],
                    ),
                    PolylineLayer(
                      polylines: [
                        for (final f in lineFeatures)
                          ...((f.geometry as List<List<LatLng>>).map(
                            (line) => Polyline(
                              points: line,
                              color: Colors.blue,
                              strokeWidth: 4.0,
                            ),
                          )),
                        if (GlobalConfig.instance.currentTool is PenTool &&
                            (GlobalConfig.instance.currentTool as PenTool)
                                .drawingLine
                                .isNotEmpty)
                          Polyline(
                            points:
                                (GlobalConfig.instance.currentTool as PenTool)
                                    .drawingLine,
                            color: Colors.orange,
                            strokeWidth: 4.0,
                          ),
                      ],
                    ),
                    PolygonLayer(
                      polygons: [
                        for (final f in polygonFeatures)
                          ...((f.geometry as List<List<List<LatLng>>>).expand(
                            (poly) => [
                              Polygon(
                                points: poly.first,
                                color: Colors.green.withOpacity(0.3),
                                borderStrokeWidth: 3.0,
                                borderColor: Colors.green,
                                isFilled: true,
                              ),
                            ],
                          )),
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
              ],
            ),
          ),
          // --- カスタムDrawer ---
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
                    // 左端ドラッグハンドル（透明）
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
                          color: Colors.black12, // 高透明度の黒
                          child: const Center(
                            child: VerticalDivider(width: 2, thickness: 2),
                          ),
                        ),
                      ),
                    ),
                    // 右側（LayerDrawer本体）は白背景
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
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Builder(
        builder: (context) {
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
                // 1つ取り消しボタン
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
                  tooltip: '1つ取り消し',
                  child: const Icon(Icons.undo),
                ),
                const SizedBox(width: 12),
                // キャンセルボタン
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
                  tooltip: 'キャンセル',
                  child: const Icon(Icons.clear),
                ),
                const SizedBox(width: 12),
                // 確定ボタン
                FloatingActionButton.extended(
                  heroTag: 'confirm',
                  onPressed: _onConfirmDrawing,
                  icon: const Icon(Icons.check),
                  label: const Text('確定'),
                ),
              ],
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
