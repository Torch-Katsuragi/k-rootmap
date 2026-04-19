// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// Root Maps: ノード可視性トグルアイコン
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
