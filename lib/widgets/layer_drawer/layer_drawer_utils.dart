import 'package:k_maps/utils/app_logger.dart';

/// K-MAPS: LayerDrawer用ユーティリティ関数

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../providers/ui_state_providers.dart';
import 'layer_drawer.dart';

/// LayerDrawer用ユーティリティ関数を提供するミックスイン
mixin LayerDrawerUtils on ConsumerState<LayerDrawer> {
  /// マップページのフィーチャ更新をトリガー
  void triggerMapRefresh() {
    try {
      ref.read(featureRefreshTriggerProvider.notifier).trigger();
      AppLogger.debug('[LayerDrawer] マップ強制更新をトリガーしました');
    } catch (e) {
      AppLogger.debug('[LayerDrawer] マップ更新エラー: $e');
    }
  }

  /// 現在のノードの全GeoPackage子ノードを展開状態に設定
  void expandAllGeoPackageNodes(
    LayerTreeNode? currentNode,
    Set<String> expandedGpkgPaths,
  ) {
    if (currentNode != null) {
      for (final child in currentNode.children) {
        if (child is GeoPackageNode) {
          final absPath = child.geoPackageFile.getAbsolutePath();
          if (absPath != null) expandedGpkgPaths.add(absPath);
        }
      }
    }
  }

  /// 新規追加されたGeoPackageノードのみを自動展開（ユーザーが閉じたものは除く）
  void expandNewGeoPackageNodesOnly(
    LayerTreeNode? currentNode,
    Set<String> expandedGpkgPaths,
    Set<String> userClosedGpkgPaths,
  ) {
    if (currentNode != null) {
      for (final child in currentNode.children) {
        if (child is GeoPackageNode) {
          final absPath = child.geoPackageFile.getAbsolutePath();
          // まだ展開状態の管理対象になっていない かつ ユーザーが閉じていないノードのみ展開
          if (absPath != null &&
              !expandedGpkgPaths.contains(absPath) &&
              !userClosedGpkgPaths.contains(absPath)) {
            expandedGpkgPaths.add(absPath);
          }
        }
      }
    }
  }
}

