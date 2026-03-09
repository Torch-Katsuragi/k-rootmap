// 地図画面の左側ツールバーウィジェット
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io' show Platform;
import '../models/nodes/folder_node.dart';
import '../providers/tool_providers.dart';
import '../providers/ui_state_providers.dart';
import '../screens/gallery_import_screen.dart';

/// 地図画面左側のツールバー（Pan, Pen, Select, GPSツールボタン, 写真インポート）
class MapToolbar extends ConsumerWidget {
  final VoidCallback onToolChanged;
  final FolderNode? currentFolder;

  const MapToolbar({
    super.key,
    required this.onToolChanged,
    this.currentFolder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTool = ref.watch(currentToolProvider);
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
                ref.read(currentToolProvider.notifier).set(ref.read(panToolProvider));
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
                ref.read(currentToolProvider.notifier).set(ref.read(penToolProvider));
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
                ref.read(currentToolProvider.notifier).set(ref.read(selectToolProvider));
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
                ref.read(currentToolProvider.notifier).set(ref.read(gpsToolProvider));
                onToolChanged();
              },
            ),
            // 写真インポートボタン（モバイルのみ表示）
            if (isMobilePlatform) ...[
              const SizedBox(height: 8),
              _ToolButton(
                icon: Icons.photo_library,
                tooltip: 'Import Photos',
                isSelected: false,
                onPressed: currentFolder != null
                    ? () async {
                        final imported = await GalleryImporter.pickAndImport(
                          context,
                          currentFolder!,
                        );
                        if (imported) {
                          await currentFolder!.updateChildren();
                          ref.read(featureRefreshTriggerProvider.notifier).trigger();
                        }
                      }
                    : () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Select a folder to import photos into')),
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
