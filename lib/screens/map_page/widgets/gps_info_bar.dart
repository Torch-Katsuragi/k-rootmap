// K-MAPS: GPS情報バーウィジェット
// AppBar下部に表示するGPS情報バー
// GPS待機タイマーを内部管理し、MapPage全体のsetStateを回避
import 'dart:async';
import 'package:flutter/material.dart';

/// GPS情報バーウィジェット
/// 現在のGPS位置情報、精度、ソースを表示
/// GPS待機タイマーは内部でStatefulに管理
class GpsInfoBar extends StatefulWidget {
  /// GPS情報（null または isActive=false の場合は「取得中」表示）
  final Map<String, dynamic>? gpsInfo;

  /// コンパス方角（ValueNotifier経由）
  final ValueNotifier<double?> headingNotifier;

  const GpsInfoBar({
    super.key,
    required this.gpsInfo,
    required this.headingNotifier,
  });

  @override
  State<GpsInfoBar> createState() => _GpsInfoBarState();
}

class _GpsInfoBarState extends State<GpsInfoBar> {
  int _waitSeconds = 0;
  Timer? _waitTimer;

  @override
  void initState() {
    super.initState();
    _updateTimer();
  }

  @override
  void didUpdateWidget(covariant GpsInfoBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GPS情報の active 状態が変わった場合にタイマーを制御
    if (_isActive(widget.gpsInfo) != _isActive(oldWidget.gpsInfo)) {
      _updateTimer();
    }
  }

  @override
  void dispose() {
    _waitTimer?.cancel();
    super.dispose();
  }

  bool _isActive(Map<String, dynamic>? info) =>
      info != null && info['isActive'] == true;

  /// GPS受信状態に応じてタイマーを開始/停止
  void _updateTimer() {
    if (_isActive(widget.gpsInfo)) {
      // GPS受信中: タイマー停止
      _waitTimer?.cancel();
      _waitTimer = null;
    } else if (_waitTimer == null) {
      // GPS未受信: 待機カウント開始
      _waitSeconds = 0;
      _waitTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _waitSeconds++);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isActive(widget.gpsInfo)) {
      return _buildWaitingBar();
    }
    return _buildActiveBar();
  }

  /// GPS取得中表示
  Widget _buildWaitingBar() {
    return Container(
      height: 48,
      color: Colors.grey[200],
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(Icons.gps_off, size: 18, color: Colors.grey),
            const SizedBox(width: 8),
            const Text('GPS: 取得中...'),
            const SizedBox(width: 12),
            Text(
              '($_waitSeconds秒経過)',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(width: 16),
            Text('ソース: ${widget.gpsInfo?['sourceName'] ?? '不明'}'),
          ],
        ),
      ),
    );
  }

  /// GPS受信中表示
  Widget _buildActiveBar() {
    final gpsInfo = widget.gpsInfo!;
    final latitude = gpsInfo['latitude'];
    final longitude = gpsInfo['longitude'];
    final accuracy = gpsInfo['accuracy'];
    final satelliteCount = gpsInfo['satelliteCount'];
    final hdop = gpsInfo['hdop'];
    final sourceName = gpsInfo['sourceName'] ?? 'GPS';
    final sourceType = gpsInfo['sourceType'];
    final isExternalGnss = sourceType == 'GNSS';

    return Container(
      height: 48,
      color: Colors.lightBlue[50],
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              isExternalGnss ? Icons.bluetooth : Icons.gps_fixed,
              size: 18,
              color: Colors.blue,
            ),
            const SizedBox(width: 8),
            Text(
              'Lat: ${latitude?.toStringAsFixed(6) ?? "取得中"} Lon: ${longitude?.toStringAsFixed(6) ?? "取得中"}',
              style: const TextStyle(fontSize: 14),
            ),
            if (accuracy != null) ...[
              const SizedBox(width: 16),
              Text('精度: ±${accuracy.toStringAsFixed(1)}m'),
            ],
            if (isExternalGnss) ...[
              if (satelliteCount != null) ...[
                const SizedBox(width: 16),
                Text('衛星数: $satelliteCount基'),
              ],
              if (hdop != null) ...[
                const SizedBox(width: 16),
                Text('HDOP: ${hdop.toStringAsFixed(2)}'),
              ],
            ],
            const SizedBox(width: 16),
            Text('ソース: $sourceName'),
            // コンパス情報（ValueListenableBuilderで局所再描画）
            ValueListenableBuilder<double?>(
              valueListenable: widget.headingNotifier,
              builder: (_, heading, __) {
                if (heading == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Text('方角: ${heading.toStringAsFixed(0)}°'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
