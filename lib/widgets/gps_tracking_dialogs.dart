// GPS追跡関連のダイアログウィジェット
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../i18n/strings.g.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/feature_node.dart';
import '../providers/ui_state_providers.dart';
import '../models/app_notification.dart';
import '../providers/notification_providers.dart';
import '../services/gps_manager_service.dart';
/// GPS追跡停止時の処理選択ダイアログ
class TrackingStopDialog extends StatefulWidget {
  final PointLayerNode pointLayer;
  final int pointCount;

  const TrackingStopDialog({
    super.key,
    required this.pointLayer,
    required this.pointCount,
  });

  @override
  State<TrackingStopDialog> createState() => _TrackingStopDialogState();
}

class _TrackingStopDialogState extends State<TrackingStopDialog> {
  LayerNode? _selectedTarget; // null = ポイントのみ保持
  bool _deletePointLayer = false;
  List<LayerNode> _availableLayers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadAvailableLayers();
  }

  Future<void> _loadAvailableLayers() async {
    // 同じGeoPackage内のライン/ポリゴンレイヤーを検索
    final geoPackageNode = _findParentGeoPackage(widget.pointLayer);
    if (geoPackageNode != null) {
      final layers = <LayerNode>[];
      void searchLayers(LayerTreeNode node) {
        if (node is LineLayerNode || node is PolygonLayerNode) {
          layers.add(node as LayerNode);
        }
        if (node is! FeatureNode) {
          for (final child in node.children) {
            searchLayers(child);
          }
        }
      }

      searchLayers(geoPackageNode);

      setState(() {
        _availableLayers = layers;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
      });
    }
  }

  GeoPackageNode? _findParentGeoPackage(LayerTreeNode node) {
    LayerTreeNode? current = node;
    while (current != null) {
      if (current is GeoPackageNode) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(t.gps.searchingLayers),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text(t.gps.trackingStopped),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.gps.pointsSaved(count: '${widget.pointCount}', layer: widget.pointLayer.name)),
          const SizedBox(height: 16),
          Text(t.gps.destination, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonHideUnderline(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
              child: DropdownButton<LayerNode?>(
                value: _selectedTarget,
                isExpanded: true,
                items: [
                  DropdownMenuItem<LayerNode?>(
                    value: null,
                    child: Text(t.gps.keepPointOnly),
                  ),
                  ..._availableLayers.map((layer) {
                    final typeLabel =
                        layer is LineLayerNode ? t.gps.lineType : t.gps.polygonType;
                    return DropdownMenuItem<LayerNode?>(
                      value: layer,
                      child: Text('${layer.name} $typeLabel'),
                    );
                  }),
                ],
                onChanged: (value) {
                  setState(() {
                    _selectedTarget = value;
                    // ポイントのみ保持の場合は削除フラグをリセット
                    if (value == null) {
                      _deletePointLayer = false;
                    }
                  });
                },
              ),
            ),
          ),
          // ポイントレイヤー削除チェックボックス（変換先が選択されている場合のみ表示）
          if (_selectedTarget != null) ...[
            const SizedBox(height: 16),
            CheckboxListTile(
              value: _deletePointLayer,
              onChanged: (value) {
                setState(() {
                  _deletePointLayer = value ?? false;
                });
              },
              title: Text(t.gps.deletePointLayer),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(t.common.cancel),
        ),
        ElevatedButton.icon(
          onPressed:
              () => Navigator.pop(context, {
                'targetLayer': _selectedTarget,
                'deletePoint': _deletePointLayer,
              }),
          icon: const Icon(Icons.check),
          label: Text(t.gps.confirm),
        ),
      ],
    );
  }
}

/// PointLayerNode選択ダイアログ（GPS追跡用）
class SelectPointLayerDialog extends ConsumerStatefulWidget {
  final List<PointLayerNode> pointLayers;

  const SelectPointLayerDialog({super.key, required this.pointLayers});

  @override
  ConsumerState<SelectPointLayerDialog> createState() => _SelectPointLayerDialogState();
}

class _SelectPointLayerDialogState extends ConsumerState<SelectPointLayerDialog> {
  PointLayerNode? _selectedLayer; // null = 新しいレイヤを作成
  int _intervalSeconds = 10; // 保存間隔（秒）
  int _minDistanceCm = 0; // 最小移動距離（cm）
  bool _useExternalGnss = false; // 外部GNSS使用フラグ
  final _intervalController = TextEditingController(text: '10');
  final _distanceController = TextEditingController(text: '0');
  final _newLayerNameController = TextEditingController(text: 'gps_track');
  final GpsManagerService _gpsManager = GpsManagerService();

  @override
  void initState() {
    super.initState();
    _selectedLayer = null; // 初期値は「新しいレイヤを作成」
    _initializeExternalGnssOption();
  }

  /// 外部GNSS使用オプションの初期化
  void _initializeExternalGnssOption() {
    // 外部GNSS機器が実際に接続されている場合、デフォルトで有効にする
    if (_gpsManager.isExternalGnssConnected) {
      setState(() {
        _useExternalGnss = true;
      });
    }
  }

