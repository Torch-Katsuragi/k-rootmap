/// K-MAPS: GeoPackageタイル構築ミックスイン
library;

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../providers/selection_providers.dart';
import '../../../services/import_export_service.dart';
import '../layer_drawer.dart';

mixin GeoPackageTileBuilder on ConsumerState<LayerDrawer> {
  void triggerMapRefresh();

  bool get isDragging;
  set isDragging(bool value);

  GeoPackageNode? get dragTargetGeoPackageNode;
  set dragTargetGeoPackageNode(GeoPackageNode? node);

  Set<String> get expandedGpkgPaths;
  Set<String> get userClosedGpkgPaths;

  ImportExportService get importExportService;

  Widget buildIconWithVisibility(LayerTreeNode node);
  Widget buildLayerTile(BuildContext context, LayerNode node);
  Widget buildAddLayerButton(BuildContext context, GeoPackageNode node);

  /// GeoPackageタイルを構築
  Widget buildGeoPackageTile(
    BuildContext context,
    GeoPackageNode node, {
    VoidCallback? onRename,
  }) {
    final absPath = node.geoPackageFile.getAbsolutePath();
    final isExpanded = absPath != null && expandedGpkgPaths.contains(absPath);
    final isDropTarget = isDragging && dragTargetGeoPackageNode == node;

    final geoPackageContent = Column(
      children: [
        ListTile(
          leading: buildIconWithVisibility(node),
          title: Row(
            children: [
              Expanded(child: Text(node.name)),
              if (isDropTarget)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'DROP LAYER HERE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          onTap: () {
            if (isExpanded) {
              expandedGpkgPaths.remove(absPath);
              userClosedGpkgPaths.add(absPath);
            } else {
              if (absPath != null) {
                expandedGpkgPaths.add(absPath);
                userClosedGpkgPaths.remove(absPath);
              }
            }
            setState(() {});
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'rename') {
                    if (onRename != null) onRename();
                  } else if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('GeoPackage削除'),
                            content: Text(
                              '${node.name} を本当に削除しますか？\nファイルも完全に削除されます。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('削除'),
                              ),
                            ],
                          ),
                    );
                    if (confirm == true) {
                      try {
                        final layersToRemove =
                            node.children.whereType<LayerNode>().toList();
                        for (final layer in layersToRemove) {
                          if (ref.read(selectedLayerNodeProvider) == layer) {
                            ref.read(selectedLayerNodeProvider.notifier).select(null);
                          }
                          ref.read(selectedFeaturesProvider.notifier).set(
                          ref.read(selectedFeaturesProvider).where((feature) {
                            if (feature is FeatureNode) {
                              return feature.parent != layer;
                            }
                            return true;
                          }).toList(),
                        );
                        }

                        await node.dispose();

                        triggerMapRefresh();

                        setState(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${node.name} を削除しました')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('削除に失敗しました: $e')),
                          );
                        }
                      }
                    }
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(value: 'rename', child: Text('名前の変更')),
                      const PopupMenuItem(value: 'delete', child: Text('削除')),
                    ],
              ),
            ],
          ),
        ),
        if (isExpanded) ...[
          ...node.children.map(
            (layerNode) => buildLayerTile(context, layerNode as LayerNode),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
              child: buildAddLayerButton(context, node),
            ),
          ),
        ],
      ],
    );

    // レイヤドロップ対応のDragTargetでラップ
    final layerDragTarget = DragTarget<LayerNode>(
      onAcceptWithDetails: (details) async {
        final sourceLayer = details.data;
        await _handleLayerDrop(context, sourceLayer, node);

        isDragging = false;
        dragTargetGeoPackageNode = null;
        setState(() {});
      },
      onWillAcceptWithDetails: (details) {
        final sourceLayer = details.data;

        if (sourceLayer.geoPackageNode == node) {
          return false;
        }

        return true;
      },
      onMove: (details) {
        if (!isDragging || dragTargetGeoPackageNode != node) {
          isDragging = true;
          dragTargetGeoPackageNode = node;
          setState(() {});
        }
      },
      onLeave: (data) {
        if (dragTargetGeoPackageNode == node) {
          dragTargetGeoPackageNode = null;
          setState(() {});
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration:
              isDropTarget
                  ? BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.blue.withValues(alpha: 0.1),
                  )
                  : null,
          child: geoPackageContent,
        );
      },
    );

    // ファイルドロップ対応のDropTargetでラップ（外側）
    return DropTarget(
      onDragEntered: (details) {
        if (!isDragging || dragTargetGeoPackageNode != node) {
          isDragging = true;
          dragTargetGeoPackageNode = node;
          setState(() {});
        }
      },
      onDragExited: (details) {
        if (dragTargetGeoPackageNode == node) {
          dragTargetGeoPackageNode = null;
          isDragging = false;
          setState(() {});
        }
      },
      onDragDone: (details) async {
        if (details.files.isNotEmpty) {
          for (final file in details.files) {
            await _handleSpecificGeoPackageDrop(file.path, node);
          }

          isDragging = false;
          dragTargetGeoPackageNode = null;
          setState(() {});
        }
      },
      child: layerDragTarget,
    );
  }

  /// 特定のGeoPackageノードへのファイルドロップを処理
  Future<void> _handleSpecificGeoPackageDrop(
    String filePath,
    GeoPackageNode targetNode,
  ) async {
    try {
      AppLogger.debug(
        '[LayerDrawer] GeoPackageドロップ処理開始: $filePath -> ${targetNode.name}',
      );

      final result = await importExportService.importFile(filePath, targetNode);

      if (result.success) {
        await targetNode.updateChildren();

        if (result.createdLayer != null) {
          AppLogger.debug(
            '[LayerDrawer] 作成されたレイヤーのフィーチャ更新: ${result.createdLayer!.layerName}',
          );
          await result.createdLayer!.updateChildren();

          final features = result.createdLayer!.features;
          AppLogger.debug(
            '[LayerDrawer] レイヤー「${result.createdLayer!.layerName}」のフィーチャ数: ${features.length}',
          );

          if (features.isNotEmpty) {
            final firstFeature = features.first;
            AppLogger.debug(
              '[LayerDrawer] 最初のフィーチャ: ${firstFeature.name}, 中心座標: ${firstFeature.centroid}',
            );
          }
        }

        final absPath = targetNode.geoPackageFile.getAbsolutePath();
        if (absPath != null) {
          expandedGpkgPaths.add(absPath);
        }

        setState(() {});

        triggerMapRefresh();

        Future.delayed(const Duration(milliseconds: 500), () {
          triggerMapRefresh();
        });

        _showImportSuccess(result);

        AppLogger.debug('[LayerDrawer] GeoPackageドロップ処理完了');
      } else {
        _showImportError(result.errorMessage ?? 'Import failed');
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] GeoPackageドロップエラー: $e');
      AppLogger.debug('スタックトレース: $stack');
      _showImportError('Unexpected error during import: $e');
    }
  }

  void _showImportSuccess(ImportExportResult result) {
    AppLogger.debug('[LayerDrawer] インポート成功: ${result.metadata}');
  }

  void _showImportError(String errorMessage) {
    // BuildContextが必要なため呼び出し側で対応
  }

  /// レイヤドロップ処理
  Future<void> _handleLayerDrop(
    BuildContext context,
    LayerNode sourceLayer,
    GeoPackageNode targetGeoPackage,
  ) async {
    try {
      AppLogger.debug(
        '[LayerDrawer] レイヤドロップ処理開始: ${sourceLayer.name} → ${targetGeoPackage.name}',
      );

      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('レイヤ移植'),
              content: Text(
                '「${sourceLayer.name}」を「${targetGeoPackage.name}」に移植しますか？\n\n'
                '移植により、元のGeoPackageからこのレイヤは削除されます。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('移植'),
                ),
              ],
            ),
      );

      if (confirm != true) {
        AppLogger.debug('[LayerDrawer] レイヤ移植がキャンセルされました');
        return;
      }

      AppLogger.debug('[LayerDrawer] レイヤ移植実行中...');
      final migratedLayer = await sourceLayer.migrateToGeoPackage(
        targetGeoPackage,
        moveLayer: true,
      );

      if (migratedLayer != null) {
        AppLogger.debug('[LayerDrawer] レイヤ移植成功: ${migratedLayer.name}');

        triggerMapRefresh();
        setState(() {});

        ref.read(selectedLayerNodeProvider.notifier).select(migratedLayer);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '「${sourceLayer.name}」を「${targetGeoPackage.name}」に移植しました',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        AppLogger.debug('[LayerDrawer] レイヤ移植失敗');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('レイヤ移植に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] レイヤドロップ処理エラー: $e');
      AppLogger.debug('スタックトレース: $stack');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('レイヤ移植中にエラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
