// K-MAPS: ホーム画面（プロジェクト作成・選択）
// プロジェクト新規作成・ローカル/DriveからインポートUI
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../utils/global_config.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/folder_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../models/nodes/photo_node.dart';
import 'map_page.dart';

/// ホーム画面（最小構成）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  String? _projectDir;
  bool _permissionsGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // アプリがフォアグラウンドに戻ったときに権限を再確認
      _checkPermissions();
    }
  }

  /// ストレージ権限の確認・リクエスト
  Future<void> _checkPermissions() async {
    print('[HomeScreen] 権限チェック開始');

    // Android 11 (API level 30) 以降での権限管理
    final manageStorageGranted =
        await Permission.manageExternalStorage.isGranted;
    print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限状態: $manageStorageGranted');

    if (manageStorageGranted) {
      print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が既に許可済み');
      // ストレージ権限OK後、Bluetooth権限をチェック
      await _checkBluetoothPermissions();
      return;
    }

    print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限をリクエスト中...');
    // MANAGE_EXTERNAL_STORAGE権限をリクエスト
    final status = await Permission.manageExternalStorage.request();
    print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限リクエスト結果: $status');

    if (status.isGranted) {
      print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が許可されました');
      // ストレージ権限OK後、Bluetooth権限をチェック
      await _checkBluetoothPermissions();
    } else if (status.isPermanentlyDenied) {
      print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が恒久的に拒否されました');
      // 権限が恒久的に拒否された場合、設定画面を開く
      _showPermissionDeniedDialog();
    } else {
      print('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が拒否されました。従来の権限を試行');
      // 従来のストレージ権限を試行
      await _requestLegacyStoragePermissions();
    }
  }

  /// 従来のストレージ権限をリクエスト
  Future<void> _requestLegacyStoragePermissions() async {
    print('[HomeScreen] 従来のストレージ権限チェック開始');

    final permissions = [Permission.storage];

    print('[HomeScreen] ストレージ権限をリクエスト中...');
    final statuses = await permissions.request();
    print('[HomeScreen] ストレージ権限リクエスト結果: $statuses');

    if (statuses[Permission.storage]?.isGranted == true) {
      print('[HomeScreen] ストレージ権限が許可されました');
      // ストレージ権限OK後、Bluetooth権限をチェック
      await _checkBluetoothPermissions();
    } else {
      print('[HomeScreen] ストレージ権限が拒否されました');
      _showPermissionDeniedDialog();
    }
  }

  /// Bluetooth権限の確認・リクエスト（ストレージ権限の後に実行）
  Future<void> _checkBluetoothPermissions() async {
    print('[HomeScreen] Bluetooth権限チェック開始');

    // Android 12以降で必要な権限
    final bluetoothScan = await Permission.bluetoothScan.status;
    final bluetoothConnect = await Permission.bluetoothConnect.status;
    
    print('[HomeScreen] BLUETOOTH_SCAN状態: $bluetoothScan');
    print('[HomeScreen] BLUETOOTH_CONNECT状態: $bluetoothConnect');

    // 両方の権限が許可されている場合
    if (bluetoothScan.isGranted && bluetoothConnect.isGranted) {
      print('[HomeScreen] Bluetooth権限が既に許可済み');
      setState(() {
        _permissionsGranted = true;
      });
      return;
    }

    // 複数の権限を一度にリクエスト（プラグイン側が適切に管理）
    print('[HomeScreen] Bluetooth権限をリクエスト中...');
    
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    
    print('[HomeScreen] Bluetooth権限リクエスト結果: $statuses');

    // 結果を確認
    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final bluetoothGranted = scanGranted && connectGranted;

    if (bluetoothGranted) {
      print('[HomeScreen] 全てのBluetooth権限が許可されました');
      setState(() {
        _permissionsGranted = true;
      });
    } else {
      print('[HomeScreen] 一部のBluetooth権限が拒否されました (SCAN: $scanGranted, CONNECT: $connectGranted)');
      // Bluetooth権限がなくてもアプリは動作可能なので、警告のみ表示してストレージ権限で起動許可
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bluetooth GNSS機能を使用するには、Bluetooth権限が必要です'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }
      
      // ストレージ権限があれば、基本機能は使える
      setState(() {
        _permissionsGranted = true;
      });
    }
  }

  /// 権限拒否ダイアログを表示
  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('ストレージ権限が必要です'),
            content: const Text(
              'ファイルの作成・編集を行うには、ストレージアクセス権限が必要です。\n'
              '設定から権限を有効にしてください。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  openAppSettings();
                },
                child: const Text('設定を開く'),
              ),
            ],
          ),
    );
  }

  Future<void> _pickProjectDir() async {
    print('[HomeScreen] プロジェクトフォルダ選択開始');
    print('[HomeScreen] 権限状態: $_permissionsGranted');

    if (!_permissionsGranted) {
      print('[HomeScreen] 権限が許可されていません');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('まずストレージ権限を許可してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    print('[HomeScreen] ファイルピッカーを開いています...');
    String? dir = await FilePicker.platform.getDirectoryPath();
    print('[HomeScreen] 選択されたディレクトリ: $dir');

    if (dir != null) {
      setState(() {
        _projectDir = dir;
      });
      // グローバル初期化
      print('[HomeScreen] GlobalConfigを初期化中...');
      GlobalConfig.instance.projectRootDir = dir;
      GlobalConfig.instance.folderTree = FolderNode('rootNode', visible: true);
      print(
        '[HomeScreen] GlobalConfig初期化完了: ${GlobalConfig.instance.folderTree?.toMap()}',
      );

      // フォルダ選択後すぐ地図編集画面へ遷移
      if (mounted) {
        print('[HomeScreen] 地図画面に遷移中...');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const KMapsHomePage()),
        );
      }
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
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.map, size: 100, color: Colors.blue),
            const SizedBox(height: 32),
            Text(
              'K-MAPS',
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'GeoPackageベースの地理情報管理・編集アプリケーション',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  children: [
                    const Icon(
                      Icons.folder_open,
                      size: 48,
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'プロジェクトを開始',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'プロジェクトフォルダを選択して地図編集を開始してください',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _permissionsGranted ? _pickProjectDir : null,
                      icon: Icon(
                        _permissionsGranted ? Icons.folder : Icons.warning,
                      ),
                      label: Text(_permissionsGranted ? 'フォルダを選択' : '権限が必要です'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            _permissionsGranted ? Colors.blue : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (!_permissionsGranted) ...[
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: _checkPermissions,
                        icon: const Icon(Icons.refresh),
                        label: const Text('権限を再確認'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_projectDir != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green[50],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '選択されたフォルダ:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _projectDir!,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
