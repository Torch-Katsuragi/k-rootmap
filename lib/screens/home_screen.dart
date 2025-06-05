// K-MAPS: ホーム画面（プロジェクト作成・選択）
// プロジェクト新規作成・ローカル/DriveからインポートUI
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/global_config.dart';
import '../models/layer_tree_node.dart';
import 'map_page.dart';
import '../services/foreground_service.dart';

/// ホーム画面（最小構成）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _projectDir;
  final ForegroundServiceManager _serviceManager = ForegroundServiceManager();
  bool _isServiceRunning = false;

  @override
  void initState() {
    super.initState();
    _updateServiceStatus();
  }

  Future<void> _pickProjectDir() async {
    String? dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      setState(() {
        _projectDir = dir;
      });
      // グローバル初期化
      GlobalConfig.instance.projectRootDir = dir;
      GlobalConfig.instance.folderTree = FolderNode('rootNode', visible: true);
      print(GlobalConfig.instance.folderTree?.toMap());
      // フォルダ選択後すぐ地図編集画面へ遷移
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const KMapsHomePage()),
        );
      }
    }
  }

  /// サービス実行状態を更新
  void _updateServiceStatus() {
    setState(() {
      _isServiceRunning = _serviceManager.isServiceRunning;
    });
  }

  /// フォアグラウンドサービス開始
  Future<void> _startForegroundService() async {
    await _serviceManager.startService();
    _updateServiceStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('フォアグラウンドサービスを開始しました'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// フォアグラウンドサービス停止
  Future<void> _stopForegroundService() async {
    await _serviceManager.stopService();
    _updateServiceStatus();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('フォアグラウンドサービスを停止しました'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('K-MAPS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // フォアグラウンドサービス制御セクション
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'フォアグラウンドサービス',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'ステータス: ${_isServiceRunning ? "実行中" : "停止中"}',
                      style: TextStyle(
                        color: _isServiceRunning ? Colors.green : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '1秒間隔でログ出力を行うテストサービスです。\n'
                      'Android端末では通知バーにサービス状態が表示されます。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isServiceRunning
                                    ? null
                                    : _startForegroundService,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('開始'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _isServiceRunning
                                    ? _stopForegroundService
                                    : null,
                            icon: const Icon(Icons.stop),
                            label: const Text('停止'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // 説明セクション
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '使用方法',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. 「開始」ボタンでフォアグラウンドサービスを開始\n'
                      '2. デバッグコンソールで1秒間隔のログ出力を確認\n'
                      '3. Android端末では通知バーでサービス状態を確認\n'
                      '4. 「停止」ボタンでサービスを停止',
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // デバッグ情報
            Card(
              color: Colors.grey[100],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'デバッグ情報',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'サービス実行状態: $_isServiceRunning\n'
                      'ログ出力: デバッグコンソールとprint文で確認可能',
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
