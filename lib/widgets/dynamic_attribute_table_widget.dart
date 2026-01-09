// K-MAPS: 動的属性テーブルウィジェット（互換性レイヤー）
// 新しいリファクタリング版ウィジェットへのエイリアス
// 旧コードからの参照を維持するため、同じクラス名でエクスポート

// 新しい実装をエクスポート
export 'attribute_table/attribute_table_widget.dart' show AttributeTableWidget;
export 'attribute_table/attribute_table_controller.dart';
export 'attribute_table/attribute_table_toolbar.dart';
export 'attribute_table/attribute_table_dialogs.dart';

// 座標系サービスもエクスポート（旧EpsgDefinitionの代替）
export '../services/coordinate/epsg_registry.dart' show EpsgDefinition, EpsgRegistry;

import 'package:flutter/material.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import 'attribute_table/attribute_table_widget.dart';

/// 互換性のための旧クラス名エイリアス
/// 新規コードでは AttributeTableWidget を直接使用してください
@Deprecated('Use AttributeTableWidget instead')
class DynamicAttributeTableWidget extends StatelessWidget {
  final LayerNode layer;
  final Function(FeatureNode feature)? onFeatureSelected;
  final Function(FeatureNode feature)? onFeatureDeleted;
  final Function()? onAddFeature;

  const DynamicAttributeTableWidget({
    super.key,
    required this.layer,
    this.onFeatureSelected,
    this.onFeatureDeleted,
    this.onAddFeature,
  });

  @override
  Widget build(BuildContext context) {
    return AttributeTableWidget(
      layer: layer,
      onFeatureSelected: onFeatureSelected,
      onFeatureDeleted: onFeatureDeleted,
      onAddFeature: onAddFeature,
    );
  }
}
