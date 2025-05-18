// K-MAPS: ホーム画面（プロジェクト作成・選択）
// プロジェクト新規作成・ローカル/DriveからインポートUI
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../utils/global_config.dart';
import '../models/folder_node.dart';
import 'map_page.dart';

/// ホーム画面（最小構成）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _projectDir;

  Future<void> _pickProjectDir() async {
    String? dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      setState(() {
        _projectDir = dir;
      });
      // グローバル初期化
      GlobalConfig.instance.projectRootDir = dir;
      GlobalConfig.instance.folderTree = FolderNode('rootNode', visible: true);
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
      appBar: AppBar(title: const Text('K-MAPS ホーム')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _pickProjectDir,
              child: const Text('プロジェクトフォルダを選択'),
            ),
          ],
        ),
      ),
    );
  }
}
