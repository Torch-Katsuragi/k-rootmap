/// K-MAPS: フォルダタイル構築ミックスイン
library;

import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/drive_folder_node.dart';
import '../../../presentation/node_presenter.dart';
import '../sync_merge_dialog.dart';

mixin FolderTileBuilder {
  Widget buildIconWithVisibility(LayerTreeNode node);

  Future<void> openSyncMergeDialog(
    BuildContext context,
    DriveFolderNode node, {
    required SyncMode mode,
  });
  Future<void> refreshSyncStatus(DriveFolderNode node);
  Future<void> unlinkDriveFolder(BuildContext context, DriveFolderNode node);
  Future<void> deleteDriveFolder(BuildContext context, DriveFolderNode node);

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// フォルダタイルを構築
  Widget buildFolderTile(
    BuildContext context,
    FolderNode node,
    VoidCallback onTap,
  ) {
    // DriveFolderNodeの場合は同期メニュー付き（モバイルのみ）
    if (node is DriveFolderNode && _isMobile) {
      return ListTile(
        leading: _buildDriveFolderIcon(node),
        title: Text(node.name),
        subtitle: _buildDriveFolderSubtitle(node),
        onTap: onTap,
        trailing: _buildDriveFolderMenu(context, node),
      );
    }

    // DriveFolderNodeだがPC版の場合はアイコンのみ変更（同期メニューなし）
    if (node is DriveFolderNode && !_isMobile) {
      return ListTile(
        leading: Icon(Icons.cloud, color: Colors.blue.shade600),
        title: Text(node.name),
        subtitle: const Text('PC版では同期不可（Google Drive Desktop使用）',
            style: TextStyle(fontSize: 10, color: Colors.grey)),
        onTap: onTap,
      );
    }

    // 通常のフォルダ
    return ListTile(
      leading: buildIconWithVisibility(node),
      title: Text(node.name),
      onTap: onTap,
    );
  }

  /// Drive連携フォルダのアイコンを構築
  Widget _buildDriveFolderIcon(DriveFolderNode node) {
    return NodePresenter.buildIconWithSyncOverlay(
      node,
      size: 24,
      syncStatus: node.syncStatus,
    );
  }

  /// Drive連携フォルダのサブタイトルを構築
  Widget? _buildDriveFolderSubtitle(DriveFolderNode node) {
    String statusText;
    Color statusColor;
    
    switch (node.syncStatus) {
      case SyncStatus.synced:
        statusText = '同期済み';
        statusColor = Colors.green;
        break;
      case SyncStatus.localChanges:
        statusText = 'ローカル変更あり';
        statusColor = Colors.orange;
        break;
      case SyncStatus.remoteChanges:
        statusText = 'Drive変更あり';
        statusColor = Colors.blue;
        break;
      case SyncStatus.conflict:
        statusText = '競合あり';
        statusColor = Colors.red;
        break;
      case SyncStatus.syncing:
        statusText = '同期中...';
        statusColor = Colors.blue;
        break;
      case SyncStatus.error:
        statusText = 'エラー';
        statusColor = Colors.red;
        break;
      case SyncStatus.unknown:
        statusText = node.isReadOnly ? '読み取り専用' : 'Drive連携';
        statusColor = Colors.grey;
        break;
    }
    
    return Text(
      statusText,
      style: TextStyle(fontSize: 12, color: statusColor),
    );
  }

  /// Drive連携フォルダのメニューを構築
  Widget _buildDriveFolderMenu(BuildContext context, DriveFolderNode node) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'upload':
            await openSyncMergeDialog(context, node, mode: SyncMode.upload);
            break;
          case 'download':
            await openSyncMergeDialog(context, node, mode: SyncMode.download);
            break;
          case 'refresh':
            await refreshSyncStatus(node);
            break;
          case 'unlink':
            await unlinkDriveFolder(context, node);
            break;
          case 'delete':
            await deleteDriveFolder(context, node);
            break;
        }
      },
      itemBuilder: (context) => [
        if (!node.isReadOnly)
          const PopupMenuItem(
            value: 'upload',
            child: ListTile(
              leading: Icon(Icons.cloud_upload, color: Colors.orange),
              title: Text('アップロード'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.cloud_download, color: Colors.green),
            title: Text('ダウンロード'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            leading: Icon(Icons.refresh, color: Colors.blue),
            title: Text('状態を更新'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'unlink',
          child: ListTile(
            leading: Icon(Icons.link_off, color: Colors.red),
            title: Text('Drive連携を解除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text('フォルダごと削除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
