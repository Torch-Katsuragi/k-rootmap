// lib/tools/pen_tool.dart
// ペンツール（レイヤ描画）
import 'package:flutter/widgets.dart';
import 'map_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../utils/global_config.dart';
import '../models/layer_tree_node.dart';
import 'package:latlong2/latlong.dart';
import 'pan_tool.dart'; // てのひらツールを利用
import 'select_tool.dart';

/// ペンツール（レイヤ描画）
class PenTool extends MapTool {
  /// てのひらツールのグローバルインスタンス（2本指パン・回転用）
  PanTool get panTool => GlobalConfig.instance.panTool;

  @override
  String get name => 'Pen';

  @override
  IconData get icon => Icons.edit;

  List<Offset> _currentPath = [];

  /// 線の描画点列
  final List<LatLng> drawingLine = [];

  /// ポリゴンの描画点列
  final List<LatLng> drawingPolygon = [];

  Offset? _lastFingerPosition;
  bool _isDrawing = false;
  int _pointerCount = 0;
  LatLng? _pointPreview;

  /// プレビュー用の点座標（外部参照用getter）
  LatLng? get pointPreview => _pointPreview;

  /// タップイベント
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    // フロートボタン押下時は消しゴム動作
    if (GlobalConfig.instance.isFabActive) {
      final latlng = mapState.offsetToLatLng(details.localPosition);
      SelectTool.selectFeatureAtLatLng(tapLatLng: latlng, mapState: mapState);
      // 選択されたfeatureを消去
      for (final f in List.from(GlobalConfig.instance.selectedFeatures)) {
        f.dispose();
      }
      GlobalConfig.instance.selectedFeatures = [];
      mapState.setState(() {});
      return;
    }
    // 通常は描画
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return;
    if (!selected.isVisibleRecursive()) {
      // 警告ポップアップ
      final context = mapState.context;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('このレイヤは不可視のため編集できません')));
      return;
    }
    final latlng = mapState.offsetToLatLng(details.localPosition);
    if (selected is PointLayerNode) {
      PointFeatureNode.createIn(selected, latlng, '', '');
      mapState.setState(() {});
    } else if (selected is LineLayerNode) {
      addDrawingLinePoint(latlng, mapState.setState);
    } else if (selected is PolygonLayerNode) {
      addDrawingPolygonPoint(latlng, mapState.setState);
    }
  }

  /// スケール開始イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null || !selected.isVisibleRecursive()) {
      if (selected != null && !selected.isVisibleRecursive()) {
        final context = mapState.context;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('このレイヤは不可視のため編集できません')));
      }
      return;
    }
    if (_pointerCount == 2) {
      //2本指を離すとき高確率で残った方の指でdetails.pointerCount=1としてonscalestartが呼ばれるので、その場合は一回スキップ(0にするとupdateとendで何もしなくなる)
      _pointerCount = 0;
      return;
    }
    _pointerCount = details.pointerCount ?? 1;
    if (_pointerCount == 2) {
      panTool.onScaleStart(details, mapState);
      return;
    }
    if (_pointerCount == 1) {
      if (GlobalConfig.instance.isFabActive) {
        return;
      }
      // Pointerバッファがあれば最初に反映
      if (pointerBuffer.isNotEmpty) {
        if (selected is LineLayerNode) {
          drawingLine.clear();
          for (final offset in pointerBuffer) {
            final latlng = mapState.offsetToLatLng(offset);
            addDrawingLinePoint(latlng, mapState.setState);
          }
        } else if (selected is PolygonLayerNode) {
          drawingPolygon.clear();
          for (final offset in pointerBuffer) {
            final latlng = mapState.offsetToLatLng(offset);
            addDrawingPolygonPoint(latlng, mapState.setState);
          }
        }
        clearPointerBuffer();
      }
      final latlng = mapState.offsetToLatLng(details.localFocalPoint);
      if (selected is PointLayerNode) {
        _pointPreview = latlng;
        mapState.setState(() {});
      } else if (selected is LineLayerNode) {
        if (drawingLine.isEmpty) {
          addDrawingLinePoint(latlng, mapState.setState);
        }
        _isDrawing = true;
      } else if (selected is PolygonLayerNode) {
        if (drawingPolygon.isEmpty) {
          addDrawingPolygonPoint(latlng, mapState.setState);
        }
        _isDrawing = true;
      }
    }
  }

  /// スケール更新イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    // 通常は従来通り
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null || !selected.isVisibleRecursive()) return;
    if (_pointerCount == 2) {
      panTool.onScaleUpdate(details, mapState);
      // 2本指終了時に1本指状態で呼ばれるので、_pointercount=2のままにしておく(スキップフラグとして利用)
      return;
    }
    if (_pointerCount == 1) {
      // フロートボタン押下時は消しゴム動作
      if (GlobalConfig.instance.isFabActive) {
        final latlng = mapState.offsetToLatLng(details.localFocalPoint);
        SelectTool.selectFeatureAtLatLng(tapLatLng: latlng, mapState: mapState);
        for (final f in List.from(GlobalConfig.instance.selectedFeatures)) {
          f.dispose();
        }
        GlobalConfig.instance.selectedFeatures = [];
        mapState.setState(() {});
        return;
      }
      final latlng = mapState.offsetToLatLng(details.localFocalPoint);
      if (selected is PointLayerNode) {
        _pointPreview = latlng;
        mapState.setState(() {});
      } else if (selected is LineLayerNode && _isDrawing) {
        addDrawingLinePoint(latlng, mapState.setState);
      } else if (selected is PolygonLayerNode && _isDrawing) {
        addDrawingPolygonPoint(latlng, mapState.setState);
      }
    }
  }

  /// スケール終了イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null || !selected.isVisibleRecursive()) return;
    if (_pointerCount == 2) {
      panTool.onScaleEnd(details, mapState);
      // _pointerCount = 0;
      return;
    }
    if (_pointerCount == 1) {
      if (selected is PointLayerNode && _pointPreview != null) {
        PointFeatureNode.createIn(
          selected,
          _pointPreview!,
          'FreeHandPoint',
          '',
        );
        _pointPreview = null;
        mapState.refreshFeatures();
        mapState.setState(() {});
      } else if (selected is LineLayerNode && drawingLine.length >= 2) {
        LineFeatureNode.createIn(
          selected,
          List<LatLng>.from(drawingLine),
          'FreeHandLine',
          '',
        );
        drawingLine.clear();
        _isDrawing = false;
        mapState.refreshFeatures();
        mapState.setState(() {});
      } else if (selected is PolygonLayerNode && drawingPolygon.length >= 3) {
        final closed = mapState.closeRing(drawingPolygon);
        PolygonFeatureNode.createIn(
          selected,
          List<List<LatLng>>.from([closed]),
          'FreeHandPolygon',
          '',
        );
        drawingPolygon.clear();
        _isDrawing = false;
        mapState.refreshFeatures();
        mapState.setState(() {});
      }
    }
    _pointerCount = 0;
  }

  /// 線の描画点を追加
  void addDrawingLinePoint(
    LatLng latlng,
    void Function(void Function()) setState,
  ) {
    setState(() {
      drawingLine.add(latlng);
    });
  }

  /// ポリゴンの描画点を追加
  void addDrawingPolygonPoint(
    LatLng latlng,
    void Function(void Function()) setState,
  ) {
    setState(() {
      drawingPolygon.add(latlng);
    });
  }

  /// 1つ取り消し
  void undo(void Function(void Function()) setState, {required bool isLine}) {
    setState(() {
      if (isLine && drawingLine.isNotEmpty) {
        drawingLine.removeLast();
      } else if (!isLine && drawingPolygon.isNotEmpty) {
        drawingPolygon.removeLast();
      }
    });
  }

  /// キャンセル（全消去）
  void cancel(void Function(void Function()) setState, {required bool isLine}) {
    setState(() {
      if (isLine) {
        drawingLine.clear();
      } else {
        drawingPolygon.clear();
      }
    });
  }

  /// 確定処理（属性入力ダイアログはUI側で呼ぶこと）
  void confirm({
    required LayerNode selected,
    required String name,
    required String description,
    required void Function(void Function()) setState,
    required List<LatLng> Function(List<LatLng>) closeRing,
  }) {
    if (selected is LineLayerNode && drawingLine.length >= 2) {
      LineFeatureNode.createIn(
        selected,
        List<LatLng>.from(drawingLine),
        name,
        description,
      );
      setState(() {
        drawingLine.clear();
      });
      // フィーチャ表示を更新（mapStateが利用可能なら）
      if (GlobalConfig.instance.mapState != null) {
        GlobalConfig.instance.mapState.refreshFeatures();
      }
    } else if (selected is PolygonLayerNode && drawingPolygon.length >= 3) {
      final closed = closeRing(drawingPolygon);
      PolygonFeatureNode.createIn(
        selected,
        List<List<LatLng>>.from([closed]),
        name,
        description,
      );
      setState(() {
        drawingPolygon.clear();
      });
      // フィーチャ表示を更新（mapStateが利用可能なら）
      if (GlobalConfig.instance.mapState != null) {
        GlobalConfig.instance.mapState.refreshFeatures();
      }
    }
  }
}
