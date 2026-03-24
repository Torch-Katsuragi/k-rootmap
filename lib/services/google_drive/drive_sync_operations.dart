/// K-MAPS: Drive同期操作のスタンドアロンサービス
/// LayerDrawerやタイトルバーなど、複数のUIから再利用可能
library;

import 'dart:io' show Directory;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_notification.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../providers/notification_providers.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../models/nodes/global_folder_node.dart';
import '../../services/kmeta_service.dart';
import '../../utils/app_logger.dart';
import '../../widgets/layer_drawer/sync_merge_dialog.dart';
import 'index.dart';

/// Drive同期操作を提供するサービスクラス
///
/// UI依存（setState等）はコールバックで受け取ることで、
/// LayerDrawer・タイトルバーどちらからでも利用可能。
class DriveSyncOperations {
  /// Riverpod ref（通知システム用）
  final WidgetRef ref;

  /// UI更新コールバック（setState相当）
  final VoidCallback onStateChanged;

  /// 地図リフレッシュコールバック
  final VoidCallback? onMapRefresh;

  DriveSyncOperations({
    required this.ref,
    required this.onStateChanged,
    this.onMapRefresh,
  });

  /// 同期状態を更新（UIのみ、ダイアログなし）
  Future<void> refreshSyncStatus(DriveFolderNode node) async {
    final localPath = node.getAbsoluteFilePath();
    if (localPath == null) return;

    node.syncStatus = SyncStatus.syncing;
    onStateChanged();

    try {
      final syncEngine = SyncEngine();
      final detail = await syncEngine.checkSyncStatusDetail(localPath);
      updateNodeSyncStatus(node, detail.status);
    } catch (e) {
      node.syncStatus = SyncStatus.error;
    }

    onStateChanged();
  }

