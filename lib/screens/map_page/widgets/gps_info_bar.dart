// K-MAPS: GPS情報バーウィジェット
// AppBar下部に表示するGPS情報バー
import 'package:flutter/material.dart';

/// GPS情報バーウィジェット
/// 現在のGPS位置情報、精度、ソースを表示
class GpsInfoBar extends StatelessWidget {
  /// GPS情報（null または isActive=false の場合は「取得中」表示）
  final Map<String, dynamic>? gpsInfo;
  
  /// GPS取得待機秒数
  final int gpsWaitSeconds;
  
  /// コンパス方角（度数）
  final double? currentHeading;

  const GpsInfoBar({
    super.key,
    required this.gpsInfo,
    required this.gpsWaitSeconds,
    this.currentHeading,
  });

  @override
  Widget build(BuildContext context) {
    if (gpsInfo == null || gpsInfo!['isActive'] != true) {
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
              '($gpsWaitSeconds秒経過)',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(width: 16),
            Text('ソース: ${gpsInfo?['sourceName'] ?? '不明'}'),
          ],
        ),
      ),
    );
  }

  /// GPS受信中表示
  Widget _buildActiveBar() {
    final latitude = gpsInfo!['latitude'];
    final longitude = gpsInfo!['longitude'];
    final accuracy = gpsInfo!['accuracy'];
    final satelliteCount = gpsInfo!['satelliteCount'];
    final hdop = gpsInfo!['hdop'];
    final sourceName = gpsInfo!['sourceName'] ?? 'GPS';
    final sourceType = gpsInfo!['sourceType'];
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
            // 外部GNSS機器の場合のみ衛星情報とHDOPを表示
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
            // コンパス情報を表示
            if (currentHeading != null) ...[
              const SizedBox(width: 16),
              Text('方角: ${currentHeading!.toStringAsFixed(0)}°'),
            ],
          ],
        ),
      ),
    );
  }
}

