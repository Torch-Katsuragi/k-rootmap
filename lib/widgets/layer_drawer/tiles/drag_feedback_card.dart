/// Root Maps: ドラッグ中フィードバックカード（共通ウィジェット）
library;

import 'package:flutter/material.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../presentation/node_presenter.dart';

/// ドラッグ操作中に指に追従して表示されるフィードバックカード。
/// 全ノードタイプ（Layer / GeoPackage / Folder / Image）で共用。
class DragFeedbackCard extends StatelessWidget {
  final LayerTreeNode node;

  const DragFeedbackCard({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8.0,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NodePresenter.buildIcon(node),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.drag_indicator, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
