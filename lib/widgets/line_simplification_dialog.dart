import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/nodes/feature_node.dart';
import '../utils/feature_calc_utils.dart';
import 'dart:math' as math;
import 'dart:ui' as ui;

/// ライン簡略化ダイアログ
class LineSimplificationDialog extends StatefulWidget {
  final LineFeatureNode lineFeature;

  const LineSimplificationDialog({super.key, required this.lineFeature});

  @override
  State<LineSimplificationDialog> createState() =>
      _LineSimplificationDialogState();
}

class _LineSimplificationDialogState extends State<LineSimplificationDialog> {
  double _tolerance = 1.0; // 初期許容誤差1m
  List<LatLng> _simplifiedLine = [];
  Map<String, dynamic>? _stats;

  @override
  void initState() {
    super.initState();
    _updateSimplification();
  }

  void _updateSimplification() {
    final originalLine = widget.lineFeature.line;
    _simplifiedLine = LineSimplification.simplifyLineDouglasPeucker(
      originalLine,
      _tolerance,
    );
    _stats = LineSimplification.getSimplificationStats(
      originalLine,
      _simplifiedLine,
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 600,
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // タイトル
            Text(
              'ライン簡略化: ${widget.lineFeature.name}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 許容誤差スライダー
            Row(
              children: [
                const Text('許容誤差: '),
                Expanded(
                  child: Slider(
                    value: _tolerance,
                    min: 0.1,
                    max: 50.0,
                    divisions: 499,
                    label: '${_tolerance.toStringAsFixed(1)}m',
                    onChanged: (value) {
                      // ドラッグ中は値の表示のみ更新（計算は行わない）
                      setState(() {
                        _tolerance = value;
                      });
                    },
                    onChangeEnd: (value) {
                      // 指を離したときに計算を実行
                      _updateSimplification();
                    },
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${_tolerance.toStringAsFixed(1)}m'),
                ),
              ],
            ),

            // 統計情報
            if (_stats != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '統計情報:',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '点数: ${_stats!['originalPoints']} → ${_stats!['simplifiedPoints']}',
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '削減率: ${_stats!['pointReductionPercent']}',
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text('長さ誤差: ${_stats!['lengthErrorPercent']}'),
                        ),
                        Expanded(
                          child: Text(
                            '誤差距離: ${(_stats!['lengthError'] as double).toStringAsFixed(1)}m',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // プレビュー
            const Text('プレビュー:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
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
                    painter: LineComparisonPainter(
                      originalLine: widget.lineFeature.line,
                      simplifiedLine: _simplifiedLine,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // 凡例
            Row(
              children: [
                Container(width: 20, height: 2, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                const Text('元のライン'),
                const SizedBox(width: 24),
                Container(width: 20, height: 2, color: Colors.black),
                const SizedBox(width: 8),
                const Text('簡略化後'),
              ],
            ),

            const SizedBox(height: 16),

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
                  onPressed: () => Navigator.of(context).pop(_simplifiedLine),
                  child: const Text('適用'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 簡略化されたラインを取得
  List<LatLng> get simplifiedLine => _simplifiedLine;
}

/// ライン比較用のCustomPainter
class LineComparisonPainter extends CustomPainter {
  final List<LatLng> originalLine;
  final List<LatLng> simplifiedLine;

  LineComparisonPainter({
    required this.originalLine,
    required this.simplifiedLine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (originalLine.isEmpty) return;

    // 境界を計算
    double minLat = originalLine.first.latitude;
    double maxLat = originalLine.first.latitude;
    double minLng = originalLine.first.longitude;
    double maxLng = originalLine.first.longitude;

    for (final point in originalLine) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    // マージンを追加
    final latMargin = (maxLat - minLat) * 0.1;
    final lngMargin = (maxLng - minLng) * 0.1;
    minLat -= latMargin;
    maxLat += latMargin;
    minLng -= lngMargin;
    maxLng += lngMargin;

    final latRange = maxLat - minLat;
    final lngRange = maxLng - minLng;

    // 座標変換関数
    Offset latLngToOffset(LatLng point) {
      final x = (point.longitude - minLng) / lngRange * size.width;
      final y = (maxLat - point.latitude) / latRange * size.height;
      return Offset(x, y);
    }

    // 元のライン描画（薄い灰色）
    final originalPaint =
        Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    _drawLine(canvas, originalLine, latLngToOffset, originalPaint);

    // 簡略化後のライン描画（黒色）
    final simplifiedPaint =
        Paint()
          ..color = Colors.black
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;

    _drawLine(canvas, simplifiedLine, latLngToOffset, simplifiedPaint);

    // 簡略化後の点を強調表示
    final pointPaint =
        Paint()
          ..color = Colors.red
          ..style = PaintingStyle.fill;

    for (final point in simplifiedLine) {
      final offset = latLngToOffset(point);
      canvas.drawCircle(offset, 3, pointPaint);
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
