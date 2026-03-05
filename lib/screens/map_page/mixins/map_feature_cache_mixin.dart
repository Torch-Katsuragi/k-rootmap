// K-MAPS: フィーチャキャッシュMixin
// 地図表示用のフィーチャキャッシュを効率的に管理
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../utils/app_logger.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/image_node.dart';
import '../map_page_state_base.dart';

/// フィーチャキャッシュMixin
/// 地図上に表示するフィーチャのキャッシュ管理を提供
mixin MapFeatureCacheMixin<T extends ConsumerStatefulWidget> on MapPageStateBase<T> {
  
  // =============================================
  // フィーチャ更新処理
  // =============================================
  
  /// フィーチャデータを非同期で更新（キャッシュに保存）
  /// KMetaスタイル読み込みとDB読み込みを並列実行し、最後にフィーチャを分類
  Future<void> updateFeaturesImpl() async {
    AppLogger.debug('[DEBUG] updateFeatures: start');
    final folderTree = ref.read(folderTreeProvider);
    AppLogger.debug('[DEBUG] updateFeatures: folderTree=$folderTree');
    
    final visibleLayers =
        folderTree != null ? folderTree.getVisibleLayerNodes() : <LayerNode>[];
    AppLogger.debug(
      '[DEBUG] updateFeatures: found ${visibleLayers.length} visible layers',
    );
    
    final newPhotoNodes = <ImageNode>[];
    if (folderTree != null) {
      collectImageNodesRecursive(folderTree, newPhotoNodes);
    }
    AppLogger.debug(
      '[DEBUG] updateFeatures: collected ${newPhotoNodes.length} photo nodes',
    );
    
    // LayerNodeのみ抽出
    final layers = visibleLayers.whereType<LayerNode>().toList();

    // KMetaスタイルの事前読み込みを並列実行
    await Future.wait(
      layers
          .where((l) => !l.isKmetaStyleLoaded)
          .map((l) => l.getKmetaStyle()),
    );

    // 初回読み込みが必要なレイヤのDB読み込みを並列実行
    final layersNeedingLoad = layers.where((l) {
      final features = l.children
          .whereType<FeatureNode>()
          .where((f) => !f.isDisposed)
          .toList();
      return features.isEmpty;
    }).toList();

    if (layersNeedingLoad.isNotEmpty) {
      AppLogger.debug(
        '[DEBUG] updateFeatures: loading ${layersNeedingLoad.length} layers from DB in parallel',
      );
      await Future.wait(
        layersNeedingLoad.map((l) => l.updateChildren()),
      );
    }

    // 全レイヤからフィーチャを分類・収集
    final newPointFeatures = <PointFeatureNode>[];
    final newLineFeatures = <LineFeatureNode>[];
    final newPolygonFeatures = <PolygonFeatureNode>[];

    for (final layer in layers) {
      final activeFeatures = layer.children
          .whereType<FeatureNode>()
          .where((f) => !f.isDisposed);

      if (layer is PointLayerNode) {
        newPointFeatures.addAll(activeFeatures.whereType<PointFeatureNode>());
      } else if (layer is LineLayerNode) {
        newLineFeatures.addAll(activeFeatures.whereType<LineFeatureNode>());
      } else if (layer is PolygonLayerNode) {
        newPolygonFeatures.addAll(activeFeatures.whereType<PolygonFeatureNode>());
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
      invalidateLayerCache();
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
    invalidateLayerCache();
    
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

