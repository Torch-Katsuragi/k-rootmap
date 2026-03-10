/// K-MAPS: LayerDrawer用タイトルバーウィジェット
library;

import 'package:flutter/material.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';

enum AddAction { folder, geoPackage, photo }

/// 濃グレーのタイトルパネル（currentNodeの名前を表示＋右側に統合追加ボタン）
class LayerDrawerTitleBar extends StatelessWidget {
  final String title;
  final LayerTreeNode currentNode;
  final void Function(AddAction action)? onAdd;
  final void Function()? onBack;

  const LayerDrawerTitleBar({
    super.key,
    required this.title,
    required this.currentNode,
    this.onAdd,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: const Color(0xFF424242),
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
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
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (currentNode is FolderNode && onAdd != null)
            PopupMenuButton<AddAction>(
              tooltip: 'Add',
              onSelected: onAdd,
              offset: const Offset(0, 40),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add, color: Colors.black, size: 22),
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: AddAction.folder,
                  child: Row(children: [
                    Icon(Icons.folder, color: Colors.amber),
                    SizedBox(width: 12),
                    Text('Folder'),
                  ]),
                ),
                PopupMenuItem(
                  value: AddAction.geoPackage,
                  child: Row(children: [
                    Icon(Icons.storage, color: Color(0xFF90A4AE)),
                    SizedBox(width: 12),
                    Text('GeoPackage'),
                  ]),
                ),
                PopupMenuItem(
                  value: AddAction.photo,
                  child: Row(children: [
                    Icon(Icons.photo_library, color: Colors.blue),
                    SizedBox(width: 12),
                    Text('Photos'),
                  ]),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