  @override
  void dispose() {
    _intervalController.dispose();
    _distanceController.dispose();
    _newLayerNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.gps.trackSettings),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.gps.destination, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonHideUnderline(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: DropdownButton<PointLayerNode?>(
                  value: _selectedLayer,
                  isExpanded: true,
                  items: [
                    DropdownMenuItem<PointLayerNode?>(
                      value: null,
                      child: Text(t.gps.createNewLayer),
                    ),
                    ...widget.pointLayers.map((layer) {
                      return DropdownMenuItem<PointLayerNode?>(
                        value: layer,
                        child: Text(layer.name),
                      );
                    }),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedLayer = value;
                    });
                  },
                ),
              ),
            ),
            // 新規レイヤ名入力フィールド（新しいレイヤを作成する場合のみ表示）
            if (_selectedLayer == null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _newLayerNameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: t.gps.newLayerName,
                  hintText: 'gps_track',
                  border: const OutlineInputBorder(),
                ),
                onTap: () {
                  // タップ時に全選択
                  _newLayerNameController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _newLayerNameController.text.length,
                  );
                },
              ),
            ],
            const SizedBox(height: 24),
            Text(
              t.gps.saveOptions,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _intervalController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.gps.saveInterval,
                hintText: t.gps.intervalHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed >= 1) {
                  _intervalSeconds = parsed;
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _distanceController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t.gps.minDistance,
                hintText: t.gps.distanceHint,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null && parsed >= 0) {
                  _minDistanceCm = parsed;
                }
              },
            ),
            const SizedBox(height: 24),
            Text(t.gps.gpsSettings, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildExternalGnssOption(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(t.common.cancel),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            // バリデーション
            if (_intervalSeconds < 1) {
              ref.read(notificationCenterProvider.notifier).add(
                title: t.gps.intervalMinWarning,
                level: NotificationLevel.warning,
              );
              return;
            }

            PointLayerNode? targetLayer = _selectedLayer;

            // 新しいレイヤーを作成する場合
            if (_selectedLayer == null) {
              final newLayerName =
                  _newLayerNameController.text.trim().isEmpty
                      ? 'gps_track'
                      : _newLayerNameController.text.trim();

              // GeoPackageNodeを検索（プロジェクトルートから最初のGeoPackageを使用）
              final rootNode = ref.read(folderTreeProvider);
              if (rootNode == null) {
                ref.read(notificationCenterProvider.notifier).add(
                  title: t.gps.geopackageNotFound,
                  level: NotificationLevel.error,
                );
                return;
              }

              GeoPackageNode? geoPackageNode;
              void findGeoPackage(LayerTreeNode node) {
                if (geoPackageNode != null) return;
                if (node is GeoPackageNode) {
                  geoPackageNode = node;
                  return;
                }
                for (final child in node.children) {
                  findGeoPackage(child);
                }
              }

              findGeoPackage(rootNode);

              if (geoPackageNode == null) {
                ref.read(notificationCenterProvider.notifier).add(
                  title: t.gps.geopackageNotFound,
                  level: NotificationLevel.error,
                );
                return;
              }

              // 新しいPointLayerNodeを作成
              targetLayer = await PointLayerNode.createIn(
                geoPackageNode!,
                newLayerName,
              );
              if (targetLayer == null) {
                ref.read(notificationCenterProvider.notifier).add(
                  title: t.gps.layerCreateFailed,
                  level: NotificationLevel.error,
                );
                return;
              }
            }

            if (targetLayer != null && context.mounted) {
              Navigator.pop(context, {
                'layer': targetLayer,
                'intervalSeconds': _intervalSeconds,
                'minDistanceCm': _minDistanceCm,
                'useExternalGnss': _useExternalGnss,
              });
            }
          },
          icon: const Icon(Icons.check),
          label: Text(t.gps.confirm),
        ),
      ],
    );
  }

  /// 外部GNSS使用オプションのウィジェット
  Widget _buildExternalGnssOption() {
    // 実際にBluetooth接続が確立されているかを確認
    final isExternalConnected = _gpsManager.isExternalGnssConnected;
    final connectedDeviceName = _gpsManager.selectedGnssDevice?.name;

    if (!isExternalConnected) {
      // 外部GNSS機器が接続されていない場合は表示しない
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: _useExternalGnss,
              onChanged: (value) {
                setState(() {
                  _useExternalGnss = value ?? false;
                });
              },
              title: Row(
                children: [
                  const Icon(Icons.bluetooth_connected, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(t.gps.useExternalGnss),
                ],
              ),
              subtitle: Text(
                t.gps.connected(name: connectedDeviceName ?? t.gps.unknownDevice),
                style: const TextStyle(color: Colors.green),
              ),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_useExternalGnss)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8),
                child: Text(
                  t.gps.externalGnssDesc(name: connectedDeviceName ?? t.gps.unknownDevice),
                  style: TextStyle(color: Colors.blue[700], fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
