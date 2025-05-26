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
import '../utils/feature_calc_utils.dart';
import '../tools/gps_utils.dart'; // GPSユーティリティを追加

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
  GpsPosition? _gpsPosition; // GPS情報格納用
  int? _satelliteCount; // 衛星数
  double? _hdop; // HDOP
  StreamSubscription? _gpsStreamSub;
  int _gpsWaitSeconds = 0; // GPS取得待ち秒数
  Timer? _gpsWaitTimer;

  // パブリックgetterを追加
  MapController get mapController => _mapController;

  @override
  void initState() {
    super.initState();
    print('[DEBUG] initState: KMapsHomePage start');
    GlobalConfig.instance.folderTree = FolderNode("rootNode", visible: true);
    _currentNode = GlobalConfig.instance.folderTree; // ルートノード参照
    print(
      '[DEBUG] initState: folderTree=[38;5;246m${GlobalConfig.instance.folderTree}[0m',
    );
    GlobalConfig.instance.mapState = this;
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
    // GPS取得待ちタイマー開始
    _gpsWaitSeconds = 0;
    _gpsWaitTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _gpsWaitSeconds++;
      });
    });
    // GPS情報ストリーム購読
    _gpsStreamSub = GpsUtils.instance.getPositionStream().listen((pos) {
      if (pos is GpsPosition) {
        setState(() {
          _gpsPosition = pos;
          _satelliteCount = pos.satellites;
          _hdop = pos.hdop;
          _gpsWaitTimer?.cancel(); // 取得できたらタイマー停止
        });
      }
    });
  }

  @override
  void dispose() {
    _gpsStreamSub?.cancel();
    _positionSubscription?.cancel();
    _gpsWaitTimer?.cancel();
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
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(36),
          child: _buildGpsInfoBar(),
        ),
      ),
      body: Stack(
        children: [
          // --- ツールバー（左端縦並び） ---
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 44, // ツールバー幅を細く
              color: Colors.transparent,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  IconButton(
                    icon: Icon(
                      Icons.pan_tool_alt,
                      color:
                          currentTool.name == 'てのひら'
                              ? Colors.blue
                              : Colors.black,
                    ),
                    tooltip: 'てのひら',
                    onPressed: () {
                      setState(() {
                        GlobalConfig.instance.currentTool =
                            GlobalConfig.instance.panTool;
                      });
                    },
                    iconSize: 32, // アイコンサイズは現状維持
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
                    iconSize: 32,
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
                    iconSize: 32,
                  ),
                ],
              ),
            ),
          ),
          // --- 地図本体 ---
          Positioned.fill(
            left: 44, // ツールバー分だけ地図を右にずらす
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
                        // --- 現在位置マーカーを追加 ---
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
                        // --- 既存のポイントフィーチャマーカー ---
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
                        // --- SelectToolの投げ縄プレビュー ---
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
                // --- ペンツール描画プレビュー情報 ---
                if (GlobalConfig.instance.currentTool is PenTool)
                  Builder(
                    builder: (context) {
                      final selected = GlobalConfig.instance.selectedLayerNode;
                      final penTool =
                          GlobalConfig.instance.currentTool as PenTool;
                      String? previewText;
                      Offset? previewOffset;
                      // 点レイヤ
                      if (selected is PointLayerNode &&
                          penTool.pointPreview != null) {
                        final pt = penTool.pointPreview!;
                        previewText =
                            '座標: (${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)})';
                        previewOffset = latLngToOffset(pt);
                      }
                      // 線レイヤ
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
                              '長さ: ${(len / 1000).toStringAsFixed(1)} km';
                        } else {
                          previewText = '長さ: ${len.toStringAsFixed(2)} m';
                        }
                        previewOffset = latLngToOffset(centroid);
                      }
                      // ポリゴンレイヤ
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
                              '面積: ${(areaM2 / 10000).toStringAsFixed(1)} ha';
                        } else {
                          previewText = '面積: ${areaM2.toStringAsFixed(2)} m²';
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
                          onJumpTo: (latLng) {
                            // 現在のズーム値を維持して中心移動
                            _mapController.move(latLng, _mapController.zoom);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // --- Feature詳細パネル ---
          if (GlobalConfig.instance.selectedFeatures.length == 1)
            Positioned(
              left: 60,
              top: 20,
              child: FeatureDetailPanel(
                feature: GlobalConfig.instance.selectedFeatures.first,
              ),
            ),
          // --- 左下フロートボタン（ツールバーの右隣に配置） ---
          Positioned(
            left: 56, // ツールバー幅(44)+余白(12)
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
            return null;
          })(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  /// GPS情報バーWidget
  Widget _buildGpsInfoBar() {
    if (_gpsPosition == null) {
      return Container(
        height: 36,
        color: Colors.grey[200],
        alignment: Alignment.centerLeft,
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Text('GPS: 取得中...'),
            SizedBox(width: 12),
            Text(
              '(${_gpsWaitSeconds}秒経過)',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    return Container(
      height: 36,
      color: Colors.lightBlue[50],
      alignment: Alignment.centerLeft,
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.gps_fixed, size: 18, color: Colors.blue),
          SizedBox(width: 8),
          Text(
            '緯度: ${_gpsPosition!.latitude.toStringAsFixed(6)} 経度: ${_gpsPosition!.longitude.toStringAsFixed(6)}',
            style: TextStyle(fontSize: 14),
          ),
          SizedBox(width: 16),
          Text('衛星: ${_satelliteCount ?? "-"}'),
          SizedBox(width: 16),
          Text('HDOP: ${_hdop?.toStringAsFixed(2) ?? "-"}'),
        ],
      ),
    );
  }
}

/// Feature詳細情報パネル
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

// --- 左下フロートボタン用Widget ---
/// 左下に表示される白い丸のフロートボタン。押下状態はGlobalConfigで管理。
class _LeftBottomFab extends StatefulWidget {
  @override
  State<_LeftBottomFab> createState() => _LeftBottomFabState();
}

class _LeftBottomFabState extends State<_LeftBottomFab> {
  @override
  Widget build(BuildContext context) {
    final isActive = GlobalConfig.instance.isFabActive;
    final currentTool = GlobalConfig.instance.currentTool;
    // currentToolに応じて中心アイコンを切り替え
    Widget centerIcon;
    switch (currentTool.runtimeType) {
      case PenTool:
        centerIcon = Icon(
          Icons.auto_fix_normal, // 最初に使っていた消しゴム風アイコンに戻す
          color: isActive ? Colors.white : Colors.grey,
          size: 32,
        );
        break;
      // 他ツール追加時はここにcaseを追加
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
