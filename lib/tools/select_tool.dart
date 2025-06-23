// lib/tools/select_tool.dart
// オブジェクト選択ツール
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // PointerScrollEvent用
import 'map_tool.dart';
import 'package:latlong2/latlong.dart';
import '../utils/global_config.dart';
import '../utils/feature_calc_utils.dart';
import '../models/layer_tree_node.dart';
import 'dart:math' as math;

/// オブジェクト選択ツール
class SelectTool extends MapTool {
  @override
  String get name => 'Select';

  @override
  IconData get icon => Icons.select_all;

  Offset? _startPosition;
  int _pointerCount = 0;
  Offset? _dragStart;
  Offset? _dragEnd;
  List<Offset> _lassoPoints = [];
  List<Offset> get lassoPoints => _lassoPoints;

  /// ズーム率から選択判定用range(m)を計算
  double _calcSelectRange(dynamic mapState) {
    // mapStateは_KMapsHomePageState想定
    try {
      final mapController = mapState.mapController;
      final zoom = mapController.zoom;
      // 例: ズーム16で20m, 1ズーム下がるごとに2倍
      // 公式: range = base * pow(2, 16 - zoom)
      const double base = 20.0; // ズーム16で20m
      final range = base * math.pow(2, 16 - zoom);
      return range;
    } catch (e) {
      return 30.0; // 取得失敗時は30m
    }
  }

  /// 指定座標・範囲でfeatureを選択する（PenTool等からも利用可・最適化）
  static Future<void> selectFeatureAtLatLng({
    required LatLng tapLatLng,
    required dynamic mapState,
    double? range,
  }) async {
    print('[DEBUG] SelectTool.selectFeatureAtLatLng: selecting at $tapLatLng');

    final layer = GlobalConfig.instance.selectedLayerNode;
    if (layer == null) {
      print('[DEBUG] SelectTool.selectFeatureAtLatLng: no layer selected');
      return;
    }

    String featureType;
    if (layer is PointLayerNode) {
      featureType = 'point';
    } else if (layer is LineLayerNode) {
      featureType = 'line';
    } else if (layer is PolygonLayerNode) {
      featureType = 'polygon';
    } else {
      print('[DEBUG] SelectTool.selectFeatureAtLatLng: unsupported layer type');
      return;
    }

    // 最適化: LayerNodeのchildrenから直接FeatureNodeを取得（高速化）
    final layerFeatures = layer.children.whereType<FeatureNode>().toList();
    List<FeatureNode> features;

    if (layerFeatures.isNotEmpty) {
      // childrenにFeatureNodeがある場合は直接使用（高速）
      features = layerFeatures;
      print(
        '[DEBUG] SelectTool.selectFeatureAtLatLng: using ${features.length} features from children',
      );
    } else {
      // childrenが空の場合のみDBから読み込み（初回読み込み時）
      final dbFeatures = await layer.features;
      features = dbFeatures.whereType<FeatureNode>().toList();
      print(
        '[DEBUG] SelectTool.selectFeatureAtLatLng: loaded ${features.length} features from DB',
      );
      // DBから読み込んだFeatureNodeをlayerのchildrenに追加
      for (final feature in features) {
        layer.addChild(feature);
      }
    }

    if (features.isEmpty) {
      print('[DEBUG] SelectTool.selectFeatureAtLatLng: no features found');
      GlobalConfig.instance.selectedFeatures = [];
      mapState.setState(() {});
      return;
    }

    // ズーム率からrange(m)を計算（未指定時は通常の範囲）
    final double selectRange =
        range ?? SelectTool()._calcSelectRange(mapState) * 3;
    print(
      '[DEBUG] SelectTool.selectFeatureAtLatLng: search range = ${selectRange}m',
    );

    final result = FeatureSearch.findNearestFeature(
      tapLatLng,
      features,
      featureType,
      selectRange,
    );

    if (result == null) {
      print(
        '[DEBUG] SelectTool.selectFeatureAtLatLng: no feature found in range',
      );
      GlobalConfig.instance.selectedFeatures = [];
      mapState.setState(() {});
      return;
    }

    print(
      '[DEBUG] SelectTool.selectFeatureAtLatLng: selected feature ${result.key.name}',
    );
    GlobalConfig.instance.selectedFeatures = [result.key];
    mapState.setState(() {});
  }

  /// タップイベント
  @override
  void onTap(TapUpDetails details, dynamic mapState) async {
    if (mapState == null) return;
    LatLng? tapLatLng;
    try {
      tapLatLng = mapState.offsetToLatLng(details.localPosition);
    } catch (e) {
      return;
    }
    if (tapLatLng == null) return;
    // staticメソッドで共通化
    await selectFeatureAtLatLng(tapLatLng: tapLatLng, mapState: mapState);
  }

