/// GPS情報表示ウィジェット
///
/// 統合GPS管理サービスから取得したGPS情報を
/// 見やすい形式で表示するためのウィジェット
///
/// Features:
/// - GPS位置情報の詳細表示
/// - GPS精度・信号強度の視覚的表示
/// - GPS状態インジケーター
/// - ソース情報の表示
library;

import 'package:flutter/material.dart';

/// GPS情報表示ウィジェット
class GpsInfoWidget extends StatelessWidget {
  /// GPS情報データ
  final Map<String, dynamic> gpsInfo;

  /// 詳細情報の表示/非表示
  final bool showDetails;

  /// コンパクト表示モード
  final bool isCompact;

  const GpsInfoWidget({
    super.key,
    required this.gpsInfo,
    this.showDetails = true,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      return _buildCompactView(context);
    } else {
      return _buildDetailedView(context);
    }
  }

  /// 詳細表示ビュー
  Widget _buildDetailedView(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // GPS状態表示
        _buildGpsStatusRow(),

        if (showDetails) ...[
          const SizedBox(height: 12),
          const Divider(),

          // 位置情報
          _buildPositionSection(),

          const SizedBox(height: 12),

          // 精度・信号情報
          _buildAccuracySection(),

          const SizedBox(height: 12),

          // ソース情報
          _buildSourceSection(),

          const SizedBox(height: 12),

          // 時刻情報
          _buildTimestampSection(),
        ],
      ],
    );
  }

  /// コンパクト表示ビュー
  Widget _buildCompactView(BuildContext context) {
    final isActive = gpsInfo['isActive'] == true;
    final latitude = gpsInfo['latitude'];
    final longitude = gpsInfo['longitude'];
    final accuracy = gpsInfo['accuracy'];

    return Row(
      children: [
        // GPS状態アイコン
        Icon(
          isActive ? Icons.gps_fixed : Icons.gps_off,
          color: isActive ? Colors.green : Colors.grey,
          size: 20,
        ),
        const SizedBox(width: 8),

        // 位置情報（簡略表示）
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (latitude != null && longitude != null)
                Text(
                  '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                )
              else
                const Text(
                  '位置情報取得中...',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              if (accuracy != null)
                Text(
                  '精度: ±${accuracy.toStringAsFixed(1)}m',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
            ],
          ),
        ),

        // ソース表示
        Text(
          gpsInfo['sourceName'] ?? 'GPS',
          style: const TextStyle(fontSize: 10, color: Colors.blue),
        ),
      ],
    );
  }

  /// GPS状態表示行
  Widget _buildGpsStatusRow() {
    final isActive = gpsInfo['isActive'] == true;
    final isInitialized = gpsInfo['isInitialized'] == true;
    final sourceName = gpsInfo['sourceName'] ?? '不明';

    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (!isInitialized) {
      statusColor = Colors.orange;
      statusText = 'GPS初期化中...';
      statusIcon = Icons.gps_not_fixed;
    } else if (isActive) {
      statusColor = Colors.green;
      statusText = 'GPS受信中 ($sourceName)';
      statusIcon = Icons.gps_fixed;
    } else {
      statusColor = Colors.grey;
      statusText = 'GPS停止中 ($sourceName)';
      statusIcon = Icons.gps_off;
    }

    return Row(
      children: [
        Icon(statusIcon, color: statusColor, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
              if (gpsInfo['usesForegroundService'] == true)
                const Text(
                  'フォアグラウンドサービス経由',
                  style: TextStyle(fontSize: 12, color: Colors.blue),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// 位置情報セクション
  Widget _buildPositionSection() {
    final latitude = gpsInfo['latitude'];
    final longitude = gpsInfo['longitude'];
    final altitude = gpsInfo['altitude'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '位置情報',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          '緯度',
          latitude != null ? '${latitude.toStringAsFixed(6)}°' : '取得中...',
        ),
        _buildInfoRow(
          '経度',
          longitude != null ? '${longitude.toStringAsFixed(6)}°' : '取得中...',
        ),
        if (altitude != null)
          _buildInfoRow('標高', '${altitude.toStringAsFixed(1)}m'),
      ],
    );
  }

  /// 精度・信号情報セクション
  Widget _buildAccuracySection() {
    final accuracy = gpsInfo['accuracy'];
    final speed = gpsInfo['speed'];
    final bearing = gpsInfo['bearing'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '精度・移動情報',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (accuracy != null) ...[
          _buildInfoRow('位置精度', '±${accuracy.toStringAsFixed(1)}m'),
          _buildAccuracyIndicator(accuracy),
        ] else
          _buildInfoRow('位置精度', '取得中...'),

        if (speed != null && speed > 0)
          _buildInfoRow('移動速度', '${(speed * 3.6).toStringAsFixed(1)} km/h'),

        if (bearing != null)
          _buildInfoRow('移動方向', '${bearing.toStringAsFixed(0)}°'),
      ],
    );
  }

  /// 精度インジケーター
  Widget _buildAccuracyIndicator(double accuracy) {
    Color accuracyColor;
    String accuracyLabel;

    if (accuracy <= 3.0) {
      accuracyColor = Colors.green;
      accuracyLabel = '高精度';
    } else if (accuracy <= 10.0) {
      accuracyColor = Colors.orange;
      accuracyLabel = '中精度';
    } else {
      accuracyColor = Colors.red;
      accuracyLabel = '低精度';
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: accuracyColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            accuracyLabel,
            style: TextStyle(
              fontSize: 12,
              color: accuracyColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// ソース情報セクション
  Widget _buildSourceSection() {
    final sourceType = gpsInfo['sourceType'] ?? '不明';
    final sourceName = gpsInfo['sourceName'] ?? '不明';
    final selectedDevice = gpsInfo['selectedDevice'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GPS ソース',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildInfoRow('ソース種別', sourceType),
        _buildInfoRow('ソース名', sourceName),
        if (selectedDevice != null) _buildInfoRow('デバイス', selectedDevice),
      ],
    );
  }

  /// 時刻情報セクション
  Widget _buildTimestampSection() {
    final timestamp = gpsInfo['timestamp'];
    final isSurveyMode = gpsInfo['isSurveyMode'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '時刻情報',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        _buildInfoRow(
          '最終更新',
          timestamp != null ? _formatTimestamp(timestamp) : '未取得',
        ),
        if (isSurveyMode)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Row(
              children: [
                Icon(Icons.engineering, size: 16, color: Colors.blue),
                SizedBox(width: 4),
                Text(
                  'GPS測量モード',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 情報行ウィジェット
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const Text(' : ', style: TextStyle(fontSize: 12, color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  /// タイムスタンプのフォーマット
  String _formatTimestamp(String timestamp) {
    try {
      final dateTime = DateTime.parse(timestamp);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return '${difference.inSeconds}秒前';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}分前';
      } else {
        return '${dateTime.hour.toString().padLeft(2, '0')}:'
            '${dateTime.minute.toString().padLeft(2, '0')}:'
            '${dateTime.second.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return timestamp;
    }
  }
}
