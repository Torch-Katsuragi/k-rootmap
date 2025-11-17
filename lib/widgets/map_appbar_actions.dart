// 地図画面のAppBarアクションボタン群
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../screens/basemap_settings_screen.dart';
import '../screens/gps_settings_screen.dart';
import '../screens/camera_screen.dart';
import '../models/nodes/folder_node.dart';

/// 地図画面AppBarの右側アクションボタン群を生成する関数
List<Widget> buildMapAppBarActions({
  required BuildContext context,
  required bool showAttributeTable,
  required bool drawerOpen,
  required VoidCallback onAttributeTableToggle,
  required VoidCallback onDrawerToggle,
  FolderNode? currentFolder,
}) {
  // プラットフォーム判定: モバイル（Android/iOS）のみカメラ使用可能
  final isMobilePlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  
  return [
      // カメラボタン（モバイルのみ表示）
      if (isMobilePlatform)
        IconButton(
          icon: const Icon(Icons.camera_alt),
          tooltip: '写真撮影',
          onPressed: currentFolder != null
              ? () async {
                  // カメラ画面へ遷移
                  final result = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CameraScreen(
                        targetFolder: currentFolder,
                      ),
                    ),
                  );
                  
                  // 撮影成功時にフォルダを更新してPhotoNodeを読み込む
                  if (result == true) {
                    // FolderNodeの子ノードを更新（PhotoNodeを再読み込み）
                    await currentFolder.updateChildren();
                  }
                }
              : null, // currentFolderがnullの場合はボタンを無効化
        ),
      // 背景地図設定ボタン
      IconButton(
        icon: const Icon(Icons.map_outlined),
        tooltip: '背景地図設定',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const BaseMapSettingsScreen(),
            ),
          );
        },
      ),
      // GPS設定ボタン
      IconButton(
        icon: const Icon(Icons.gps_fixed),
        tooltip: 'GPS設定',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GpsSettingsScreen(),
            ),
          );
        },
      ),
      // 属性テーブルボタン
      IconButton(
        icon: Icon(
          Icons.table_view,
          color: showAttributeTable ? Colors.blue : null,
        ),
        tooltip: showAttributeTable ? '属性テーブルを閉じる' : '属性テーブルを開く',
        onPressed: onAttributeTableToggle,
      ),
      // レイヤードロワーボタン
      IconButton(
        icon: Icon(
          Icons.layers,
          color: drawerOpen ? Colors.blue : null,
        ),
        tooltip: drawerOpen ? 'Close Layer Drawer' : 'Open Layer Drawer',
        onPressed: onDrawerToggle,
      ),
  ];
}

