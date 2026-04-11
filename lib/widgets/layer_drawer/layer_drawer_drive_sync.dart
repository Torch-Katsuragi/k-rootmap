/// Root Maps: Drive同期関連ミックスイン
/// DriveSyncOperationsへの薄いラッパー
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../services/google_drive/drive_sync_operations.dart';
import '../../widgets/layer_drawer/sync_merge_dialog.dart';
import 'layer_drawer.dart';

mixin LayerDrawerDriveSync on ConsumerState<LayerDrawer> {
  void triggerMapRefresh();

  DriveSyncOperations? _syncOps;

  DriveSyncOperations get syncOps => _syncOps ??= DriveSyncOperations(
        ref: ref,
        onStateChanged: () => setState(() {}),
        onMapRefresh: triggerMapRefresh,
      );

  Future<void> refreshSyncStatus(DriveFolderNode node) =>
      syncOps.refreshSyncStatus(node);

  Future<void> openSyncMergeDialog(
    BuildContext context,
    DriveFolderNode node, {
    required SyncMode mode,
  }) =>
      syncOps.openSyncMergeDialog(context, node, mode: mode);

  Future<void> unlinkDriveFolder(
          BuildContext context, DriveFolderNode node) =>
      syncOps.unlinkDriveFolder(context, node);

  Future<void> deleteDriveFolder(
          BuildContext context, DriveFolderNode node) =>
      syncOps.deleteDriveFolder(context, node);
}
