// K-MAPS: Map and edit screen
// Main UI for map display and layer/feature editing
// リファクタリング: Mixinとウィジェットに分割して疎結合化
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/gps_track.dart';
import '../../widgets/layer_drawer/layer_drawer.dart';
import '../../widgets/resizable_side_panel.dart';
import '../../widgets/dynamic_attribute_table_widget.dart';
import '../../widgets/cached_tile_layer.dart';
import '../../widgets/compass_fan_painter.dart';
import '../../widgets/feature_detail_panel.dart';
import '../../widgets/left_bottom_fab.dart';
import '../../widgets/map_toolbar.dart';
import '../../widgets/map_appbar_actions.dart';
import '../../utils/global_config.dart';
import '../../utils/global_drawing_state.dart';
import '../../utils/app_logger.dart';
import '../../utils/feature_calc_utils.dart';
import '../../utils/keyboard_handler.dart';
import '../../tools/pan_tool.dart';
import '../../tools/pen_tool.dart';
import '../../tools/select_tool.dart';
import '../../tools/gps_tool.dart';
import '../layer_style_settings_screen.dart';

// Mixins
import 'map_page_state_base.dart';
import 'mixins/index.dart';

// Widgets
import 'widgets/index.dart';

/// Map and edit screen (main structure)
class KMapsHomePage extends StatefulWidget {
  const KMapsHomePage({super.key});
  @override
  State<KMapsHomePage> createState() => _KMapsHomePageState();
}

/// Tool types
enum ToolType { pen, eraser, gps }

