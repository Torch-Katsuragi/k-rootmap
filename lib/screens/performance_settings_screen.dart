/// パフォーマンス設定画面
///
/// 地図描画のパフォーマンスチューニングパラメータを宣言的に定義。
/// SettingsStoreとDataDrivenSettingsScreenで自動UI生成。
library;

import 'package:flutter/material.dart';
import '../core/settings_schema.dart';
import '../widgets/settings_widgets.dart';

// ============================================================
// 設定定義
// ============================================================

final lineSimplification = DoubleDef(
  key: 'perf_line_simplification_tolerance',
  title: 'ライン簡略化',
  description: 'PolylineLayerの簡略化強度（Douglas-Peucker）',
  defaultValue: 1.0,
  min: 0.0,
  max: 2.0,
  divisions: 20,
  formatter: (v) => v.toStringAsFixed(1),
);

final polygonSimplification = DoubleDef(
  key: 'perf_polygon_simplification_tolerance',
  title: 'ポリゴン簡略化',
  description: 'PolygonLayerの簡略化強度（Douglas-Peucker）',
  defaultValue: 0.8,
  min: 0.0,
  max: 2.0,
  divisions: 20,
  formatter: (v) => v.toStringAsFixed(1),
);

final polygonAltRendering = SwitchDef(
  key: 'perf_polygon_alt_rendering',
  title: 'ポリゴン高速描画',
  description:
      '三角形分割（earcut）による代替レンダリング。'
      '大量のポリゴン描画が高速になりますが、'
      '一部の複雑な形状で表示が崩れる場合があります。',
  defaultValue: true,
  icon: Icons.change_history,
);

// ============================================================
// ストア（シングルトン）
// ============================================================

final performanceSettings = SettingsStore([
  SettingSectionDef(
    title: 'ジオメトリ簡略化',
    icon: Icons.timeline,
    iconColor: Colors.orange,
    description:
        'ズームレベルに応じて頂点数を削減し、描画を高速化します。'
        '値が大きいほど軽量ですが、形状が崩れやすくなります。',
    items: [lineSimplification, polygonSimplification],
  ),
  SettingSectionDef(
    title: 'レンダリング方式',
    icon: Icons.speed,
    iconColor: Colors.blue,
    items: [polygonAltRendering],
  ),
]);

// ============================================================
// 画面
// ============================================================

class PerformanceSettingsScreen extends StatelessWidget {
  final bool isEmbedded;

  const PerformanceSettingsScreen({
    super.key,
    this.isEmbedded = false,
  });

  @override
  Widget build(BuildContext context) {
    return DataDrivenSettingsScreen(
      title: 'パフォーマンス',
      store: performanceSettings,
      isEmbedded: isEmbedded,
    );
  }
}
