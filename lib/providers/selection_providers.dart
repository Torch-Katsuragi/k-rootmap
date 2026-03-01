import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../utils/app_logger.dart';
import 'ui_state_providers.dart';

part 'selection_providers.g.dart';

@Riverpod(keepAlive: true)
class SelectedLayerNode extends _$SelectedLayerNode {
  @override
  LayerNode? build() => null;

  void select(LayerNode? node) => state = node;
}

@Riverpod(keepAlive: true)
class SelectedFeatures extends _$SelectedFeatures {
  @override
  List<LayerTreeNode> build() => [];

  void add(LayerTreeNode node) => state = [...state, node];

  void remove(LayerTreeNode node) =>
      state = state.where((n) => n != node).toList();

  void clear() => state = [];

  void set(List<LayerTreeNode> features) => state = [...features];

  void toggle(LayerTreeNode node) {
    if (state.contains(node)) {
      remove(node);
    } else {
      add(node);
    }
  }

  Future<void> disposeSelectedFeatures() async {
    final features = List<LayerTreeNode>.from(state);
    AppLogger.debug(
      '[SelectedFeatures] 削除処理開始: ${features.length}個のフィーチャ',
    );

    if (features.isEmpty) return;

    state = [];
    ref.read(featureRefreshTriggerProvider.notifier).trigger();

    final disposeFutures = features.map((node) async {
      try {
        final String idInfo =
            node is FeatureNode ? ' (ID: ${node.rowId})' : '';
        AppLogger.debug('[SelectedFeatures] フィーチャ削除中: ${node.name}$idInfo');
        await node.dispose();
      } catch (e) {
        AppLogger.debug(
          '[ERROR] SelectedFeatures: フィーチャ削除失敗 ${node.name}: $e',
        );
      }
    }).toList();

    await Future.wait(disposeFutures).then((_) {
      AppLogger.debug(
        '[SelectedFeatures] 全${features.length}個のフィーチャ削除完了',
      );
      ref.read(featureRefreshTriggerProvider.notifier).trigger();
    }).catchError((e) {
      AppLogger.debug('[ERROR] SelectedFeatures: バッチ削除エラー: $e');
    });
  }
}
