/// K-MAPS: LayerDrawer用タイトルバーウィジェット
library;

import 'package:flutter/material.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../models/nodes/global_folder_node.dart';
import '../../presentation/node_presenter.dart';

enum AddAction { folder, geoPackage, photo }

/// 濃グレーのタイトルパネル（currentNodeの名前を表示＋右側に統合追加ボタン）
/// Drive連携フォルダ配下ではクラウドカラー背景＋同期UIを表示
class LayerDrawerTitleBar extends StatelessWidget {
  final String title;
  final LayerTreeNode currentNode;
  final void Function(AddAction action)? onAdd;
  final void Function()? onBack;

  /// Drive同期関連（null なら非表示）
  final SyncStatus? syncStatus;
  final void Function(String action)? onCloudAction;
  final bool isReadOnly;

  const LayerDrawerTitleBar({
    super.key,
    required this.title,
    required this.currentNode,
    this.onAdd,
    this.onBack,
    this.syncStatus,
    this.onCloudAction,
    this.isReadOnly = false,
  });

  bool get _isUnderDriveFolder {
    LayerTreeNode? node = currentNode;
    while (node != null) {
      if (node is DriveFolderNode) return true;
      if (node is GlobalFolderNode) return false;
      node = node.parent;
    }
    return false;
  }

  (String, Color) get _syncLabel => switch (syncStatus) {
        SyncStatus.synced => ('同期済み', Colors.greenAccent),
        SyncStatus.localChanges => ('ローカル変更あり', Colors.orangeAccent),
        SyncStatus.remoteChanges => ('Drive変更あり', Colors.lightBlueAccent),
        SyncStatus.conflict => ('競合あり', Colors.redAccent),
        SyncStatus.syncing => ('同期中...', Colors.lightBlueAccent),
        SyncStatus.error => ('エラー', Colors.redAccent),
        SyncStatus.unknown => ('Drive連携中', Colors.white70),
        null => ('', Colors.white70),
      };

  static const _buttonDecoration = BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.all(Radius.circular(8)),
  );

  @override
  Widget build(BuildContext context) {
    final isDrive = _isUnderDriveFolder;
    final bgColor = isDrive ? cloudColor : const Color(0xFF424242);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      color: bgColor,
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
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
          Expanded(child: _buildTitle(isDrive)),
          if (currentNode is DriveFolderNode && onCloudAction != null)
            _buildCloudButton(),
          if (currentNode is FolderNode && onAdd != null) ...[
            if (currentNode is DriveFolderNode && onCloudAction != null)
              const SizedBox(width: 8),
            _buildAddButton(),
          ],
        ],
      ),
    );
  }

  Widget _buildTitle(bool isDrive) {
    final showSyncLabel = currentNode is DriveFolderNode && syncStatus != null;
    if (!showSyncLabel) {
      return Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }
    final (label, _) = _syncLabel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black87)),
      ],
    );
  }

  Widget _buildCloudButton() {
    final iconData = switch (syncStatus) {
      SyncStatus.syncing => Icons.cloud_sync,
      SyncStatus.error => Icons.cloud_off,
      _ => Icons.cloud,
    };

    return PopupMenuButton<String>(
      tooltip: 'Drive同期',
      onSelected: onCloudAction,
      offset: const Offset(0, 40),
      child: Container(
        width: 34,
        height: 34,
        decoration: _buttonDecoration,
        child: Icon(iconData, color: Colors.black, size: 20),
      ),
      itemBuilder: (_) => [
        if (!isReadOnly)
          const PopupMenuItem(
            value: 'upload',
            child: Row(children: [
              Icon(Icons.cloud_upload, color: Colors.orange),
              SizedBox(width: 12),
              Text('アップロード'),
            ]),
          ),
        const PopupMenuItem(
          value: 'download',
          child: Row(children: [
            Icon(Icons.cloud_download, color: Colors.green),
            SizedBox(width: 12),
            Text('ダウンロード'),
          ]),
        ),
        const PopupMenuItem(
          value: 'refresh',
          child: Row(children: [
            Icon(Icons.refresh, color: Colors.blue),
            SizedBox(width: 12),
            Text('状態を更新'),
          ]),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'unlink',
          child: Row(children: [
            Icon(Icons.link_off, color: Colors.red),
            SizedBox(width: 12),
            Text('Drive連携を解除'),
          ]),
        ),
      ],
    );
  }

  Widget _buildAddButton() {
    return PopupMenuButton<AddAction>(
      tooltip: 'Add',
      onSelected: onAdd,
      offset: const Offset(0, 40),
      child: Container(
        width: 34,
        height: 34,
        decoration: _buttonDecoration,
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
    );
  }
}
