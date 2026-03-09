/// K-MAPS: レイヤタイルウィジェット
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../models/geometry_type.dart';
import '../../../providers/selection_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../services/geometry_conversion_service.dart';
import '../../../utils/feature_calc_utils.dart';
import '../../../widgets/dialog_manager.dart';
import '../../../widgets/geometry_conversion_dialogs.dart';
import '../../../screens/layer_style_settings_screen.dart';
import '../../../presentation/node_presenter.dart';
import '../common_dialogs.dart';

/// レイヤノード用 ListTile（選択・可視切り替え・ドラッグ対応）
class LayerTile extends ConsumerWidget {
  final LayerNode node;

  /// ジオメトリ変換時にターゲットレイヤーを検索するための親ディレクトリ
  final LayerTreeNode? currentDir;

  final ValueChanged<bool>? onDragActiveChanged;

  const LayerTile({
    super.key,
    required this.node,
    this.currentDir,
    this.onDragActiveChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSelected = ref.watch(selectedLayerNodeProvider) == node;

    final tileContent = GestureDetector(
      onTap: () => ref.read(selectedLayerNodeProvider.notifier).select(node),
      onDoubleTap: () {
        final coords = node.getAllCoordinates();
        if (coords.isEmpty) return;
        ref.read(mapControllerHolderProvider)?.fitCoordinates(
          coords,
          padding: const EdgeInsets.all(50),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        leading: _buildLeadingIcon(ref, isSelected),
        title: Text(
          node.name,
          style: TextStyle(
            color: isSelected ? Colors.blue : (node.isVisibleRecursive() ? null : Colors.grey),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        trailing: _buildMenu(context, ref),
      ),
    );

    return LongPressDraggable<LayerNode>(
      data: node,
      dragAnchorStrategy: (_, __, ___) => const Offset(0, 0),
      feedback: _buildDragFeedback(),
      childWhenDragging: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Opacity(opacity: 0.5, child: tileContent),
      ),
      onDragStarted: () => onDragActiveChanged?.call(true),
      onDragEnd: (_) => onDragActiveChanged?.call(false),
      child: tileContent,
    );
  }

  // ---------- UI 部品 ----------

  Widget _buildLeadingIcon(WidgetRef ref, bool isSelected) {
    return GestureDetector(
      onTap: () {
        node.visible = !node.visible;
        node.persistVisibility();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? Colors.blue.withValues(alpha: 0.15) : Colors.transparent,
            ),
            padding: const EdgeInsets.all(4),
            child: Icon(
              NodePresenter.getIcon(node),
              color: isSelected
                  ? Colors.blue
                  : (node.isVisibleRecursive() ? NodePresenter.getColor(node) : Colors.grey),
            ),
          ),
          if (!node.visible)
            Transform.rotate(
              angle: -0.7,
              child: Container(width: 32, height: 4, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildDragFeedback() {
    return Material(
      elevation: 8.0,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              NodePresenter.buildIcon(node),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  node.name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.drag_indicator, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuButton<String> _buildMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            await _showRenameDialog(context, ref);
          case 'style':
            await _openStyleSettings(context, ref);
          case 'export':
            await DialogManager.showLayerExportDialog(context, sourceLayer: node);
          case 'convert_to_line' when node is PointLayerNode:
            await _convertPointsToLine(context, ref, node as PointLayerNode);
          case 'merge' when node is PolygonLayerNode:
            await _mergePolygons(context, ref, node as PolygonLayerNode);
          case 'absorb':
            await _absorbMatchingLayers(context, ref);
          case 'delete':
            await _handleDelete(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'rename',
          child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Rename')]),
        ),
        const PopupMenuItem(
          value: 'style',
          child: Row(children: [Icon(Icons.palette, size: 16), SizedBox(width: 8), Text('Style')]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'export',
          child: Row(children: [Icon(Icons.file_download, size: 16), SizedBox(width: 8), Text('Export Layer')]),
        ),
        if (node is PointLayerNode)
          const PopupMenuItem(
            value: 'convert_to_line',
            child: Row(children: [Icon(Icons.transform, size: 16), SizedBox(width: 8), Text('ライン/ポリゴンに変換')]),
          ),
        if (node is PolygonLayerNode)
          const PopupMenuItem(value: 'merge', child: Text('合成')),
        const PopupMenuItem(
          value: 'absorb',
          child: Row(children: [Icon(Icons.merge_type, size: 16), SizedBox(width: 8), Text('同構造レイヤを吸収')]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'delete', child: Text('削除')),
      ],
    );
  }

  // ---------- レイヤー操作 ----------

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final newName = await RenameDialog.show(
      context,
      title: 'Rename Layer',
      currentName: node.layerName,
      label: 'Layer Name',
      hint: 'Enter new layer name',
      submitLabel: 'Rename',
    );
    if (newName == null || newName == node.layerName) return;
    try {
      await node.geoPackageFile.renameLayer(node.layerName, newName);
      await node.geoPackageNode.updateChildren();
      ref.read(featureRefreshTriggerProvider.notifier).trigger();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
      }
    }
  }

  Future<void> _openStyleSettings(BuildContext context, WidgetRef ref) async {
    final folderPath = node.folderNode?.getAbsoluteFilePath();
    if (folderPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not determine folder path')));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LayerStyleSettingsScreen(targetLayer: node, folderPath: folderPath)),
    );
    ref.read(featureRefreshTriggerProvider.notifier).trigger();
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    await confirmAndExecute(
      context,
      title: 'レイヤ削除',
      content: Text('${node.name} を本当に削除しますか？'),
      confirmLabel: '削除',
      execute: () async {
        if (ref.read(selectedLayerNodeProvider) == node) {
          ref.read(selectedLayerNodeProvider.notifier).select(null);
        }
        ref.read(selectedFeaturesProvider.notifier).set(
          ref.read(selectedFeaturesProvider).where((f) {
            if (f is FeatureNode) return f.parent != node;
            return true;
          }).toList(),
        );
        node.dispose();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
    );
  }

  // ---------- ジオメトリ変換・合成・吸収 ----------

  Future<void> _convertPointsToLine(
    BuildContext context,
    WidgetRef ref,
    PointLayerNode sourceLayer,
  ) async {
    final features = sourceLayer.features;
    if (features.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ポイントが存在しないため変換できません')),
      );
      return;
    }

    final targetLayers = GeometryConversionService.findTargetLayersForPoints(currentDir);
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
      builder: (_) => ConvertPointsToGeometryDialog(sourceLayer: sourceLayer, availableLayers: targetLayers),
    );
    if (targetLayer == null) return;

    final typeLabel = targetLayer is LineLayerNode ? 'ライン' : 'ポリゴン';
    String? featureName = await showDialog<String>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController(text: sourceLayer.name);
        return AlertDialog(
          title: Text('$typeLabel フィーチャ名の入力'),
          content: TextField(autofocus: true, controller: ctrl, decoration: const InputDecoration(labelText: '名前（任意）')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('キャンセル')),
            TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
          ],
        );
      },
    );
    if (featureName == null) return;

    try {
      final created = await GeometryConversionService.convertPointsToGeometry(
        sourceLayer: sourceLayer,
        targetLayer: targetLayer,
        name: featureName.isNotEmpty ? featureName : null,
      );
      if (created != null) {
        await targetLayer.updateChildren();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ポイントを$typeLabel に変換しました (${features.length}個の点)')),
          );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('フィーチャの作成に失敗しました')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('変換処理中にエラーが発生しました: $e')));
      }
    }
  }

  Future<void> _mergePolygons(
    BuildContext context,
    WidgetRef ref,
    PolygonLayerNode layerNode,
  ) async {
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
      builder: (context) => AlertDialog(
        title: const Text('ポリゴン合成'),
        content: Text(
          '${layerNode.name} 内の $mergeableCount 個のポリゴンを合成しますか？\n\n'
          '最も面積の大きいポリゴンを外形とし、それ以外を穴として扱います。\n'
          '合成後は新しいレイヤー「${layerNode.name}_merged」に保存されます。',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('合成')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final merged = PolygonMerge.mergePolygonFeatures(features);
      if (merged.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ポリゴンの合成に失敗しました')));
        return;
      }

      final parentGpkg = layerNode.parent as GeoPackageNode;
      final newLayerName = '${layerNode.name}_merged';
      final newLayer = await PolygonLayerNode.createIn(parentGpkg, newLayerName);
      if (newLayer == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('新しいレイヤーの作成に失敗しました')));
        return;
      }

      final mergedFeature = await PolygonFeatureNode.createIn(
        newLayer,
        merged,
        'merged_polygon',
        '${layerNode.name}の$mergeableCount個のポリゴンを合成',
        metadata: {
          'source_layer': layerNode.name,
          'merged_count': mergeableCount,
          'created_at': DateTime.now().toIso8601String(),
        },
      );
      if (mergedFeature != null) {
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ポリゴンを合成しました。新しいレイヤー「$newLayerName」に保存されました。')),
          );
        }
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('合成ポリゴンの保存に失敗しました')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('合成処理中にエラーが発生しました: $e')));
      }
    }
  }

  Future<void> _absorbMatchingLayers(BuildContext context, WidgetRef ref) async {
    final parentGpkg = node.parent;
    if (parentGpkg is! GeoPackageNode) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('GeoPackage内のレイヤーではありません')));
      return;
    }

    try {
      final targetColumns = await parentGpkg.geoPackageFile.getTableColumns(node.name);
      if (targetColumns.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('レイヤーのカラム情報を取得できませんでした')));
        return;
      }

      final siblings = parentGpkg.children
          .whereType<LayerNode>()
          .where((l) => l != node && l.runtimeType == node.runtimeType)
          .toList();
      if (siblings.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('同じ型の他のレイヤーがありません')));
        return;
      }

      final systemCols = {'id', 'fid', 'geom', 'geometry', 'ROWID'};
      bool columnsMatch(List<String> a, List<String> b) {
        final a1 = a.where((c) => !systemCols.contains(c.toLowerCase())).toSet();
        final b1 = b.where((c) => !systemCols.contains(c.toLowerCase())).toSet();
        return a1.length == b1.length && a1.containsAll(b1);
      }

      final matching = <LayerNode>[];
      for (final layer in siblings) {
        final cols = await parentGpkg.geoPackageFile.getTableColumns(layer.name);
        if (columnsMatch(targetColumns, cols)) matching.add(layer);
      }
      if (matching.isEmpty) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('カラム構造が一致するレイヤーが見つかりません')));
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
              Text('以下の ${matching.length} 件のレイヤーを「${node.name}」に吸収しますか？\n'),
              ...matching.map((l) => Text('  • ${l.name}')),
              const SizedBox(height: 12),
              const Text('※吸収されたレイヤーは削除されます', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('吸収')),
          ],
        ),
      );
      if (confirm != true) return;

      int count = 0;
      for (final src in matching) {
        final copied = await parentGpkg.geoPackageFile.copyFeaturesBetweenLayers(src.name, node.name);
        if (copied > 0) {
          count += copied;
          src.dispose();
        }
      }

      await node.updateChildren();
      ref.read(featureRefreshTriggerProvider.notifier).trigger();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count 件のフィーチャを吸収しました')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('吸収処理中にエラーが発生しました: $e')));
      }
    }
  }
}

