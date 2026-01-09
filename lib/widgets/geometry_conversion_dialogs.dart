// lib/widgets/geometry_conversion_dialogs.dart
// ジオメトリ変換ダイアログウィジェット
import 'package:flutter/material.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../presentation/node_presenter.dart';

/// ポイント→ライン/ポリゴン変換ダイアログ
class ConvertPointsToGeometryDialog extends StatefulWidget {
  final PointLayerNode sourceLayer;
  final List<LayerNode> availableLayers;

  const ConvertPointsToGeometryDialog({
    super.key,
    required this.sourceLayer,
    required this.availableLayers,
  });

  @override
  State<ConvertPointsToGeometryDialog> createState() => _ConvertPointsToGeometryDialogState();
}

class _ConvertPointsToGeometryDialogState extends State<ConvertPointsToGeometryDialog> {
  late LayerNode _selectedLayer;

  @override
  void initState() {
    super.initState();
    _selectedLayer = widget.availableLayers.first;
  }

  String _getLayerTypeLabel(LayerNode layer) {
    if (layer is LineLayerNode) {
      return 'ライン';
    } else if (layer is PolygonLayerNode) {
      return 'ポリゴン';
    }
    return '不明';
  }

  @override
  Widget build(BuildContext context) {
    final selectedTypeLabel = _getLayerTypeLabel(_selectedLayer);
    
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.transform, color: Colors.blue),
          SizedBox(width: 8),
          Text('ポイント変換'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.sourceLayer.name} のポイント (${widget.sourceLayer.features.length}個) を$selectedTypeLabel に変換します。',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            // レイヤー選択
            const Text(
              '変換先のレイヤー:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<LayerNode>(
                  value: _selectedLayer,
                  isExpanded: true,
                  items: widget.availableLayers.map((layer) {
                    final typeLabel = _getLayerTypeLabel(layer);
                    return DropdownMenuItem(
                      value: layer,
                      child: Row(
                        children: [
                          NodePresenter.buildIcon(layer, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${layer.geoPackageNode.name} / ${layer.name} ($typeLabel)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedLayer = value;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(_selectedLayer),
          icon: const Icon(Icons.check),
          label: const Text('変換'),
        ),
      ],
    );
  }
}

/// ライン/ポリゴン→ポイント変換ダイアログ
class ConvertGeometryToPointsDialog extends StatefulWidget {
  final FeatureNode sourceFeature;
  final List<PointLayerNode> availableLayers;
  final int pointCount;

  const ConvertGeometryToPointsDialog({
    super.key,
    required this.sourceFeature,
    required this.availableLayers,
    required this.pointCount,
  });

  @override
  State<ConvertGeometryToPointsDialog> createState() => _ConvertGeometryToPointsDialogState();
}

class _ConvertGeometryToPointsDialogState extends State<ConvertGeometryToPointsDialog> {
  late PointLayerNode _selectedLayer;

  @override
  void initState() {
    super.initState();
    _selectedLayer = widget.availableLayers.first;
  }

  String _getFeatureTypeLabel() {
    if (widget.sourceFeature is LineFeatureNode) {
      return 'ライン';
    } else if (widget.sourceFeature is PolygonFeatureNode) {
      return 'ポリゴン';
    }
    return '不明';
  }

  @override
  Widget build(BuildContext context) {
    final typeLabel = _getFeatureTypeLabel();
    
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.scatter_plot, color: Colors.blue),
          SizedBox(width: 8),
          Text('ポイントに変換'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$typeLabel「${widget.sourceFeature.name}」の頂点 (${widget.pointCount}個) をポイントに変換します。',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            
            // レイヤー選択
            const Text(
              '追加先のポイントレイヤー:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<PointLayerNode>(
                  value: _selectedLayer,
                  isExpanded: true,
                  items: widget.availableLayers.map((layer) {
                    return DropdownMenuItem(
                      value: layer,
                      child: Row(
                        children: [
                          NodePresenter.buildIcon(layer, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${layer.geoPackageNode.name} / ${layer.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedLayer = value;
                      });
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('キャンセル'),
        ),
        ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(_selectedLayer),
          icon: const Icon(Icons.check),
          label: const Text('変換'),
        ),
      ],
    );
  }
}

