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

  /// タップイベント
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    // 必要に応じて
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
