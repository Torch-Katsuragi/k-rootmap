// K-MAPS: ホーム画面（プロジェクト作成・選択）
// プロジェクト新規作成・ローカル/DriveからインポートUI
import 'dart:io';

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/nodes/folder_node.dart';
import '../models/nodes/global_folder_node.dart';
import '../providers/project_providers.dart';
import '../providers/ui_state_providers.dart';
import 'map_page/map_page.dart';
import 'maplibre_poc_screen.dart';

/// ホーム画面（最小構成）
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  String? _projectDir;
  bool _permissionsGranted = false;
  bool _isCheckingPermissions = false; // 権限チェック中フラグ
  bool _navigatedToMapPage = false; // マップ画面に遷移済みフラグ
  bool _isOpeningProject = false; // プロジェクト開始中フラグ
  String _openingProjectStatus = '';

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
      // ただし、既に権限チェック中またはマップ画面に遷移済みの場合はスキップ
      // （MapPageでのGPS権限リクエストと競合を防ぐため）
      if (!_isCheckingPermissions && !_navigatedToMapPage) {
        _checkPermissions();
      }
    }
  }

  /// ストレージ権限の確認・リクエスト
  Future<void> _checkPermissions() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (mounted) {
        setState(() {
          _permissionsGranted = true;
        });
      }
      return;
    }

    // 既に権限チェック中の場合はスキップ
    if (_isCheckingPermissions) {
      AppLogger.debug('[HomeScreen] 権限チェックが既に実行中のため、スキップします');
      return;
    }

    _isCheckingPermissions = true; // フラグをセット
    AppLogger.debug('[HomeScreen] 権限チェック開始');

    try {
      // Android 11 (API level 30) 以降での権限管理
      final manageStorageGranted =
          await Permission.manageExternalStorage.isGranted;
      AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限状態: $manageStorageGranted');

      if (manageStorageGranted) {
        AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が既に許可済み');
        // ストレージ権限OK後、Bluetooth権限をチェック
        await _checkBluetoothPermissions();
        return;
      }

      AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限をリクエスト中...');
      // MANAGE_EXTERNAL_STORAGE権限をリクエスト
      final status = await Permission.manageExternalStorage.request();
      AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限リクエスト結果: $status');

      if (status.isGranted) {
        AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が許可されました');
        // ストレージ権限OK後、Bluetooth権限をチェック
        await _checkBluetoothPermissions();
      } else if (status.isPermanentlyDenied) {
        AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が恒久的に拒否されました');
        // 権限が恒久的に拒否された場合、設定画面を開く
        _showPermissionDeniedDialog();
      } else {
        AppLogger.debug('[HomeScreen] MANAGE_EXTERNAL_STORAGE権限が拒否されました。従来の権限を試行');
        // 従来のストレージ権限を試行
        await _requestLegacyStoragePermissions();
      }
    } catch (e) {
      AppLogger.debug('[HomeScreen] 権限チェック中にエラーが発生: $e');
    } finally {
      _isCheckingPermissions = false; // フラグをクリア
      AppLogger.debug('[HomeScreen] 権限チェック終了');
    }
  }

  /// 従来のストレージ権限をリクエスト
  Future<void> _requestLegacyStoragePermissions() async {
    AppLogger.debug('[HomeScreen] 従来のストレージ権限チェック開始');

    final permissions = [Permission.storage];

    AppLogger.debug('[HomeScreen] ストレージ権限をリクエスト中...');
    final statuses = await permissions.request();
    AppLogger.debug('[HomeScreen] ストレージ権限リクエスト結果: $statuses');

    if (statuses[Permission.storage]?.isGranted == true) {
      AppLogger.debug('[HomeScreen] ストレージ権限が許可されました');
      // ストレージ権限OK後、Bluetooth権限をチェック
      await _checkBluetoothPermissions();
    } else {
      AppLogger.debug('[HomeScreen] ストレージ権限が拒否されました');
      _showPermissionDeniedDialog();
    }
  }

  /// Bluetooth権限の確認・リクエスト（ストレージ権限の後に実行）
  Future<void> _checkBluetoothPermissions() async {
    AppLogger.debug('[HomeScreen] Bluetooth権限チェック開始');

    // Android 12以降で必要な権限
    final bluetoothScan = await Permission.bluetoothScan.status;
    final bluetoothConnect = await Permission.bluetoothConnect.status;
    
    AppLogger.debug('[HomeScreen] BLUETOOTH_SCAN状態: $bluetoothScan');
    AppLogger.debug('[HomeScreen] BLUETOOTH_CONNECT状態: $bluetoothConnect');

    // 両方の権限が許可されている場合
    if (bluetoothScan.isGranted && bluetoothConnect.isGranted) {
      AppLogger.debug('[HomeScreen] Bluetooth権限が既に許可済み');
      setState(() {
        _permissionsGranted = true;
      });
      return;
    }

    // 複数の権限を一度にリクエスト（プラグイン側が適切に管理）
    AppLogger.debug('[HomeScreen] Bluetooth権限をリクエスト中...');
    
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    
    AppLogger.debug('[HomeScreen] Bluetooth権限リクエスト結果: $statuses');

    // 結果を確認
    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted ?? false;
    final connectGranted = statuses[Permission.bluetoothConnect]?.isGranted ?? false;
    final bluetoothGranted = scanGranted && connectGranted;

    if (bluetoothGranted) {
      AppLogger.debug('[HomeScreen] 全てのBluetooth権限が許可されました');
      setState(() {
        _permissionsGranted = true;
      });
    } else {
      AppLogger.debug('[HomeScreen] 一部のBluetooth権限が拒否されました (SCAN: $scanGranted, CONNECT: $connectGranted)');
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

  /// グローバルフォルダの初期化
  /// アプリケーションDocumentsディレクトリにk_maps_globalフォルダを作成し、
  /// ルートノードの先頭に追加
  Future<void> _initializeGlobalFolder() async {
    try {
      // アプリケーションDocumentsディレクトリを取得
      final appDir = await getApplicationDocumentsDirectory();
      final globalPath = p.join(appDir.path, 'k_maps_global');
      
      // グローバルフォルダパスを保存
      ref.read(globalFolderPathProvider.notifier).set(globalPath);
      AppLogger.debug('[HomeScreen] グローバルフォルダパス: $globalPath');

      // グローバルフォルダノードを作成
      final globalFolderNode = GlobalFolderNode(
        'Global',
        globalPath: globalPath,
        visible: true,
        parent: ref.read(folderTreeProvider),
      );

      final rootNode = ref.read(folderTreeProvider);
      if (rootNode != null) {
        // 既存のグローバルフォルダがあれば削除
        rootNode.children.removeWhere((child) => child is GlobalFolderNode);
        // 先頭に挿入
        rootNode.children.insert(0, globalFolderNode);
        AppLogger.debug('[HomeScreen] グローバルフォルダをルートノードに追加');
      }
    } catch (e) {
      AppLogger.debug('[HomeScreen] グローバルフォルダ初期化エラー: $e');
    }
  }

  Future<void> _pickProjectDir() async {
    AppLogger.debug('[HomeScreen] プロジェクトフォルダ選択開始');
    AppLogger.debug('[HomeScreen] 権限状態: $_permissionsGranted');

    if (!_permissionsGranted) {
      AppLogger.debug('[HomeScreen] 権限が許可されていません');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('まずストレージ権限を許可してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    AppLogger.debug('[HomeScreen] ファイルピッカーを開いています...');
    String? dir = await FilePicker.platform.getDirectoryPath();
    AppLogger.debug('[HomeScreen] 選択されたディレクトリ: $dir');

    if (dir != null) {
      if (!mounted) return;
      setState(() {
        _projectDir = dir;
        _isOpeningProject = true;
        _openingProjectStatus = 'プロジェクトを初期化しています...';
      });
      AppLogger.debug('[HomeScreen] フォルダ選択完了、初期化を開始');
      ref.read(projectRootDirProvider.notifier).set(dir);
      AppLogger.debug('[HomeScreen] projectRootDirProvider 設定完了');
      final rootNode = FolderNode('rootNode', visible: true);
      ref.read(folderTreeProvider.notifier).set(rootNode);
      AppLogger.debug('[HomeScreen] rootNode 設定完了');

      setState(() {
        _openingProjectStatus = '共有フォルダを準備しています...';
      });
      await _initializeGlobalFolder();
      AppLogger.debug('[HomeScreen] GlobalFolder 初期化完了');

      // フォルダ選択後すぐ地図編集画面へ遷移
      if (mounted) {
        AppLogger.debug('[HomeScreen] 地図画面に遷移中...');
        // マップ画面遷移後は権限チェックを無効化（GPS権限リクエストとの競合防止）
        _navigatedToMapPage = true;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const KMapsHomePage()),
        ).then((_) {
          if (!mounted) return;
          setState(() {
            _navigatedToMapPage = false;
            _isOpeningProject = false;
            _openingProjectStatus = '';
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('K-MAPS'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // MapLibre PoC（技術検証用）
          IconButton(
            icon: const Icon(Icons.terrain),
            tooltip: 'MapLibre PoC',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MapLibrePocScreen()),
            ),
          ),
        ],
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
                      onPressed:
                          (_permissionsGranted && !_isOpeningProject)
                              ? _pickProjectDir
                              : null,
                      icon: Icon(
                        _isOpeningProject
                            ? Icons.hourglass_top
                            : (_permissionsGranted ? Icons.folder : Icons.warning),
                      ),
                      label: Text(
                        _isOpeningProject
                            ? '起動中...'
                            : (_permissionsGranted ? 'フォルダを選択' : '権限が必要です'),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            (_permissionsGranted && !_isOpeningProject)
                                ? Colors.blue
                                : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
                    if (_isOpeningProject) ...[
                      const SizedBox(height: 12),
                      Text(
                        _openingProjectStatus,
                        style: const TextStyle(color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                    ],
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

