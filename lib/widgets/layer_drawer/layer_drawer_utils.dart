/// K-MAPS: LayerDrawer用ユーティリティ関数
library;

import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/photo_node.dart';
import '../../utils/global_config.dart';
import 'layer_drawer_extensions.dart';

/// LayerDrawer用ユーティリティ関数を提供するミックスイン
mixin LayerDrawerUtils {
  /// マップページのフィーチャ更新をトリガー
  void triggerMapRefresh() {
    try {
      // GlobalConfigを通じてマップページの更新をトリガー
      final mapState = GlobalConfig.instance.mapState;
      if (mapState != null && mapState.mounted) {
        // レイヤ削除時は強制的にマップを更新（フィーチャキャッシュクリア）
        (mapState as dynamic).forceMapRefresh();
        print('[LayerDrawer] マップ強制更新をトリガーしました');
      } else {
        print('[LayerDrawer] マップページが見つからないか、マウントされていません');
      }
    } catch (e) {
      print('[LayerDrawer] マップ更新エラー: $e');
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