  /// 同期マージダイアログを開く
  Future<void> openSyncMergeDialog(
    BuildContext context,
    DriveFolderNode node, {
    required SyncMode mode,
  }) async {
    final localPath = node.getAbsoluteFilePath();
    if (localPath == null) return;

    if (!await ensureDriveAuthenticated()) return;

    try {
      node.syncStatus = SyncStatus.syncing;
      onStateChanged();

      if (!context.mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('変更を確認しています...'),
            ],
          ),
        ),
      );

      final syncEngine = SyncEngine();
      final entries = await syncEngine.getMergeEntries(localPath);

      if (context.mounted) Navigator.of(context).pop();

      if (!context.mounted) return;

      if (entries.isEmpty) {
        // ファイル変更なしでもDriveの新フォルダをローカルに作成
        final foldersCreated = await syncEngine.ensureDriveFolders(localPath);
        node.syncStatus = SyncStatus.synced;
        onStateChanged();
        if (foldersCreated > 0) {
          await updateChildrenRecursive(node);
          onStateChanged();
        }
        ref.read(notificationCenterProvider.notifier).add(
              title: foldersCreated > 0
                  ? '$foldersCreatedフォルダを作成しました'
                  : '変更はありません',
              level: NotificationLevel.success,
            );
        return;
      }

      final decisions = await SyncMergeDialog.show(
        context,
        folderName: node.name,
        entries: entries,
        mode: mode,
      );

      if (decisions == null || decisions.isEmpty) {
        final detail = await syncEngine.checkSyncStatusDetail(localPath);
        updateNodeSyncStatus(node, detail.status);
        onStateChanged();
        return;
      }

      node.syncStatus = SyncStatus.syncing;
      onStateChanged();

      final result = await syncEngine.executeMerge(localPath, decisions);

      if (result.success) {
        node.syncStatus = SyncStatus.synced;

        if (result.downloadedCount > 0 || result.deletedCount > 0 || result.movedCount > 0) {
          await updateChildrenRecursive(node);
          onMapRefresh?.call();
          onStateChanged();
        }

        ref.read(notificationCenterProvider.notifier).add(
              title: '同期完了: ${result.uploadedCount}アップロード, '
                  '${result.downloadedCount}ダウンロード, '
                  '${result.deletedCount}削除, '
                  '${result.movedCount}移動',
              level: NotificationLevel.success,
            );
      } else {
        node.syncStatus = SyncStatus.error;
        ref.read(notificationCenterProvider.notifier).add(
              title: 'エラー: ${result.errorMessage}',
              level: NotificationLevel.error,
            );
      }
    } catch (e) {
      node.syncStatus = SyncStatus.error;
      ref.read(notificationCenterProvider.notifier).add(
            title: 'エラー: $e',
            level: NotificationLevel.error,
          );
    }

    onStateChanged();
  }

  /// Drive連携を解除（子ノード付きフォルダ用、ルート以外）
  Future<void> unlinkDriveFolder(
    BuildContext context,
    DriveFolderNode node,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Drive連携を解除'),
        content: Text(
          '${node.name} のDrive連携を解除しますか？\n\nローカルファイルは削除されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('解除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final folderPath = node.getAbsoluteFilePath();
    if (folderPath == null) return;

    await KMetaService.instance.unlinkDrive(folderPath);

    final parentNode = node.parent;
    if (parentNode != null) {
      final index = parentNode.children.indexOf(node);
      if (index >= 0) {
        LayerTreeNode replacement;
        if (parentNode is GlobalFolderNode) {
          replacement = GlobalSubFolderNode(
            node.name,
            basePath: parentNode.globalPath,
            visible: node.visible,
            parent: parentNode,
            children: [],
          );
        } else if (parentNode is GlobalSubFolderNode) {
          replacement = GlobalSubFolderNode(
            node.name,
            basePath: parentNode.basePath,
            visible: node.visible,
            parent: parentNode,
            children: [],
          );
        } else {
          replacement = FolderNode(
            node.name,
            visible: node.visible,
            parent: parentNode,
            children: [],
          );
        }
        parentNode.children[index] = replacement;
        node.parent = null;
      }
    }

    onStateChanged();

    ref.read(notificationCenterProvider.notifier).add(
          title: 'Drive連携を解除しました',
          level: NotificationLevel.info,
        );
  }

  /// Drive連携フォルダをローカルから完全削除
  Future<void> deleteDriveFolder(
    BuildContext context,
    DriveFolderNode node,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダ削除'),
        content: Text(
          '${node.name} をローカルから完全に削除しますか？\n\n'
          'フォルダ内のすべてのファイルが削除されます。\n'
          'Drive上のデータには影響しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final folderPath = node.getAbsoluteFilePath();
    if (folderPath == null) return;

    try {
      final dir = Directory(folderPath);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      node.parent?.removeChild(node);
      onStateChanged();

      ref.read(notificationCenterProvider.notifier).add(
            title: '${node.name} を削除しました',
            level: NotificationLevel.info,
          );
    } catch (e) {
      AppLogger.error('[DriveSyncOps] フォルダ削除エラー: $e');
      ref.read(notificationCenterProvider.notifier).add(
            title: '削除に失敗しました: $e',
            level: NotificationLevel.info,
          );
    }
  }

  /// Drive操作前の認証チェック
  Future<bool> ensureDriveAuthenticated() async {
    final driveService = GoogleDriveService();

    if (driveService.isDriveApiAvailable) {
      await driveService.refreshToken();
      return true;
    }

    await driveService.initialize();
    if (driveService.isDriveApiAvailable) {
      return true;
    }

    ref.read(notificationCenterProvider.notifier).add(
          title: 'Google Driveにログインしています...',
          level: NotificationLevel.info,
        );

    final signInResult = await driveService.signIn();

    if (signInResult) {
      return true;
    }

    ref.read(notificationCenterProvider.notifier).add(
          title: 'Google Driveへのログインに失敗しました',
          level: NotificationLevel.error,
        );
    return false;
  }

  /// ノードの同期状態を更新
  static void updateNodeSyncStatus(
    DriveFolderNode node,
    FolderSyncStatus status,
  ) {
    switch (status) {
      case FolderSyncStatus.synced:
        node.syncStatus = SyncStatus.synced;
      case FolderSyncStatus.localChanges:
        node.syncStatus = SyncStatus.localChanges;
      case FolderSyncStatus.remoteChanges:
        node.syncStatus = SyncStatus.remoteChanges;
      case FolderSyncStatus.conflict:
        node.syncStatus = SyncStatus.conflict;
      case FolderSyncStatus.notLinked:
      case FolderSyncStatus.error:
        node.syncStatus = SyncStatus.error;
    }
  }

  /// 子ノードを再帰的に更新（フォルダ・GeoPackage両方）
  static Future<void> updateChildrenRecursive(LayerTreeNode node) async {
    await node.updateChildren();
    for (final child in node.children) {
      if (child is FolderNode) {
        await updateChildrenRecursive(child);
      } else if (child is GeoPackageNode) {
        await child.updateChildren();
      }
    }
  }
}
