/// K-MAPS: レイヤ構造Drawerウィジェット（メインファイル）
/// プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示し、
/// 可視切り替え・リネーム・削除などの操作を提供するUI。
library;

import 'dart:async';
import 'dart:io';
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/image_node.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';
import '../../providers/project_providers.dart';
import '../../providers/ui_state_providers.dart';
import '../../screens/gallery_import_screen.dart';
import '../../services/kmeta_service.dart';
import '../../services/layer_drawer_service.dart';
import '../dialogs/add_folder_type_dialog.dart';
import '../dialogs/drive_url_input_dialog.dart';
import 'common_dialogs.dart';
import 'layer_drawer_title_bar.dart';
import 'layer_drawer_drive_sync.dart';
import 'sync_merge_dialog.dart';
import 'tiles/drag_feedback_card.dart';
import 'tiles/folder_tile.dart';
import 'tiles/geopackage_tile.dart';
import 'tiles/photo_tile.dart';

/// レイヤ構造Drawer
class LayerDrawer extends ConsumerStatefulWidget {
  final LayerTreeNode? currentNode;
  final void Function(LayerTreeNode? newNode) onDirChanged;
  final void Function(LatLng latLng)? onJumpTo;
  final void Function(FeatureNode feature)? onStartAppendMode;

  const LayerDrawer({
    super.key,
    required this.currentNode,
    required this.onDirChanged,
    this.onJumpTo,
    this.onStartAppendMode,
  });

  @override
  ConsumerState<LayerDrawer> createState() => _LayerDrawerState();
}

