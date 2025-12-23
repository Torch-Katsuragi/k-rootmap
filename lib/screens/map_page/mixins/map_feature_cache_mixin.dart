// K-MAPS: フィーチャキャッシュMixin
// 地図表示用のフィーチャキャッシュを効率的に管理
import 'package:flutter/material.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/global_config.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/image_node.dart';
import '../map_page_state_base.dart';

/// フィーチャキャッシュMixin
/// 地図上に表示するフィーチャのキャッシュ管理を提供
mixin MapFeatureCacheMixin<T extends StatefulWidget> on MapPageStateBase<T> {
  
  // =============================================
  // フィーチャ更新処理
  // =============================================
  
  /// フィーチャデータを非同期で更新（キャッシュに保存）
  /// LayerNodeが管理するFeatureNodeを直接参照し、DBアクセスを最小限に抑制
  Future<void> updateFeaturesImpl() async {
    AppLogger.debug('[DEBUG] updateFeatures: start');
    final folderTree = GlobalConfig.instance.folderTree;
    AppLogger.debug('[DEBUG] updateFeatures: folderTree=$folderTree');
    
    final visibleLayers =
        folderTree != null ? folderTree.getVisibleLayerNodes() : <LayerNode>[];
    AppLogger.debug(
      '[DEBUG] updateFeatures: found ${visibleLayers.length} visible layers',
    );
    
    final newPointFeatures = <PointFeatureNode>[];
    final newLineFeatures = <LineFeatureNode>[];
    final newPolygonFeatures = <PolygonFeatureNode>[];
    final newPhotoNodes = <ImageNode>[];
    
    // ImageNodeを収集（FolderNode配下を再帰的に検索）
    if (folderTree != null) {
      collectImageNodesRecursive(folderTree, newPhotoNodes);
    }
    AppLogger.debug(
      '[DEBUG] updateFeatures: collected ${newPhotoNodes.length} photo nodes',
    );
    
    for (final node in visibleLayers) {
      // LayerNode以外はスキップ
      if (node is! LayerNode) continue;
      final layer = node;
      
      AppLogger.debug(
        '[DEBUG] updateFeatures: processing layer ${layer.name} (${layer.runtimeType})',
      );
      
      // KMetaスタイルを事前読み込み（描画時に同期アクセスするため）
      if (!layer.isKmetaStyleLoaded) {
        await layer.getKmetaStyle();
      }
      
      // LayerNodeのchildrenから直接FeatureNodeを取得（dispose済みを除外）
      final layerFeatures = layer.children
          .whereType<FeatureNode>()
          .where((f) => !f.isDisposed)
          .toList();
      
      if (layer is PointLayerNode) {
        final layerPointFeatures =
            layerFeatures.whereType<PointFeatureNode>().toList();
        AppLogger.debug(
          '[DEBUG] updateFeatures: found ${layerPointFeatures.length} point features in ${layer.name}',
        );
        newPointFeatures.addAll(layerPointFeatures);
        
        // childrenが空の場合のみDBから読み込み（初回読み込み時）
        if (layerFeatures.isEmpty) {
          await layer.updateChildren();
          final dbPointFeatures =
              layer.features.whereType<PointFeatureNode>().toList();
          AppLogger.debug(
            '[DEBUG] updateFeatures: loaded ${dbPointFeatures.length} point features from DB for ${layer.name}',
          );
          newPointFeatures.addAll(dbPointFeatures);
        }
      } else if (layer is LineLayerNode) {
        final layerLineFeatures =
            layerFeatures.whereType<LineFeatureNode>().toList();
        AppLogger.debug(
          '[DEBUG] updateFeatures: found ${layerLineFeatures.length} line features in ${layer.name}',
        );
        newLineFeatures.addAll(layerLineFeatures);
        
        if (layerFeatures.isEmpty) {
          await layer.updateChildren();
          final dbLineFeatures =
              layer.features.whereType<LineFeatureNode>().toList();
          AppLogger.debug(
            '[DEBUG] updateFeatures: loaded ${dbLineFeatures.length} line features from DB for ${layer.name}',
          );
          newLineFeatures.addAll(dbLineFeatures);
        }
      } else if (layer is PolygonLayerNode) {
        final layerPolygonFeatures =
            layerFeatures.whereType<PolygonFeatureNode>().toList();
        AppLogger.debug(
          '[DEBUG] updateFeatures: found ${layerPolygonFeatures.length} polygon features in ${layer.name}',
        );
        newPolygonFeatures.addAll(layerPolygonFeatures);
        
        if (layerFeatures.isEmpty) {
          await layer.updateChildren();
          final dbPolygonFeatures =
              layer.features.whereType<PolygonFeatureNode>().toList();
          AppLogger.debug(
            '[DEBUG] updateFeatures: loaded ${dbPolygonFeatures.length} polygon features from DB for ${layer.name}',
          );
          newPolygonFeatures.addAll(dbPolygonFeatures);
        }
      }
    }
    
    AppLogger.debug(
      '[DEBUG] updateFeatures: total - points:${newPointFeatures.length}, lines:${newLineFeatures.length}, polygons:${newPolygonFeatures.length}, photos:${newPhotoNodes.length}',
    );
    
    if (mounted) {
      triggerSetState(() {
        pointFeatures = newPointFeatures;
        lineFeatures = newLineFeatures;
        polygonFeatures = newPolygonFeatures;
        photoNodes = newPhotoNodes;
      });
      AppLogger.debug('[DEBUG] updateFeatures: state updated successfully');
    } else {
      AppLogger.debug('[DEBUG] updateFeatures: widget not mounted, skipping state update');
    }
  }
  
  /// ImageNodeを再帰的に収集する補助メソッド
  void collectImageNodesRecursive(
    LayerTreeNode node,
    List<ImageNode> photos,
  ) {
    // 現在のノードがImageNodeなら追加
    if (node is ImageNode && node.visible && node.isVisibleRecursive()) {
      photos.add(node);
    }
    
    // 子ノードを再帰的に処理
    for (final child in node.children) {
      collectImageNodesRecursive(child, photos);
    }
  }
  
  // =============================================
  // IMapState実装
  // =============================================
  
  /// フィーチャデータの公開更新メソッド（外部から呼び出し可能）
  @override
  void refreshFeatures() {
    updateFeaturesImpl();
  }
  
  /// マップの強制更新処理（外部から呼び出し可能）
  @override
  void forceMapRefresh() {
    refreshMapUI();
  }
  
  // =============================================
  // マップUI更新
  // =============================================
  
  /// マップUI更新処理
  /// フィーチャの追加・更新・削除後にマップ表示を更新
  /// 【重要】childrenはクリアせず、メモリ上のインスタンスから読み込む（DBアクセスなし）
  void refreshMapUI() {
    AppLogger.debug('[MAP] マップUI更新開始（インスタンスベース）');
    
    // 1. フィーチャデータのキャッシュをクリア
    pointFeatures.clear();
    lineFeatures.clear();
    polygonFeatures.clear();
    photoNodes.clear();
    
    // 2. 【重要】LayerNodeのchildrenはクリアしない（メモリ上のインスタンスを維持）
    
    // 3. フィーチャデータを再読み込み
    updateFeaturesImpl().then((_) {
      // 4. UI全体を更新
      if (mounted) {
        triggerSetState(() {});
        AppLogger.debug('[MAP] マップUI更新完了');
      }
    }).catchError((error) {
      AppLogger.debug('[ERROR] マップUI更新エラー: $error');
    });
  }
}

