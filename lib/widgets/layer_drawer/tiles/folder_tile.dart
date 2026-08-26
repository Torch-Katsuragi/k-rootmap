// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// Root Maps: フォルダタイルウィジェット
library;

import 'dart:io' show Directory;
import 'package:flutter/material.dart';
import '../../../core/platform_capabilities.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../i18n/strings.g.dart';
import '../../../models/nodes/folder_node.dart';
import '../../../models/nodes/drive_folder_node.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../presentation/node_presenter.dart';
import '../../../services/qgis/qgs_export_action.dart';
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

  static bool get _isMobile => PlatformCapabilities.isMobile;

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
        subtitle: Text(
          t.layerDrawer.folder.pcSyncDisabled,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
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
          case 'export_qgis':
            await exportQgsProject(ref, node);
          case 'delete':
            await _handleDelete(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'rename', child: Text(t.layerDrawer.folder.rename)),
        // 共有の単位は dir。フォルダ単位で書けることに意味がある
        // （このdirを丸ごと渡された人が、そのdirだけでQGISを開ける）
        PopupMenuItem(
          value: 'export_qgis',
          child: Text(t.qgis.exportProject),
        ),
        PopupMenuItem(value: 'delete', child: Text(t.layerDrawer.folder.delete)),
      ],
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    final absPath = node.getAbsoluteFilePath();
    await confirmAndExecute(
      context,
      ref: ref,
      title: t.layerDrawer.folder.deleteTitle,
      content: Text(t.layerDrawer.folder.deleteConfirm(name: node.name)),
      confirmLabel: t.common.delete,
      successMessage: t.layerDrawer.folder.deleted(name: node.name),
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
      SyncStatus.synced => (t.layerDrawer.folder.synced, Colors.green, null),
      SyncStatus.localChanges => (t.layerDrawer.folder.localChanges, Colors.orange, null),
      SyncStatus.remoteChanges => (t.layerDrawer.folder.remoteChanges, Colors.blue, null),
      SyncStatus.conflict => (t.layerDrawer.folder.conflict, Colors.red, Icons.warning_amber_rounded),
      SyncStatus.syncing => (t.layerDrawer.folder.syncing, Colors.blue, null),
      SyncStatus.error => (t.layerDrawer.folder.syncError, Colors.red, null),
      SyncStatus.unknown => (driveNode.isReadOnly ? t.layerDrawer.folder.readOnly : t.layerDrawer.folder.driveLinked, Colors.grey, null),
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
          PopupMenuItem(
            value: 'upload',
            child: ListTile(
              leading: const Icon(Icons.cloud_upload, color: Colors.orange),
              title: Text(t.layerDrawer.folder.upload),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: const Icon(Icons.cloud_download, color: Colors.green),
            title: Text(t.layerDrawer.folder.download),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            leading: const Icon(Icons.refresh, color: Colors.blue),
            title: Text(t.layerDrawer.folder.refreshStatus),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'unlink',
          child: ListTile(
            leading: const Icon(Icons.link_off, color: Colors.red),
            title: Text(t.layerDrawer.folder.unlinkDrive),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(t.layerDrawer.folder.deleteFolderAll),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}