class _LayerDrawerState extends ConsumerState<LayerDrawer>
    with LayerDrawerDriveSync {
  LayerTreeNode? _draggingNode;
  GeoPackageNode? _dragTarget;

  bool get _isDragging => _draggingNode != null;
  bool get _isLayerDrag => _draggingNode is LayerNode;
  Timer? _dragNavTimer;

  void _endDrag() {
    if (!_isDragging) return;
    setState(() { _draggingNode = null; _dragTarget = null; });
  }

  @override
  void triggerMapRefresh() =>
      ref.read(featureRefreshTriggerProvider.notifier).trigger();

  // --- ライフサイクル ---

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncExpansionState(reset: false);
    });
  }

  @override
  void didUpdateWidget(LayerDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentNode != widget.currentNode) {
      _cancelDragNavTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncExpansionState(reset: true);
      });
    }
  }

  @override
  void dispose() {
    _dragNavTimer?.cancel();
    super.dispose();
  }

  void _syncExpansionState({required bool reset}) {
    final paths = _collectGpkgPaths(widget.currentNode);
    final notifier = ref.read(expandedGeoPackagesProvider.notifier);
    if (reset) {
      notifier.resetAndExpandAll(paths);
    } else {
      notifier.expandAll(paths);
    }
  }

  static List<String> _collectGpkgPaths(LayerTreeNode? node) {
    if (node == null) return [];
    return [
      for (final child in node.children)
        if (child is GeoPackageNode)
          if (child.geoPackageFile.getAbsolutePath() case final String p) p,
    ];
  }

  // --- ドラッグ中フォルダナビゲーション ---

  void _startDragNavTimer(VoidCallback navigate) {
    if (_dragNavTimer != null) return;
    _dragNavTimer = Timer(const Duration(milliseconds: 500), () {
      _dragNavTimer = null;
      if (mounted) navigate();
    });
  }

  void _cancelDragNavTimer() {
    _dragNavTimer?.cancel();
    _dragNavTimer = null;
  }

  /// ドラッグ中に0.5秒ホバーでディレクトリ遷移 + ファイル移動ドロップを受け付ける DragTarget ラッパー。
  /// [dropTarget] が指定された場合、非LayerNode のドロップでファイル移動を実行する。
  Widget _wrapDragNav(Widget child, VoidCallback onNavigate, {FolderNode? dropTarget}) {
    return DragTarget<LayerTreeNode>(
      onWillAcceptWithDetails: (details) {
        if (dropTarget != null && identical(details.data, dropTarget)) return false;
        return true;
      },
      onMove: (_) => _startDragNavTimer(onNavigate),
      onLeave: (_) => _cancelDragNavTimer(),
      onAcceptWithDetails: (details) {
        _cancelDragNavTimer();
        if (dropTarget != null && details.data is! LayerNode) {
          _moveNodeToFolder(details.data, dropTarget);
        }
      },
      builder: (context, candidateData, __) => Container(
        decoration: candidateData.isNotEmpty
            ? BoxDecoration(
                border: Border.all(color: Colors.orange, width: 2),
                borderRadius: BorderRadius.circular(4),
                color: Colors.orange.withValues(alpha: 0.1),
              )
            : null,
        child: child,
      ),
    );
  }

  // --- ファイル移動 ---

  Future<void> _moveNodeToFolder(LayerTreeNode source, FolderNode target) async {
    _endDrag();

    final sourcePath = source.getAbsoluteFilePath();
    final targetDir = target.getAbsoluteFilePath();
    if (sourcePath == null || targetDir == null) return;

    final baseName = p.basename(sourcePath);
    final newPath = p.join(targetDir, baseName);
    if (sourcePath == newPath) return;

    if (FileSystemEntity.typeSync(newPath) != FileSystemEntityType.notFound) {
      ref.read(notificationCenterProvider.notifier).add(
            title: '"$baseName" already exists in ${target.name}',
            level: NotificationLevel.info,
          );
      return;
    }

    try {
      await _moveFileOrDir(sourcePath, newPath, isDir: source is FolderNode);
      await LayerDrawerService.notifySyncedPathChange(source, sourcePath, newPath);

      final sourceParent = source.parent;
      if (sourceParent != null) await sourceParent.updateChildren();
      await target.updateChildren();

      if (source is GeoPackageNode) {
        final moved = target.children.whereType<GeoPackageNode>()
            .where((n) => n.name == baseName).firstOrNull;
        if (moved != null) await moved.updateChildren();
      }

      ref.read(featureRefreshTriggerProvider.notifier).trigger();
      ref.read(notificationCenterProvider.notifier).add(
            title: 'Moved "${source.name}" to ${target.name}',
            level: NotificationLevel.info,
          );
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'Move failed: $e',
            level: NotificationLevel.error,
          );
    }
  }

  Future<void> _moveFileOrDir(String src, String dst, {required bool isDir}) async {
    try {
      if (isDir) {
        await Directory(src).rename(dst);
      } else {
        await File(src).rename(dst);
      }
    } on FileSystemException {
      if (isDir) {
        await _copyDirectory(Directory(src), Directory(dst));
        await Directory(src).delete(recursive: true);
      } else {
        await File(src).copy(dst);
        await File(src).delete();
      }
    }
  }

  Future<void> _copyDirectory(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      final name = p.basename(entity.path);
      if (entity is File) {
        await entity.copy(p.join(dst.path, name));
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(dst.path, name)));
      }
    }
  }

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    ref.watch(featureRefreshTriggerProvider);

    if (widget.currentNode == null) {
      return const Center(child: Text('ディレクトリが見つかりません'));
    }

    final parent = widget.currentNode!.parent;
    final driveRoot = LayerDrawerService.findDriveRoot(widget.currentNode);
    Widget titleBar = LayerDrawerTitleBar(
      title: widget.currentNode!.name,
      currentNode: widget.currentNode!,
      onAdd: widget.currentNode is FolderNode
          ? (action) => switch (action) {
                AddAction.folder => _addFolder(context),
                AddAction.geoPackage => _addGeoPackage(context),
                AddAction.photo => _addPhoto(context),
              }
          : null,
      onBack: parent != null ? () => widget.onDirChanged(parent) : null,
      syncStatus: driveRoot?.syncStatus,
      isReadOnly: driveRoot?.isReadOnly ?? false,
      onCloudAction: driveRoot != null
          ? (action) => _handleCloudAction(context, driveRoot, action)
          : null,
    );
    if (parent != null) {
      titleBar = _wrapDragNav(
        titleBar,
        () => widget.onDirChanged(parent),
        dropTarget: parent is FolderNode ? parent : null,
      );
    }

    return Container(
      decoration: _isDragging
          ? BoxDecoration(
              border: Border.all(color: Colors.blue, width: 2),
              borderRadius: BorderRadius.circular(8),
              color: Colors.blue.withValues(alpha: 0.1),
            )
          : null,
      child: Column(
        children: [
          titleBar,
          if (_isDragging)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (_isLayerDrag ? Colors.blue : Colors.orange).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    _isLayerDrag ? Icons.cloud_upload : Icons.drive_file_move,
                    color: _isLayerDrag ? Colors.blue : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _isLayerDrag
                          ? 'Drop layer on GeoPackage to migrate'
                          : 'Drop here or on a folder to move',
                      style: TextStyle(
                        color: _isLayerDrag ? Colors.blue : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox.shrink(),
          Expanded(
            child: DragTarget<LayerTreeNode>(
              onWillAcceptWithDetails: (details) =>
                  details.data is! LayerNode &&
                  widget.currentNode is FolderNode &&
                  details.data.parent != widget.currentNode,
              onAcceptWithDetails: (details) {
                if (widget.currentNode case final FolderNode folder) {
                  _moveNodeToFolder(details.data, folder);
                }
              },
              builder: (context, candidateData, __) => Container(
                decoration: candidateData.isNotEmpty
                    ? BoxDecoration(
                        border: Border.all(color: Colors.orange, width: 2),
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.orange.withValues(alpha: 0.05),
                      )
                    : null,
                child: ListView(
                  children: widget.currentNode!.children.map(_buildNodeTile).toList(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(LayerTreeNode node) {
    if (node is FolderNode) {
      final tile = FolderTile(
        node: node,
        onTap: () => widget.onDirChanged(node),
        onRename: node is! DriveFolderNode ? () => _renameFolder(context, node) : null,
        onSyncMerge: node is DriveFolderNode ? openSyncMergeDialog : null,
        onRefreshSync: node is DriveFolderNode ? refreshSyncStatus : null,
        onUnlinkDrive: node is DriveFolderNode ? unlinkDriveFolder : null,
        onDeleteDrive: node is DriveFolderNode ? deleteDriveFolder : null,
      );
      Widget result = _wrapDragNav(tile, () => widget.onDirChanged(node), dropTarget: node);
      if (node is! DriveFolderNode) {
        result = _wrapDraggable(result, node);
      }
      return result;
    }
    if (node is ImageNode) {
      return _wrapDraggable(
        PhotoTile(node: node, onRename: () => _renamePhoto(context, node), onJumpTo: widget.onJumpTo),
        node,
      );
    }
    if (node is GeoPackageNode) {
      return GeoPackageTile(
        node: node,
        isDropTarget: (_isLayerDrag || !_isDragging) && _dragTarget == node,
        onRename: () => _renameGeoPackage(context, node),
        onDragTargetChanged: (t) => setState(() => _dragTarget = t),
        onDragActiveChanged: (dragNode) => setState(() {
          _draggingNode = dragNode;
          if (dragNode == null) _dragTarget = null;
        }),
        currentDir: widget.currentNode,
      );
    }
    return const SizedBox.shrink();
  }

  /// ファイル移動用の LongPressDraggable ラッパー
  Widget _wrapDraggable(Widget child, LayerTreeNode node) {
    return LongPressDraggable<LayerTreeNode>(
      data: node,
      dragAnchorStrategy: (_, __, ___) => const Offset(0, 0),
      feedback: DragFeedbackCard(node: node),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      onDragStarted: () => setState(() => _draggingNode = node),
      onDraggableCanceled: (_, __) => _endDrag(),
      onDragEnd: (_) => _endDrag(),
      child: child,
    );
  }

  // --- UI アクション ---

  Future<void> _renameFolder(BuildContext context, FolderNode node) async {
    final result = await RenameDialog.show(
      context,
      title: 'Rename Folder',
      currentName: node.name,
      label: 'New name',
    );
    if (result == null || result.isEmpty || result == node.name) return;
    try {
      final absPath = node.getAbsoluteFilePath();
      if (absPath != null) {
        final newPath = p.join(p.dirname(absPath), result);
        await Directory(absPath).rename(newPath);
        await LayerDrawerService.notifySyncedPathChange(node, absPath, newPath);
      }
      node.name = result;
      triggerMapRefresh();
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'Rename failed: $e',
            level: NotificationLevel.info,
          );
    }
  }

  Future<void> _renamePhoto(BuildContext context, ImageNode node) async {
    final currentName = p.basenameWithoutExtension(node.name);
    final result = await RenameDialog.show(
      context,
      title: '写真のリネーム',
      currentName: currentName,
      label: '新しいファイル名',
    );
    if (result == null || result.isEmpty || result == currentName) return;
    try {
      await LayerDrawerService.renamePhoto(node, result);
      triggerMapRefresh();
      ref.read(notificationCenterProvider.notifier).add(
            title: '写真をリネームしました: $result',
            level: NotificationLevel.info,
          );
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'リネームに失敗しました: $e',
            level: NotificationLevel.info,
          );
    }
  }

  Future<void> _renameGeoPackage(BuildContext context, GeoPackageNode node) async {
    final currentName = p.basenameWithoutExtension(node.name);
    final result = await RenameDialog.show(
      context,
      title: 'GeoPackageのリネーム',
      currentName: currentName,
      label: '新しいファイル名',
    );
    if (result == null || result.isEmpty || result == currentName) return;
    try {
      final oldPath = node.geoPackageFile.getAbsolutePath();
      final wasExpanded = ref.read(expandedGeoPackagesProvider).isExpanded(oldPath);
      // updateChildren()でnode.parentがnullになるため、先に保持
      final parentNode = node.parent;

      final projectRoot = ref.read(projectRootDirProvider);
      final newFileName = await LayerDrawerService.renameGeoPackage(
        node, result, projectRootDir: projectRoot ?? '',
      );

      if (oldPath != null && parentNode != null) {
        final newPath = p.join(p.dirname(oldPath), newFileName);
        if (wasExpanded) {
          ref.read(expandedGeoPackagesProvider.notifier).updatePath(oldPath, newPath);
        }
        // 新しいGeoPackageNodeのレイヤを読み込む
        for (final child in parentNode.children) {
          if (child is GeoPackageNode && child.geoPackageFile.getAbsolutePath() == newPath) {
            await child.updateChildren();
            break;
          }
        }
      }

      triggerMapRefresh();
      ref.read(notificationCenterProvider.notifier).add(
            title: 'GeoPackageをリネームしました: $newFileName',
            level: NotificationLevel.info,
          );
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'リネームに失敗しました: $e',
            level: NotificationLevel.info,
          );
    }
  }

  Future<void> _handleCloudAction(
    BuildContext context,
    DriveFolderNode driveRoot,
    String action,
  ) async {
    switch (action) {
      case 'upload':
        await openSyncMergeDialog(context, driveRoot, mode: SyncMode.upload);
      case 'download':
        await openSyncMergeDialog(context, driveRoot, mode: SyncMode.download);
      case 'refresh':
        await refreshSyncStatus(driveRoot);
      case 'unlink':
        if (driveRoot.parent != null) {
          await unlinkDriveFolder(context, driveRoot);
        } else {
          await _unlinkRootDrive(context, driveRoot);
        }
    }
  }

  Future<void> _unlinkRootDrive(
    BuildContext context,
    DriveFolderNode driveRoot,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Drive連携を解除'),
        content: Text(
          '${driveRoot.name} のDrive連携を解除しますか？\n\nローカルファイルは削除されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final folderPath = driveRoot.getAbsoluteFilePath();
    if (folderPath == null) return;

    await KMetaService.instance.unlinkDrive(folderPath);

    final replacement = FolderNode(
      driveRoot.name,
      visible: driveRoot.visible,
      children: [],
    );
    for (final child in driveRoot.children) {
      child.parent = replacement;
      replacement.children.add(child);
    }
    driveRoot.children.clear();

    ref.read(folderTreeProvider.notifier).set(replacement);
    widget.onDirChanged(replacement);

    ref.read(notificationCenterProvider.notifier).add(
          title: 'Drive連携を解除しました',
          level: NotificationLevel.info,
        );
  }

  Future<void> _addFolder(BuildContext context) async {
    final isUnderDrive = LayerDrawerService.findDriveRoot(widget.currentNode) != null;
    final typeResult = await AddFolderTypeDialog.show(context, allowDrive: !isUnderDrive);
    if (typeResult == null) return;
    if (typeResult.type == AddFolderType.local) {
      try {
        LayerDrawerService.createLocalFolder(widget.currentNode as FolderNode, typeResult.folderName!);
        triggerMapRefresh();
      } catch (e) {
        ref.read(notificationCenterProvider.notifier).add(title: '$e', level: NotificationLevel.info);
      }
    } else {
      if (!context.mounted) return;
      await _addDriveFolder(context);
    }
  }

  Future<void> _addDriveFolder(BuildContext context) async {
    final urlResult = await DriveUrlInputDialog.show(context);
    if (urlResult == null) return;

    ref.read(notificationCenterProvider.notifier).add(
          title: '${urlResult.folderName} をクローン中...',
          level: NotificationLevel.info,
        );

    try {
      final node = await LayerDrawerService.cloneDriveFolder(
        parent: widget.currentNode as FolderNode,
        folderId: urlResult.folderId,
        folderName: urlResult.folderName,
        url: urlResult.url,
        isReadOnly: urlResult.isReadOnly,
      );

      if (node != null) {
        triggerMapRefresh();
        ref.read(notificationCenterProvider.notifier).add(
              title: '${urlResult.folderName} をクローンしました',
              level: NotificationLevel.success,
            );
      } else {
        ref.read(notificationCenterProvider.notifier).add(
              title: 'クローンに失敗しました',
              level: NotificationLevel.error,
            );
      }
    } catch (e) {
      AppLogger.error('[LayerDrawer] Driveフォルダクローンエラー: $e');
      ref.read(notificationCenterProvider.notifier).add(
            title: 'エラー: $e',
            level: NotificationLevel.error,
          );
    }
  }

  Future<void> _addGeoPackage(BuildContext context) async {
    final result = await RenameDialog.show(
      context,
      title: '新規GeoPackageファイル',
      currentName: '',
      label: 'ファイル名（.gpkg）',
      submitLabel: '作成',
    );
    if (result == null || result.isEmpty) return;

    try {
      final newNode = await LayerDrawerService.createGeoPackage(widget.currentNode as FolderNode, result);
      if (newNode == null) {
        ref.read(notificationCenterProvider.notifier).add(
              title: 'GeoPackageファイルの作成に失敗しました',
              level: NotificationLevel.info,
            );
        return;
      }
      final absPath = newNode.geoPackageFile.getAbsolutePath();
      if (absPath != null) ref.read(expandedGeoPackagesProvider.notifier).addExpanded(absPath);
      triggerMapRefresh();
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(title: '$e', level: NotificationLevel.info);
    }
  }

  Future<void> _addPhoto(BuildContext context) async {
    final folder = widget.currentNode as FolderNode;
    final imported = await GalleryImporter.pickAndImport(context, folder, ref: ref);
    if (imported) {
      await folder.updateChildren();
      triggerMapRefresh();
    }
  }
}
