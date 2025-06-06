import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../models/bluetooth_gnss_service.dart';
import '../services/foreground_service.dart';
import '../utils/global_gnss_manager.dart';

/// Bluetooth GNSS接続画面
///
/// 外部GNSS受信機との接続管理およびリアルタイム位置情報表示を行います。
///
/// Features:
/// - デバイススキャンと接続
/// - 接続状態のリアルタイム監視
/// - NMEAデータ受信状況の表示
/// - 位置情報の詳細表示
/// - 統計情報の表示
class BluetoothGnssScreen extends StatefulWidget {
  const BluetoothGnssScreen({super.key});

  @override
  State<BluetoothGnssScreen> createState() => _BluetoothGnssScreenState();
}

class _BluetoothGnssScreenState extends State<BluetoothGnssScreen> {
  // グローバルマネージャーから共有インスタンスを取得
  final GlobalGnssManager _gnssManager = GlobalGnssManager();
  late final BluetoothGnssService _gnssService;
  List<BluetoothDevice> _devices = [];
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // グローバルマネージャーから共有サービスを取得
    _gnssService = _gnssManager.gnssService;
    _gnssService.addListener(_onGnssServiceUpdate);
    _scanDevices();

    // デバッグ情報出力
    _gnssManager.printDebugInfo();
  }

  @override
  void dispose() {
    _gnssService.removeListener(_onGnssServiceUpdate);
    // 重要: グローバルマネージャー使用時は接続を維持
    // dispose()は明示的な切断時のみ呼び出される
    debugPrint('[BluetoothGnssScreen] 画面終了 - 接続は維持されます');
    _gnssManager.printDebugInfo();
    super.dispose();
  }

  /// GNSSサービスの状態更新時のコールバック
  void _onGnssServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  /// Bluetoothデバイスをスキャン
  Future<void> _scanDevices() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final devices = await _gnssService.scanDevices();
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
      });
    }
  }

  /// デバイスに接続
  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      await _gnssService.connectToDevice(device);

      // 接続成功時にフォアグラウンドサービスにGNSS設定を保存
      if (_gnssService.isConnected) {
        ForegroundServiceManager.setGnssDevice(
          device.address,
          device.name ?? 'Unknown GNSS Device',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${device.name ?? 'GNSS'}に接続し、フォアグラウンドサービスに設定しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('接続エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 接続を切断
  Future<void> _disconnect() async {
    await _gnssService.disconnect();

    // 切断時にフォアグラウンドサービスのGNSS設定をクリア
    ForegroundServiceManager.clearGnssDevice();

    // 明示的な切断時のみグローバルマネージャーをリセット
    // （画面遷移での自動dispose()とは区別）
    debugPrint('[BluetoothGnssScreen] 明示的な切断 - グローバルマネージャーをリセット');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GNSS接続を切断し、フォアグラウンドサービス設定をクリアしました'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bluetooth GNSS'),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
        actions: [
          if (!_gnssService.isConnected && !_gnssService.isConnecting)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _isScanning ? null : _scanDevices,
              tooltip: 'デバイス再スキャン',
            ),
          if (_gnssService.isConnected)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
              tooltip: '接続切断',
            ),
        ],
      ),
      body: Column(
        children: [
          // 接続状態表示
          _buildConnectionStatus(),

          // 位置情報表示
          if (_gnssService.isConnected) ...[
            _buildPositionInfo(),
            _buildStatistics(),
          ],

          // デバイスリスト
          if (!_gnssService.isConnected) _buildDeviceList(),
        ],
      ),
    );
  }

  /// 接続状態表示ウィジェット
  Widget _buildConnectionStatus() {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (_gnssService.isConnecting) {
      statusColor = Colors.orange;
      statusText = '接続中...';
      statusIcon = Icons.bluetooth_searching;
    } else if (_gnssService.isConnected) {
      statusColor = Colors.green;
      statusText = '接続済み: ${_gnssService.connectedDevice?.name ?? 'Unknown'}';
      statusIcon = Icons.bluetooth_connected;
    } else {
      statusColor = Colors.grey;
      statusText = '未接続';
      statusIcon = Icons.bluetooth_disabled;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      color: statusColor.withOpacity(0.1),
      child: Row(
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
                if (_gnssService.connectedDevice != null)
                  Text(
                    'アドレス: ${_gnssService.connectedDevice!.address}',
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor.withOpacity(0.8),
                    ),
                  ),
              ],
            ),
          ),
          if (_gnssService.isConnecting)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  /// 位置情報表示ウィジェット
  Widget _buildPositionInfo() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '現在位置',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_gnssService.timestamp != null)
                  Text(
                    '更新: ${_formatTime(_gnssService.timestamp!)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow(
              '緯度',
              _gnssService.latitude?.toStringAsFixed(7) ?? 'N/A',
            ),
            _buildInfoRow(
              '経度',
              _gnssService.longitude?.toStringAsFixed(7) ?? 'N/A',
            ),
            if (_gnssService.altitude != null)
              _buildInfoRow(
                '高度',
                '${_gnssService.altitude!.toStringAsFixed(1)} m',
              ),
            if (_gnssService.accuracy != null)
              _buildInfoRow(
                '精度',
                '${_gnssService.accuracy!.toStringAsFixed(1)} m',
              ),
            if (_gnssService.speed != null)
              _buildInfoRow(
                '速度',
                '${(_gnssService.speed! * 3.6).toStringAsFixed(1)} km/h',
              ),
            if (_gnssService.bearing != null)
              _buildInfoRow(
                '方位',
                '${_gnssService.bearing!.toStringAsFixed(1)}°',
              ),
          ],
        ),
      ),
    );
  }

  /// 統計情報表示ウィジェット
  Widget _buildStatistics() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.green),
                SizedBox(width: 8),
                Text(
                  '統計情報',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('受信NMEA文数', '${_gnssService.receivedSentenceCount}'),
            _buildInfoRow('有効位置数', '${_gnssService.validPositionCount}'),
            if (_gnssService.lastPositionUpdate != null)
              _buildInfoRow(
                '最終更新',
                _formatTime(_gnssService.lastPositionUpdate!),
              ),
            _buildInfoRow(
              'Mock Location',
              _gnssService.isMockLocationEnabled ? '有効' : '無効',
            ),
          ],
        ),
      ),
    );
  }

  /// デバイスリスト表示ウィジェット
  Widget _buildDeviceList() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.devices, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'ペアリング済みデバイス',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isScanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMessage!)),
                ],
              ),
            ),
          Expanded(
            child:
                _devices.isEmpty
                    ? const Center(
                      child: Text(
                        'ペアリング済みデバイスが見つかりません',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                    : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) {
                        final device = _devices[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.bluetooth,
                            color: Colors.blue,
                          ),
                          title: Text(device.name ?? 'Unknown Device'),
                          subtitle: Text(device.address),
                          trailing: ElevatedButton(
                            onPressed: () => _connectToDevice(device),
                            child: const Text('接続'),
                          ),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }

  /// 情報行ウィジェット
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
          const Text(': '),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  /// 時刻フォーマット
  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}:'
        '${time.second.toString().padLeft(2, '0')}';
  }
}
