// K-MAPS: MapLibre GeoJSONソース直接管理
// layersプロパティを経由せず、StyleController経由でソース/レイヤを管理
// データ変更時のみupdateGeoJsonSourceを呼び出し、OOMを防止
import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geobase/geobase.dart' as geo;
import 'package:maplibre/maplibre.dart' as ml;
// ignore: implementation_imports
import 'package:maplibre_webview/src/style_controller.dart' as webview_style;
import 'package:supercluster/supercluster.dart';
import '../core/constants.dart';
import '../utils/app_logger.dart';
import '../utils/map_icon_generator.dart';

/// GeoJSONソース/スタイルレイヤをStyleController経由で直接管理
/// layers プロパティによる毎rebuild時のGeoJSONシリアライズを回避
class MapSourceManager {
  ml.StyleController? _style;
  bool _initialized = false;
  Completer<void>? _initCompleter;

  // 前回送信したGeoJSON文字列（変更検知用）
  final Map<String, String> _lastData = {};

  bool get isInitialized => _initialized;

  // ソースID定数
  static const kPolygons = 'k-polygons';
  static const kPolygonsSel = 'k-polygons-sel';
  static const kLines = 'k-lines';
  static const kLinesSel = 'k-lines-sel';
  static const kPoints = 'k-points';
  static const kPointsSel = 'k-points-sel';
  static const kClusters = 'k-clusters';
  static const kGpsTrack = 'k-gps-track';
  static const kImages = 'k-images';
  static const kImagesSel = 'k-images-sel';
  static const kImageClusters = 'k-image-clusters';
  static const kLineVertices = 'k-line-vertices';
  static const kLineVerticesSel = 'k-line-vertices-sel';
  static const kPolyVertices = 'k-poly-vertices';
  static const kPolyVerticesSel = 'k-poly-vertices-sel';

  // レイヤID定数
  static const kPolygonsFill = 'k-polygons-fill';
  static const kPolygonsOutline = 'k-polygons-outline';
  static const kPolygonsSelFill = 'k-polygons-sel-fill';
  static const kPolygonsSelOutline = 'k-polygons-sel-outline';
  static const kLinesLine = 'k-lines-line';
  static const kLinesSelLine = 'k-lines-sel-line';
  static const kPolyVerticesCircle = 'k-poly-vertices-circle';
  static const kPolyVerticesSelCircle = 'k-poly-vertices-sel-circle';
  static const kLineVerticesCircle = 'k-line-vertices-circle';
  static const kLineVerticesSelCircle = 'k-line-vertices-sel-circle';
  static const kPointsCircle = 'k-points-circle';
  static const kPointsSelCircle = 'k-points-sel-circle';
  static const kClusterCircle = 'k-cluster-circle';
  static const kClusterCount = 'k-cluster-count';
  static const kGpsTrackLine = 'k-gps-track-line';
  static const kImagesSymbol = 'k-images-symbol';
  static const kImagesSelSymbol = 'k-images-sel-symbol';
  static const kImageClusterCircle = 'k-image-cluster-circle';
  static const kImageClusterCount = 'k-image-cluster-count';
  static const kImageClusterName = 'k-image-cluster-name';

  // アイコン画像ID
  static const _iconPhotoMarker = 'photo-marker';
  static const _iconPhotoMarkerSel = 'photo-marker-sel';
  static const _iconPhotoMarkerNoDir = 'photo-marker-no-dir';
  static const _iconPhotoMarkerNoDirSel = 'photo-marker-no-dir-sel';

  static const _emptyGeoJson =
      '{"type":"FeatureCollection","features":[]}';

  // Isolate化の閾値
  static const _isolateThreshold = 500;

  static const _allSourceIds = [
    kPolygons, kPolygonsSel,
    kLines, kLinesSel,
    kLineVertices, kLineVerticesSel,
    kPolyVertices, kPolyVerticesSel,
    kPoints, kPointsSel,
    kClusters,
    kGpsTrack,
    kImages, kImagesSel,
    kImageClusters,
  ];

  // 描画順: polygon → line → gpsTrack → vertices → clusters → points → imageClusters → images
  static const _allLayerIds = [
    kPolygonsFill, kPolygonsOutline,
    kPolygonsSelFill, kPolygonsSelOutline,
    kLinesLine, kLinesSelLine, kGpsTrackLine,
    kPolyVerticesCircle, kPolyVerticesSelCircle,
    kLineVerticesCircle, kLineVerticesSelCircle,
    kClusterCircle, kClusterCount,
    kPointsCircle, kPointsSelCircle,
    kImageClusterCircle, kImageClusterCount, kImageClusterName,
    kImagesSymbol, kImagesSelSymbol,
  ];

  // --------------------------------------------------
  // クラスタリング
  // --------------------------------------------------
  bool _clusterEnabled = true;
  int _clusterRadius = 25;
  int _clusterMaxZoom = 18;
  int _lastClusterIntZoom = -1;

  // Supercluster インデックス（不変版: rebuild時に丸ごと再生成）
  SuperclusterImmutable<_IndexedPoint>? _clusterIndex;
  SuperclusterImmutable<_IndexedPoint>? _imageClusterIndex;
  int _lastImageClusterIntZoom = -1;

  // 生ポイントデータ保持（クラスタリング用）
  List<geo.Feature<geo.Point>> _rawPoints = [];
  List<geo.Feature<geo.Point>> _rawImages = [];

  /// クラスタリング設定を更新
  void configureClustering({
    required bool enabled,
    required int radius,
    required int maxZoom,
  }) {
    final changed = _clusterEnabled != enabled ||
        _clusterRadius != radius ||
        _clusterMaxZoom != maxZoom;
    _clusterEnabled = enabled;
    _clusterRadius = radius;
    _clusterMaxZoom = maxZoom;
    if (changed) {
      if (_rawPoints.isNotEmpty) _rebuildClusterIndex();
      if (_rawImages.isNotEmpty) _rebuildImageClusterIndex();
    }
  }