  /// スケール開始イベント
  /// 1本指: 投げ縄選択, 2本指: パン
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    if (mapState == null) return;
    // 中ボタンドラッグ中は何もしない（意図しない選択を防ぐ）
    if (GlobalConfig.instance.panTool.isMiddleButtonDragging) return;
    _pointerCount = details.pointerCount ?? 1;
    if (_pointerCount == 2) {
      GlobalConfig.instance.panTool.onScaleStart(details, mapState);
      return;
    }
    if (_pointerCount == 1) {
      _lassoPoints = [details.localFocalPoint];
      mapState.setState(() {});
    }
  }

  /// スケール更新イベント
  /// 1本指: 投げ縄選択, 2本指: パン
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    if (mapState == null) return;
    // 中ボタンドラッグ中は何もしない（意図しない選択を防ぐ）
    if (GlobalConfig.instance.panTool.isMiddleButtonDragging) return;
    if (_pointerCount == 2) {
      GlobalConfig.instance.panTool.onScaleUpdate(details, mapState);
      return;
    }
    if (_pointerCount == 1) {
      _lassoPoints.add(details.localFocalPoint);
      mapState.setState(() {});
    }
  }

  /// スケール終了イベント
  /// 1本指: 投げ縄選択, 2本指: パン
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) async {
    if (mapState == null) return;
    // 中ボタンドラッグ中は何もしない（意図しない選択を防ぐ）
    if (GlobalConfig.instance.panTool.isMiddleButtonDragging) return;
    if (_pointerCount == 2) {
      GlobalConfig.instance.panTool.onScaleEnd(details, mapState);
      _pointerCount = 0;
      return;
    }
    if (_pointerCount == 1 && _lassoPoints.length >= 3) {
      // 投げ縄点列をLatLngに変換
      final lassoPolygon =
          _lassoPoints
              .map((offset) => mapState.offsetToLatLng(offset))
              .toList();
      final lassoPolygonLatLng = List<LatLng>.from(lassoPolygon);
      // 閉じる
      if (lassoPolygonLatLng.first != lassoPolygonLatLng.last) {
        lassoPolygonLatLng.add(lassoPolygonLatLng.first);
      }
      final layer = GlobalConfig.instance.selectedLayerNode;
      if (layer != null) {
        // 最適化: LayerNodeのchildrenから直接FeatureNodeを取得
        final layerFeatures = layer.children.whereType<FeatureNode>().toList();
        List<FeatureNode> features;

        if (layerFeatures.isNotEmpty) {
          features = layerFeatures;
          print(
            '[DEBUG] SelectTool.onScaleEnd: using ${features.length} features from children',
          );
        } else {
          final dbFeatures = await layer.features;
          features = dbFeatures.whereType<FeatureNode>().toList();
          print(
            '[DEBUG] SelectTool.onScaleEnd: loaded ${features.length} features from DB',
          );
          for (final feature in features) {
            layer.addChild(feature);
          }
        }

        final selected =
            features.where((f) {
              // 点: centroidが投げ縄内
              if (f is PointFeatureNode) {
                return GeometryCalc.pointInPolygonWithHoles(f.centroid, [
                  lassoPolygonLatLng,
                ]);
              }
              // 線: いずれかの頂点が投げ縄内
              if (f is LineFeatureNode) {
                final line = f.geometry as List<LatLng>;
                return line.any(
                  (pt) => GeometryCalc.pointInPolygonWithHoles(pt, [
                    lassoPolygonLatLng,
                  ]),
                );
              }
              // 面: いずれかの頂点が投げ縄内 or 投げ縄がポリゴン内
              if (f is PolygonFeatureNode) {
                final poly = f.geometry as List<List<LatLng>>;
                return poly
                        .expand((ring) => ring)
                        .any(
                          (pt) => GeometryCalc.pointInPolygonWithHoles(pt, [
                            lassoPolygonLatLng,
                          ]),
                        ) ||
                    lassoPolygonLatLng.any(
                      (pt) => GeometryCalc.pointInPolygonWithHoles(pt, poly),
                    );
              }
              return false;
            }).toList();
        GlobalConfig.instance.selectedFeatures = selected;
      }
      _lassoPoints.clear();
      mapState.setState(() {});
    }
    _pointerCount = 0;
  }

  /// マウスホイールスクロールイベント（ズーム機能）
  /// PanToolの統一処理を呼び出し
  @override
  void onPointerSignal(PointerEvent event, dynamic mapState) {
    if (event is PointerScrollEvent) {
      // PanToolの統一されたマウスホイールズーム処理を使用
      GlobalConfig.instance.panTool.handleMouseWheelZoom(event, mapState);
    }
  }

  /// 中ボタンドラッグイベント - PanToolに委譲
  @override
  void onMiddleButtonDown(PointerDownEvent event, dynamic mapState) {
    GlobalConfig.instance.panTool.onMiddleButtonDown(event, mapState);
  }

  @override
  void onMiddleButtonMove(PointerMoveEvent event, dynamic mapState) {
    GlobalConfig.instance.panTool.onMiddleButtonMove(event, mapState);
  }

  @override
  void onMiddleButtonUp(PointerUpEvent event, dynamic mapState) {
    GlobalConfig.instance.panTool.onMiddleButtonUp(event, mapState);
  }
}