/// GeoPackage 内レイヤ追加ボタン
class AddLayerButton extends ConsumerWidget {
  final GeoPackageNode node;

  const AddLayerButton({super.key, required this.node});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog<Map<String, String>>(
          context: context,
          builder: (_) => const _NewLayerDialog(),
        );
        if (result == null || result['name'] == null) return;

        final geomType = GeometryType.fromString(result['geomType']!);
        try {
          final created = switch (geomType) {
            GeometryType.point => await PointLayerNode.createIn(node, result['name']!),
            GeometryType.linestring => await LineLayerNode.createIn(node, result['name']!),
            GeometryType.polygon => await PolygonLayerNode.createIn(node, result['name']!),
            null => null,
          };
          if (created != null) {
            ref.read(featureRefreshTriggerProvider.notifier).trigger();
          }
        } catch (_) {}
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 24),
          SizedBox(width: 8),
          Text('Add Layer', style: TextStyle(fontSize: 16, color: Colors.black87)),
        ],
      ),
    );
  }
}

/// レイヤ新規作成ダイアログ
class _NewLayerDialog extends StatefulWidget {
  const _NewLayerDialog();

  @override
  _NewLayerDialogState createState() => _NewLayerDialogState();
}

class _NewLayerDialogState extends State<_NewLayerDialog> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  GeometryType _geomType = GeometryType.point;
  bool _isUserInput = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _geomType.defaultLayerName);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) _selectAll();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectAll());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAll() {
    _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length);
  }

  void _create() {
    final name = _controller.text.trim();
    Navigator.pop(context, {
      'name': name.isEmpty ? _geomType.defaultLayerName : name,
      'geomType': _geomType.value,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新規レイヤ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(labelText: 'レイヤ名', hintText: _geomType.defaultLayerName),
            onTap: _selectAll,
            onChanged: (v) => _isUserInput = v.isNotEmpty && v != _geomType.defaultLayerName,
            onSubmitted: (_) => _create(),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GeometryType>(
            initialValue: _geomType,
            decoration: const InputDecoration(labelText: 'ジオメトリタイプ'),
            items: [
              DropdownMenuItem(value: GeometryType.point, child: Text(GeometryType.point.displayName)),
              DropdownMenuItem(value: GeometryType.linestring, child: Text(GeometryType.linestring.displayName)),
              DropdownMenuItem(value: GeometryType.polygon, child: Text(GeometryType.polygon.displayName)),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() {
                _geomType = v;
                if (!_isUserInput) {
                  _controller.text = _geomType.defaultLayerName;
                  _selectAll();
                }
              });
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, null), child: const Text('キャンセル')),
        TextButton(onPressed: _create, child: const Text('作成')),
      ],
    );
  }
}
