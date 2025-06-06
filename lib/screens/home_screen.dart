// K-MAPS: ホーム画面（プロジェクト作成・選択）
// プロジェクト新規作成・ローカル/DriveからインポートUI
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/global_config.dart';
import '../models/layer_tree_node.dart';
import 'map_page.dart';

/// ホーム画面（最小構成）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _projectDir;

  @override
  void initState() {
    super.initState();
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
                      onPressed: _pickProjectDir,
                      icon: const Icon(Icons.folder),
                      label: const Text('フォルダを選択'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        textStyle: const TextStyle(fontSize: 16),
                      ),
                    ),
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