  /// クラスタインデックスを再構築
  void _rebuildClusterIndex() {
    if (!_clusterEnabled || _rawPoints.isEmpty) {
      _clusterIndex = null;
      return;
    }
    final indexed = <_IndexedPoint>[];
    for (var i = 0; i < _rawPoints.length; i++) {
      final geom = _rawPoints[i].geometry;
      if (geom == null) continue;
      final coord = geom.position;
      indexed.add(_IndexedPoint(
        index: i,
        longitude: coord.x.toDouble(),
        latitude: coord.y.toDouble(),
      ));
    }
    _clusterIndex = SuperclusterImmutable<_IndexedPoint>(
      getX: (p) => p.longitude,
      getY: (p) => p.latitude,
      radius: _clusterRadius,
      maxZoom: _clusterMaxZoom,
    )..load(indexed);
    _lastClusterIntZoom = -1;
  }

  /// ImageNodeクラスタインデックスを再構築
  void _rebuildImageClusterIndex() {
    if (!_clusterEnabled || _rawImages.isEmpty) {
      _imageClusterIndex = null;
      return;
    }
    final indexed = <_IndexedPoint>[];
    for (var i = 0; i < _rawImages.length; i++) {
      final geom = _rawImages[i].geometry;
      if (geom == null) continue;
      final coord = geom.position;
      indexed.add(_IndexedPoint(
        index: i,
        longitude: coord.x.toDouble(),
        latitude: coord.y.toDouble(),
      ));
    }
    _imageClusterIndex = SuperclusterImmutable<_IndexedPoint>(
      getX: (p) => p.longitude,
      getY: (p) => p.latitude,
      radius: _clusterRadius,
      maxZoom: _clusterMaxZoom,
    )..load(indexed);
    _lastImageClusterIntZoom = -1;
  }

  /// 現在のズームレベルでクラスタ/個別ポイントを再生成しソースに送信
  void refreshClusters(double zoom) {
    if (!_initialized) return;
    _refreshPointClusters(zoom);
    _refreshImageClusters(zoom);
  }

  /// Pointクラスタリング
  void _refreshPointClusters(double zoom) {
    if (!_clusterEnabled || _clusterIndex == null) {
      _updateRaw(kClusters, _emptyGeoJson);
      return;
    }

    final intZoom = zoom.floor();
    if (intZoom == _lastClusterIntZoom) return;
    _lastClusterIntZoom = intZoom;

    final results = _clusterIndex!.search(-180, -90, 180, 90, intZoom);

    final clusterBuf = StringBuffer();
    final pointBuf = StringBuffer();
    var clusterCount = 0;
    var pointCount = 0;

    for (final item in results) {
      item.handle(
        cluster: (cluster) {
          if (clusterCount > 0) clusterBuf.write(',');
          clusterBuf.write(
            '{"type":"Feature","geometry":{"type":"Point",'
            '"coordinates":[${cluster.longitude},${cluster.latitude}]},'
            '"properties":{"point_count":${cluster.childPointCount},'
            '"point_count_abbreviated":"${_abbreviate(cluster.childPointCount)}"}}',
          );
          clusterCount++;
        },
        point: (point) {
          if (pointCount > 0) pointBuf.write(',');
          final raw = _rawPoints[point.originalPoint.index];
          final name = raw.properties['name'] ?? '';
          pointBuf.write(
            '{"type":"Feature","geometry":{"type":"Point",'
            '"coordinates":[${point.originalPoint.longitude},${point.originalPoint.latitude}]},'
            '"properties":{"name":${jsonEncode(name)}}}',
          );
          pointCount++;
        },
      );
    }

    _updateRaw(kClusters,
        '{"type":"FeatureCollection","features":[$clusterBuf]}');
    _updateRaw(kPoints,
        '{"type":"FeatureCollection","features":[$pointBuf]}');
  }

  /// ImageNodeクラスタリング
  void _refreshImageClusters(double zoom) {
    if (!_clusterEnabled || _imageClusterIndex == null) {
      _updateRaw(kImageClusters, _emptyGeoJson);
      return;
    }

    final intZoom = zoom.floor();
    if (intZoom == _lastImageClusterIntZoom) return;
    _lastImageClusterIntZoom = intZoom;

    final results = _imageClusterIndex!.search(-180, -90, 180, 90, intZoom);

    final clusterBuf = StringBuffer();
    final imageBuf = StringBuffer();
    var clusterCount = 0;
    var imageCount = 0;

    for (final item in results) {
      item.handle(
        cluster: (cluster) {
          // クラスタ内の最新ファイル名を取得
          final newestName = _findNewestImageName(cluster);
          if (clusterCount > 0) clusterBuf.write(',');
          clusterBuf.write(
            '{"type":"Feature","geometry":{"type":"Point",'
            '"coordinates":[${cluster.longitude},${cluster.latitude}]},'
            '"properties":{"point_count":${cluster.childPointCount},'
            '"point_count_abbreviated":"${_abbreviate(cluster.childPointCount)}"'
            ',"name":${jsonEncode(newestName)}}}',
          );
          clusterCount++;
        },
        point: (point) {
          if (imageCount > 0) imageBuf.write(',');
          final raw = _rawImages[point.originalPoint.index];
          final name = raw.properties['name'] ?? '';
          final dir = raw.properties['direction'];
          final hasDir = dir != null;
          imageBuf.write(
            '{"type":"Feature","geometry":{"type":"Point",'
            '"coordinates":[${point.originalPoint.longitude},${point.originalPoint.latitude}]},'
            '"properties":{"name":${jsonEncode(name)},'
            '"has_direction":$hasDir'
            '${hasDir ? ',"direction":$dir' : ''}}}',
          );
          imageCount++;
        },
      );
    }

    _updateRaw(kImageClusters,
        '{"type":"FeatureCollection","features":[$clusterBuf]}');
    _updateRaw(kImages,
        '{"type":"FeatureCollection","features":[$imageBuf]}');
  }

