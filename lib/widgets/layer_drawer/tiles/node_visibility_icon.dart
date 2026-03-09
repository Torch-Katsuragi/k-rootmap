/// K-MAPS: ノード可視性トグルアイコン
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../presentation/node_presenter.dart';
import '../../../providers/ui_state_providers.dart';

/// 可視性トグル付きノードアイコン
/// タップで visible を切り替え、非表示時は斜線オーバーレイを表示
class NodeVisibilityIcon extends ConsumerWidget {
  final LayerTreeNode node;

  const NodeVisibilityIcon({super.key, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () {
        node.visible = !node.visible;
        node.persistVisibility();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            NodePresenter.getIcon(node),
            color: node.isVisibleRecursive()
                ? NodePresenter.getColor(node)
                : Colors.grey,
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
