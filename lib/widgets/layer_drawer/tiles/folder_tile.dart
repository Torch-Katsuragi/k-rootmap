/// K-MAPS: フォルダタイルウィジェット
library;

import 'dart:io' show Directory, Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/drive_folder_node.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../presentation/node_presenter.dart';
import '../common_dialogs.dart';
import '../sync_merge_dialog.dart';
import 'node_visibility_icon.dart';

/// フォルダノード用の ListTile ウィジェット
/// DriveFolderNode の場合は同期メニューを追加（モバイルのみ）
class FolderTile extends ConsumerWidget {
  final FolderNode node;
  final VoidCallback onTap;
  final VoidCallback? onRename;
  final Future<void> Function(BuildContext, DriveFolderNode, {required SyncMode mode})? onSyncMerge;
  final Future<void> Function(DriveFolderNode)? onRefreshSync;
  final Future<void> Function(BuildContext, DriveFolderNode)? onUnlinkDrive;
  final Future<void> Function(BuildContext, DriveFolderNode)? onDeleteDrive;

  const FolderTile({
    super.key,
    required this.node,
    required this.onTap,
    this.onRename,
    this.onSyncMerge,
    this.onRefreshSync,
    this.onUnlinkDrive,
    this.onDeleteDrive,
  });

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (node is DriveFolderNode && _isMobile) {
      final driveNode = node as DriveFolderNode;
      return ListTile(
        leading: NodePresenter.buildIconWithSyncOverlay(
          driveNode,
          size: 24,
          syncStatus: driveNode.syncStatus,
        ),
        title: Text(node.name),
        subtitle: _buildSyncSubtitle(context, driveNode),
        onTap: onTap,
        trailing: _buildDriveMenu(context, driveNode),
      );
    }

    if (node is DriveFolderNode) {
      return ListTile(
        leading: Icon(Icons.cloud, color: Colors.blue.shade600),
        title: Text(node.name),
        subtitle: const Text(
          'PC版では同期不可（Google Drive Desktop使用）',
          style: TextStyle(fontSize: 10, color: Colors.grey),
        ),
        onTap: onTap,
      );
    }

    return ListTile(
      leading: NodeVisibilityIcon(node: node),
      title: Text(node.name),
      onTap: onTap,
      trailing: _buildFolderMenu(context, ref),
    );
  }

  Widget _buildFolderMenu(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'rename':
            onRename?.call();
          case 'delete':
            await _handleDelete(context, ref);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    final absPath = node.getAbsoluteFilePath();
    await confirmAndExecute(
      context,
      ref: ref,
      title: 'Delete Folder',
      content: Text('Delete "${node.name}" and all its contents?'),
      confirmLabel: 'Delete',
      successMessage: '${node.name} deleted',
      execute: () async {
        if (absPath != null) {
          final dir = Directory(absPath);
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        }
        await node.dispose();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
    );
  }

  Widget _buildSyncSubtitle(BuildContext context, DriveFolderNode driveNode) {
    final (text, color, icon) = switch (driveNode.syncStatus) {
      SyncStatus.synced => ('Synced', Colors.green, null),
      SyncStatus.localChanges => ('Local changes pending', Colors.orange, null),
      SyncStatus.remoteChanges => ('Drive changes available', Colors.blue, null),
      SyncStatus.conflict => ('Conflict — tap to resolve', Colors.red, Icons.warning_amber_rounded),
      SyncStatus.syncing => ('Syncing...', Colors.blue, null),
      SyncStatus.error => ('Error', Colors.red, null),
      SyncStatus.unknown => (driveNode.isReadOnly ? 'Read-only' : 'Drive linked', Colors.grey, null),
    };
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
    if (driveNode.syncStatus == SyncStatus.conflict) {
      return GestureDetector(
        onTap: () => onSyncMerge?.call(context, driveNode, mode: SyncMode.download),
        child: child,
      );
    }
    return child;
  }

  Widget _buildDriveMenu(BuildContext context, DriveFolderNode driveNode) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'upload':
            await onSyncMerge?.call(context, driveNode, mode: SyncMode.upload);
          case 'download':
            await onSyncMerge?.call(context, driveNode, mode: SyncMode.download);
          case 'refresh':
            await onRefreshSync?.call(driveNode);
          case 'unlink':
            await onUnlinkDrive?.call(context, driveNode);
          case 'delete':
            await onDeleteDrive?.call(context, driveNode);
        }
      },
      itemBuilder: (context) => [
        if (!driveNode.isReadOnly)
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
