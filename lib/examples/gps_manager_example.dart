/// GPS管理サービスの使用例
///
/// 統合GPS管理サービスの主要な機能の使用方法を示すサンプルコード
///
/// Features:
/// - GPS ソースの切り替え
/// - GPS記録の開始・停止
/// - リアルタイム位置情報の取得
/// - 記録履歴の管理
library;

import 'package:flutter/material.dart';
import '../services/gps_manager_service.dart';

/// GPS管理サービスの使用例画面
class GpsManagerExampleScreen extends StatefulWidget {
  const GpsManagerExampleScreen({super.key});

  @override
  State<GpsManagerExampleScreen> createState() =>
      _GpsManagerExampleScreenState();
}

class _GpsManagerExampleScreenState extends State<GpsManagerExampleScreen> {
  final GpsManagerService _gpsManager = GpsManagerService();
  Map<String, dynamic>? _currentGpsInfo;
  Map<String, dynamic>? _recordingStats;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _initializeGpsManager();
    _gpsManager.addListener(_onGpsManagerUpdate);
  }

  @override
  void dispose() {
    _gpsManager.removeListener(_onGpsManagerUpdate);
    super.dispose();
  }

  /// GPS管理サービスを初期化
  Future<void> _initializeGpsManager() async {
    try {
      // 保存されたGPS設定を読み込み
      await _gpsManager.loadSourceFromGlobalConfig();

      // 外部GNSS機器をスキャン
      await _gpsManager.scanExternalGnssDevices();

      setState(() {
        _lastError = null;
      });
    } catch (e) {
      setState(() {
        _lastError = 'GPS初期化エラー: $e';
      });
    }
  }

  /// GPS管理サービスの更新通知コールバック
  void _onGpsManagerUpdate() {
    if (mounted) {
      setState(() {
        _currentGpsInfo = _gpsManager.getCurrentGpsInfo();
        _recordingStats = _gpsManager.getRecordingStatistics();
      });
    }
  }

  /// GPSソース切り替えダイアログを表示
  Future<void> _showGpsSourceDialog() async {
    final sources = _gpsManager.getAvailableGpsSources();

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('GPSソース選択'),
          content: SizedBox(
            height: 300,
            width: double.maxFinite,
            child: ListView.builder(
              itemCount: sources.length,
              itemBuilder: (context, index) {
                final source = sources[index];
                return ListTile(
                  leading: Icon(
                    source['type'] == GpsSourceType.internal
                        ? Icons.gps_fixed
                        : Icons.bluetooth,
                  ),
                  title: Text(source['name']),
                  subtitle: Text(source['description']),
                  trailing:
                      source['isSelected']
                          ? const Icon(Icons.check, color: Colors.green)
                          : null,
                  onTap: () async {
                    Navigator.of(context).pop();
                    await _switchGpsSource(source);
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  /// GPSソースを切り替え
  Future<void> _switchGpsSource(Map<String, dynamic> source) async {
    try {
      if (source['type'] == GpsSourceType.internal) {
        await _gpsManager.switchGpsSource(GpsSourceType.internal);
      } else {
        await _gpsManager.switchGpsSource(
          GpsSourceType.external,
          source['device'],
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPSソースを${source['name']}に切り替えました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS切り替えエラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// GPS記録を開始
  Future<void> _startRecording() async {
    // 記録オプションを選択するダイアログを表示
    final options = await _selectRecordingOptions();
    if (options == null) return;

    try {
      await _gpsManager.startRecording(options);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS記録を開始しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('GPS記録開始エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// GPS記録を停止
  void _stopRecording() {
    final summary = _gpsManager.stopRecording();

    if (summary != null && mounted) {
      _showRecordingSummary(summary);
    }
  }

  /// 記録オプション選択ダイアログ
  Future<GpsRecordingOptions?> _selectRecordingOptions() async {
    return showDialog<GpsRecordingOptions>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('記録オプション選択'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('デフォルト'),
                subtitle: const Text('1秒間隔、1m移動'),
                onTap:
                    () => Navigator.pop(
                      context,
                      GpsRecordingOptions.defaultOptions,
                    ),
              ),
              ListTile(
                leading: const Icon(Icons.high_quality),
                title: const Text('高精度'),
                subtitle: const Text('1秒間隔、0.5m移動、精度5m以下'),
                onTap:
                    () => Navigator.pop(
                      context,
                      GpsRecordingOptions.highAccuracy,
                    ),
              ),
              ListTile(
                leading: const Icon(Icons.battery_saver),
                title: const Text('省電力'),
                subtitle: const Text('10秒間隔、5m移動、精度20m以下'),
                onTap:
                    () =>
                        Navigator.pop(context, GpsRecordingOptions.powerSaver),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
          ],
        );
      },
    );
  }

  /// 記録完了サマリーを表示
  void _showRecordingSummary(Map<String, dynamic> summary) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('記録完了'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('記録ポイント数: ${summary['totalPoints']}'),
              Text(
                '総移動距離: ${(summary['totalDistance'] as double).toStringAsFixed(1)}m',
              ),
              Text('記録時間: ${summary['duration']}秒'),
              Text('データソース: ${summary['sourceName']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  /// GPS履歴を表示
  void _showGpsHistory() {
    final history = _gpsManager.gpsHistory;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('GPS記録履歴 (${history.length}ポイント)'),
          content: SizedBox(
            height: 400,
            width: double.maxFinite,
            child:
                history.isEmpty
                    ? const Center(child: Text('記録履歴がありません'))
                    : ListView.builder(
                      itemCount: history.length,
                      itemBuilder: (context, index) {
                        final point = history[index];
                        return ListTile(
                          leading: CircleAvatar(child: Text('${index + 1}')),
                          title: Text(
                            'Lat: ${(point['latitude'] as double).toStringAsFixed(6)}\n'
                            'Lon: ${(point['longitude'] as double).toStringAsFixed(6)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            '精度: ${point['accuracy']?.toStringAsFixed(1) ?? 'N/A'}m\n'
                            '時刻: ${DateTime.parse(point['timestamp']).toLocal().toString().substring(0, 19)}',
                          ),
                          trailing: Text(point['sourceDisplayName']),
                        );
                      },
                    ),
          ),
          actions: [
            if (history.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  _gpsManager.clearHistory();
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('履歴をクリアしました')));
                },
                child: const Text('履歴クリア'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('閉じる'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GPS管理サービス例'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // エラー表示
            if (_lastError != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _lastError!,
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                ),
              ),

            // 現在のGPS情報
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '現在のGPS情報',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_currentGpsInfo != null) ...[
                      Text('データソース: ${_currentGpsInfo!['sourceName']}'),
                      if (_currentGpsInfo!['selectedDevice'] != null)
                        Text('接続機器: ${_currentGpsInfo!['selectedDevice']}'),
                      Text(
                        '状態: ${_currentGpsInfo!['isActive'] ? 'アクティブ' : '非アクティブ'}',
                      ),
                      if (_currentGpsInfo!['latitude'] != null) ...[
                        Text(
                          '緯度: ${(_currentGpsInfo!['latitude'] as double).toStringAsFixed(6)}',
                        ),
                        Text(
                          '経度: ${(_currentGpsInfo!['longitude'] as double).toStringAsFixed(6)}',
                        ),
                        if (_currentGpsInfo!['accuracy'] != null)
                          Text(
                            '精度: ${(_currentGpsInfo!['accuracy'] as double).toStringAsFixed(1)}m',
                          ),
                        if (_currentGpsInfo!['speed'] != null)
                          Text(
                            '速度: ${(_currentGpsInfo!['speed'] as double).toStringAsFixed(1)}m/s',
                          ),
                      ] else
                        const Text('位置情報取得中...'),
                    ] else
                      const Text('GPS情報読み込み中...'),
                  ],
                ),
              ),
            ),

            // GPSソース切り替えボタン
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showGpsSourceDialog,
                icon: const Icon(Icons.swap_horiz),
                label: const Text('GPSソース切り替え'),
              ),
            ),

            // 記録制御ボタン
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _gpsManager.isRecording ? null : _startRecording,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('記録開始'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _gpsManager.isRecording ? _stopRecording : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('記録停止'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),

            // 記録統計情報
            if (_recordingStats != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '記録統計',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '記録状態: ${_recordingStats!['isRecording'] ? '記録中' : '停止中'}',
                      ),
                      Text('記録ポイント数: ${_recordingStats!['totalPoints']}'),
                      Text(
                        '総移動距離: ${(_recordingStats!['totalDistance'] as double).toStringAsFixed(1)}m',
                      ),
                      Text('記録時間: ${_recordingStats!['duration']}秒'),
                      if (_recordingStats!['isRecording']) ...[
                        Text(
                          '平均インターバル: ${(_recordingStats!['averageInterval'] as double).toStringAsFixed(1)}秒',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],

            // 履歴表示ボタン
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showGpsHistory,
                icon: const Icon(Icons.history),
                label: Text('GPS履歴表示 (${_gpsManager.historyCount}ポイント)'),
              ),
            ),

            // スキャンボタン
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await _gpsManager.scanExternalGnssDevices();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${_gpsManager.availableGnssDevices.length}個のGNSS機器を発見',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('スキャンエラー: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('GNSS機器スキャン'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
