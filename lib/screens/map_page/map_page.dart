// K-MAPS: Map and edit screen
// Main UI for map display and layer/feature editing
// リファクタリング: Mixinとウィジェットに分割して疎結合化
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
// gps_track.dart は不要に（GpsHistoryRecorder に統合）
import '../../widgets/layer_drawer/layer_drawer.dart';
import '../../widgets/resizable_side_panel.dart';
import '../../widgets/dynamic_attribute_table_widget.dart';
import '../../widgets/cached_tile_layer.dart';
import '../../widgets/compass_fan_painter.dart';
import '../../widgets/feature_detail_panel.dart';
import '../../widgets/left_bottom_fab.dart';
import '../../widgets/map_toolbar.dart';
import '../../widgets/map_appbar_actions.dart';
import '../../core/constants.dart';
import '../../utils/app_logger.dart';
import '../../utils/feature_calc_utils.dart';
import '../../utils/keyboard_handler.dart';
import '../../tools/pan_tool.dart';
import '../../tools/pen_tool.dart';
import '../../tools/select_tool.dart';
import '../../tools/gps_tool.dart';
import '../../providers/selection_providers.dart';
import '../../providers/tool_providers.dart';
import '../../utils/global_drawing_state.dart';
import '../../providers/ui_state_providers.dart';
import '../layer_style_settings_screen.dart';

// Mixins
import 'map_page_state_base.dart';
import 'mixins/index.dart';

// Widgets
import 'widgets/index.dart';

/// Map and edit screen (main structure)
class KMapsHomePage extends ConsumerStatefulWidget {
  const KMapsHomePage({super.key});
  @override
  ConsumerState<KMapsHomePage> createState() => _KMapsHomePageState();
}

/// Tool types
enum ToolType { pen, eraser, gps }

