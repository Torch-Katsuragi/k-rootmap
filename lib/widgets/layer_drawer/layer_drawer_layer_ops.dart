/// K-MAPS: レイヤ操作（変換・合成・吸収）ミックスイン
library;

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../utils/feature_calc_utils.dart';
import '../../providers/ui_state_providers.dart';
import '../../services/geometry_conversion_service.dart';
import '../../widgets/geometry_conversion_dialogs.dart';
import 'layer_drawer.dart';

mixin LayerDrawerLayerOps on ConsumerState<LayerDrawer> {
  void triggerMapRefresh();
  LayerTreeNode? get currentNode;

  /// ポイントレイヤーをライン/ポリゴンに変換
  Future<void> convertPointsToLine(
    BuildContext context,
    PointLayerNode sourceLayer,
  ) async {
    try {
      final features = sourceLayer.features;
      
      if (features.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ポイントが存在しないため変換できません')),
        );
        return;
      }

      final targetLayers = GeometryConversionService.findTargetLayersForPoints(currentNode);
      
      if (targetLayers.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('カレントディレクトリ直下にライン/ポリゴンレイヤーが見つかりません。\n先にレイヤーを作成してください。')),
          );
        }
        return;
      }
      
      final targetLayer = await showDialog<LayerNode>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return ConvertPointsToGeometryDialog(
            sourceLayer: sourceLayer,
            availableLayers: targetLayers,
          );
        },
      );

      if (targetLayer == null) {
        return;
      }

      String? featureName = await showDialog<String>(
        context: context,
        builder: (context) {
          final controller = TextEditingController(text: sourceLayer.name);
          final typeLabel = targetLayer is LineLayerNode ? 'ライン' : 'ポリゴン';
          return AlertDialog(
            title: Text('$typeLabel フィーチャ名の入力'),
            content: TextField(
              autofocus: true,
              controller: controller,
              decoration: const InputDecoration(labelText: '名前（任意）'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      if (featureName == null) {
        return;
      }

      final createdFeature = await GeometryConversionService.convertPointsToGeometry(
        sourceLayer: sourceLayer,
        targetLayer: targetLayer,
        name: featureName.isNotEmpty ? featureName : null,
      );

      if (createdFeature != null) {
        await targetLayer.updateChildren();
        setState(() {});
        
        triggerMapRefresh();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();

        final typeLabel = targetLayer is LineLayerNode ? 'ライン' : 'ポリゴン';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ポイントを$typeLabel に変換しました (${features.length}個の点)'),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('フィーチャの作成に失敗しました')));
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] ポイント変換エラー: $e');
      AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('変換処理中にエラーが発生しました: $e')));
      }
    }
  }

  /// ポリゴンレイヤー内のポリゴンを合成
  Future<void> mergePolygonsInLayer(
    BuildContext context,
    PolygonLayerNode layerNode,
  ) async {
    try {
      final features = layerNode.children.cast<FeatureNode>();

      final mergeableCount = PolygonMerge.countMergeablePolygons(features);

      if (mergeableCount < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('合成するには2つ以上の有効なポリゴンが必要です')),
        );
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('ポリゴン合成'),
              content: Text(
                '${layerNode.name} 内の $mergeableCount 個のポリゴンを合成しますか？\n\n'
                '最も面積の大きいポリゴンを外形とし、それ以外を穴として扱います。\n'
                '合成後は新しいレイヤー「${layerNode.name}_merged」に保存されます。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('合成'),
                ),
              ],
            ),
      );

      if (confirm != true) return;

      final mergedPolygon = PolygonMerge.mergePolygonFeatures(features);

      if (mergedPolygon.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ポリゴンの合成に失敗しました')));
        }
        return;
      }

      final newLayerName = '${layerNode.name}_merged';

      final parentGpkg = layerNode.parent as GeoPackageNode;
      final newLayerNode = await PolygonLayerNode.createIn(
        parentGpkg,
        newLayerName,
      );

      if (newLayerNode == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('新しいレイヤーの作成に失敗しました')));
        }
        return;
      }

      final mergedFeature = await PolygonFeatureNode.createIn(
        newLayerNode,
        mergedPolygon,
        'merged_polygon',
        '${layerNode.name}の$mergeableCount個のポリゴンを合成',
        metadata: {
          'source_layer': layerNode.name,
          'merged_count': mergeableCount,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      if (mergedFeature != null) {
        setState(() {});
        ref.read(featureRefreshTriggerProvider.notifier).trigger();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ポリゴンを合成しました。新しいレイヤー「$newLayerName」に保存されました。'),
            ),
          );
        }

        AppLogger.debug('[LayerDrawer] ポリゴン合成完了: $newLayerName');
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('合成ポリゴンの保存に失敗しました')));
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] ポリゴン合成エラー: $e');
      AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('合成処理中にエラーが発生しました: $e')));
      }
    }
  }

  /// 同一GeoPackage内のカラム名が完全一致するレイヤーを吸収
  Future<void> absorbMatchingLayers(
    BuildContext context,
    LayerNode targetNode,
  ) async {
    try {
      final parentGpkg = targetNode.parent;
      if (parentGpkg is! GeoPackageNode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoPackage内のレイヤーではありません')),
        );
        return;
      }

      final targetColumns = await parentGpkg.geoPackageFile.getTableColumns(targetNode.name);
      if (targetColumns.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レイヤーのカラム情報を取得できませんでした')),
        );
        return;
      }

      final siblingLayers = parentGpkg.children
          .whereType<LayerNode>()
          .where((layer) => layer != targetNode && layer.runtimeType == targetNode.runtimeType)
          .toList();

      if (siblingLayers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同じ型の他のレイヤーがありません')),
        );
        return;
      }

      final matchingLayers = <LayerNode>[];
      for (final layer in siblingLayers) {
        final layerColumns = await parentGpkg.geoPackageFile.getTableColumns(layer.name);
        if (_columnsMatch(targetColumns, layerColumns)) {
          matchingLayers.add(layer);
        }
      }

      if (matchingLayers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カラム構造が一致するレイヤーが見つかりません')),
        );
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('レイヤー吸収'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('以下の ${matchingLayers.length} 件のレイヤーを「${targetNode.name}」に吸収しますか？\n'),
              ...matchingLayers.map((l) => Text('  • ${l.name}')),
              const SizedBox(height: 12),
              const Text('※吸収されたレイヤーは削除されます', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('吸収'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      int absorbedCount = 0;
      for (final sourceLayer in matchingLayers) {
        try {
          final copied = await parentGpkg.geoPackageFile.copyFeaturesBetweenLayers(
            sourceLayer.name,
            targetNode.name,
          );
          
          if (copied > 0) {
            absorbedCount += copied;
            
            sourceLayer.dispose();
            
            AppLogger.debug('[LayerDrawer] レイヤー吸収完了: ${sourceLayer.name} -> ${targetNode.name} ($copied features)');
          }
        } catch (e) {
          AppLogger.debug('[LayerDrawer] レイヤー吸収エラー: ${sourceLayer.name} - $e');
        }
      }

      await targetNode.updateChildren();

      triggerMapRefresh();
      setState(() {});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$absorbedCount 件のフィーチャを吸収しました')),
        );
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] レイヤー吸収エラー: $e');
      AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('吸収処理中にエラーが発生しました: $e')),
        );
      }
    }
  }

  /// カラム構造が一致するか確認（geomカラムを除く属性カラムのみ比較）
  bool _columnsMatch(List<String> columns1, List<String> columns2) {
    final systemColumns = {'id', 'fid', 'geom', 'geometry', 'ROWID'};
    final attrs1 = columns1.where((c) => !systemColumns.contains(c.toLowerCase())).toSet();
    final attrs2 = columns2.where((c) => !systemColumns.contains(c.toLowerCase())).toSet();
    return attrs1.length == attrs2.length && attrs1.containsAll(attrs2);
  }
}
