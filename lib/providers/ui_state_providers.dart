import 'package:flutter/foundation.dart' show immutable;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/nodes/layer_tree_node.dart';
import '../core/k_map_controller.dart';

part 'ui_state_providers.g.dart';

/// GeoPackage タイル展開状態（不変値オブジェクト）
@immutable
class GpkgExpansionState {
  final Set<String> expandedPaths;
  final Set<String> userClosedPaths;

  const GpkgExpansionState({
    this.expandedPaths = const {},
    this.userClosedPaths = const {},
  });

  bool isExpanded(String? path) => path != null && expandedPaths.contains(path);

  GpkgExpansionState copyWith({Set<String>? expandedPaths, Set<String>? userClosedPaths}) =>
      GpkgExpansionState(
        expandedPaths: expandedPaths ?? this.expandedPaths,
        userClosedPaths: userClosedPaths ?? this.userClosedPaths,
      );
}

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
  KMapController? build() => null;

  void set(KMapController controller) => state = controller;
}

@Riverpod(keepAlive: true)
class FolderTree extends _$FolderTree {
  @override
  LayerTreeNode? build() => null;

  void set(LayerTreeNode? tree) => state = tree;
}

@Riverpod(keepAlive: true)
class ExpandedGeoPackages extends _$ExpandedGeoPackages {
  @override
  GpkgExpansionState build() => const GpkgExpansionState();

  void toggle(String path) {
    final expanded = Set<String>.from(state.expandedPaths);
    final closed = Set<String>.from(state.userClosedPaths);
    if (expanded.contains(path)) {
      expanded.remove(path);
      closed.add(path);
    } else {
      expanded.add(path);
      closed.remove(path);
    }
    state = GpkgExpansionState(expandedPaths: expanded, userClosedPaths: closed);
  }

  void expandAll(Iterable<String> paths) {
    final expanded = Set<String>.from(state.expandedPaths)..addAll(paths);
    state = state.copyWith(expandedPaths: expanded);
  }

  /// 新規追加ノードのみ展開（ユーザーが閉じたものは除く）。変更がなければ state を更新しない
  void expandNewOnly(Iterable<String> paths) {
    final expanded = Set<String>.from(state.expandedPaths);
    var changed = false;
    for (final p in paths) {
      if (!expanded.contains(p) && !state.userClosedPaths.contains(p)) {
        expanded.add(p);
        changed = true;
      }
    }
    if (changed) state = state.copyWith(expandedPaths: expanded);
  }

  void resetAndExpandAll(Iterable<String> paths) {
    state = GpkgExpansionState(expandedPaths: Set.from(paths));
  }

  void addExpanded(String path) {
    state = state.copyWith(expandedPaths: {...state.expandedPaths, path});
  }

  void updatePath(String oldPath, String newPath) {
    final expanded = Set<String>.from(state.expandedPaths);
    if (expanded.remove(oldPath)) expanded.add(newPath);
    state = state.copyWith(expandedPaths: expanded);
  }
}