class _KMapsHomePageState extends ConsumerState<KMapsHomePage>
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(mapControllerHolderProvider.notifier).set(mapController);
    });
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
      final layer = targetLayer ?? ref.read(selectedLayerNodeProvider);

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
      ref.read(selectedFeaturesProvider.notifier).set([feature]);
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
    ref.listen<int>(featureRefreshTriggerProvider, (prev, next) {
      if (prev != null && prev != next) {
        updateFeaturesImpl();
      }
    });

    final folderTree = ref.watch(folderTreeProvider);
    currentNode ??= folderTree;

    final currentTool = ref.watch(currentToolProvider);
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
              currentFolder:
                  currentNode is FolderNode ? currentNode as FolderNode : null,
            ),
            // 地図本体
            Positioned.fill(
              left: 44,
              child: Stack(
                children: [
                  _buildFlutterMap(isPanTool),
                  _buildGestureLayer(),
                  _buildDrawingPreviewInfo(),
                ],
              ),
            ),
            // Layer Drawer Panel
            if (drawerOpen) _buildLayerDrawerPanel(),
            // Attribute Table Panel
            if (showAttributeTable && attributeTableLayer != null)
              _buildAttributeTablePanel(),
            // Feature detail panel
            if (ref.read(selectedFeaturesProvider).length == 1)
              Positioned(
                left: 60,
                top: 20,
                child: FeatureDetailPanel(
                  feature: ref.read(selectedFeaturesProvider).first,
                ),
              ),
            // Left bottom floating buttons
            Positioned(
              left: 56,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (currentTool.name == 'GPS')
                    GpsSurveyButtons(
                      isLongPressing: isLongPressing,
                      longPressGpsCount: longPressGpsCount,
                      onRecordGpsPosition: recordGpsPosition,
                      onStartLongPressGpsSurvey: startLongPressGpsSurvey,
                      onStopLongPressGpsSurvey: stopLongPressGpsSurvey,
                      onOpenTrackExtraction: openTrackExtractionDialog,
                    ),
                  const LeftBottomFab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: DrawingActionButtons(
          onConfirmDrawing: onConfirmDrawing,
          onConfirmGpsSurvey: onConfirmGpsSurvey,
          onTriggerSetState: () => triggerSetState(() {}),
          getGpsTool: () =>
              ref.read(currentToolProvider) is GpsTool
                  ? ref.read(currentToolProvider) as GpsTool
                  : null,
          onShowSnackBar: (message, {color}) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message),
                  backgroundColor: color,
                  duration: const Duration(seconds: 1),
                ),
              );
            }
          },
        ),
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
          flags:
              isPanTool
                  ? InteractiveFlag.all
                  : (InteractiveFlag.pinchZoom |
                      InteractiveFlag.scrollWheelZoom),
        ),
        keepAlive: true,
        onPositionChanged: (_, __) => scheduleMarkerRefresh(),
      ),
      children: [
        CachedTileLayer(
          provider: baseMapService.currentProvider,
          baseMapService: baseMapService,
        ),
        _buildPolylineLayer(),
        _buildPolygonLayer(),
        _buildClusteredMarkerLayer(),
        _buildOverlayMarkerLayer(),
      ],
    );
  }

  /// ポリラインレイヤー構築
  PolylineLayer _buildPolylineLayer() {
    final styleConfig = LayerStyleConfig();
    final drawingState = GlobalDrawingState.instance;

    return PolylineLayer(
      polylines: [
        // 本日のGPS軌跡（常時表示）
        if (gpsHistoryRecorder.todayPoints.length >= 2)
          Polyline(
            points: gpsHistoryRecorder.todayPoints,
            color: MapColors.trackingRoute,
            strokeWidth: 3.0,
          ),
        // 既存のラインフィーチャ
        for (final f in lineFeatures)
          if (f.geometry != null)
            (() {
              final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
              final isSelected = ref.read(selectedFeaturesProvider)
                  .contains(f);
              final lineColor = styleConfig.getLineColor(kmetaStyle);
              final lineWidth = styleConfig.getLineWidth(kmetaStyle);
              return Polyline(
                points: f.geometry as List<LatLng>,
                color: isSelected ? styleConfig.selectedColor : lineColor,
                strokeWidth:
                    isSelected
                        ? lineWidth * styleConfig.selectedMultiplier
                        : lineWidth,
              );
            })(),
        // GPS測量ラインプレビュー
        if (ref.read(currentToolProvider) is GpsTool &&
            drawingState.drawingLine.isNotEmpty)
          Polyline(
            points: drawingState.drawingLine,
            color: Colors.purple,
            strokeWidth: 2.0,
          ),
        // ペンツールラインプレビュー
        if (ref.read(currentToolProvider) is PenTool &&
            drawingState.drawingLine.isNotEmpty)
          Polyline(
            points: drawingState.drawingLine,
            color: Colors.orange,
            strokeWidth: 1.5,
          ),
        // GPS測量ポリゴン2点プレビュー
        if (ref.read(currentToolProvider) is GpsTool &&
            drawingState.drawingPolygon.length == 2)
          Polyline(
            points: drawingState.drawingPolygon,
            color: Colors.purple,
            strokeWidth: 2.0,
          ),
        // ペンツールポリゴン2点プレビュー
        if (ref.read(currentToolProvider) is PenTool &&
            drawingState.drawingPolygon.length == 2)
          Polyline(
            points: drawingState.drawingPolygon,
            color: Colors.orange,
            strokeWidth: 1.5,
          ),
        // (旧 GPS追跡軌跡プレビューは本日軌跡ポリラインに統合済み)
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
              final isSelected = ref.read(selectedFeaturesProvider)
                  .contains(f);
              final fillColor = styleConfig.getPolygonFillColor(kmetaStyle);
              final fillOpacity = styleConfig.getPolygonFillOpacity(kmetaStyle);
              final borderColor = styleConfig.getPolygonBorderColor(kmetaStyle);
              final borderOpacity = styleConfig.getPolygonBorderOpacity(
                kmetaStyle,
              );
              final borderWidth = styleConfig.getPolygonBorderWidth(kmetaStyle);
              return Polygon(
                points: (f.geometry as List<List<LatLng>>).first,
                holePointsList:
                    (f.geometry as List<List<LatLng>>).skip(1).toList(),
                color:
                    isSelected
                        ? styleConfig.selectedColor.withValues(alpha: 0.5)
                        : fillColor.withValues(alpha: fillOpacity),
                borderStrokeWidth:
                    isSelected
                        ? borderWidth * styleConfig.selectedMultiplier
                        : borderWidth,
                borderColor:
                    isSelected
                        ? styleConfig.selectedColor
                        : borderColor.withValues(alpha: borderOpacity),
              );
            })(),
        // GPS測量ポリゴンプレビュー
        if (ref.read(currentToolProvider) is GpsTool &&
            drawingState.drawingPolygon.length >= 3)
          Polygon(
            points: closeRing(drawingState.drawingPolygon),
            color: Colors.purple.withValues(alpha: 0.4),
            borderStrokeWidth: 2.0,
            borderColor: Colors.purple,
          ),
        // ペンツールポリゴンプレビュー
        if (ref.read(currentToolProvider) is PenTool &&
            drawingState.drawingPolygon.length >= 3)
          Polygon(
            points: closeRing(drawingState.drawingPolygon),
            color: Colors.orange.withValues(alpha: 0.4),
            borderStrokeWidth: 1.5,
            borderColor: Colors.orange,
          ),
        // SelectTool lassoプレビュー
        if (ref.read(currentToolProvider) is SelectTool &&
            (ref.read(currentToolProvider) as SelectTool)
                    .lassoPoints
                    .length >=
                3)
          Polygon(
            points: closeRing(
              (ref.read(currentToolProvider) as SelectTool).lassoPoints
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

  /// ビューポートを拡張して返す（カリング用）
  LatLngBounds? _getExpandedVisibleBounds(double factor) {
    try {
      final bounds = mapController.camera.visibleBounds;
      final latSpan = bounds.north - bounds.south;
      final lngSpan = bounds.east - bounds.west;
      if (latSpan <= 0 || lngSpan <= 0) return null;
      return LatLngBounds(
        LatLng(bounds.south - latSpan * factor, bounds.west - lngSpan * factor),
        LatLng(bounds.north + latSpan * factor, bounds.east + lngSpan * factor),
      );
    } catch (_) {
      return null;
    }
  }

  /// マーカーレイヤー構築（クラスタリング設定に応じて切り替え）
  Widget _buildClusteredMarkerLayer() {
    final styleConfig = LayerStyleConfig();
    final visibleBounds = _getExpandedVisibleBounds(0.5);
    final markers = <Marker>[
      ..._buildPointFeatureMarkers(styleConfig, visibleBounds),
      ..._buildImageNodeMarkers(styleConfig, visibleBounds),
    ];
    if (markers.isEmpty) return const SizedBox.shrink();

    if (!styleConfig.clusteringEnabled) {
      return MarkerLayer(markers: markers);
    }

    return MarkerClusterLayerWidget(
      options: MarkerClusterLayerOptions(
        maxClusterRadius: styleConfig.clusteringRadius,
        disableClusteringAtZoom: styleConfig.clusteringDisableZoom,
        size: const Size(40, 40),
        markers: markers,
        builder: (context, clusterMarkers) {
          final count = clusterMarkers.length;
          final bgColor =
              count < 10
                  ? Colors.blue
                  : count < 50
                  ? Colors.orange
                  : Colors.red;
          return Container(
            decoration: BoxDecoration(
              color: bgColor.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// オーバーレイマーカーレイヤー（現在位置、測量ポイント、頂点マーカー）
  MarkerLayer _buildOverlayMarkerLayer() {
    final styleConfig = LayerStyleConfig();
    final drawingState = GlobalDrawingState.instance;
    return MarkerLayer(
      markers: [
        if (currentLocation != null)
          Marker(
            point: currentLocation!,
            width: 64,
            height: 64,
            child: _buildLocationMarkerWithCompass(),
          ),
        if (ref.read(currentToolProvider) is GpsTool) ...[
          for (int i = 0; i < drawingState.drawingLine.length; i++)
            _buildSurveyPointMarker(drawingState.drawingLine[i], i, true),
          for (int i = 0; i < drawingState.drawingPolygon.length; i++)
            _buildSurveyPointMarker(drawingState.drawingPolygon[i], i, false),
        ],
        ..._buildVertexMarkers(styleConfig),
      ],
    );
  }

  /// ポイント地物マーカーリストを構築
  List<Marker> _buildPointFeatureMarkers(
    LayerStyleConfig styleConfig,
    LatLngBounds? visibleBounds,
  ) {
    final markers = <Marker>[];
    for (final f in pointFeatures) {
      if (f.geometry == null) continue;
      final kmetaStyle = (f.parent as LayerNode?)?.cachedKmetaStyle;
      final isSelected = ref.read(selectedFeaturesProvider).contains(f);
      final pointSize = styleConfig.getPointSize(kmetaStyle);
      final pointColor = styleConfig.getPointColor(kmetaStyle);
      final size =
          isSelected ? pointSize * styleConfig.selectedMultiplier : pointSize;
      final labelEnabled = styleConfig.getLabelEnabled(kmetaStyle);
      final labelProp = styleConfig.getLabelProperty(kmetaStyle);
      final labelValue = f.turfFeature.properties?[labelProp]?.toString();
      final showLabel =
          labelEnabled && labelValue != null && labelValue.isNotEmpty;
      for (final pt in f.geometry as List<LatLng>) {
        if (visibleBounds != null && !visibleBounds.contains(pt)) continue;
        markers.add(
          Marker(
            point: pt,
            width: size + 4,
            height: size + 4,
            child: Tooltip(
              message: f.name,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      color:
                          isSelected ? styleConfig.selectedColor : pointColor,
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
                  if (showLabel)
                    Positioned(
                      left: size + 4,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Opacity(
                          opacity: styleConfig.getLabelOpacity(kmetaStyle),
                          child: Text(
                            labelValue,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              fontSize: styleConfig.getLabelFontSize(
                                kmetaStyle,
                              ),
                              color: styleConfig.getLabelColor(kmetaStyle),
                              fontWeight: FontWeight.w500,
                              shadows: _buildHaloShadows(
                                styleConfig.getLabelHaloColor(kmetaStyle),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      }
    }
    return markers;
  }

  /// ImageNodeマーカーリストを構築
  List<Marker> _buildImageNodeMarkers(
    LayerStyleConfig styleConfig,
    LatLngBounds? visibleBounds,
  ) {
    final markers = <Marker>[];
    for (final photo in photoNodes.where((p) => p.hasLocation)) {
      if (visibleBounds != null && !visibleBounds.contains(photo.location!))
        continue;
      final isPhotoSelected = ref.read(selectedFeaturesProvider).contains(
        photo,
      );
      final showPhotoLabel = styleConfig.labelEnabled && photo.name.isNotEmpty;
      markers.add(
        Marker(
          point: photo.location!,
          width: 20,
          height: 20,
          child: GestureDetector(
            onTap: () {
              ref.read(selectedFeaturesProvider.notifier).set([photo]);
              triggerSetState(() {});
            },
            child: Tooltip(
              message:
                  '${photo.name}\n撮影位置: ${photo.location!.latitude.toStringAsFixed(6)}, ${photo.location!.longitude.toStringAsFixed(6)}',
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color:
                          isPhotoSelected ? Colors.yellow[100] : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isPhotoSelected ? Colors.orange : Colors.purple,
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
                      color: isPhotoSelected ? Colors.orange : Colors.purple,
                      size: isPhotoSelected ? 14 : 12,
                    ),
                  ),
                  if (showPhotoLabel)
                    Positioned(
                      left: 22,
                      top: 0,
                      bottom: 0,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Opacity(
                          opacity: styleConfig.labelOpacity,
                          child: Text(
                            photo.name,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                            style: TextStyle(
                              fontSize: styleConfig.labelFontSize,
                              color: styleConfig.labelColor,
                              fontWeight: FontWeight.w500,
                              shadows: _buildHaloShadows(
                                styleConfig.labelHaloColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return markers;
  }

  /// テキスト縁取り用のShadowリストを生成
  List<Shadow> _buildHaloShadows(Color haloColor) {
    return [
      for (final offset in const [
        Offset(1, 0),
        Offset(-1, 0),
        Offset(0, 1),
        Offset(0, -1),
      ])
        Shadow(color: haloColor, offset: offset, blurRadius: 2),
    ];
  }

  /// GPS測量ポイントマーカー構築
  Marker _buildSurveyPointMarker(LatLng point, int index, bool isLine) {
    final drawingState = GlobalDrawingState.instance;
    final metadataList =
        isLine ? drawingState.lineMetadata : drawingState.polygonMetadata;

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

        final isSelected = ref.read(selectedFeaturesProvider).contains(f);
        final color = isSelected ? style.selectedColor : style.lineColor;
        final strokeWidth =
            isSelected
                ? style.lineWidth * style.selectedMultiplier
                : style.lineWidth;
        final size = (strokeWidth * style.lineVertexPointSizeFactor).clamp(
          4.0,
          48.0,
        );

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

        final isSelected = ref.read(selectedFeaturesProvider).contains(f);
        final color =
            isSelected
                ? style.selectedColor
                : style.polygonBorderColor.withValues(
                  alpha: style.polygonBorderOpacity,
                );
        final strokeWidth =
            isSelected
                ? style.polygonBorderWidth * style.selectedMultiplier
                : style.polygonBorderWidth;
        final size = (strokeWidth * style.polygonVertexPointSizeFactor).clamp(
          4.0,
          48.0,
        );

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
          border: Border.all(color: Colors.white, width: size > 10 ? 1.5 : 1.0),
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
            ref.read(currentToolProvider).onMiddleButtonMove(event, this);
          } else {
            ref.read(currentToolProvider).addPointerToBuffer(
              event.localPosition,
            );
          }
        },
        onPointerDown: (event) {
          if (event.buttons == kMiddleMouseButton) {
            ref.read(currentToolProvider).onMiddleButtonDown(event, this);
          } else {
            ref.read(currentToolProvider).addPointerToBuffer(
              event.localPosition,
            );
          }
        },
        onPointerUp: (event) {
          if (event.buttons == 0) {
            ref.read(currentToolProvider).onMiddleButtonUp(event, this);
          }
          ref.read(currentToolProvider).clearPointerBuffer();
        },
        onPointerSignal: (event) {
          ref.read(currentToolProvider).onPointerSignal(event, this);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (details) {
            ref.read(currentToolProvider).onTap(details, this);
          },
          onScaleStart: (details) {
            ref.read(currentToolProvider).onScaleStart(details, this);
          },
          onScaleUpdate: (details) {
            ref.read(currentToolProvider).onScaleUpdate(details, this);
          },
          onScaleEnd: (details) {
            ref.read(currentToolProvider).onScaleEnd(details, this);
          },
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  /// 描画プレビュー情報構築
  Widget _buildDrawingPreviewInfo() {
    if (ref.read(currentToolProvider) is! PenTool) {
      return const SizedBox.shrink();
    }

    final selected = ref.read(selectedLayerNodeProvider);
    final penTool = ref.read(currentToolProvider) as PenTool;
    final drawingState = GlobalDrawingState.instance;
    String? previewText;
    Offset? previewOffset;

    if (selected is PointLayerNode && penTool.pointPreview != null) {
      final pt = penTool.pointPreview!;
      previewText =
          'Coordinates: (${pt.latitude.toStringAsFixed(6)}, ${pt.longitude.toStringAsFixed(6)})';
      previewOffset = latLngToOffset(pt);
    } else if (selected is LineLayerNode &&
        drawingState.drawingLine.length >= 2) {
      final len = GeometryCalc.calcLineLength(drawingState.drawingLine);
      final centroid = GeometryCalc.calcLineCentroid(drawingState.drawingLine);
      previewText =
          len >= 10000
              ? 'Length: ${(len / 1000).toStringAsFixed(1)} km'
              : 'Length: ${len.toStringAsFixed(2)} m';
      previewOffset = latLngToOffset(centroid);
    } else if (selected is PolygonLayerNode &&
        drawingState.drawingPolygon.length >= 3) {
      final closed = closeRing(drawingState.drawingPolygon);
      final areaDeg2 = GeometryCalc.calcPolygonArea([closed]);
      final centroid = GeometryCalc.calcPolygonCentroid([closed]);
      final areaM2 = DegreeMeterConverter.convertAreaToMeters2(
        areaDeg2,
        centroid.latitude,
      );
      previewText =
          areaM2 >= 10000
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
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('新規フィーチャ追加機能は開発中です')));
          }
        },
      ),
    );
  }

}
