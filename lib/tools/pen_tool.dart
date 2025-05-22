// lib/tools/pen_tool.dart
// ペンツール（レイヤ描画）
import 'package:flutter/widgets.dart';
import 'map_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../utils/global_config.dart';
import '../models/layer_tree_node.dart';

/// ペンツール（レイヤ描画）
class PenTool extends MapTool {
  @override
  String get name => 'ペン';

  @override
  IconData get icon => Icons.edit;

  List<Offset> _currentPath = [];

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
      mapState.addDrawingLinePoint(latlng);
    } else if (selected is PolygonLayerNode) {
      mapState.addDrawingPolygonPoint(latlng);
    }
  }

  /// スケール開始イベント
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    // 必要に応じて
  }

  /// スケール更新イベント
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    // 必要に応じて
  }

  /// スケール終了イベント
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    // 必要に応じて
  }
}