  /// クラスタ内で最も taken_at が新しいポイントの name を返す
  String _findNewestImageName(LayerCluster cluster) {
    final immCluster = cluster as ImmutableLayerCluster;
    final leaves = _imageClusterIndex!.pointsWithin(
      immCluster.id,
      limit: cluster.childPointCount,
    );
    String newestName = '';
    int newestTs = -1;
    for (final leaf in leaves) {
      final props = _rawImages[leaf.index].properties;
      final ts = props['taken_at'] as int? ?? 0;
      if (ts > newestTs) {
        newestTs = ts;
        newestName = (props['name'] ?? '') as String;
      }
    }
    return newestName;
  }

  /// 数値を略記（1000 → 1k, 10000 → 10k）
  static String _abbreviate(int n) {
    if (n < 1000) return '$n';
    if (n < 10000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000).round()}k';
  }

  // --------------------------------------------------
  // 初期化
  // --------------------------------------------------

  /// StyleController にソースとレイヤを一括登録（二重実行防止）
  Future<void> initialize(ml.StyleController style) async {
    if (_initialized) return;

    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      _style = style;

      // アイコン画像を登録（4枚: 通常/選択 × 方向あり/なし）
      await _registerPhotoIcons(style);

      // 全ソースを空GeoJSONで登録
      for (final id in _allSourceIds) {
        await style.addSource(
          ml.GeoJsonSource(id: id, data: _emptyGeoJson),
        );
        _lastData[id] = _emptyGeoJson;
      }

      // デフォルトスタイルでレイヤを登録（basemap-layerの上に積む）
      await _addDefaultLayers(style);

      _initialized = true;
      AppLogger.debug('[MapSourceManager] initialized: ${_allSourceIds.length} sources, ${_allLayerIds.length} layers');
      _initCompleter!.complete();
    } catch (e, stack) {
      _initCompleter!.completeError(e, stack);
      rethrow;
    } finally {
      _initCompleter = null;
    }
  }

  /// 写真マーカーアイコンをMapLibreに登録（バッファ競合回避のため1枚ずつ生成・登録）
  Future<void> _registerPhotoIcons(ml.StyleController style) async {
    const normalColor = Colors.purple;
    const selColor = Colors.orange;
    const entries = <(String, Future<Uint8List> Function(Color))>[
      (_iconPhotoMarker, MapIconGenerator.generatePhotoMarker),
      (_iconPhotoMarkerSel, MapIconGenerator.generatePhotoMarkerSel),
      (_iconPhotoMarkerNoDir, MapIconGenerator.generatePhotoMarkerNoDir),
      (_iconPhotoMarkerNoDirSel, MapIconGenerator.generatePhotoMarkerNoDirSel),
    ];
    for (final (id, gen) in entries) {
      final color = id.contains('-sel') ? selColor : normalColor;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final bytes = await gen(color);
          await style.addImage(id, bytes);
          break;
        } catch (e) {
          AppLogger.debug('[MapSourceManager] icon registration retry ($id): $e');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    }
  }

  /// デフォルトのpaint設定でスタイルレイヤを追加
  Future<void> _addDefaultLayers(ml.StyleController style) async {
    // ポリゴン塗りつぶし（通常）
    await style.addLayer(ml.FillStyleLayer(
      id: kPolygonsFill,
      sourceId: kPolygons,
      paint: {
        'fill-color': '#4CAF50',
        'fill-opacity': 0.3,
      },
    ));
    // ポリゴン輪郭線（通常） — fill-outline-colorは1px固定のため別途LineStyleLayerで描画
    await style.addLayer(ml.LineStyleLayer(
      id: kPolygonsOutline,
      sourceId: kPolygons,
      paint: {
        'line-color': '#388E3C',
        'line-width': 2.0,
      },
    ));
    // ポリゴン塗りつぶし（選択）
    await style.addLayer(ml.FillStyleLayer(
      id: kPolygonsSelFill,
      sourceId: kPolygonsSel,
      paint: {
        'fill-color': '#FF0000',
        'fill-opacity': 0.5,
      },
    ));
    // ポリゴン輪郭線（選択）
    await style.addLayer(ml.LineStyleLayer(
      id: kPolygonsSelOutline,
      sourceId: kPolygonsSel,
      paint: {
        'line-color': '#FF0000',
        'line-width': 3.0,
      },
    ));
    // ライン（通常）
    await style.addLayer(ml.LineStyleLayer(
      id: kLinesLine,
      sourceId: kLines,
      paint: {
        'line-color': '#2196F3',
        'line-width': 2.0,
      },
    ));
    // ライン（選択）
    await style.addLayer(ml.LineStyleLayer(
      id: kLinesSelLine,
      sourceId: kLinesSel,
      paint: {
        'line-color': '#FF0000',
        'line-width': 4.0,
      },
    ));
    // GPS軌跡（ラインと同等の優先度）
    await style.addLayer(ml.LineStyleLayer(
      id: kGpsTrackLine,
      sourceId: kGpsTrack,
      paint: {
        'line-color': _colorToHex(MapColors.trackingRoute),
        'line-width': 3.0,
      },
    ));
    // ポリゴン頂点（通常）
    await style.addLayer(ml.CircleStyleLayer(
      id: kPolyVerticesCircle,
      sourceId: kPolyVertices,
      paint: {
        'circle-radius': 4.0,
        'circle-color': '#388E3C',
        'circle-stroke-width': 1.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // ポリゴン頂点（選択）
    await style.addLayer(ml.CircleStyleLayer(
      id: kPolyVerticesSelCircle,
      sourceId: kPolyVerticesSel,
      paint: {
        'circle-radius': 5.0,
        'circle-color': '#FF0000',
        'circle-stroke-width': 1.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // ライン頂点（通常）
    await style.addLayer(ml.CircleStyleLayer(
      id: kLineVerticesCircle,
      sourceId: kLineVertices,
      paint: {
        'circle-radius': 4.0,
        'circle-color': '#2196F3',
        'circle-stroke-width': 1.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // ライン頂点（選択）
    await style.addLayer(ml.CircleStyleLayer(
      id: kLineVerticesSelCircle,
      sourceId: kLineVerticesSel,
      paint: {
        'circle-radius': 5.0,
        'circle-color': '#FF0000',
        'circle-stroke-width': 1.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // クラスタ円（ポイント数に応じてサイズを段階的に変化、色はポイント設定に準拠）
    await style.addLayer(ml.CircleStyleLayer(
      id: kClusterCircle,
      sourceId: kClusters,
      paint: {
        'circle-color': '#2196F3',
        'circle-radius': <Object>[
          'step', ['get', 'point_count'],
          7.0,
          10, 9.0,
          50, 11.0,
          200, 14.0,
        ],
        'circle-stroke-width': 1.5,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // クラスタ数テキスト
    await style.addLayer(ml.SymbolStyleLayer(
      id: kClusterCount,
      sourceId: kClusters,
      layout: {
        'text-field': '{point_count_abbreviated}',
        'text-size': 10.0,
      },
      paint: {
        'text-color': '#000000',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 1.5,
      },
    ));
    // ポイント（通常） — CircleStyleLayerで高速描画
    await style.addLayer(ml.CircleStyleLayer(
      id: kPointsCircle,
      sourceId: kPoints,
      paint: {
        'circle-radius': 6.0,
        'circle-color': '#2196F3',
        'circle-stroke-width': 1.5,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // ポイント（選択）
    await style.addLayer(ml.CircleStyleLayer(
      id: kPointsSelCircle,
      sourceId: kPointsSel,
      paint: {
        'circle-radius': 9.0,
        'circle-color': '#FF0000',
        'circle-stroke-width': 2.0,
        'circle-stroke-color': '#FFFFFF',
      },
    ));

    // --- ImageNode レイヤ ---
    // ImageNodeクラスタ円
    await style.addLayer(ml.CircleStyleLayer(
      id: kImageClusterCircle,
      sourceId: kImageClusters,
      paint: {
        'circle-color': '#9C27B0',
        'circle-radius': <Object>[
          'step', ['get', 'point_count'],
          7.0, 10, 9.0, 50, 11.0, 200, 14.0,
        ],
        'circle-stroke-width': 1.5,
        'circle-stroke-color': '#FFFFFF',
      },
    ));
    // ImageNodeクラスタ数テキスト（円の中央）
    await style.addLayer(ml.SymbolStyleLayer(
      id: kImageClusterCount,
      sourceId: kImageClusters,
      layout: {
        'text-field': '{point_count_abbreviated}',
        'text-size': 10.0,
      },
      paint: {
        'text-color': '#000000',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 1.5,
      },
    ));
    // ImageNodeクラスタ最新ファイル名（円の右横）
    await style.addLayer(ml.SymbolStyleLayer(
      id: kImageClusterName,
      sourceId: kImageClusters,
      layout: {
        'text-field': <Object>['get', 'name'],
        'text-size': 10.0,
        'text-anchor': 'left',
        'text-offset': <Object>[1.2, 0],
        'text-max-width': 100.0,
      },
      paint: {
        'text-color': '#000000',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 1.5,
      },
    ));
    // ImageNode（通常）
    await style.addLayer(ml.SymbolStyleLayer(
      id: kImagesSymbol,
      sourceId: kImages,
      layout: {
        'icon-image': <Object>[
          'case', ['get', 'has_direction'],
          _iconPhotoMarker, _iconPhotoMarkerNoDir,
        ],
        'icon-rotate': <Object>['coalesce', ['get', 'direction'], 0],
        'icon-rotation-alignment': 'map',
        'icon-allow-overlap': true,
        'icon-size': 0.7,
        'text-field': <Object>['get', 'name'],
        'text-size': 12.0,
        'text-anchor': 'left',
        'text-offset': <Object>[1.0, 0],
        'text-max-width': 100.0,
        'text-optional': true,
      },
      paint: {
        'text-color': '#000000',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 1.5,
      },
    ));
    // ImageNode（選択）
    await style.addLayer(ml.SymbolStyleLayer(
      id: kImagesSelSymbol,
      sourceId: kImagesSel,
      layout: {
        'icon-image': <Object>[
          'case', ['get', 'has_direction'],
          _iconPhotoMarkerSel, _iconPhotoMarkerNoDirSel,
        ],
        'icon-rotate': <Object>['coalesce', ['get', 'direction'], 0],
        'icon-rotation-alignment': 'map',
        'icon-allow-overlap': true,
        'icon-size': 1.0,
        'text-field': <Object>['get', 'name'],
        'text-size': 13.0,
        'text-anchor': 'left',
        'text-offset': <Object>[1.0, 0],
        'text-max-width': 100.0,
        'text-optional': true,
      },
      paint: {
        'text-color': '#FF9800',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 1.5,
      },
    ));
  }

  // --------------------------------------------------
  // データ更新メソッド（変更時のみネイティブに送信）
  // --------------------------------------------------

  /// GeoJSONソースを更新（変更がなければスキップ）
  ///
  /// WebView環境では maplibre_webview の WebSocket バイナリ転送が
  /// 非ASCII文字を破損する(.codeUnits → setUint8 で上位バイト欠落)ため、
  /// callAsyncJavaScript (Platform Channel) 経由で直接更新する。
  void _updateRaw(String sourceId, String geoJson) {
    if (!_initialized || _style == null) return;
    if (_lastData[sourceId] == geoJson) return;
    _lastData[sourceId] = geoJson;
    final s = _style;
    if (s is webview_style.StyleControllerWebView) {
      // GeoJSON は有効な JS オブジェクトリテラルでもあるので直接埋め込み
      s.webViewController.callAsyncJavaScript(
        functionBody:
            'const src = window.map.getSource("$sourceId");'
            'if (src) src.setData($geoJson);',
      );
    } else {
      s!.updateGeoJsonSource(id: sourceId, data: geoJson);
    }
  }

  /// Feature リストからGeoJSONを生成して更新
  /// ポイント(kPoints)の場合はクラスタインデックスも更新
  Future<void> updateFeatures<T extends geo.Geometry>(
    String sourceId,
    List<geo.Feature<T>> features,
  ) async {
    if (!_initialized) return;

    // kPointsの場合: クラスタリング用にrawデータを保持
    if (sourceId == kPoints) {
      _rawPoints = features.cast<geo.Feature<geo.Point>>();
      if (_clusterEnabled) {
        _rebuildClusterIndex();
        return;
      }
    }

    // kImagesの場合: ImageNodeクラスタリング用にrawデータを保持
    if (sourceId == kImages) {
      _rawImages = features.cast<geo.Feature<geo.Point>>();
      if (_clusterEnabled) {
        _rebuildImageClusterIndex();
        return;
      }
    }

    if (features.isEmpty) {
      _updateRaw(sourceId, _emptyGeoJson);
      return;
    }
    final geoJson = features.length > _isolateThreshold
        ? await _serializeInIsolate(features)
        : geo.FeatureCollection(features).toText();
    _updateRaw(sourceId, geoJson);
  }

  /// GPS軌跡を更新
  void updateGpsTrack(List<geo.Position> points) {
    if (!_initialized || points.length < 2) {
      _updateRaw(kGpsTrack, _emptyGeoJson);
      return;
    }
    final feature = geo.Feature(
      geometry: geo.LineString.from(points),
    );
    final geoJson = geo.FeatureCollection([feature]).toText();
    _updateRaw(kGpsTrack, geoJson);
  }

  // --------------------------------------------------
  // スタイル更新（設定変更時にレイヤを再構築）
  // --------------------------------------------------

  /// ユーザー設定のスタイルをレイヤ再登録で反映
  /// removeLayer+addLayerは全プラットフォームで動作する安全な方式
  Future<void> updateLayerStyles({
    required Color polygonFillColor,
    required double polygonFillOpacity,
    required Color polygonOutlineColor,
    required double polygonOutlineOpacity,
    required double polygonBorderWidth,
    required Color lineColor,
    required double lineWidth,
    required Color pointColor,
    required double pointSize,
    required Color selectedColor,
    required double selectedMultiplier,
    required bool lineVertexEnabled,
    required double lineVertexSizeFactor,
    required bool polygonVertexEnabled,
    required double polygonVertexSizeFactor,
  }) async {
    if (!_initialized || _style == null) return;
    final s = _style!;

    final fillHex = _colorToHex(polygonFillColor);
    final outlineHex = _colorToHex(polygonOutlineColor);
    final selHex = _colorToHex(selectedColor);
    final lineHex = _colorToHex(lineColor);
    final pointHex = _colorToHex(pointColor);

    // 頂点半径の計算
    final polyVR = polygonVertexEnabled
        ? (polygonBorderWidth * polygonVertexSizeFactor / 2).clamp(2.0, 24.0)
        : 0.0;
    final polyVSelR = polygonVertexEnabled
        ? (polygonBorderWidth * selectedMultiplier * polygonVertexSizeFactor / 2).clamp(2.0, 24.0)
        : 0.0;
    final lineVR = lineVertexEnabled
        ? (lineWidth * lineVertexSizeFactor / 2).clamp(2.0, 24.0)
        : 0.0;
    final lineVSelR = lineVertexEnabled
        ? (lineWidth * selectedMultiplier * lineVertexSizeFactor / 2).clamp(2.0, 24.0)
        : 0.0;

    final clusterRadius = <Object>['step', ['get', 'point_count'], 7.0, 10, 9.0, 50, 11.0, 200, 14.0];

    if (s is webview_style.StyleControllerWebView) {
      await _webViewBatchSetPaint(
        s,
        fillHex: fillHex, outlineHex: outlineHex, selHex: selHex,
        lineHex: lineHex, pointHex: pointHex,
        polygonFillOpacity: polygonFillOpacity,
        polygonOutlineOpacity: polygonOutlineOpacity,
        polygonBorderWidth: polygonBorderWidth,
        lineWidth: lineWidth, pointSize: pointSize,
        selectedMultiplier: selectedMultiplier,
        polygonOutlineColor: polygonOutlineColor,
        polyVR: polyVR, polyVSelR: polyVSelR,
        lineVR: lineVR, lineVSelR: lineVSelR,
        clusterRadius: clusterRadius,
      );
    } else {
      await _removeAndReaddLayers(
        s,
        fillHex: fillHex, outlineHex: outlineHex, selHex: selHex,
        lineHex: lineHex, pointHex: pointHex,
        polygonFillOpacity: polygonFillOpacity,
        polygonOutlineOpacity: polygonOutlineOpacity,
        polygonBorderWidth: polygonBorderWidth,
        lineWidth: lineWidth, pointSize: pointSize,
        selectedMultiplier: selectedMultiplier,
        polygonOutlineColor: polygonOutlineColor,
        polyVR: polyVR, polyVSelR: polyVSelR,
        lineVR: lineVR, lineVSelR: lineVSelR,
        clusterRadius: clusterRadius,
      );
    }

    AppLogger.debug('[MapSourceManager] layer styles updated');
  }

  /// Windows/macOS WebView向け: setPaintPropertyで直接ペイント属性を更新
  /// removeLayer+addLayerと違い、レイヤー削除時のE_INVALIDARGエラーを回避
  Future<void> _webViewBatchSetPaint(
    webview_style.StyleControllerWebView s, {
    required String fillHex,
    required String outlineHex,
    required String selHex,
    required String lineHex,
    required String pointHex,
    required double polygonFillOpacity,
    required double polygonOutlineOpacity,
    required double polygonBorderWidth,
    required double lineWidth,
    required double pointSize,
    required double selectedMultiplier,
    required Color polygonOutlineColor,
    required double polyVR,
    required double polyVSelR,
    required double lineVR,
    required double lineVSelR,
    required List<Object> clusterRadius,
  }) async {
    final outlineColorHex = _colorToHex(polygonOutlineColor);
    final clusterRadiusJson = jsonEncode(clusterRadius);

    final js = StringBuffer('const m = window.map;\n');

    void sp(String layerId, String prop, Object value) {
      final v = value is String ? '"$value"' : '$value';
      js.writeln('m.setPaintProperty("$layerId","$prop",$v);');
    }

    void spExpr(String layerId, String prop, String jsonExpr) {
      js.writeln('m.setPaintProperty("$layerId","$prop",$jsonExpr);');
    }

    sp(kPolygonsFill, 'fill-color', fillHex);
    sp(kPolygonsFill, 'fill-opacity', polygonFillOpacity);

    sp(kPolygonsOutline, 'line-color', outlineHex);
    sp(kPolygonsOutline, 'line-opacity', polygonOutlineOpacity);
    sp(kPolygonsOutline, 'line-width', polygonBorderWidth);

    sp(kPolygonsSelFill, 'fill-color', selHex);

    sp(kPolygonsSelOutline, 'line-color', selHex);

    sp(kLinesLine, 'line-color', lineHex);
    sp(kLinesLine, 'line-width', lineWidth);

    sp(kLinesSelLine, 'line-color', selHex);
    sp(kLinesSelLine, 'line-width', lineWidth * selectedMultiplier);

    sp(kPolyVerticesCircle, 'circle-radius', polyVR);
    sp(kPolyVerticesCircle, 'circle-color', outlineColorHex);

    sp(kPolyVerticesSelCircle, 'circle-radius', polyVSelR);
    sp(kPolyVerticesSelCircle, 'circle-color', selHex);

    sp(kLineVerticesCircle, 'circle-radius', lineVR);
    sp(kLineVerticesCircle, 'circle-color', lineHex);

    sp(kLineVerticesSelCircle, 'circle-radius', lineVSelR);
    sp(kLineVerticesSelCircle, 'circle-color', selHex);

    spExpr(kClusterCircle, 'circle-color', '"$pointHex"');
    spExpr(kClusterCircle, 'circle-radius', clusterRadiusJson);

    sp(kPointsCircle, 'circle-radius', pointSize);
    sp(kPointsCircle, 'circle-color', pointHex);

    sp(kPointsSelCircle, 'circle-radius', pointSize * selectedMultiplier);
    sp(kPointsSelCircle, 'circle-color', selHex);

    await s.webViewController.callAsyncJavaScript(
      functionBody: js.toString(),
    );
  }

  /// Android/iOS向け: 全レイヤーを削除→再追加でスタイル更新
  Future<void> _removeAndReaddLayers(
    ml.StyleController s, {
    required String fillHex,
    required String outlineHex,
    required String selHex,
    required String lineHex,
    required String pointHex,
    required double polygonFillOpacity,
    required double polygonOutlineOpacity,
    required double polygonBorderWidth,
    required double lineWidth,
    required double pointSize,
    required double selectedMultiplier,
    required Color polygonOutlineColor,
    required double polyVR,
    required double polyVSelR,
    required double lineVR,
    required double lineVSelR,
    required List<Object> clusterRadius,
  }) async {
    for (final id in _allLayerIds.reversed) {
      try { await s.removeLayer(id); } catch (_) {}
    }

    await s.addLayer(ml.FillStyleLayer(id: kPolygonsFill, sourceId: kPolygons,
      paint: {'fill-color': fillHex, 'fill-opacity': polygonFillOpacity}));
    await s.addLayer(ml.LineStyleLayer(id: kPolygonsOutline, sourceId: kPolygons,
      paint: {'line-color': outlineHex, 'line-opacity': polygonOutlineOpacity, 'line-width': polygonBorderWidth}));
    await s.addLayer(ml.FillStyleLayer(id: kPolygonsSelFill, sourceId: kPolygonsSel,
      paint: {'fill-color': selHex, 'fill-opacity': 0.5}));
    await s.addLayer(ml.LineStyleLayer(id: kPolygonsSelOutline, sourceId: kPolygonsSel,
      paint: {'line-color': selHex, 'line-width': 3.0}));
    await s.addLayer(ml.LineStyleLayer(id: kLinesLine, sourceId: kLines,
      paint: {'line-color': lineHex, 'line-width': lineWidth}));
    await s.addLayer(ml.LineStyleLayer(id: kLinesSelLine, sourceId: kLinesSel,
      paint: {'line-color': selHex, 'line-width': lineWidth * selectedMultiplier}));
    await s.addLayer(ml.LineStyleLayer(id: kGpsTrackLine, sourceId: kGpsTrack,
      paint: {'line-color': _colorToHex(MapColors.trackingRoute), 'line-width': 3.0}));
    await s.addLayer(ml.CircleStyleLayer(id: kPolyVerticesCircle, sourceId: kPolyVertices,
      paint: {'circle-radius': polyVR, 'circle-color': _colorToHex(polygonOutlineColor), 'circle-stroke-width': 1.0, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.CircleStyleLayer(id: kPolyVerticesSelCircle, sourceId: kPolyVerticesSel,
      paint: {'circle-radius': polyVSelR, 'circle-color': selHex, 'circle-stroke-width': 1.0, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.CircleStyleLayer(id: kLineVerticesCircle, sourceId: kLineVertices,
      paint: {'circle-radius': lineVR, 'circle-color': lineHex, 'circle-stroke-width': 1.0, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.CircleStyleLayer(id: kLineVerticesSelCircle, sourceId: kLineVerticesSel,
      paint: {'circle-radius': lineVSelR, 'circle-color': selHex, 'circle-stroke-width': 1.0, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.CircleStyleLayer(id: kClusterCircle, sourceId: kClusters,
      paint: {'circle-color': pointHex, 'circle-radius': clusterRadius, 'circle-stroke-width': 1.5, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.SymbolStyleLayer(id: kClusterCount, sourceId: kClusters,
      layout: {'text-field': '{point_count_abbreviated}', 'text-size': 10.0},
      paint: {'text-color': '#000000', 'text-halo-color': '#FFFFFF', 'text-halo-width': 1.5}));
    await s.addLayer(ml.CircleStyleLayer(id: kPointsCircle, sourceId: kPoints,
      paint: {'circle-radius': pointSize, 'circle-color': pointHex, 'circle-stroke-width': 1.5, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.CircleStyleLayer(id: kPointsSelCircle, sourceId: kPointsSel,
      paint: {'circle-radius': pointSize * selectedMultiplier, 'circle-color': selHex, 'circle-stroke-width': 2.0, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.CircleStyleLayer(id: kImageClusterCircle, sourceId: kImageClusters,
      paint: {'circle-color': '#9C27B0', 'circle-radius': clusterRadius, 'circle-stroke-width': 1.5, 'circle-stroke-color': '#FFFFFF'}));
    await s.addLayer(ml.SymbolStyleLayer(id: kImageClusterCount, sourceId: kImageClusters,
      layout: {'text-field': '{point_count_abbreviated}', 'text-size': 10.0},
      paint: {'text-color': '#000000', 'text-halo-color': '#FFFFFF', 'text-halo-width': 1.5}));
    await s.addLayer(ml.SymbolStyleLayer(id: kImageClusterName, sourceId: kImageClusters,
      layout: {'text-field': <Object>['get', 'name'], 'text-size': 10.0, 'text-anchor': 'left', 'text-offset': <Object>[1.2, 0], 'text-max-width': 100.0},
      paint: {'text-color': '#000000', 'text-halo-color': '#FFFFFF', 'text-halo-width': 1.5}));
    await s.addLayer(ml.SymbolStyleLayer(id: kImagesSymbol, sourceId: kImages,
      layout: {
        'icon-image': <Object>['case', ['get', 'has_direction'], _iconPhotoMarker, _iconPhotoMarkerNoDir],
        'icon-rotate': <Object>['coalesce', ['get', 'direction'], 0],
        'icon-rotation-alignment': 'map', 'icon-allow-overlap': true, 'icon-size': 0.7,
        'text-field': <Object>['get', 'name'], 'text-size': 12.0,
        'text-anchor': 'left', 'text-offset': <Object>[1.0, 0], 'text-max-width': 100.0, 'text-optional': true,
      },
      paint: {'text-color': '#000000', 'text-halo-color': '#FFFFFF', 'text-halo-width': 1.5}));
    await s.addLayer(ml.SymbolStyleLayer(id: kImagesSelSymbol, sourceId: kImagesSel,
      layout: {
        'icon-image': <Object>['case', ['get', 'has_direction'], _iconPhotoMarkerSel, _iconPhotoMarkerNoDirSel],
        'icon-rotate': <Object>['coalesce', ['get', 'direction'], 0],
        'icon-rotation-alignment': 'map', 'icon-allow-overlap': true, 'icon-size': 1.0,
        'text-field': <Object>['get', 'name'], 'text-size': 13.0,
        'text-anchor': 'left', 'text-offset': <Object>[1.0, 0], 'text-max-width': 100.0, 'text-optional': true,
      },
      paint: {'text-color': '#FF9800', 'text-halo-color': '#FFFFFF', 'text-halo-width': 1.5}));
  }

  /// 全ソースをクリア
  void clearAll() {
    for (final id in _allSourceIds) {
      _updateRaw(id, _emptyGeoJson);
    }
  }

  // --------------------------------------------------
  // オーバーレイ画像管理
  // --------------------------------------------------

  /// 管理中のオーバーレイ画像ソースID
  final Set<String> _overlaySourceIds = {};

  /// Native パスの排他制御: ソースIDごとの処理中フラグ
  final Map<String, bool> _overlayUpdateLocks = {};

  /// Native パスの pending キュー: 処理中に来た最新リクエストを保持
  final Map<String, _OverlayUpdateRequest> _pendingOverlayUpdates = {};

  /// オーバーレイ画像を追加
  /// basemap-layerの直上、k-polygons-fillの直下に配置
  Future<void> addOverlayImage({
    required String sourceId,
    required String layerId,
    required String imageUrl,
    required ml.LngLatQuad coordinates,
    required double opacity,
  }) async {
    final s = _style;
    if (s == null) return;

    try {
      await s.addSource(ml.ImageSource(
        id: sourceId,
        url: imageUrl,
        coordinates: coordinates,
      ));
      await s.addLayer(
        ml.RasterStyleLayer(id: layerId, sourceId: sourceId),
        belowLayerId: kPolygonsFill,
      );
      _overlaySourceIds.add(sourceId);

      // 不透明度を設定
      _setOverlayPaintProperty(layerId, 'raster-opacity', opacity);

      AppLogger.debug('[MapSourceManager] addOverlayImage: $sourceId');
    } catch (e) {
      AppLogger.debug('[MapSourceManager] addOverlayImage error: $e');
    }
  }

  /// オーバーレイ画像の座標を更新
  ///
  /// WebView: JS経由でsetCoordinates呼び出し（同期的、競合なし）
  /// Native: remove+addが非同期のため、排他制御+最新値drain loopで競合を防止
  Future<void> updateOverlayCoordinates(
    String sourceId,
    ml.LngLatQuad coords, {
    String? imageUrl,
    String? layerId,
    double opacity = 1.0,
  }) async {
    final s = _style;
    if (s == null) return;

    if (s is webview_style.StyleControllerWebView) {
      // WebView: JS経由でsetCoordinates呼び出し（同期的）
      final tl = coords.topLeft;
      final tr = coords.topRight;
      final br = coords.bottomRight;
      final bl = coords.bottomLeft;
      s.webViewController.callAsyncJavaScript(
        functionBody:
            'const src = window.map.getSource("$sourceId");'
            'if (src) src.setCoordinates(['
            '  [${tl.lon},${tl.lat}],[${tr.lon},${tr.lat}],'
            '  [${br.lon},${br.lat}],[${bl.lon},${bl.lat}]]);',
      );
    } else if (imageUrl != null && layerId != null) {
      // Native: 排他制御付き drain loop で競合を防止
      // pending に最新値を保存（前の pending は上書き＝最新値のみ保持）
      _pendingOverlayUpdates[sourceId] = _OverlayUpdateRequest(
        coords: coords,
        imageUrl: imageUrl,
        layerId: layerId,
        opacity: opacity,
      );

      // 既に drain loop が動いていればスキップ（最新値は pending に保存済み）
      if (_overlayUpdateLocks[sourceId] == true) return;
      _overlayUpdateLocks[sourceId] = true;

      try {
        // pending が空になるまで最新値を消化し続ける
        while (_pendingOverlayUpdates.containsKey(sourceId)) {
          final req = _pendingOverlayUpdates.remove(sourceId)!;
          try {
            await s.removeLayer(req.layerId);
            await s.removeSource(sourceId);
          } catch (_) {
            // 初回やすでに削除済みの場合は無視
          }
          // drain loop 中に新しいリクエストが来ていたら、add をスキップして
          // 次のイテレーションで最新値を使う（無駄な add を避ける）
          if (_pendingOverlayUpdates.containsKey(sourceId)) continue;
          try {
            await s.addSource(ml.ImageSource(
              id: sourceId,
              url: req.imageUrl,
              coordinates: req.coords,
            ));
            await s.addLayer(
              ml.RasterStyleLayer(id: req.layerId, sourceId: sourceId),
              belowLayerId: kPolygonsFill,
            );
            _overlaySourceIds.add(sourceId);
            _setOverlayPaintProperty(
              req.layerId, 'raster-opacity', req.opacity,
            );
          } catch (e) {
            AppLogger.debug(
              '[MapSourceManager] updateOverlayCoordinates native error: $e',
            );
          }
        }
      } finally {
        _overlayUpdateLocks[sourceId] = false;
      }
    }
  }

  /// オーバーレイ画像の不透明度を更新
  void updateOverlayOpacity(String layerId, double opacity) {
    _setOverlayPaintProperty(layerId, 'raster-opacity', opacity);
  }

  /// オーバーレイ画像を削除
  Future<void> removeOverlayImage(String sourceId, String layerId) async {
    final s = _style;
    if (s == null) return;
    try {
      await s.removeLayer(layerId);
    } catch (_) {}
    try {
      await s.removeSource(sourceId);
    } catch (_) {}
    _overlaySourceIds.remove(sourceId);
    AppLogger.debug('[MapSourceManager] removeOverlayImage: $sourceId');
  }

  /// 管理中のオーバーレイソースIDを取得
  Set<String> get activeOverlaySourceIds => Set.unmodifiable(_overlaySourceIds);

  /// オーバーレイのpaintプロパティを設定
  void _setOverlayPaintProperty(String layerId, String property, dynamic value) {
    final s = _style;
    if (s == null) return;

    if (s is webview_style.StyleControllerWebView) {
      final valueStr = value is String ? '"$value"' : value.toString();
      s.webViewController.callAsyncJavaScript(
        functionBody:
            'window.map.setPaintProperty("$layerId","$property",$valueStr);',
      );
    }
  }

  // --------------------------------------------------
  // ユーティリティ
  // --------------------------------------------------

  /// Color → MapLibre paint用 #RRGGBB 文字列
  static String _colorToHex(Color c) {
    final r = (c.r * 255.0).round() & 0xff;
    final g = (c.g * 255.0).round() & 0xff;
    final b = (c.b * 255.0).round() & 0xff;
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  /// Isolateでのシリアライズ（大量フィーチャ用）
  static Future<String> _serializeInIsolate<T extends geo.Geometry>(
    List<geo.Feature<T>> features,
  ) async {
    return Isolate.run(
      () => geo.FeatureCollection(features).toText(),
    );
  }
}

/// supercluster用ポイントラッパー（元フィーチャのインデックスと座標を保持）
class _IndexedPoint {
  final int index;
  final double longitude;
  final double latitude;

  const _IndexedPoint({
    required this.index,
    required this.longitude,
    required this.latitude,
  });
}

/// オーバーレイ座標更新リクエスト（drain loop の pending キュー用）
class _OverlayUpdateRequest {
  final ml.LngLatQuad coords;
  final String imageUrl;
  final String layerId;
  final double opacity;

  const _OverlayUpdateRequest({
    required this.coords,
    required this.imageUrl,
    required this.layerId,
    required this.opacity,
  });
}
