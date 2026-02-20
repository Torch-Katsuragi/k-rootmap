/// GPS軌跡抽出ダイアログ
///
/// GpsHistoryRecorder から日付別のGPS軌跡を読み取り、
/// 時間範囲の切り取り・Douglas-Peucker簡略化・ライン保存を行う。
/// 保存時は抽出範囲のポイント詳細をsub_table JSONとして付与。
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../models/gps_track.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../services/gps_history_recorder.dart';
import '../utils/app_logger.dart';
import '../utils/feature_calc_utils.dart';
import '../utils/global_config.dart';

/// GPS軌跡抽出ダイアログ
class TrackExtractionDialog extends StatefulWidget {
  final GpsHistoryRecorder recorder;

  const TrackExtractionDialog({super.key, required this.recorder});

  @override
  State<TrackExtractionDialog> createState() => _TrackExtractionDialogState();
}

class _TrackExtractionDialogState extends State<TrackExtractionDialog> {
  // 日付選択
  List<String> _availableDates = [];
  String? _selectedDate;

  // 読み込んだポイント
  List<GpsTrackPoint> _allPoints = [];
  List<GpsTrackPoint> _selectedPoints = [];

  // 時間範囲
  RangeValues? _timeRange;
  double _timeMin = 0;
  double _timeMax = 1;

  // 簡略化
  double _tolerance = 5.0;
  List<LatLng> _simplifiedLine = [];

