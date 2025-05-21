// lib/tools/pan_tool.dart
// てのひらツール（地図パン専用）
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'map_tool.dart';

/// 地図パン（移動）専用ツール
class PanTool extends MapTool {
  @override
  String get name => 'てのひら';

  @override
  IconData get icon => Icons.pan_tool_alt;

  Offset? _lastPosition;

  @override
  void onPointerDown(PointerDownEvent event, dynamic mapState) {
    _lastPosition = event.position;
  }

  @override
  void onPointerMove(PointerMoveEvent event, dynamic mapState) {
    if (_lastPosition != null) {
      final delta = event.position - _lastPosition!;
      // mapStateに地図移動処理を委譲（実装はMapPage側で）
      mapState?.onPan(delta);
      _lastPosition = event.position;
    }
  }

  @override
  void onPointerUp(PointerUpEvent event, dynamic mapState) {
    _lastPosition = null;
  }
}
