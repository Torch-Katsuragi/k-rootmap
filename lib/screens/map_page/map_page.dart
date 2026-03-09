// K-MAPS: Map and edit screen
// Main UI for map display and layer/feature editing
// maplibre移行: FlutterMap → MapLibreMap
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:geobase/geobase.dart' as geo;
import 'package:latlong2/latlong.dart';
import '../../models/nodes/image_node.dart';
import '../../services/map_source_manager.dart';
import '../../utils/geo_converter.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
// gps_track.dart は不要に（GpsHistoryRecorder に統合）
import '../../widgets/layer_drawer/layer_drawer.dart';
import '../../widgets/resizable_side_panel.dart';
import '../../widgets/dynamic_attribute_table_widget.dart';
import '../../widgets/compass_fan_painter.dart';
import '../../widgets/feature_detail_panel.dart';
import '../../widgets/left_bottom_fab.dart';
import '../../widgets/map/k_map_widget.dart';
import '../../widgets/map_toolbar.dart';
import '../../widgets/map_appbar_actions.dart';
import '../../core/settings_schema.dart' show SettingsStore;
import '../../utils/app_logger.dart';
import '../../utils/feature_calc_utils.dart';
import '../../utils/keyboard_handler.dart';
import '../../tools/pen_tool.dart';
import '../../tools/select_tool.dart';
import '../../tools/gps_tool.dart';
import '../../providers/selection_providers.dart';
import '../../providers/tool_providers.dart';
import '../../utils/global_drawing_state.dart';
import '../../providers/ui_state_providers.dart';
import '../layer_style_settings_screen.dart'
    show
        layerStyleSettings,
        pointSizeDef,
        pointColorDef,
        lineWidthDef,
        lineColorDef,
        lineVertexPointsEnabledDef,
        lineVertexPointSizeFactorDef,
        polygonBorderWidthDef,
        polygonBorderColorDef,
        polygonFillColorDef,
        polygonFillOpacityDef,
        polygonBorderOpacityDef,
        polygonVertexPointsEnabledDef,
        polygonVertexPointSizeFactorDef,
        selectedColorDef,
        selectedMultiplierDef,
        clusteringEnabledDef,
        clusteringRadiusDef,
        clusteringDisableZoomDef;

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

  /// dirtyフラグ設定と同時にフィーチャソースを再同期
  /// build()からの毎フレーム呼び出しを排除し、データ変更時のみ同期する
  @override
  void invalidateLayerCache() {
    super.invalidateLayerCache();
    _syncFeatureSources();
  }

  @override
  void onBaseMapServiceUpdate() {
    if (mounted) {
      replaceBasemapSource();
      triggerSetState(() {});
    }
  }

  @override
  void onLayerStyleChanged() {
    if (mounted) {
      _applyLayerStyles();
      invalidateLayerCache(); // dirty設定 + _syncFeatureSources() 呼び出し
      triggerSetState(() {});
    }
  }

  @override
  void updateCurrentGpsInfo() {
    triggerSetState(() {
      currentGpsInfo = gpsManager.getCurrentGpsInfo();
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

  /// コンパス方向付きの現在位置マーカー
  /// headingNotifier経由で局所再描画（MapPage全体のrebuildを回避）
  Widget _buildLocationMarkerWithCompass() {
    return ValueListenableBuilder<double?>(
      valueListenable: headingNotifier,
      builder: (_, heading, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            if (heading != null)
              Transform.rotate(
                angle: (heading * pi / 180) - (pi / 2),
                child: SizedBox(
                  width: 60,
                  height: 60,
                  child: CustomPaint(painter: CompassFanPainter()),
                ),
              ),
            child!,
          ],
        );
      },
      child: Container(
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

    // 選択状態の変更をリッスンしてフィーチャソースを再同期
    ref.listen<List<LayerTreeNode>>(selectedFeaturesProvider, (_, __) {
      _syncFeatureSources();
    });

    // 選択状態を監視（変更時に自動rebuild）
    final selectedFeatures = ref.watch(selectedFeaturesProvider);

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
              headingNotifier: headingNotifier,
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
                  _buildMapLibreMap(isPanTool),
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
            if (selectedFeatures.length == 1)
              Positioned(
                left: 60,
                top: 20,
                child: FeatureDetailPanel(
                  feature: selectedFeatures.first,
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

  /// MapLibreMap構築
  /// フィーチャ系レイヤはMapSourceManager経由で管理（OOM防止）
  /// layersには描画プレビューと投げ縄のみ（超軽量）
  Widget _buildMapLibreMap(bool isPanTool) {
    final selectedSet = ref.read(selectedFeaturesProvider).toSet();
    final drawingState = GlobalDrawingState.instance;
    final currentTool = ref.read(currentToolProvider);

    return KMapWidget(
      options: ml.MapOptions(
        initCenter: defaultCenter.toGeographic(),
        initZoom: 16.0,
        gestures: const ml.MapGestures(
          pan: false,
          zoom: false,
          rotate: false,
          pitch: false,
        ),
      ),
      onMapCreated: (controller) {
        mapControllerInstance.attach(controller.raw!);
      },
      onStyleLoaded: (_, style) => _onMapStyleLoaded(style),
      onEvent: _onMapEvent,
      // 描画プレビューと投げ縄のみ（数点、超軽量）
      layers: [
        // 描画プレビュー: ポリゴン（GPSツール）
        if (currentTool is GpsTool &&
            drawingState.drawingPolygon.length >= 3)
          ml.PolygonLayer(
            polygons: [
              geo.Feature(
                geometry: geo.Polygon.from([
                  closeRing(drawingState.drawingPolygon).toGeographics(),
                ]),
              ),
            ],
            color: Colors.purple.withValues(alpha: 0.4),
            outlineColor: Colors.purple,
          ),
        // 描画プレビュー: ポリゴン（ペンツール）
        if (currentTool is PenTool &&
            drawingState.drawingPolygon.length >= 3)
          ml.PolygonLayer(
            polygons: [
              geo.Feature(
                geometry: geo.Polygon.from([
                  closeRing(drawingState.drawingPolygon).toGeographics(),
                ]),
              ),
            ],
            color: Colors.orange.withValues(alpha: 0.4),
            outlineColor: Colors.orange,
          ),
        // 投げ縄選択ポリゴン
        if (currentTool case SelectTool(:final lassoPoints) when lassoPoints.length >= 3)
          ml.PolygonLayer(
            polygons: [
              geo.Feature(
                geometry: geo.Polygon.from([
                  closeRing(
                    lassoPoints
                        .map((offset) => offsetToLatLng(offset))
                        .toList(),
                  ).toGeographics(),
                ]),
              ),
            ],
            color: Colors.white.withValues(alpha: 0.2),
            outlineColor: Colors.black,
          ),
        // 描画プレビュー: ライン
        ..._buildDrawingPreviewPolylines(currentTool, drawingState),
      ],
      children: [
        // Widgetマーカー（現在位置、測量ポイント、頂点マーカー）
        ml.WidgetLayer(
          markers: _buildOverlayWidgetMarkers(selectedSet),
        ),
      ],
    );
  }

  /// mapスタイル読み込み完了時: タイルソース・GeoJSONソース初期化
  Future<void> _onMapStyleLoaded(ml.StyleController style) async {
    mapControllerInstance.attachStyle(style);
    await _addBasemapSource(style);

    // GeoJSONソース/スタイルレイヤを一括初期化
    await sourceManager.initialize(style);

    // 現在のスタイル設定を反映
    _applyLayerStyles();

    // ソース初期化完了 → dirty フラグを強制セットして確実にフィーチャを送信
    // invalidateLayerCache() 内で _syncFeatureSources() も呼ばれる
    invalidateLayerCache();
  }

  /// マップイベント処理（カメラ移動完了時にクラスタ更新）
  void _onMapEvent(ml.MapEvent event) {
    if (event is ml.MapEventCameraIdle || event is ml.MapEventIdle) {
      _refreshPointClusters();
    }
  }

  /// ベースマップソース追加（TileServer経由のlocalhost URL）
  Future<void> _addBasemapSource(ml.StyleController style) async {
    final provider = baseMapService.currentProvider;
    final url = tileServer.isRunning
        ? tileServer.urlTemplate(provider.id)
        : provider.urlTemplate;

    AppLogger.debug('[MAP] addBasemapSource: url=$url (tileServer=${tileServer.isRunning})');

    try {
      final source = ml.RasterSource(
        id: 'basemap',
        tiles: [url],
        maxZoom: provider.maxZoom.toDouble(),
        tileSize: 256,
        attribution: provider.attribution,
      );
      await style.addSource(source);
      await style.addLayer(
        const ml.RasterStyleLayer(id: 'basemap-layer', sourceId: 'basemap'),
      );
      AppLogger.debug('[MAP] addBasemapSource: success');
    } catch (e) {
      AppLogger.debug('[MAP] addBasemapSource: error: $e');
    }
  }

  /// ベースマップ切替（旧ソース削除→新ソース追加）
  Future<void> replaceBasemapSource() async {
    final style = mapControllerInstance.style;
    if (style == null) return;
    try {
      await style.removeLayer('basemap-layer');
      await style.removeSource('basemap');
    } catch (_) {}
    await _addBasemapSource(style);
  }

  /// 描画プレビュー用ポリラインレイヤのリスト生成
  List<ml.PolylineLayer> _buildDrawingPreviewPolylines(
    dynamic currentTool,
    GlobalDrawingState drawingState,
  ) {
    final layers = <ml.PolylineLayer>[];
    // GPSツールの線プレビュー（LineStringは最低2点必要）
    if (currentTool is GpsTool && drawingState.drawingLine.length >= 2)
      layers.add(ml.PolylineLayer(
        polylines: [
          geo.Feature(
            geometry: geo.LineString.from(
              drawingState.drawingLine.toGeographics(),
            ),
          ),
        ],
        color: Colors.purple,
        width: 2,
      ));
    // ペンツールの線プレビュー（LineStringは最低2点必要）
    if (currentTool is PenTool && drawingState.drawingLine.length >= 2)
      layers.add(ml.PolylineLayer(
        polylines: [
          geo.Feature(
            geometry: geo.LineString.from(
              drawingState.drawingLine.toGeographics(),
            ),
          ),
        ],
        color: Colors.orange,
        width: 2,
      ));
    // GPSツールのポリゴン辺プレビュー（2点時）
    if (currentTool is GpsTool && drawingState.drawingPolygon.length == 2)
      layers.add(ml.PolylineLayer(
        polylines: [
          geo.Feature(
            geometry: geo.LineString.from(
              drawingState.drawingPolygon.toGeographics(),
            ),
          ),
        ],
        color: Colors.purple,
        width: 2,
      ));
    // ペンツールのポリゴン辺プレビュー（2点時）
    if (currentTool is PenTool && drawingState.drawingPolygon.length == 2)
      layers.add(ml.PolylineLayer(
        polylines: [
          geo.Feature(
            geometry: geo.LineString.from(
              drawingState.drawingPolygon.toGeographics(),
            ),
          ),
        ],
        color: Colors.orange,
        width: 2,
      ));
    return layers;
  }

  /// フィーチャキャッシュを再構築し、MapSourceManager経由でGeoJSONソースを更新
  /// データ変更時のみネイティブに送信（変更なしならスキップ）
  void _syncFeatureSources() {
    final currentSelection = ref.read(selectedFeaturesProvider);
    final selectionChanged =
        !identical(lastCacheSelection, currentSelection);

    if (!layerCacheDirty && !selectionChanged) return;
    layerCacheDirty = false;
    lastCacheSelection = currentSelection;

    final selectedSet = currentSelection.toSet();

    // ポリラインをmaplibre Feature型に変換（選択/非選択分離）
    cachedPolylines = [];
    cachedSelectedPolylines = [];
    for (final f in lineFeatures) {
      if (f.geometry == null) continue;
      final pts = (f.geometry as List<LatLng>).toGeographics();
      final feature = geo.Feature(
        geometry: geo.LineString.from(pts),
      );
      if (selectedSet.contains(f)) {
        cachedSelectedPolylines.add(feature);
      } else {
        cachedPolylines.add(feature);
      }
    }

    // ポリゴンをmaplibre Feature型に変換（選択/非選択分離）
    cachedPolygons = [];
    cachedSelectedPolygons = [];
    for (final f in polygonFeatures) {
      if (f.geometry == null) continue;
      final rings = f.geometry as List<List<LatLng>>;
      final geoRings = rings.map((r) => r.toGeographics()).toList();
      final feature = geo.Feature(
        geometry: geo.Polygon.from(geoRings),
      );
      if (selectedSet.contains(f)) {
        cachedSelectedPolygons.add(feature);
      } else {
        cachedPolygons.add(feature);
      }
    }

    // ポイントをmaplibre Feature型に変換（選択/非選択分離）
    cachedMarkers = [];
    cachedSelectedMarkers = [];
    for (final f in pointFeatures) {
      if (f.geometry == null) continue;
      for (final pt in f.geometry as List<LatLng>) {
        final feature = geo.Feature(
          geometry: geo.Point(pt.toGeographic()),
          properties: {'name': f.name},
        );
        if (selectedSet.contains(f)) {
          cachedSelectedMarkers.add(feature);
        } else {
          cachedMarkers.add(feature);
        }
      }
    }

    // ImageNodeをGeoJSON Feature化（SymbolStyleLayerでGPU描画）
    cachedImageFeatures = [];
    cachedSelectedImageFeatures = [];
    for (final photo in photoNodes.where((p) => p.hasLocation)) {
      final props = <String, Object?>{
        'name': photo.name,
        'has_direction': photo.direction != null,
        if (photo.direction != null) 'direction': photo.direction,
        if (photo.takenAt != null) 'taken_at': photo.takenAt!.millisecondsSinceEpoch,
      };
      final feature = geo.Feature(
        geometry: geo.Point(photo.location!.toGeographic()),
        properties: props,
      );
      if (selectedSet.contains(photo)) {
        cachedSelectedImageFeatures.add(feature);
      } else {
        cachedImageFeatures.add(feature);
      }
    }

    // MapSourceManager経由でGeoJSONソースを更新（変更時のみ送信）
    _pushFeaturesToSources();
  }

  /// キャッシュ済みフィーチャをMapSourceManagerに送信
  void _pushFeaturesToSources() {
    if (!sourceManager.isInitialized) {
      // ソース未初期化 → dirty フラグを復元して次回リトライ
      layerCacheDirty = true;
      return;
    }
    sourceManager.updateFeatures(MapSourceManager.kPolygons, cachedPolygons);
    sourceManager.updateFeatures(MapSourceManager.kPolygonsSel, cachedSelectedPolygons);
    sourceManager.updateFeatures(MapSourceManager.kLines, cachedPolylines);
    sourceManager.updateFeatures(MapSourceManager.kLinesSel, cachedSelectedPolylines);
    sourceManager.updateFeatures(MapSourceManager.kPoints, cachedMarkers);
    sourceManager.updateFeatures(MapSourceManager.kPointsSel, cachedSelectedMarkers);
    sourceManager.updateFeatures(MapSourceManager.kImages, cachedImageFeatures);
    sourceManager.updateFeatures(MapSourceManager.kImagesSel, cachedSelectedImageFeatures);
    // クラスタリング: 現在のズームでクラスタ表示を更新
    _refreshPointClusters();
  }

  /// 現在のズームレベルでクラスタ表示を更新
  void _refreshPointClusters() {
    if (!sourceManager.isInitialized) return;
    final zoom = mapController.raw != null
        ? mapController.camera.zoom
        : 16.0;
    sourceManager.refreshClusters(zoom);
  }

  /// タップ位置のImageNodeを検出し選択する（見つかればtrue）
  bool _trySelectImageNodeAt(Offset localPosition) {
    if (photoNodes.isEmpty) return false;
    LatLng tapLatLng;
    try {
      tapLatLng = offsetToLatLng(localPosition);
    } catch (_) {
      return false;
    }
    // ズームに応じた選択範囲（メートル）
    final zoom = mapController.raw != null ? mapController.camera.zoom : 16.0;
    final thresholdMeters = 20.0 * pow(2, 16 - zoom);

    final distCalc = const Distance();
    ImageNode? nearest;
    double nearestDist = double.infinity;

    for (final photo in photoNodes) {
      if (!photo.hasLocation) continue;
      final d = distCalc.as(LengthUnit.Meter, tapLatLng, photo.location!);
      if (d < nearestDist) {
        nearestDist = d;
        nearest = photo;
      }
    }

    if (nearest != null && nearestDist <= thresholdMeters) {
      ref.read(selectedFeaturesProvider.notifier).set([nearest]);
      ref.read(featureRefreshTriggerProvider.notifier).trigger();
      return true;
    }
    return false;
  }

  /// レイヤスタイル設定をMapSourceManagerに反映
  void _applyLayerStyles() {
    final style = layerStyleSettings;
    // クラスタリング設定を反映
    sourceManager.configureClustering(
      enabled: style.getBool(clusteringEnabledDef),
      radius: style.getInt(clusteringRadiusDef),
      maxZoom: style.getInt(clusteringDisableZoomDef),
    );
    sourceManager.updateLayerStyles(
      polygonFillColor: style.getColor(polygonFillColorDef),
      polygonFillOpacity: style.getDouble(polygonFillOpacityDef),
      polygonOutlineColor: style.getColor(polygonBorderColorDef),
      polygonOutlineOpacity: style.getDouble(polygonBorderOpacityDef),
      lineColor: style.getColor(lineColorDef),
      lineWidth: style.getDouble(lineWidthDef),
      pointColor: style.getColor(pointColorDef),
      pointSize: style.getDouble(pointSizeDef),
      selectedColor: style.getColor(selectedColorDef),
      selectedMultiplier: style.getDouble(selectedMultiplierDef),
    );
  }

  /// オーバーレイWidgetマーカーを構築（現在位置、測量ポイント、頂点マーカー）
  List<ml.Marker> _buildOverlayWidgetMarkers(Set<LayerTreeNode> selectedSet) {
    final drawingState = GlobalDrawingState.instance;
    final currentTool = ref.read(currentToolProvider);
    return [
      // 頂点マーカー
      ..._buildVertexMarkers(layerStyleSettings, selectedSet),
      // ペンツール: 線/ポリゴン描画中の1点目インジケータ
      if (currentTool is PenTool && drawingState.drawingLine.length == 1)
        _buildFirstPointIndicator(drawingState.drawingLine.first),
      if (currentTool is PenTool && drawingState.drawingPolygon.length == 1)
        _buildFirstPointIndicator(drawingState.drawingPolygon.first),
      // GPS測量ポイント
      if (currentTool is GpsTool) ...[
        for (int i = 0; i < drawingState.drawingLine.length; i++)
          _buildSurveyPointMarker(drawingState.drawingLine[i], i, true),
        for (int i = 0; i < drawingState.drawingPolygon.length; i++)
          _buildSurveyPointMarker(drawingState.drawingPolygon[i], i, false),
      ],
      // 現在位置マーカー — 最上位（常に見える）
      if (currentLocation != null)
        ml.Marker(
          point: currentLocation!.toGeographic(),
          size: const Size.square(64),
          child: _buildLocationMarkerWithCompass(),
        ),
    ];
  }

  /// 描画開始の1点目インジケータ（十字マーク）
  ml.Marker _buildFirstPointIndicator(LatLng point) {
    return ml.Marker(
      point: point.toGeographic(),
      size: const Size.square(18),
      child: const CustomPaint(painter: _CrosshairPainter()),
    );
  }

  /// GPS測量ポイントマーカー構築（maplibre Marker型）
  ml.Marker _buildSurveyPointMarker(LatLng point, int index, bool isLine) {
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

    return ml.Marker(
      point: point.toGeographic(),
      size: const Size.square(32),
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

  /// 頂点マーカー構築（maplibre Marker型）
  List<ml.Marker> _buildVertexMarkers(
    SettingsStore style,
    Set<LayerTreeNode> selectedSet,
  ) {
    final selColor = style.getColor(selectedColorDef);
    final selMult = style.getDouble(selectedMultiplierDef);
    final markers = <ml.Marker>[];

    if (style.getBool(lineVertexPointsEnabledDef)) {
      final lc = style.getColor(lineColorDef);
      final lw = style.getDouble(lineWidthDef);
      final lvf = style.getDouble(lineVertexPointSizeFactorDef);
      for (final f in lineFeatures) {
        if (f.geometry == null) continue;
        final pts = f.geometry as List<LatLng>;
        if (pts.isEmpty) continue;

        final isSelected = selectedSet.contains(f);
        final color = isSelected ? selColor : lc;
        final sw = isSelected ? lw * selMult : lw;
        final size = (sw * lvf).clamp(4.0, 48.0);

        for (final pt in pts) {
          markers.add(_buildVertexMarker(pt, size, color));
        }
      }
    }

    if (style.getBool(polygonVertexPointsEnabledDef)) {
      final pbc = style.getColor(polygonBorderColorDef);
      final pbo = style.getDouble(polygonBorderOpacityDef);
      final pbw = style.getDouble(polygonBorderWidthDef);
      final pvf = style.getDouble(polygonVertexPointSizeFactorDef);
      for (final f in polygonFeatures) {
        if (f.geometry == null) continue;
        final rings = f.geometry as List<List<LatLng>>;
        if (rings.isEmpty) continue;

        final isSelected = selectedSet.contains(f);
        final color =
            isSelected ? selColor : pbc.withValues(alpha: pbo);
        final sw = isSelected ? pbw * selMult : pbw;
        final size = (sw * pvf).clamp(4.0, 48.0);

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

  /// 単一頂点マーカー構築（maplibre Marker型）
  ml.Marker _buildVertexMarker(LatLng point, double size, Color color) {
    return ml.Marker(
      point: point.toGeographic(),
      size: Size.square(size + 4),
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
            // ImageNode（SymbolStyleLayer）のタップ検出を先に行う
            if (_trySelectImageNodeAt(details.localPosition)) return;
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

/// 描画開始地点を示す十字マーク（ポイントフィーチャと差別化）
class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // 白アウトライン → オレンジ本体の順で描画
    final outline = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = Colors.orange
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final p in [outline, fill]) {
      canvas.drawLine(Offset(cx - r, cy), Offset(cx + r, cy), p);
      canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
