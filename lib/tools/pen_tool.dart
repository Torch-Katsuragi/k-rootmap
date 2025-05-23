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

/// ペンツール（レイヤ描画）
class PenTool extends MapTool {
  @override
  String get name => 'ペン';

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

  /// タップイベント
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return;
    final latlng = mapState.offsetToLatLng(details.localPosition);
    if (selected is PointLayerNode) {
      selected.geoPackageFile.addPoint(selected.layerName, latlng, '');
      mapState.setState(() {});
    } else if (selected is LineLayerNode) {
      addDrawingLinePoint(latlng, mapState.setState);
    } else if (selected is PolygonLayerNode) {
      addDrawingPolygonPoint(latlng, mapState.setState);
    }
  }

  /// スケール開始イベント
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    _pointerCount = details.pointerCount ?? 1;
    if (_pointerCount == 1) {
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) return;
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
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    if (_pointerCount == 1) {
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) return;
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
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    if (_pointerCount == 1) {
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected == null) return;
      if (selected is PointLayerNode && _pointPreview != null) {
        selected.geoPackageFile.addPoint(
          selected.layerName,
          _pointPreview!,
          '',
        );
        _pointPreview = null;
        mapState.setState(() {});
      } else if (selected is LineLayerNode && drawingLine.length >= 2) {
        selected.geoPackageFile.addLine(selected.layerName, drawingLine, '');
        drawingLine.clear();
        _isDrawing = false;
        mapState.setState(() {});
      } else if (selected is PolygonLayerNode && drawingPolygon.length >= 3) {
        final closed = mapState.closeRing(drawingPolygon);
        selected.geoPackageFile.addPolygon(selected.layerName, closed, '');
        drawingPolygon.clear();
        _isDrawing = false;
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
    required String attr,
    required void Function(void Function()) setState,
    required List<LatLng> Function(List<LatLng>) closeRing,
  }) {
    if (selected is LineLayerNode && drawingLine.length >= 2) {
      selected.geoPackageFile.addLine(selected.layerName, drawingLine, attr);
      setState(() {
        drawingLine.clear();
      });
    } else if (selected is PolygonLayerNode && drawingPolygon.length >= 3) {
      final closed = closeRing(drawingPolygon);
      selected.geoPackageFile.addPolygon(selected.layerName, closed, attr);
      setState(() {
        drawingPolygon.clear();
      });
    }
  }
}