  // ローディング
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableDates();
  }

  /// 利用可能な日付を読み込み
  Future<void> _loadAvailableDates() async {
    setState(() => _isLoading = true);

    final dates = await widget.recorder.getAvailableDates();
    if (!mounted) return;

    setState(() {
      _availableDates = dates;
      _selectedDate = dates.isNotEmpty ? dates.first : null;
    });

    if (_selectedDate != null) {
      await _loadPointsForDate(_selectedDate!);
    } else {
      setState(() => _isLoading = false);
    }
  }

  /// 特定日付のポイントを読み込み
  Future<void> _loadPointsForDate(String layerName) async {
    setState(() => _isLoading = true);

    final points = await widget.recorder.getPointsForDate(layerName);
    if (!mounted) return;

    setState(() {
      _allPoints = points;
      _isLoading = false;

      if (points.isNotEmpty) {
        _timeMin = 0;
        _timeMax = (points.length - 1).toDouble();
        _timeRange = RangeValues(_timeMin, _timeMax);
        _updateSelection();
      } else {
        _timeRange = null;
        _selectedPoints = [];
        _simplifiedLine = [];
      }
    });
  }

  /// 選択範囲のポイントと簡略化を更新
  void _updateSelection() {
    if (_allPoints.isEmpty || _timeRange == null) return;

    final start = _timeRange!.start.round();
    final end = _timeRange!.end.round();
    _selectedPoints = _allPoints.sublist(
      start.clamp(0, _allPoints.length - 1),
      (end + 1).clamp(0, _allPoints.length),
    );

    _updateSimplification();
  }

  /// 簡略化を更新
  void _updateSimplification() {
    if (_selectedPoints.length < 2) {
      _simplifiedLine = _selectedPoints.map((p) => p.toLatLng()).toList();
      return;
    }

    final line = _selectedPoints.map((p) => p.toLatLng()).toList();
    _simplifiedLine = LineSimplification.simplifyLineDouglasPeucker(
      line,
      _tolerance,
    );
    setState(() {});
  }

  /// 距離を計算（メートル）
  double _calculateDistance(List<LatLng> points) {
    if (points.length < 2) return 0;
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += _haversineDistance(points[i - 1], points[i]);
    }
    return total;
  }

  double _haversineDistance(LatLng p1, LatLng p2) {
    const R = 6371000.0;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1.latitude * math.pi / 180) *
            math.cos(p2.latitude * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// 時間を表示用にフォーマット
  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  /// 時間差を表示用にフォーマット
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}時間${d.inMinutes % 60}分';
    } else if (d.inMinutes > 0) {
      return '${d.inMinutes}分${d.inSeconds % 60}秒';
    }
    return '${d.inSeconds}秒';
  }

  /// 選択ポイントからsub_table JSON文字列を構築
  String _buildSubTableJson() {
    final header = [
      'timestamp', 'latitude', 'longitude',
      'altitude', 'accuracy', 'speed', 'bearing', 'source_type',
    ];
    final rows = <List<dynamic>>[header];
    for (final pt in _selectedPoints) {
      rows.add([
        pt.timestamp.toIso8601String(),
        pt.latitude,
        pt.longitude,
        pt.altitude,
        pt.accuracy,
        pt.speed,
        pt.bearing,
        pt.sourceType,
      ]);
    }
    return jsonEncode(rows);
  }

  /// 保存処理
  Future<void> _saveTrack() async {
    if (_simplifiedLine.length < 2) return;

    // ラインレイヤ選択ダイアログ
    final lineLayer = await _selectLineLayer();
    if (lineLayer == null || !mounted) return;

    setState(() => _isSaving = true);

    try {
      final dateLabel =
          GpsHistoryRecorder.formatLayerNameAsDate(_selectedDate ?? '');

      final feature = await LineFeatureNode.createIn(
        lineLayer,
        _simplifiedLine,
        'GPS軌跡 $dateLabel',
        '${_selectedPoints.length}点から抽出、${_simplifiedLine.length}点に簡略化',
      );

      // sub_table JSON をフィーチャに付与
      if (feature != null && _selectedPoints.isNotEmpty) {
        try {
          await lineLayer.geoPackageFile.addAttributeColumn(
            lineLayer.layerName,
            'sub_table',
            'TEXT',
          );
        } catch (_) {
          // カラムが既に存在する場合は無視
        }

        final subTableJson = _buildSubTableJson();
        await feature.setAttributeValue('sub_table', subTableJson);
        await feature.flushChanges();
      }

      if (feature != null && mounted) {
        Navigator.of(context).pop(true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('軌跡の保存に失敗しました'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[TrackExtractionDialog] 保存エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存エラー: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// ラインレイヤ選択ダイアログ
  Future<LineLayerNode?> _selectLineLayer() async {
    final rootNode = GlobalConfig.instance.folderTree;
    if (rootNode == null) return null;

    // ラインレイヤを検索
    final lineLayers = <LineLayerNode>[];
    void searchLineLayers(LayerTreeNode node) {
      if (node is LineLayerNode) {
        lineLayers.add(node);
      }
      if (node is! FeatureNode) {
        for (final child in node.children) {
          searchLineLayers(child);
        }
      }
    }
    searchLineLayers(rootNode);

    if (lineLayers.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存先のラインレイヤがありません。先にラインレイヤを作成してください。'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return null;
    }

    return await showDialog<LineLayerNode>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('保存先ラインレイヤを選択'),
        content: SizedBox(
          width: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: lineLayers.length,
            itemBuilder: (context, index) {
              final layer = lineLayers[index];
              return ListTile(
                leading: const Icon(Icons.timeline, color: Colors.blue),
                title: Text(layer.name),
                subtitle: Text(layer.parent?.name ?? ''),
                onTap: () => Navigator.of(context).pop(layer),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('キャンセル'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 650,
        height: 600,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル
            const Text(
              'GPS軌跡の抽出',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 日付選択
            Row(
              children: [
                const Text('日付: '),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedDate,
                    isExpanded: true,
                    items: _availableDates.map((date) {
                      return DropdownMenuItem(
                        value: date,
                        child: Text(GpsHistoryRecorder.formatLayerNameAsDate(date)),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        _selectedDate = value;
                        _loadPointsForDate(value);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_allPoints.length}点',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // ローディング中
            if (_isLoading)
              const Expanded(
                child: Center(child: CircularProgressIndicator()),
              )
            // データなし
            else if (_allPoints.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    'この日付のGPS軌跡データがありません',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
              )
            // メインUI
            else ...[
              // 時間範囲スライダー
              if (_timeRange != null) ...[
                Row(
                  children: [
                    Text(
                      '開始: ${_formatTime(_allPoints[_timeRange!.start.round().clamp(0, _allPoints.length - 1)].timestamp)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    Text(
                      '終了: ${_formatTime(_allPoints[_timeRange!.end.round().clamp(0, _allPoints.length - 1)].timestamp)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                RangeSlider(
                  values: _timeRange!,
                  min: _timeMin,
                  max: _timeMax,
                  divisions: _allPoints.length > 1 ? _allPoints.length - 1 : 1,
                  onChanged: (values) {
                    setState(() {
                      _timeRange = values;
                    });
                  },
                  onChangeEnd: (values) {
                    _updateSelection();
                  },
                ),
              ],

              // プレビュー
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _TrackPreviewPainter(
                        allPoints: _allPoints.map((p) => p.toLatLng()).toList(),
                        selectedLine: _simplifiedLine,
                        startIndex: _timeRange?.start.round() ?? 0,
                        endIndex: _timeRange?.end.round() ?? _allPoints.length - 1,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // 統計情報
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '選択範囲: ${_selectedPoints.length}点 / 全体: ${_allPoints.length}点',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        if (_selectedPoints.length >= 2)
                          Expanded(
                            child: Text(
                              '時間: ${_formatDuration(_selectedPoints.last.timestamp.difference(_selectedPoints.first.timestamp))}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    if (_selectedPoints.length >= 2)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '距離: ${(_calculateDistance(_selectedPoints.map((p) => p.toLatLng()).toList()) / 1000).toStringAsFixed(2)}km',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              '簡略化後: ${_simplifiedLine.length}点 '
                              '(${_selectedPoints.isNotEmpty ? (100 - _simplifiedLine.length / _selectedPoints.length * 100).toStringAsFixed(0) : 0}%削減)',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // 簡略化スライダー
              Row(
                children: [
                  const Text('許容誤差: ', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: _tolerance,
                      min: 0.1,
                      max: 50.0,
                      divisions: 499,
                      onChanged: (value) {
                        setState(() => _tolerance = value);
                      },
                      onChangeEnd: (value) {
                        _updateSimplification();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text(
                      '${_tolerance.toStringAsFixed(1)}m',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),

              // 凡例
              Row(
                children: [
                  Container(width: 16, height: 2, color: Colors.grey.shade400),
                  const SizedBox(width: 4),
                  const Text('全軌跡', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 16),
                  Container(width: 16, height: 2, color: Colors.black),
                  const SizedBox(width: 4),
                  const Text('選択範囲', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 16),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('頂点', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],

            const SizedBox(height: 12),

            // ボタン
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  child: const Text('キャンセル'),
                ),
                const SizedBox(width: 16),
                ElevatedButton(
                  onPressed: _isSaving || _simplifiedLine.length < 2
                      ? null
                      : _saveTrack,
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('保存先を選択して保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 軌跡プレビュー用のCustomPainter
class _TrackPreviewPainter extends CustomPainter {
  final List<LatLng> allPoints;
  final List<LatLng> selectedLine;
  final int startIndex;
  final int endIndex;

  _TrackPreviewPainter({
    required this.allPoints,
    required this.selectedLine,
    required this.startIndex,
    required this.endIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (allPoints.isEmpty) return;

    // 全ポイントから座標範囲を計算
    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final point in allPoints) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    // マージンを追加
    final latMargin = (maxLat - minLat) * 0.1 + 0.0001;
    final lngMargin = (maxLng - minLng) * 0.1 + 0.0001;
    minLat -= latMargin;
    maxLat += latMargin;
    minLng -= lngMargin;
    maxLng += lngMargin;

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    // 座標変換関数
    Offset toOffset(LatLng point) {
      final x = (point.longitude - minLng) / lngRange * size.width;
      final y = (maxLat - point.latitude) / latRange * size.height;
      return Offset(x, y);
    }

    // 全軌跡を灰色で描画
    final allPaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    _drawLine(canvas, allPoints, toOffset, allPaint);

    // 選択範囲を黒で描画
    if (selectedLine.length >= 2) {
      final selectedPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      _drawLine(canvas, selectedLine, toOffset, selectedPaint);

      // 頂点を赤で表示
      final pointPaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;
      for (final point in selectedLine) {
        canvas.drawCircle(toOffset(point), 2.5, pointPaint);
      }
    }
  }

  void _drawLine(
    Canvas canvas,
    List<LatLng> line,
    Offset Function(LatLng) transform,
    Paint paint,
  ) {
    if (line.length < 2) return;

    final path = ui.Path();
    final startPoint = transform(line.first);
    path.moveTo(startPoint.dx, startPoint.dy);

    for (int i = 1; i < line.length; i++) {
      final point = transform(line[i]);
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
