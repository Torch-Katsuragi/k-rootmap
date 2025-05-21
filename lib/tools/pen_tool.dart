// lib/tools/pen_tool.dart
// ペンツール（レイヤ描画）
import 'package:flutter/widgets.dart';
import 'map_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';

/// ペンツール（レイヤ描画）
class PenTool extends MapTool {
  @override
  String get name => 'ペン';

  @override
  IconData get icon => Icons.edit;

  List<Offset> _currentPath = [];

  @override
  void onPointerDown(PointerDownEvent event, dynamic mapState) {
    if (event.kind == PointerDeviceKind.stylus) {
      // ペン入力: フリーハンド描画開始
      _currentPath = [event.localPosition];
      mapState?.startFreehand(_currentPath);
    } else if (event.kind == PointerDeviceKind.touch) {
      // 指タップ: 点追加
      mapState?.addPoint(event.localPosition);
    }
  }

  @override
  void onPointerMove(PointerMoveEvent event, dynamic mapState) {
    if (event.kind == PointerDeviceKind.stylus && _currentPath.isNotEmpty) {
      _currentPath.add(event.localPosition);
      mapState?.updateFreehand(_currentPath);
    }
  }

  @override
  void onPointerUp(PointerUpEvent event, dynamic mapState) {
    if (event.kind == PointerDeviceKind.stylus && _currentPath.isNotEmpty) {
      mapState?.endFreehand(_currentPath);
      _currentPath = [];
    }
  }
}
