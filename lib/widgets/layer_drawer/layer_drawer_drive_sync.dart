/// K-MAPS: Drive同期関連ミックスイン
library;

import 'dart:io' show Directory;
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../models/nodes/global_folder_node.dart';
import '../../services/google_drive/index.dart';
import '../../services/kmeta_service.dart';
import 'layer_drawer.dart';
import 'sync_merge_dialog.dart';

mixin LayerDrawerDriveSync on ConsumerState<LayerDrawer> {
  void triggerMapRefresh();

  /// 同期状態を更新（UIのみ、ダイアログなし）
  Future<void> refreshSyncStatus(DriveFolderNode node) async {
    final localPath = node.getAbsoluteFilePath();
    if (localPath == null) return;

    node.syncStatus = SyncStatus.syncing;
    setState(() {});

    try {
      final syncEngine = SyncEngine();
      final detail = await syncEngine.checkSyncStatusDetail(localPath);
      _updateNodeSyncStatus(node, detail.status);
    } catch (e) {
      node.syncStatus = SyncStatus.error;
    }

    setState(() {});
  }

  /// 子ノードを再帰的に更新（フォルダ・GeoPackage両方）
  Future<void> _updateChildrenRecursive(LayerTreeNode node) async {
    await node.updateChildren();
    for (final child in node.children) {
      if (child is FolderNode) {
        await _updateChildrenRecursive(child);
      } else if (child is GeoPackageNode) {
        await child.updateChildren();
      }
    }
  }

  /// Drive操作前の認証チェック
  Future<bool> _ensureDriveAuthenticated(BuildContext context) async {
    final driveService = GoogleDriveService();
    
    if (driveService.isDriveApiAvailable) {
      await driveService.refreshToken();
      return true;
    }
    
    await driveService.initialize();
    if (driveService.isDriveApiAvailable) {
      return true;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Driveにログインしています...'),
        duration: Duration(seconds: 3),
      ),
    );
    
    final signInResult = await driveService.signIn();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    if (signInResult) {
      return true;
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Driveへのログインに失敗しました'),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }

  /// 同期マージダイアログを開く
  Future<void> openSyncMergeDialog(
    BuildContext context,
    DriveFolderNode node, {
    required SyncMode mode,
  }) async {
    final localPath = node.getAbsoluteFilePath();
    if (localPath == null) return;

    if (!await _ensureDriveAuthenticated(context)) return;

    try {
      node.syncStatus = SyncStatus.syncing;
      setState(() {});

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
        node.syncStatus = SyncStatus.synced;
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('変更はありません'),
            backgroundColor: Colors.green,
          ),
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
        _updateNodeSyncStatus(node, detail.status);
        setState(() {});
        return;
      }

      node.syncStatus = SyncStatus.syncing;
      setState(() {});

      final result = await syncEngine.executeMerge(localPath, decisions);

      if (result.success) {
        node.syncStatus = SyncStatus.synced;
        
        if (result.downloadedCount > 0 || result.deletedCount > 0) {
          await _updateChildrenRecursive(node);
          triggerMapRefresh();
          setState(() {});
        }
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '同期完了: ${result.uploadedCount}アップロード, '
                '${result.downloadedCount}ダウンロード, '
                '${result.deletedCount}削除',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        node.syncStatus = SyncStatus.error;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('エラー: ${result.errorMessage}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      node.syncStatus = SyncStatus.error;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() {});
  }

  /// ノードの同期状態を更新
  void _updateNodeSyncStatus(DriveFolderNode node, FolderSyncStatus status) {
    switch (status) {
      case FolderSyncStatus.synced:
        node.syncStatus = SyncStatus.synced;
        break;
      case FolderSyncStatus.localChanges:
        node.syncStatus = SyncStatus.localChanges;
        break;
      case FolderSyncStatus.remoteChanges:
        node.syncStatus = SyncStatus.remoteChanges;
        break;
      case FolderSyncStatus.conflict:
        node.syncStatus = SyncStatus.conflict;
        break;
      case FolderSyncStatus.notLinked:
      case FolderSyncStatus.error:
        node.syncStatus = SyncStatus.error;
        break;
    }
  }

  /// Drive連携を解除
  Future<void> unlinkDriveFolder(BuildContext context, DriveFolderNode node) async {
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

    setState(() {});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drive連携を解除しました')),
      );
    }
  }

  /// Drive連携フォルダをローカルから完全削除
  Future<void> deleteDriveFolder(BuildContext context, DriveFolderNode node) async {
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
      setState(() {});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${node.name} を削除しました')),
        );
      }
    } catch (e) {
      AppLogger.error('[LayerDrawerTiles] フォルダ削除エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
      }
    }
  }
}
