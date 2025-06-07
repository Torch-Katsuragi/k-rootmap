// lib/widgets/track_save_dialog.dart
// GPS軌跡保存ダイアログ
import 'package:flutter/material.dart';
import '../models/layer_tree_node.dart';
import '../models/gps_track.dart';

/// GPS軌跡保存ダイアログ
class TrackSaveDialog extends StatefulWidget {
  final GpsTrack track;
  final LayerTreeNode? rootNode;

  const TrackSaveDialog({super.key, required this.track, this.rootNode});

  @override
  State<TrackSaveDialog> createState() => _TrackSaveDialogState();
}

class _TrackSaveDialogState extends State<TrackSaveDialog> {
  final TextEditingController _trackNameController = TextEditingController();
  GeoPackageNode? _selectedGeoPackage;
  List<GeoPackageNode> _geoPackageNodes = [];

  @override
  void initState() {
    super.initState();
    _trackNameController.text = widget.track.trackName;
    _loadGeoPackageNodes();
  }

  @override
  void dispose() {
    _trackNameController.dispose();
    super.dispose();
  }

  /// 利用可能なGeoPackageノードを収集
  void _loadGeoPackageNodes() {
    final nodes = <GeoPackageNode>[];
    if (widget.rootNode != null) {
      _collectGeoPackageNodes(widget.rootNode!, nodes);
    }
    setState(() {
      _geoPackageNodes = nodes;
      if (nodes.isNotEmpty) {
        _selectedGeoPackage = nodes.first;
      }
    });
  }

  /// 再帰的にGeoPackageノードを収集
  void _collectGeoPackageNodes(LayerTreeNode node, List<GeoPackageNode> nodes) {
    if (node is GeoPackageNode) {
      nodes.add(node);
    }
    for (final child in node.children) {
      _collectGeoPackageNodes(child, nodes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final stats = widget.track.getStatistics();

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.directions_walk, color: Colors.green),
          SizedBox(width: 8),
          Text('GPS軌跡を保存'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 軌跡の統計情報
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('軌跡情報', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  _buildStatRow('ポイント数', '${stats['pointCount']}個'),
                  _buildStatRow(
                    '距離',
                    '${(stats['totalDistance'] / 1000).toStringAsFixed(2)}km',
                  ),
                  _buildStatRow('時間', _formatDuration(stats['duration'])),
                  _buildStatRow(
                    'GPS/GNSS',
                    '${stats['gpsPoints']}/${stats['gnssPoints']}ポイント',
                  ),
                  if (stats['averageSpeed'] > 0)
                    _buildStatRow(
                      '平均速度',
                      '${(stats['averageSpeed'] * 3.6).toStringAsFixed(1)}km/h',
                    ),
                ],
              ),
            ),
            SizedBox(height: 16),

            // 軌跡名入力
            TextField(
              controller: _trackNameController,
              decoration: InputDecoration(
                labelText: '軌跡名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            SizedBox(height: 16),

            // GeoPackage選択
            Text(
              '保存先GeoPackage:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            if (_geoPackageNodes.isEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[300]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'GeoPackageファイルが見つかりません。\n先にGeoPackageを作成してください。',
                        style: TextStyle(color: Colors.orange[800]),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<GeoPackageNode>(
                    value: _selectedGeoPackage,
                    isExpanded: true,
                    items:
                        _geoPackageNodes.map((gpkg) {
                          return DropdownMenuItem(
                            value: gpkg,
                            child: Row(
                              children: [
                                Icon(Icons.storage, size: 16),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    gpkg.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedGeoPackage = value;
                      });
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
          child: Text('キャンセル'),
        ),
        ElevatedButton.icon(
          onPressed:
              _geoPackageNodes.isEmpty
                  ? null
                  : () {
                    final trackName = _trackNameController.text.trim();
                    if (trackName.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('軌跡名を入力してください')));
                      return;
                    }
                    if (_selectedGeoPackage == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('保存先GeoPackageを選択してください')),
                      );
                      return;
                    }

                    // 軌跡名を設定して返す
                    widget.track.trackName = trackName;
                    Navigator.of(context).pop({
                      'track': widget.track,
                      'geoPackage': _selectedGeoPackage!,
                    });
                  },
          icon: Icon(Icons.save),
          label: Text('保存'),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(label)),
          Expanded(
            flex: 3,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;

    if (hours > 0) {
      return '$hours時間$minutes分';
    } else if (minutes > 0) {
      return '$minutes分$seconds秒';
    } else {
      return '$seconds秒';
    }
  }
}
