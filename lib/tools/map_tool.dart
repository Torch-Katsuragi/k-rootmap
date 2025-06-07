// lib/tools/map_tool.dart
// 地図操作ツールの抽象基底クラス
// 各ツール（てのひら・ペン・選択等）はこのクラスを継承
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart';

/// 地図操作ツールの抽象基底クラス
abstract class MapTool {
  /// PointerEventバッファ（Listener等でonPointerMove時に記録）
  final List<Offset> pointerBuffer = [];

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

  /// バッファに座標を追加
  void addPointerToBuffer(Offset offset) {
    pointerBuffer.add(offset);
  }

  /// バッファをクリア
  void clearPointerBuffer() {
    pointerBuffer.clear();
  }

  /// バッファ内容を取得
  List<Offset> getPointerBuffer() {
    return List.unmodifiable(pointerBuffer);
  }
}
