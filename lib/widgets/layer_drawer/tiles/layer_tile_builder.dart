/// K-MAPS: レイヤタイル構築ミックスイン
library;

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/layer_node.dart';
import '../../../models/nodes/feature_node.dart';
import '../../../models/nodes/geopackage_node.dart';
import '../../../models/geometry_type.dart';
import '../../../providers/selection_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../widgets/dialog_manager.dart';
import '../../../screens/layer_style_settings_screen.dart';
import '../../../presentation/node_presenter.dart';
import '../layer_drawer.dart';

mixin LayerTileBuilder on ConsumerState<LayerDrawer> {
  void triggerMapRefresh();
  LayerTreeNode? get currentNode;

  bool get isDragging;
  set isDragging(bool value);
  GeoPackageNode? get dragTargetGeoPackageNode;
  set dragTargetGeoPackageNode(GeoPackageNode? node);

  Future<void> convertPointsToLine(BuildContext context, PointLayerNode sourceLayer);
  Future<void> mergePolygonsInLayer(BuildContext context, PolygonLayerNode layerNode);
  Future<void> absorbMatchingLayers(BuildContext context, LayerNode targetNode);

  /// レイヤタイルを構築（可視切り替え・選択・削除・ドラッグアンドドロップ）
  Widget buildLayerTile(BuildContext context, LayerNode node) {
    final isSelected = ref.read(selectedLayerNodeProvider) == node;

    final layerTileContent = GestureDetector(
      onTap: () {
        ref.read(selectedLayerNodeProvider.notifier).select(node);
        setState(() {});
      },
      onDoubleTap: () {
        final coords = node.getAllCoordinates();
        if (coords.isEmpty) return;
        final mapController = ref.read(mapControllerHolderProvider);
        if (mapController == null) return;
        mapController.fitCoordinates(
          coords,
          padding: const EdgeInsets.all(50),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        leading: GestureDetector(
          onTap: () {
            node.visible = !node.visible;
            node.persistVisibility();
            ref.read(featureRefreshTriggerProvider.notifier).trigger();
            setState(() {});
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.transparent,
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  NodePresenter.getIcon(node),
                  color:
                      isSelected
                          ? Colors.blue
                          : (node.isVisibleRecursive()
                              ? NodePresenter.getColor(node)
                              : Colors.grey),
                ),
              ),
              if (!node.visible)
                Transform.rotate(
                  angle: -0.7,
                  child: Container(width: 32, height: 4, color: Colors.grey),
                ),
            ],
          ),
        ),
        title: Text(
          node.name,
          style: TextStyle(
            color:
                isSelected
                    ? Colors.blue
                    : (node.isVisibleRecursive() ? null : Colors.grey),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            await _showRenameLayerDialog(context, node);
          } else if (value == 'style') {
            await _openLayerStyleSettings(context, node);
          } else if (value == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('レイヤ削除'),
                    content: Text('${node.name} を本当に削除しますか？'),
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
              if (ref.read(selectedLayerNodeProvider) == node) {
                ref.read(selectedLayerNodeProvider.notifier).select(null);
              }

              ref.read(selectedFeaturesProvider.notifier).set(
                ref.read(selectedFeaturesProvider).where((feature) {
                  if (feature is FeatureNode) {
                    return feature.parent != node;
                  }
                  return true;
                }).toList(),
              );

              node.dispose();

              triggerMapRefresh();

              setState(() {});
            }
          } else if (value == 'export') {
            await DialogManager.showLayerExportDialog(
              context,
              sourceLayer: node,
            );
          } else if (value == 'convert_to_line' && node is PointLayerNode) {
            await convertPointsToLine(context, node);
          } else if (value == 'merge' && node is PolygonLayerNode) {
            await mergePolygonsInLayer(context, node);
          } else if (value == 'absorb') {
            await absorbMatchingLayers(context, node);
          }
        },
        itemBuilder:
            (context) => [
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 16),
                    SizedBox(width: 8),
                    Text('Rename'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'style',
                child: Row(
                  children: [
                    Icon(Icons.palette, size: 16),
                    SizedBox(width: 8),
                    Text('Style'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download, size: 16),
                    SizedBox(width: 8),
                    Text('Export Layer'),
                  ],
                ),
              ),
              if (node is PointLayerNode)
                const PopupMenuItem(
                  value: 'convert_to_line',
                  child: Row(
                    children: [
                      Icon(Icons.transform, size: 16),
                      SizedBox(width: 8),
                      Text('ライン/ポリゴンに変換'),
                    ],
                  ),
                ),
              if (node is PolygonLayerNode)
                const PopupMenuItem(value: 'merge', child: Text('合成')),
              const PopupMenuItem(
                value: 'absorb',
                child: Row(
                  children: [
                    Icon(Icons.merge_type, size: 16),
                    SizedBox(width: 8),
                    Text('同構造レイヤを吸収'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('削除')),
            ],
      ),
      ),
    );

    // LongPressDraggableでラップしてドラッグ機能を追加
    return LongPressDraggable<LayerNode>(
      data: node,
      dragAnchorStrategy:
          (draggable, context, position) => const Offset(0, 0),
      feedback: Material(
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
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.drag_indicator, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Opacity(opacity: 0.5, child: layerTileContent),
      ),
      onDragStarted: () {
        AppLogger.debug('[LayerDrawer] レイヤドラッグ開始: ${node.name}');
        isDragging = true;
        setState(() {});
      },
      onDragEnd: (details) {
        AppLogger.debug('[LayerDrawer] レイヤドラッグ終了: ${node.name}');
        isDragging = false;
        dragTargetGeoPackageNode = null;
        setState(() {});
      },
      child: layerTileContent,
    );
  }

  /// レイヤ追加ボタンを構築
  Widget buildAddLayerButton(BuildContext context, GeoPackageNode node) {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog<Map<String, String>>(
          context: context,
          builder: (context) => _NewLayerDialog(),
        );
        if (result != null &&
            result['name'] != null) {
          AppLogger.debug(
            '[LayerDrawer] レイヤ作成開始: ${result['name']}, タイプ: ${result['geomType']}',
          );

          LayerTreeNode? newLayerNode;
          final geomTypeString = result['geomType']!;
          final geomType = GeometryType.fromString(geomTypeString);

          AppLogger.debug('[LayerDrawer] ジオメトリタイプ解析: $geomTypeString -> $geomType');

          try {
            switch (geomType) {
              case GeometryType.point:
                AppLogger.debug('[LayerDrawer] PointLayerNode作成中...');
                newLayerNode = await PointLayerNode.createIn(
                  node,
                  result['name']!,
                );
                break;
              case GeometryType.linestring:
                AppLogger.debug('[LayerDrawer] LineLayerNode作成中...');
                newLayerNode = await LineLayerNode.createIn(
                  node,
                  result['name']!,
                );
                break;
              case GeometryType.polygon:
                AppLogger.debug('[LayerDrawer] PolygonLayerNode作成中...');
                newLayerNode = await PolygonLayerNode.createIn(
                  node,
                  result['name']!,
                );
                break;
              case null:
                AppLogger.debug('[LayerDrawer] 不明なジオメトリタイプです');
                break;
            }

            if (newLayerNode != null) {
              AppLogger.debug('[LayerDrawer] レイヤ作成成功、UI更新中...');
              setState(() {});
              ref.read(featureRefreshTriggerProvider.notifier).trigger();
              AppLogger.debug('[LayerDrawer] レイヤ作成完了');
            } else {
              AppLogger.debug('[LayerDrawer] レイヤ作成失敗: newLayerNodeがnull');
            }
          } catch (e, stack) {
            AppLogger.debug('[LayerDrawer] レイヤ作成エラー: $e');
            AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
          }
        }
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, size: 24),
          SizedBox(width: 8),
          Text(
            'Add Layer',
            style: TextStyle(fontSize: 16, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  /// レイヤー名変更ダイアログ
  Future<void> _showRenameLayerDialog(
    BuildContext context,
    LayerNode node,
  ) async {
    final controller = TextEditingController(text: node.layerName);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Layer'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Layer Name',
              hintText: 'Enter new layer name',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name cannot be empty';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName != node.layerName) {
      try {
        await node.geoPackageFile.renameLayer(node.layerName, newName);
        await node.geoPackageNode.updateChildren();
        triggerMapRefresh();
        setState(() {});
        AppLogger.debug('[LayerDrawer] Layer renamed: ${node.layerName} -> $newName');
      } catch (e) {
        AppLogger.debug('[LayerDrawer] Rename failed: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rename failed: $e')),
          );
        }
      }
    }
  }

  /// スタイル設定画面を開く
  Future<void> _openLayerStyleSettings(
    BuildContext context,
    LayerNode node,
  ) async {
    final folderNode = node.folderNode;
    final folderPath = folderNode?.getAbsoluteFilePath();

    if (folderPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine folder path')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LayerStyleSettingsScreen(
          targetLayer: node,
          folderPath: folderPath,
        ),
      ),
    );

    triggerMapRefresh();
    setState(() {});
  }
}

