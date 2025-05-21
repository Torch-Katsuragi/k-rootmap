// lib/tools/select_tool.dart
// オブジェクト選択ツール
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';
import 'map_tool.dart';

/// オブジェクト選択ツール
class SelectTool extends MapTool {
  @override
  String get name => '選択';

  @override
  IconData get icon => Icons.select_all;

  Offset? _startPosition;

  @override
  void onPointerDown(PointerDownEvent event, dynamic mapState) {
    _startPosition = event.localPosition;
    mapState?.startSelection(_startPosition!);
  }

  @override
  void onPointerMove(PointerMoveEvent event, dynamic mapState) {
    if (_startPosition != null) {
      mapState?.updateSelection(_startPosition!, event.localPosition);
    }
  }

  @override
  void onPointerUp(PointerUpEvent event, dynamic mapState) {
    if (_startPosition != null) {
      mapState?.endSelection(_startPosition!, event.localPosition);
      _startPosition = null;
    }
  }
}