class _KMapsHomePageState extends State<KMapsHomePage>
    with 
      TickerProviderStateMixin,
      MapPageStateBase,
      MapInitializationMixin,
      MapGpsTrackingMixin,
      MapGpsSurveyMixin,
      MapFeatureCacheMixin,
      MapDrawingMixin {
  
  @override
  void initState() {
    super.initState();
    AppLogger.debug('[DEBUG] initState: KMapsHomePage start');
    initializeAllServices();
  }
  
  @override
  void dispose() {
    disposeAllServices();
    super.dispose();
  }
  
  // =============================================
  // 抽象メソッド実装（MapPageStateBaseより）
  // =============================================
  
  @override
  void onGpsManagerUpdate() {
    if (mounted) {
      updateCurrentGpsInfo();
    }
  }
  
  @override
  void onBaseMapServiceUpdate() {
    if (mounted) {
      triggerSetState(() {});
    }
  }
  
  @override
  void onLayerStyleChanged() {
    if (mounted) {
      triggerSetState(() {});
    }
  }
  
  @override
  void updateCurrentGpsInfo() {
    triggerSetState(() {
      currentGpsInfo = gpsManager.getCurrentGpsInfo();
      if (currentGpsInfo != null && currentGpsInfo!['isActive'] == true) {
        gpsWaitTimer?.cancel();
      }
    });
  }
  
  @override
  Future<void> updateFeatures() async {
    await updateFeaturesImpl();
  }
  
  // =============================================
  // 属性テーブル管理
  // =============================================
  
  /// 属性テーブルを開く
  Future<void> _openAttributeTable([LayerNode? targetLayer]) async {
    try {
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
      
      triggerSetState(() {
        attributeTableLayer = layer;
        showAttributeTable = true;
        drawerOpen = false;
      });
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
    triggerSetState(() {
      showAttributeTable = false;
      attributeTableLayer = null;
    });
    AppLogger.debug('[MAP] 属性テーブル表示終了');
  }
  
  /// 属性テーブルでフィーチャが選択されたときの処理
  void _onAttributeTableFeatureSelected(FeatureNode feature) {
    try {
      AppLogger.debug('[MAP] 属性テーブルでフィーチャ選択: ${feature.rowId}');
      GlobalConfig.instance.selectedFeatures = [feature];
      triggerSetState(() {});
      mapController.move(feature.centroid, mapController.camera.zoom);
    } catch (e) {
      AppLogger.debug('[MAP] フィーチャ選択処理エラー: $e');
    }
  }
  
  // =============================================
  // コンパス方向付きの現在位置マーカー
  // =============================================
  
  Widget _buildLocationMarkerWithCompass() {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (currentHeading != null)
          Transform.rotate(
            angle: (currentHeading! * pi / 180) - (pi / 2),
            child: SizedBox(
              width: 60,
              height: 60,
              child: CustomPaint(painter: CompassFanPainter()),
            ),
          ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: Colors.blue,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
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
  
  // =============================================
  // ビルドメソッド
  // =============================================
  
  @override
  Widget build(BuildContext context) {
    final currentTool = GlobalConfig.instance.currentTool;
    final isPanTool = currentTool.name == 'Pan';
    
    return KeyboardShortcutWrapper(
      mapState: this,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('K-MAPS GIS'),
          actions: buildMapAppBarActions(
            context: context,
            showAttributeTable: showAttributeTable,
            drawerOpen: drawerOpen,
            onAttributeTableToggle: () {
              if (showAttributeTable) {
                _closeAttributeTable();
              } else {
                _openAttributeTable();
              }
            },
            onDrawerToggle: () {
              triggerSetState(() {
                if (drawerOpen) {
                  drawerOpen = false;
                } else {
                  drawerOpen = true;
                  drawerWidth = 320;
                  showAttributeTable = false;
                  attributeTableLayer = null;
                }
              });
            },
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(36),
            child: GpsInfoBar(
              gpsInfo: currentGpsInfo,
              gpsWaitSeconds: gpsWaitSeconds,
              currentHeading: currentHeading,
            ),
          ),
        ),
        body: Stack(
          children: [
            // 左側ツールバー
            MapToolbar(
              onToolChanged: () => triggerSetState(() {}),
              currentFolder: currentNode is FolderNode
                  ? currentNode as FolderNode
                  : null,
            ),
            // 地図本体
            Positioned.fill(
              left: 44,
              child: Stack(
                children: [
                  _buildFlutterMap(isPanTool),
                  _buildGestureLayer(),
                  _buildDrawingPreviewInfo(),
                  // GPS追跡オーバーレイ
                  if (isGpsTrackingServiceRunning && currentLocation != null)
                    GpsTrackingOverlay(
                      rotationAnimation: trackingRotationAnimation,
                      screenPosition: latLngToOffset(currentLocation!),
                    ),
                ],
              ),
            ),
            // Layer Drawer Panel
            if (drawerOpen)
              _buildLayerDrawerPanel(),
            // Attribute Table Panel
            if (showAttributeTable && attributeTableLayer != null)
              _buildAttributeTablePanel(),
            // Feature detail panel
            if (GlobalConfig.instance.selectedFeatures.length == 1)
              Positioned(
                left: 60,
                top: 20,
                child: FeatureDetailPanel(
                  feature: GlobalConfig.instance.selectedFeatures.first,
                ),
              ),
            // Left bottom floating buttons
            Positioned(
              left: 56,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (GlobalConfig.instance.currentTool.name == 'GPS')
                    GpsSurveyButtons(
                      isLongPressing: isLongPressing,
                      longPressGpsCount: longPressGpsCount,
                      isGpsTrackingServiceRunning: isGpsTrackingServiceRunning,
                      onRecordGpsPosition: recordGpsPosition,
                      onStartLongPressGpsSurvey: startLongPressGpsSurvey,
                      onStopLongPressGpsSurvey: stopLongPressGpsSurvey,
                      onStartGpsTracking: startGpsTrackingService,
                      onStopGpsTracking: stopGpsTrackingService,
                    ),
                  const LeftBottomFab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFloatingActionButton(),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      ),
    );
  }
  
  /// FlutterMap構築
  Widget _buildFlutterMap(bool isPanTool) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCenter: defaultCenter,
        initialZoom: 16.0,
        maxZoom: PanTool.maxZoom,
        interactionOptions: InteractionOptions(
          flags: isPanTool
              ? InteractiveFlag.all
              : (InteractiveFlag.pinchZoom | InteractiveFlag.scrollWheelZoom),
        ),
        keepAlive: true,
      ),
      children: [
        CachedTileLayer(
          provider: GlobalConfig.instance.baseMapService.currentProvider,
          baseMapService: GlobalConfig.instance.baseMapService,
        ),
        _buildPolylineLayer(),
        _buildPolygonLayer(),
        _buildMarkerLayer(),
      ],
    );
  }
  
  /// ポリラインレイヤー構築
  PolylineLayer _buildPolylineLayer() {
    final styleConfig = LayerStyleConfig();
    final drawingState = GlobalDrawingState.instance;
    
    return PolylineLayer(
      polylines: [
        // 既存のラインフィーチャ
        for (final f in lineFeatures)
          if (f.geometry != null)
            (() {
              final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
              final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
              final lineColor = styleConfig.getLineColor(kmetaStyle);
              final lineWidth = styleConfig.getLineWidth(kmetaStyle);
              return Polyline(
                points: f.geometry as List<LatLng>,
                color: isSelected ? styleConfig.selectedColor : lineColor,
                strokeWidth: isSelected
                    ? lineWidth * styleConfig.selectedMultiplier
                    : lineWidth,
              );
            })(),
        // GPS測量ラインプレビュー
        if (GlobalConfig.instance.currentTool is GpsTool &&
            drawingState.drawingLine.isNotEmpty)
          Polyline(
            points: drawingState.drawingLine,
            color: Colors.purple,
            strokeWidth: 2.0,
          ),
        // ペンツールラインプレビュー
        if (GlobalConfig.instance.currentTool is PenTool &&
            drawingState.drawingLine.isNotEmpty)
          Polyline(
            points: drawingState.drawingLine,
            color: Colors.orange,
            strokeWidth: 1.5,
          ),
        // GPS測量ポリゴン2点プレビュー
        if (GlobalConfig.instance.currentTool is GpsTool &&
            drawingState.drawingPolygon.length == 2)
          Polyline(
            points: drawingState.drawingPolygon,
            color: Colors.purple,
            strokeWidth: 2.0,
          ),
        // ペンツールポリゴン2点プレビュー
        if (GlobalConfig.instance.currentTool is PenTool &&
            drawingState.drawingPolygon.length == 2)
          Polyline(
            points: drawingState.drawingPolygon,
            color: Colors.orange,
            strokeWidth: 1.5,
          ),
        // GPS追跡軌跡プレビュー
        if (isGpsTrackingServiceRunning &&
            GpsTrackManager().currentTrack != null &&
            GpsTrackManager().currentTrack!.points.length >= 2)
          Polyline(
            points: GpsTrackManager().currentTrack!.toLatLngList(),
            color: Colors.cyan,
            strokeWidth: 2.0,
          ),
      ],
    );
  }
  
  /// ポリゴンレイヤー構築
  PolygonLayer _buildPolygonLayer() {
    final styleConfig = LayerStyleConfig();
    final drawingState = GlobalDrawingState.instance;
    
    return PolygonLayer(
      polygons: [
        // 既存のポリゴンフィーチャ
        for (final f in polygonFeatures)
          if (f.geometry != null)
            (() {
              final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
              final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
              final fillColor = styleConfig.getPolygonFillColor(kmetaStyle);
              final fillOpacity = styleConfig.getPolygonFillOpacity(kmetaStyle);
              final borderColor = styleConfig.getPolygonBorderColor(kmetaStyle);
              final borderOpacity = styleConfig.getPolygonBorderOpacity(kmetaStyle);
              final borderWidth = styleConfig.getPolygonBorderWidth(kmetaStyle);
              return Polygon(
                points: (f.geometry as List<List<LatLng>>).first,
                holePointsList: (f.geometry as List<List<LatLng>>).skip(1).toList(),
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
        // GPS測量ポリゴンプレビュー
        if (GlobalConfig.instance.currentTool is GpsTool &&
            drawingState.drawingPolygon.length >= 3)
          Polygon(
            points: closeRing(drawingState.drawingPolygon),
            color: Colors.purple.withValues(alpha: 0.4),
            borderStrokeWidth: 2.0,
            borderColor: Colors.purple,
          ),
        // ペンツールポリゴンプレビュー
        if (GlobalConfig.instance.currentTool is PenTool &&
            drawingState.drawingPolygon.length >= 3)
          Polygon(
            points: closeRing(drawingState.drawingPolygon),
            color: Colors.orange.withValues(alpha: 0.4),
            borderStrokeWidth: 1.5,
            borderColor: Colors.orange,
          ),
        // SelectTool lassoプレビュー
        if (GlobalConfig.instance.currentTool is SelectTool &&
            (GlobalConfig.instance.currentTool as SelectTool).lassoPoints.length >= 3)
          Polygon(
            points: closeRing(
              (GlobalConfig.instance.currentTool as SelectTool)
                  .lassoPoints
                  .map((offset) => offsetToLatLng(offset))
                  .toList(),
            ),
            color: Colors.white.withValues(alpha: 0.2),
            borderStrokeWidth: 1.0,
            borderColor: Colors.black,
          ),
      ],
    );
  }
  
  /// マーカーレイヤー構築
  MarkerLayer _buildMarkerLayer() {
    final styleConfig = LayerStyleConfig();
    final drawingState = GlobalDrawingState.instance;
    
    return MarkerLayer(
      markers: [
        // 現在位置マーカー
        if (currentLocation != null)
          Marker(
            point: currentLocation!,
            width: 64,
            height: 64,
            child: _buildLocationMarkerWithCompass(),
          ),
        // GPS測量ポイントマーカー
        if (GlobalConfig.instance.currentTool is GpsTool) ...[
          for (int i = 0; i < drawingState.drawingLine.length; i++)
            _buildSurveyPointMarker(drawingState.drawingLine[i], i, true),
          for (int i = 0; i < drawingState.drawingPolygon.length; i++)
            _buildSurveyPointMarker(drawingState.drawingPolygon[i], i, false),
        ],
        // 頂点マーカー（ライン/ポリゴン）
        ..._buildVertexMarkers(styleConfig),
        // ポイントフィーチャマーカー
        for (final f in pointFeatures)
          if (f.geometry != null)
            ...((f.geometry as List<LatLng>).map((pt) {
              final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
              final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
              final pointSize = styleConfig.getPointSize(kmetaStyle);
              final pointColor = styleConfig.getPointColor(kmetaStyle);
              final size = isSelected
                  ? pointSize * styleConfig.selectedMultiplier
                  : pointSize;
              return Marker(
                point: pt,
                width: size + 4,
                height: size + 4,
                child: Tooltip(
                  message: f.name,
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color: isSelected ? styleConfig.selectedColor : pointColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: size > 8 ? 1.5 : 0.5,
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
            })),
        // ImageNodeマーカー
        for (final photo in photoNodes)
          Marker(
            point: photo.location,
            width: 20,
            height: 20,
            child: GestureDetector(
              onTap: () {
                triggerSetState(() {
                  GlobalConfig.instance.selectedFeatures.clear();
                  GlobalConfig.instance.selectedFeatures.add(photo);
                });
              },
              child: Tooltip(
                message: '📸 ${photo.name}\n撮影位置: ${photo.location.latitude.toStringAsFixed(6)}, ${photo.location.longitude.toStringAsFixed(6)}',
                child: Container(
                  decoration: BoxDecoration(
                    color: GlobalConfig.instance.selectedFeatures.contains(photo)
                        ? Colors.yellow[100]
                        : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: GlobalConfig.instance.selectedFeatures.contains(photo)
                          ? Colors.orange
                          : Colors.purple,
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.photo_camera,
                    color: GlobalConfig.instance.selectedFeatures.contains(photo)
                        ? Colors.orange
                        : Colors.purple,
                    size: GlobalConfig.instance.selectedFeatures.contains(photo)
                        ? 14
                        : 12,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
  
  /// GPS測量ポイントマーカー構築
  Marker _buildSurveyPointMarker(LatLng point, int index, bool isLine) {
    final drawingState = GlobalConfig.instance.drawingState;
    final metadataList = isLine
        ? drawingState.lineMetadata
        : drawingState.polygonMetadata;
    
    int pointCount = 1;
    try {
      if (index < metadataList.length) {
        final metadata = metadataList[index];
        if (metadata != null) {
          if (metadata.containsKey('point_count')) {
            pointCount = metadata['point_count'] as int? ?? 1;
          } else if (metadata.containsKey('collected_points') &&
              metadata['collected_points'] is List) {
            pointCount = (metadata['collected_points'] as List).length;
          }
        }
      }
    } catch (e) {
      pointCount = index + 1;
    }
    
    return Marker(
      point: point,
      width: 32,
      height: 32,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.purple,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Center(
          child: Text(
            '$pointCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
  
  /// 頂点マーカー構築
  List<Marker> _buildVertexMarkers(LayerStyleConfig style) {
    final markers = <Marker>[];
    
    if (style.lineVertexPointsEnabled) {
      for (final f in lineFeatures) {
        if (f.geometry == null) continue;
        final pts = f.geometry as List<LatLng>;
        if (pts.isEmpty) continue;
        
        final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
        final color = isSelected ? style.selectedColor : style.lineColor;
        final strokeWidth = isSelected
            ? style.lineWidth * style.selectedMultiplier
            : style.lineWidth;
        final size = (strokeWidth * style.lineVertexPointSizeFactor).clamp(4.0, 48.0);
        
        for (final pt in pts) {
          markers.add(_buildVertexMarker(pt, size, color));
        }
      }
    }
    
    if (style.polygonVertexPointsEnabled) {
      for (final f in polygonFeatures) {
        if (f.geometry == null) continue;
        final rings = f.geometry as List<List<LatLng>>;
        if (rings.isEmpty) continue;
        
        final isSelected = GlobalConfig.instance.selectedFeatures.contains(f);
        final color = isSelected
            ? style.selectedColor
            : style.polygonBorderColor.withValues(alpha: style.polygonBorderOpacity);
        final strokeWidth = isSelected
            ? style.polygonBorderWidth * style.selectedMultiplier
            : style.polygonBorderWidth;
        final size = (strokeWidth * style.polygonVertexPointSizeFactor).clamp(4.0, 48.0);
        
        for (final ring in rings) {
          if (ring.isEmpty) continue;
          final pts = List<LatLng>.from(ring);
          if (pts.length >= 2 && pts.first == pts.last) {
            pts.removeLast();
          }
          for (final pt in pts) {
            markers.add(_buildVertexMarker(pt, size, color));
          }
        }
      }
    }
    
    return markers;
  }
  
  /// 単一頂点マーカー構築
  Marker _buildVertexMarker(LatLng point, double size, Color color) {
    return Marker(
      point: point,
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
    );
  }
  
  /// ジェスチャーレイヤー構築
  Widget _buildGestureLayer() {
    return Positioned.fill(
      child: Listener(
        onPointerMove: (event) {
          if (event.buttons == kMiddleMouseButton) {
            GlobalConfig.instance.currentTool.onMiddleButtonMove(event, this);
          } else {
            GlobalConfig.instance.currentTool.addPointerToBuffer(event.localPosition);
          }
        },
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) {
            GlobalConfig.instance.currentTool.onMiddleButtonDown(event, this);
          } else {
            GlobalConfig.instance.currentTool.addPointerToBuffer(event.localPosition);
          }
        },
        onPointerUp: (event) {
          if (event.buttons == 0) {
            GlobalConfig.instance.currentTool.onMiddleButtonUp(event, this);
          }
          GlobalConfig.instance.currentTool.clearPointerBuffer();
        },
        onPointerSignal: (event) {
          GlobalConfig.instance.currentTool.onPointerSignal(event, this);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) {
            GlobalConfig.instance.currentTool.onTap(details, this);
          },
          onScaleStart: (details) {
            GlobalConfig.instance.currentTool.onScaleStart(details, this);
          },
          onScaleUpdate: (details) {
            GlobalConfig.instance.currentTool.onScaleUpdate(details, this);
          },
          onScaleEnd: (details) {
            GlobalConfig.instance.currentTool.onScaleEnd(details, this);
          },
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }
  
  /// 描画プレビュー情報構築
  Widget _buildDrawingPreviewInfo() {
    if (GlobalConfig.instance.currentTool is! PenTool) {
      return const SizedBox.shrink();
    }
    
    final selected = GlobalConfig.instance.selectedLayerNode;
    final penTool = GlobalConfig.instance.currentTool as PenTool;
    final drawingState = GlobalDrawingState.instance;
    String? previewText;
    Offset? previewOffset;
    
    if (selected is PointLayerNode && penTool.pointPreview != null) {
      final pt = penTool.pointPreview!;
      previewText = 'Coordinates: (${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)})';
      previewOffset = latLngToOffset(pt);
    } else if (selected is LineLayerNode && drawingState.drawingLine.length >= 2) {
      final len = GeometryCalc.calcLineLength(drawingState.drawingLine);
      final centroid = GeometryCalc.calcLineCentroid(drawingState.drawingLine);
      previewText = len >= 10000
          ? 'Length: ${(len / 1000).toStringAsFixed(1)} km'
          : 'Length: ${len.toStringAsFixed(2)} m';
      previewOffset = latLngToOffset(centroid);
    } else if (selected is PolygonLayerNode && drawingState.drawingPolygon.length >= 3) {
      final closed = closeRing(drawingState.drawingPolygon);
      final areaDeg2 = GeometryCalc.calcPolygonArea([closed]);
      final centroid = GeometryCalc.calcPolygonCentroid([closed]);
      final areaM2 = DegreeMeterConverter.convertAreaToMeters2(areaDeg2, centroid.latitude);
      previewText = areaM2 >= 10000
          ? 'Area: ${(areaM2 / 10000).toStringAsFixed(3)} ha'
          : 'Area: ${areaM2.toStringAsFixed(3)} m²';
      previewOffset = latLngToOffset(centroid);
    }
    
    if (previewText != null && previewOffset != null) {
      return Positioned(
        left: previewOffset.dx + 10,
        top: previewOffset.dy - 30,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            previewText,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
  
  /// レイヤードロワーパネル構築
  Widget _buildLayerDrawerPanel() {
    return ResizableSidePanel(
      initialWidth: drawerWidth,
      minWidth: minDrawerWidth,
      maxWidthRatio: 0.67,
      initiallyOpen: drawerOpen,
      onOpenChanged: (isOpen) {
        triggerSetState(() {
          drawerOpen = isOpen;
        });
      },
      onWidthChanged: (width) {
        triggerSetState(() {
          drawerWidth = width;
        });
      },
      child: LayerDrawer(
        currentNode: currentNode,
        onDirChanged: (node) {
          triggerSetState(() {
            currentNode = node;
          });
        },
        setStateCallback: (fn) => triggerSetState(fn),
        onJumpTo: (latLng) {
          mapController.move(latLng, mapController.camera.zoom);
        },
        onStartAppendMode: (feature) {
          startAppendMode(feature);
        },
      ),
    );
  }
  
  /// 属性テーブルパネル構築
  Widget _buildAttributeTablePanel() {
    return ResizableSidePanel(
      initialWidth: attributeTableWidth,
      minWidth: 300,
      maxWidthRatio: 0.8,
      initiallyOpen: showAttributeTable,
      onOpenChanged: (isOpen) {
        if (!isOpen) {
          _closeAttributeTable();
        }
      },
      onWidthChanged: (width) {
        triggerSetState(() {
          attributeTableWidth = width;
        });
      },
      child: DynamicAttributeTableWidget(
        layer: attributeTableLayer!,
        onFeatureSelected: _onAttributeTableFeatureSelected,
        onFeatureDeleted: (feature) async {
          try {
            await feature.dispose();
            attributeTableLayer!.children.remove(feature);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('フィーチャが削除されました: ID ${feature.rowId}'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            refreshMapUI();
          } catch (e) {
            AppLogger.debug('[MAP] フィーチャ削除エラー: $e');
          }
        },
        onAddFeature: () {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('新規フィーチャ追加機能は開発中です')),
            );
          }
        },
      ),
    );
  }
  
  /// FloatingActionButton構築
  Widget? _buildFloatingActionButton() {
    final selected = GlobalConfig.instance.selectedLayerNode;
    final currentTool = GlobalConfig.instance.currentTool;
    final gpsTool = currentTool is GpsTool ? currentTool : null;
    final drawingState = GlobalDrawingState.instance;
    
    // GPS測量中
    final isGpsSurveyLine = selected is LineLayerNode &&
        gpsTool != null &&
        gpsTool.surveyLine.isNotEmpty;
    final isGpsSurveyPolygon = selected is PolygonLayerNode &&
        gpsTool != null &&
        gpsTool.surveyPolygon.isNotEmpty;
    
    // ペンツール描画中
    final isLineDrawing = selected is LineLayerNode &&
        currentTool is PenTool &&
        drawingState.drawingLine.isNotEmpty;
    final isPolygonDrawing = selected is PolygonLayerNode &&
        currentTool is PenTool &&
        drawingState.drawingPolygon.isNotEmpty;
    
    if (isGpsSurveyLine || isGpsSurveyPolygon) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'gps_undo',
            onPressed: () {
              drawingState.undo(isLine: gpsTool.surveyLine.isNotEmpty);
              triggerSetState(() {});
            },
            tooltip: 'GPS測量の最後のポイントを取り消し',
            child: const Icon(Icons.undo),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'gps_cancel',
            onPressed: () async {
              try {
                await gpsTool.cancelSurveyWithGpsStop();
                triggerSetState(() {});
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
          FloatingActionButton.extended(
            heroTag: 'gps_confirm',
            onPressed: onConfirmGpsSurvey,
            icon: const Icon(Icons.check),
            label: const Text('GPS測量確定'),
          ),
        ],
      );
    } else if (isLineDrawing || isPolygonDrawing) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'undo',
            onPressed: () {
              if (isLineDrawing) {
                drawingState.undo(isLine: true);
              } else {
                drawingState.undo(isLine: false);
              }
              triggerSetState(() {});
            },
            tooltip: 'Undo',
            child: const Icon(Icons.undo),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'cancel',
            onPressed: () {
              if (isLineDrawing) {
                drawingState.cancel(isLine: true);
              } else {
                drawingState.cancel(isLine: false);
              }
              triggerSetState(() {});
            },
            tooltip: 'Cancel',
            child: const Icon(Icons.clear),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'confirm',
            onPressed: onConfirmDrawing,
            icon: const Icon(Icons.check),
            label: const Text('Confirm'),
          ),
        ],
      );
    }
    return null;
  }
}

