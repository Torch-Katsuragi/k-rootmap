/// 全画面フィーチャ編集スクリーン
///
/// FlutterMap を背景に、下部パネルで編集コントロールを表示。
/// カメラツールと同じ Navigator.push パターンで遷移する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nodes/feature_node.dart';
import '../../providers/service_providers.dart';
import '../../services/basemap_service.dart';
import '../../widgets/cached_tile_layer.dart';
import 'feature_edit_action.dart';

class FeatureEditorScreen extends ConsumerStatefulWidget {
  final FeatureNode feature;
  final List<FeatureEditAction> actions;

  const FeatureEditorScreen({
    super.key,
    required this.feature,
    required this.actions,
  });

  @override
  ConsumerState<FeatureEditorScreen> createState() => _FeatureEditorScreenState();
}

class _FeatureEditorScreenState extends ConsumerState<FeatureEditorScreen> {
  late final List<FeatureEditAction> _applicable;
  late final ValueNotifier<PreviewLines> _previewLines;
  late final MapController _mapController;
  bool _mapReady = false;
  bool _initialFitDone = false;

  @override
  void initState() {
    super.initState();
    _applicable =
        widget.actions.where((a) => a.canApplyTo(widget.feature)).toList();
    _previewLines = ValueNotifier(PreviewLines.empty);
    _mapController = MapController();
    _previewLines.addListener(_onPreviewChanged);
  }

  @override
  void dispose() {
    _previewLines.removeListener(_onPreviewChanged);
    _previewLines.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onPreviewChanged() {
    _tryInitialFit();
    setState(() {});
  }

  void _onMapReady() {
    _mapReady = true;
    _tryInitialFit();
  }

  void _tryInitialFit() {
    if (_initialFitDone || !_mapReady) return;
    final bounds = _calcBounds();
    if (bounds == null) return;
    _initialFitDone = true;
    // 全子ウィジェットのセットアップ完了後に実行
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(40)),
      );
    });
  }

  LatLngBounds? _calcBounds() {
    final lines = _previewLines.value;
    final allPoints = [
      ...lines.backgroundLine,
      ...lines.foregroundLine,
    ];
    if (allPoints.isEmpty) return null;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    return LatLngBounds(
      LatLng(minLat, minLng),
      LatLng(maxLat, maxLng),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_applicable.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('編集')),
        body: const Center(child: Text('利用可能な編集操作がありません')),
      );
    }

    final baseMapService = ref.read(baseMapServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.feature.name} を編集',
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: Column(
        children: [
          // 上: FlutterMap
          Expanded(
            child: _buildMap(baseMapService),
          ),

          // 下: コントロールパネル
          Material(
            elevation: 8,
            child: _applicable.length == 1
                ? _buildSinglePanel()
                : _buildTabbedPanel(),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(BaseMapService baseMapService) {
    final lines = _previewLines.value;
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(onMapReady: _onMapReady),
      children: [
        CachedTileLayer(
          provider: baseMapService.currentProvider,
          baseMapService: baseMapService,
        ),
        if (lines.backgroundLine.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: lines.backgroundLine,
                color: Colors.grey.shade400,
                strokeWidth: 3,
              ),
            ],
          ),
        if (lines.foregroundLine.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: lines.foregroundLine,
                color: Colors.blue.shade700,
                strokeWidth: 4,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildSinglePanel() {
    final action = _applicable.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: action.buildControls(
        context,
        widget.feature,
        _previewLines,
      ),
    );
  }

  Widget _buildTabbedPanel() {
    return DefaultTabController(
      length: _applicable.length,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TabBar(
            isScrollable: true,
            tabs: [
              for (final action in _applicable)
                Tab(icon: Icon(action.icon, size: 18), text: action.label),
            ],
          ),
          SizedBox(
            height: 200,
            child: TabBarView(
              children: [
                for (final action in _applicable)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: action.buildControls(
                      context,
                      widget.feature,
                      _previewLines,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
