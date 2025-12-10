// 地図画面の左側ツールバーウィジェット
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import '../utils/global_config.dart';
import '../models/nodes/folder_node.dart';
import '../screens/camera_screen.dart';

/// 地図画面左側のツールバー（Pan, Pen, Select, GPSツールボタン, カメラ）
class MapToolbar extends StatelessWidget {
  final VoidCallback onToolChanged;
  final FolderNode? currentFolder;

  const MapToolbar({
    super.key,
    required this.onToolChanged,
    this.currentFolder,
  });

  @override
  Widget build(BuildContext context) {
    final currentTool = GlobalConfig.instance.currentTool;
    // プラットフォーム判定: モバイル（Android/iOS）のみカメラ使用可能
    final isMobilePlatform = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 44,
        color: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Panツールボタン
            _ToolButton(
              icon: Icons.pan_tool_alt,
              tooltip: 'Pan',
              isSelected: currentTool.name == 'Pan',
              onPressed: () {
                GlobalConfig.instance.currentTool = GlobalConfig.instance.panTool;
                onToolChanged();
              },
            ),
            const SizedBox(height: 8),
            // Penツールボタン
            _ToolButton(
              icon: Icons.edit,
              tooltip: 'Pen',
              isSelected: currentTool.name == 'Pen',
              onPressed: () {
                GlobalConfig.instance.currentTool = GlobalConfig.instance.penTool;
                onToolChanged();
              },
            ),
            const SizedBox(height: 8),
            // Selectツールボタン
            _ToolButton(
              icon: Icons.select_all,
              tooltip: 'Select',
              isSelected: currentTool.name == 'Select',
              onPressed: () {
                GlobalConfig.instance.currentTool = GlobalConfig.instance.selectTool;
                onToolChanged();
              },
            ),
            const SizedBox(height: 8),
            // GPSツールボタン
            _ToolButton(
              icon: Icons.gps_fixed,
              tooltip: 'GPS Tool',
              isSelected: currentTool.name == 'GPS',
              onPressed: () {
                GlobalConfig.instance.currentTool = GlobalConfig.instance.gpsTool;
                onToolChanged();
              },
            ),
            // カメラボタン（モバイルのみ表示）
            if (isMobilePlatform) ...[
              const SizedBox(height: 8),
              _ToolButton(
                icon: Icons.camera_alt,
                tooltip: '写真撮影',
                isSelected: false, // ツールではないので選択状態にはならない
                onPressed: currentFolder != null
                    ? () async {
                        // カメラ画面へ遷移
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => CameraScreen(
                              targetFolder: currentFolder!,
                            ),
                          ),
                        );
                        
                        // 撮影成功時にフォルダを更新してImageNodeを読み込む
                        if (result == true) {
                          // FolderNodeの子ノードを更新（ImageNodeを再読み込み）
                          await currentFolder!.updateChildren();
                        }
                      }
                    : () {
                      // フォルダ未選択時のフィードバック（オプション）
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('写真を保存するフォルダを選択してください')),
                      );
                    },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ツールボタン（選択状態で青い円が表示される）
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? Colors.blue : Colors.transparent,
      ),
      child: IconButton(
        icon: Icon(
          icon,
          color: isSelected ? Colors.white : Colors.black,
        ),
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 24,
        padding: EdgeInsets.zero,
      ),
    );
  }
}

