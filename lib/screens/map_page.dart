// K-MAPS: 地図・編集画面
// 地図表示・レイヤ/フィーチャ編集UI本体
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/layer.dart';
import '../utils/wkb_utils.dart';
import '../models/layer_tree_node.dart';
import '../widgets/inline_edit.dart';
import '../widgets/layer_drawer.dart';
import '../utils/global_config.dart';
import '../models/folder_node.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

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
  final List<LatLng> _drawingLine = [];
  final List<LatLng> _drawingPolygon = [];
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

  IconData _layerTypeIcon(LayerType type) {
    switch (type) {
      case LayerType.point:
        return Icons.location_on;
      case LayerType.line:
        return Icons.show_chart;
      case LayerType.polygon:
        return Icons.pentagon;
    }
  }

  // --- 地図タップ・レイヤ/フィーチャ編集・Drawer・BottomNavigationBar・属性入力・インライン編集UIの全ロジックを完全移植 ---
  void _onMapTap(TapPosition tapPosition, LatLng latlng) async {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return;
    if (selected is PointLayerNode) {
      // 点レイヤ: その場で属性入力→保存
      String? attr = await showDialog<String>(
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
      if (attr == null) return;
      selected.geoPackageFile.addPoint(selected.layerName, latlng, attr);
      setState(() {});
    } else if (selected is LineLayerNode) {
      setState(() {
        _drawingLine.add(latlng);
      });
    } else if (selected is PolygonLayerNode) {
      setState(() {
        _drawingPolygon.add(latlng);
      });
    }
  }

  // --- 線・ポリゴン確定処理 ---
  Future<void> _onConfirmDrawing() async {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return;
    if (selected is LineLayerNode && _drawingLine.length >= 2) {
      String? attr = await showDialog<String>(
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
      if (attr == null) return;
      selected.geoPackageFile.addLine(selected.layerName, _drawingLine, attr);
      setState(() {
        _drawingLine.clear();
      });
    } else if (selected is PolygonLayerNode && _drawingPolygon.length >= 3) {
      String? attr = await showDialog<String>(
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
      if (attr == null) return;
      final closed = closeRing(_drawingPolygon);
      selected.geoPackageFile.addPolygon(selected.layerName, closed, attr);
      setState(() {
        _drawingPolygon.clear();
      });
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

  @override
  Widget build(BuildContext context) {
    final selected = GlobalConfig.instance.selectedLayerNode;
    return Scaffold(
      appBar: AppBar(title: const Text('K-MAPS 最小構成')),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(center: _center, zoom: 16.0, onTap: _onMapTap),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.k_maps',
          ),
          MarkerLayer(
            markers: [
              ...((selected is PointLayerNode)
                  ? selected.features.expand(
                    (f) => f.points.map(
                      (pt) => Marker(
                        point: pt,
                        width: 40,
                        height: 40,
                        child: Tooltip(
                          message: f.attr,
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                      ),
                    ),
                  )
                  : <Marker>[]), // 他レイヤは空
            ],
          ),
          PolylineLayer(
            polylines: [
              ...((selected is LineLayerNode)
                  ? selected.features.expand(
                    (f) => f.lines.map(
                      (line) => Polyline(
                        points: line,
                        color: Colors.blue,
                        strokeWidth: 4.0,
                      ),
                    ),
                  )
                  : <Polyline>[]),
              if (_drawingLine.isNotEmpty)
                Polyline(
                  points: _drawingLine,
                  color: Colors.orange,
                  strokeWidth: 4.0,
                ),
            ],
          ),
          PolygonLayer(
            polygons: [
              ...((selected is PolygonLayerNode)
                  ? selected.features.expand(
                    (f) => f.polygons.expand(
                      (poly) => [
                        Polygon(
                          points: poly.first,
                          color: Colors.green.withOpacity(0.3),
                          borderStrokeWidth: 3.0,
                          borderColor: Colors.green,
                        ),
                      ],
                    ),
                  )
                  : <Polygon>[]),
              if (_drawingPolygon.length >= 2)
                Polygon(
                  points: closeRing(_drawingPolygon),
                  color: Colors.orange.withOpacity(0.3),
                  borderStrokeWidth: 3.0,
                  borderColor: Colors.orange,
                ),
            ],
          ),
        ],
      ),
      endDrawer: Drawer(
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
      floatingActionButton: Builder(
        builder: (context) {
          final selected = GlobalConfig.instance.selectedLayerNode;
          if ((selected is LineLayerNode && _drawingLine.length >= 2) ||
              (selected is PolygonLayerNode && _drawingPolygon.length >= 3)) {
            return FloatingActionButton.extended(
              onPressed: _onConfirmDrawing,
              icon: const Icon(Icons.check),
              label: const Text('確定'),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
