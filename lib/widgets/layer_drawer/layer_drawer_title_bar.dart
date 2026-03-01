/// K-MAPS: LayerDrawer用タイトルバーウィジェット
library;

import 'package:flutter/material.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';

/// 青いタイトルパネル（currentNodeの名前を表示＋右側に追加ボタン）
class LayerDrawerTitleBar extends StatelessWidget {
  final String title;
  final LayerTreeNode currentNode;
  final void Function()? onAddFolder;
  final void Function()? onAddGeoPackage;
  final void Function()? onBack;

  const LayerDrawerTitleBar({
    super.key,
    required this.title,
    required this.currentNode,
    this.onAddFolder,
    this.onAddGeoPackage,
    this.onBack,
  });

  /// アイコン右上に緑の+を合成するWidget（再利用可）
  static Widget buildAddIconOverlay(IconData baseIcon, Color baseColor) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(baseIcon, color: baseColor, size: 28),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_circle, color: Colors.green, size: 16),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      color: Colors.blue,
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: '一つ上の階層に戻る',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ),
            ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (currentNode is FolderNode) ...[
            IconButton(
              tooltip: 'サブフォルダ追加',
              icon: buildAddIconOverlay(Icons.folder, Colors.amber),
              onPressed: onAddFolder,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'GeoPackage追加',
              icon: buildAddIconOverlay(Icons.storage, Color(0xFFCFD8DC)),
              onPressed: onAddGeoPackage,
            ),
          ],
        ],
      ),
    );
  }
}
