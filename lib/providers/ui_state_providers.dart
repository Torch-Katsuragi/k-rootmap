import 'package:flutter_map/flutter_map.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/nodes/layer_tree_node.dart';

part 'ui_state_providers.g.dart';

@Riverpod(keepAlive: true)
class IsFabActive extends _$IsFabActive {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

@Riverpod(keepAlive: true)
class IsAttributeTableEditing extends _$IsAttributeTableEditing {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

@Riverpod(keepAlive: true)
class FeatureRefreshTrigger extends _$FeatureRefreshTrigger {
  @override
  int build() => 0;

  void trigger() => state++;
}

@Riverpod(keepAlive: true)
class MapControllerHolder extends _$MapControllerHolder {
  @override
  MapController? build() => null;

  void set(MapController controller) => state = controller;
}

@Riverpod(keepAlive: true)
class FolderTree extends _$FolderTree {
  @override
  LayerTreeNode? build() => null;

  void set(LayerTreeNode? tree) => state = tree;
}
