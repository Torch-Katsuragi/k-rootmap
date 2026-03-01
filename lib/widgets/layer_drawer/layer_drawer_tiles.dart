/// K-MAPS: LayerDrawer用各種タイル描画ロジック（構成ミックスイン）
///
/// サブミックスインをエクスポートし、共通ヘルパーを提供する。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../presentation/node_presenter.dart';
import '../../providers/ui_state_providers.dart';
import 'layer_drawer.dart';

export 'tiles/folder_tile_builder.dart';
export 'tiles/geopackage_tile_builder.dart';
export 'tiles/layer_tile_builder.dart';
export 'tiles/photo_tile_builder.dart';
export 'layer_drawer_drive_sync.dart';
export 'layer_drawer_layer_ops.dart';

mixin LayerDrawerTiles on ConsumerState<LayerDrawer> {
  void Function(FeatureNode feature)? get onStartAppendMode;

  Widget buildIconWithVisibility(LayerTreeNode node) {
    return GestureDetector(
      onTap: () {
        node.visible = !node.visible;
        node.persistVisibility();
            ref.read(featureRefreshTriggerProvider.notifier).trigger();
        setState(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            NodePresenter.getIcon(node),
            color: node.isVisibleRecursive() ? NodePresenter.getColor(node) : Colors.grey,
          ),
          if (!node.visible)
            Transform.rotate(
              angle: -0.7,
              child: Container(width: 32, height: 4, color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
