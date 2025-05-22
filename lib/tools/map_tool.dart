// lib/tools/map_tool.dart
// 地図操作ツールの抽象基底クラス
// 各ツール（てのひら・ペン・選択等）はこのクラスを継承
import 'package:flutter/widgets.dart';

/// 地図操作ツールの抽象基底クラス
abstract class MapTool {
  /// ツール名（UI表示用）
  String get name;

  /// ツールアイコン（UI用）
  IconData get icon;

  /// ツール有効化時の初期化処理
  void onActivate() {}

  /// ツール無効化時の終了処理
  void onDeactivate() {}

  /// タップイベント
  void onTap(TapUpDetails details, dynamic mapState) {}

  /// スケール開始イベント
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {}

  /// スケール更新イベント
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {}

  /// スケール終了イベント
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {}
}
