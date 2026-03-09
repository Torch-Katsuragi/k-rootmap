/// K-MAPS: レイヤ構造Drawerウィジェット（メインファイル）
/// プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示し、
/// 可視切り替え・リネーム・削除などの操作を提供するUI。
library;

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/image_node.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../providers/project_providers.dart';
import '../../providers/ui_state_providers.dart';
import '../../services/layer_drawer_service.dart';
import '../dialogs/add_folder_type_dialog.dart';
import '../dialogs/drive_url_input_dialog.dart';
import 'common_dialogs.dart';
import 'layer_drawer_title_bar.dart';
import 'layer_drawer_drive_sync.dart';
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
  bool _isDragging = false;
  GeoPackageNode? _dragTarget;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncExpansionState(reset: true);
      });
    }
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

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    ref.watch(featureRefreshTriggerProvider);

    if (widget.currentNode == null) {
      return const Center(child: Text('ディレクトリが見つかりません'));
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
          LayerDrawerTitleBar(
            title: widget.currentNode!.name,
            currentNode: widget.currentNode!,
            onAddFolder:
                widget.currentNode is FolderNode ? () => _addFolder(context) : null,
            onAddGeoPackage:
                widget.currentNode is FolderNode ? () => _addGeoPackage(context) : null,
            onBack: widget.currentNode!.parent != null
                ? () => widget.onDirChanged(widget.currentNode!.parent)
                : null,
          ),
          if (_isDragging)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_upload, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Drop file on GeoPackage to import as layer',
                    style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              children: widget.currentNode!.children.map(_buildNodeTile).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeTile(LayerTreeNode node) {
    if (node is FolderNode) {
      return FolderTile(
        node: node,
        onTap: () => widget.onDirChanged(node),
        onSyncMerge: node is DriveFolderNode ? openSyncMergeDialog : null,
        onRefreshSync: node is DriveFolderNode ? refreshSyncStatus : null,
        onUnlinkDrive: node is DriveFolderNode ? unlinkDriveFolder : null,
        onDeleteDrive: node is DriveFolderNode ? deleteDriveFolder : null,
      );
    }
    if (node is ImageNode) {
      return PhotoTile(
        node: node,
        onRename: () => _renamePhoto(context, node),
        onJumpTo: widget.onJumpTo,
      );
    }
    if (node is GeoPackageNode) {
      return GeoPackageTile(
        node: node,
        isDropTarget: _isDragging && _dragTarget == node,
        onRename: () => _renameGeoPackage(context, node),
        onDragTargetChanged: (t) => setState(() => _dragTarget = t),
        onDragActiveChanged: (a) => setState(() {
          _isDragging = a;
          if (!a) _dragTarget = null;
        }),
        currentDir: widget.currentNode,
      );
    }
    return const SizedBox.shrink();
  }

  // --- UI アクション ---

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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('写真をリネームしました: $result')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('リネームに失敗しました: $e')));
      }
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

      final projectRoot = ref.read(projectRootDirProvider);
      final newFileName = await LayerDrawerService.renameGeoPackage(
        node, result, projectRootDir: projectRoot ?? '',
      );

      if (oldPath != null && wasExpanded) {
        final newPath = p.join(p.dirname(oldPath), newFileName);
        ref.read(expandedGeoPackagesProvider.notifier).updatePath(oldPath, newPath);
        if (node.parent != null) {
          for (final child in node.parent!.children) {
            if (child is GeoPackageNode && child.geoPackageFile.getAbsolutePath() == newPath) {
              await child.updateChildren();
              break;
            }
          }
        }
      }

      triggerMapRefresh();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GeoPackageをリネームしました: $newFileName')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('リネームに失敗しました: $e')));
      }
    }
  }

  Future<void> _addFolder(BuildContext context) async {
    final typeResult = await AddFolderTypeDialog.show(context);
    if (typeResult == null) return;
    if (typeResult.type == AddFolderType.local) {
      try {
        LayerDrawerService.createLocalFolder(widget.currentNode as FolderNode, typeResult.folderName!);
        triggerMapRefresh();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } else {
      await _addDriveFolder(context);
    }
  }

  Future<void> _addDriveFolder(BuildContext context) async {
    final urlResult = await DriveUrlInputDialog.show(context);
    if (urlResult == null) return;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text('${urlResult.folderName} をクローン中...'),
          ]),
          duration: const Duration(seconds: 30),
        ),
      );
    }

    try {
      final node = await LayerDrawerService.cloneDriveFolder(
        parent: widget.currentNode as FolderNode,
        folderId: urlResult.folderId,
        folderName: urlResult.folderName,
        url: urlResult.url,
        isReadOnly: urlResult.isReadOnly,
      );
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (node != null) {
        triggerMapRefresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${urlResult.folderName} をクローンしました'), backgroundColor: Colors.green),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('クローンに失敗しました'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      AppLogger.error('[LayerDrawer] Driveフォルダクローンエラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
        );
      }
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GeoPackageファイルの作成に失敗しました')),
          );
        }
        return;
      }
      final absPath = newNode.geoPackageFile.getAbsolutePath();
      if (absPath != null) ref.read(expandedGeoPackagesProvider.notifier).addExpanded(absPath);
      triggerMapRefresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}
