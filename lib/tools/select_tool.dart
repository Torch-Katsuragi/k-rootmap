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
