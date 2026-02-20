/// フィーチャ編集アクションの抽象インタフェース
///
/// 各ジオメトリ操作（簡略化・切り取り等）はこのクラスを実装する。
/// FeatureEditorScreen はこのインタフェースだけに依存し、
/// 具象アクション / 具象FeatureNode型を知らなくてよい。
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nodes/feature_node.dart';

/// アクションが地図上に表示するポリラインデータ
class PreviewLines {
  final List<LatLng> backgroundLine;
  final List<LatLng> foregroundLine;
  const PreviewLines({
    required this.backgroundLine,
    required this.foregroundLine,
  });

  static const empty = PreviewLines(backgroundLine: [], foregroundLine: []);
}

abstract class FeatureEditAction {
  /// タブに表示するラベル
  String get label;

  /// タブに表示するアイコン
  IconData get icon;

  /// このアクションが対象フィーチャに適用可能か
  bool canApplyTo(FeatureNode feature);

  /// コントロールUIのみを構築（プレビュー地図は Screen 側で表示）
  /// [previewLines] を更新すると地図上のポリラインが変わる
  Widget buildControls(
    BuildContext context,
    FeatureNode feature,
    ValueNotifier<PreviewLines> previewLines,
  );
}