/// レイヤ新規作成ダイアログ
class _NewLayerDialog extends StatefulWidget {
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
      if (_focusNode.hasFocus) {
        _selectAllText();
      }
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectAllText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _selectAllText() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  String _getLayerName() {
    final input = _controller.text.trim();
    return input.isEmpty ? _geomType.defaultLayerName : input;
  }

  void _createLayer() {
    Navigator.pop(context, {
      'name': _getLayerName(),
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
            decoration: InputDecoration(
              labelText: 'レイヤ名',
              hintText: _geomType.defaultLayerName,
            ),
            onTap: () {
              _selectAllText();
            },
            onChanged: (value) {
              _isUserInput = value.isNotEmpty && value != _geomType.defaultLayerName;
            },
            onSubmitted: (value) {
              _createLayer();
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GeometryType>(
            initialValue: _geomType,
            decoration: const InputDecoration(labelText: 'ジオメトリタイプ'),
            items: [
              DropdownMenuItem(
                value: GeometryType.point,
                child: Text(GeometryType.point.displayName),
              ),
              DropdownMenuItem(
                value: GeometryType.linestring,
                child: Text(GeometryType.linestring.displayName),
              ),
              DropdownMenuItem(
                value: GeometryType.polygon,
                child: Text(GeometryType.polygon.displayName),
              ),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _geomType = v;
                  if (!_isUserInput) {
                    _controller.text = _geomType.defaultLayerName;
                    _selectAllText();
                  }
                });
              }
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: _createLayer,
          child: const Text('作成'),
        ),
      ],
    );
  }
}
