/// K-MAPS: GeoPackageタイルウィジェット
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../providers/selection_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../services/import_export_service.dart';
import '../common_dialogs.dart';
import 'layer_tile.dart';
import 'node_visibility_icon.dart';

/// GeoPackage ノード用タイル（展開/折りたたみ・ドラッグ&ドロップ対応）
class GeoPackageTile extends ConsumerWidget {
  final GeoPackageNode node;
  final bool isDropTarget;
  final VoidCallback? onRename;
  final void Function(GeoPackageNode?) onDragTargetChanged;
  final ValueChanged<bool> onDragActiveChanged;
  final LayerTreeNode? currentDir;

  const GeoPackageTile({
    super.key,
    required this.node,
    required this.isDropTarget,
    required this.onDragTargetChanged,
    required this.onDragActiveChanged,
    this.onRename,
    this.currentDir,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(featureRefreshTriggerProvider);
    final expansionState = ref.watch(expandedGeoPackagesProvider);
    final absPath = node.geoPackageFile.getAbsolutePath();
    final isExpanded = expansionState.isExpanded(absPath);

    final content = Column(
      children: [
        ListTile(
          leading: NodeVisibilityIcon(node: node),
          title: Row(
            children: [
              Expanded(child: Text(node.name)),
              if (isDropTarget)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                  child: const Text(
                    'DROP LAYER HERE',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          onTap: () {
            if (absPath != null) ref.read(expandedGeoPackagesProvider.notifier).toggle(absPath);
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'rename') {
                    onRename?.call();
                  } else if (value == 'delete') {
                    await _handleDelete(context, ref);
                  }
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('名前の変更')),
                  PopupMenuItem(value: 'delete', child: Text('削除')),
                ],
              ),
            ],
          ),
        ),
        if (isExpanded) ...[
          ...node.children.map(
            (layerNode) => LayerTile(
              node: layerNode as LayerNode,
              currentDir: currentDir,
              onDragActiveChanged: (active) {
                onDragActiveChanged(active);
                if (!active) onDragTargetChanged(null);
              },
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
              child: AddLayerButton(node: node),
            ),
          ),
        ],
      ],
    );

    // レイヤ D&D ターゲット
    final layerDragTarget = DragTarget<LayerNode>(
      onAcceptWithDetails: (details) async {
        await _handleLayerDrop(context, ref, details.data, node);
        onDragActiveChanged(false);
        onDragTargetChanged(null);
      },
      onWillAcceptWithDetails: (details) => details.data.geoPackageNode != node,
      onMove: (_) {
        onDragActiveChanged(true);
        onDragTargetChanged(node);
      },
      onLeave: (_) => onDragTargetChanged(null),
      builder: (context, _, __) {
        return Container(
          decoration: isDropTarget
              ? BoxDecoration(
                  border: Border.all(color: Colors.blue, width: 2),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.blue.withValues(alpha: 0.1),
                )
              : null,
          child: content,
        );
      },
    );

    // ファイル D&D ターゲット（外側）
    return DropTarget(
      onDragEntered: (_) {
        onDragActiveChanged(true);
        onDragTargetChanged(node);
      },
      onDragExited: (_) {
        onDragTargetChanged(null);
        onDragActiveChanged(false);
      },
      onDragDone: (details) async {
        for (final file in details.files) {
          await _handleFileDrop(file.path, ref);
        }
        onDragActiveChanged(false);
        onDragTargetChanged(null);
      },
      child: layerDragTarget,
    );
  }

  Future<void> _handleFileDrop(String filePath, WidgetRef ref) async {
    try {
      final result = await ImportExportService().importFile(filePath, node);
      if (result.success) {
        await node.updateChildren();
        if (result.createdLayer != null) await result.createdLayer!.updateChildren();

        final absPath = node.geoPackageFile.getAbsolutePath();
        if (absPath != null) ref.read(expandedGeoPackagesProvider.notifier).addExpanded(absPath);

        ref.read(featureRefreshTriggerProvider.notifier).trigger();
        Future.delayed(const Duration(milliseconds: 500), () {
          ref.read(featureRefreshTriggerProvider.notifier).trigger();
        });
      }
    } catch (_) {}
  }

  Future<void> _handleLayerDrop(
    BuildContext context,
    WidgetRef ref,
    LayerNode sourceLayer,
    GeoPackageNode targetGpkg,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('レイヤ移植'),
        content: Text(
          '「${sourceLayer.name}」を「${targetGpkg.name}」に移植しますか？\n\n'
          '移植により、元のGeoPackageからこのレイヤは削除されます。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('移植')),
        ],
      ),
    );
    if (confirm != true) return;

    final migrated = await sourceLayer.migrateToGeoPackage(targetGpkg, moveLayer: true);
    if (migrated != null) {
      ref.read(featureRefreshTriggerProvider.notifier).trigger();
      ref.read(selectedLayerNodeProvider.notifier).select(migrated);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('「${sourceLayer.name}」を「${targetGpkg.name}」に移植しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('レイヤ移植に失敗しました'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    await confirmAndExecute(
      context,
      title: 'GeoPackage削除',
      content: Text('${node.name} を本当に削除しますか？\nファイルも完全に削除されます。'),
      confirmLabel: '削除',
      successMessage: '${node.name} を削除しました',
      execute: () async {
        for (final layer in node.children.whereType<LayerNode>()) {
          if (ref.read(selectedLayerNodeProvider) == layer) {
            ref.read(selectedLayerNodeProvider.notifier).select(null);
          }
          ref.read(selectedFeaturesProvider.notifier).set(
            ref.read(selectedFeaturesProvider).where((f) {
              if (f is FeatureNode) return f.parent != layer;
              return true;
            }).toList(),
          );
        }
        await node.dispose();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
    );
  }
}
