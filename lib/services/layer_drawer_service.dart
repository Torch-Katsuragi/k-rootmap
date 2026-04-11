/// Root Maps: LayerDrawer 用ビジネスロジック Service
/// フォルダ・GeoPackage の作成/リネーム/Driveクローンを UI 非依存で提供
library;

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/folder_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/image_node.dart';
import '../models/nodes/global_folder_node.dart';
import '../models/nodes/drive_folder_node.dart';
import '../models/geopackage/geopackage_file.dart';
import '../services/google_drive/index.dart';
import '../services/kmeta_service.dart';
import '../i18n/strings.g.dart';

class LayerDrawerService {
  const LayerDrawerService._();

  // ---------- フォルダ ----------

  /// ローカルフォルダを作成して親ノードに追加。同名が存在すると [StateError]
  static FolderNode createLocalFolder(FolderNode parent, String name) {
    final dir = parent.getAbsoluteFilePath();
    final path = p.join(dir ?? '', name);
    if (Directory(path).existsSync()) {
      throw StateError(t.services.folderAlreadyExists);
    }
    Directory(path).createSync();

    final child = switch (parent) {
      GlobalFolderNode p => GlobalSubFolderNode(name, basePath: p.globalPath, visible: true, parent: parent),
      GlobalSubFolderNode p => GlobalSubFolderNode(name, basePath: p.basePath, visible: true, parent: parent),
      _ => FolderNode(name, visible: true, parent: parent),
    };
    parent.addChild(child);
    return child;
  }

  /// Drive フォルダをクローンして追加。失敗時は null
  static Future<DriveFolderNode?> cloneDriveFolder({
    required FolderNode parent,
    required String folderId,
    required String folderName,
    required String url,
    required bool isReadOnly,
  }) async {
    final parentDir = parent.getAbsoluteFilePath();
    if (parentDir == null) return null;

    final localPath = p.join(parentDir, folderName);
    if (Directory(localPath).existsSync()) {
      throw StateError(t.services.folderAlreadyExists);
    }

    final success = await SyncEngine().cloneFromDrive(
      driveId: folderId,
      localPath: localPath,
      folderName: folderName,
      driveUrl: url,
      isReadOnly: isReadOnly,
    );
    if (!success) return null;

    final node = DriveFolderNode(
      folderName,
      driveId: folderId,
      driveUrl: url,
      isReadOnly: isReadOnly,
      visible: true,
      parent: parent,
    );
    parent.addChild(node);
    await _reloadRecursive(node);
    return node;
  }

  // ---------- GeoPackage ----------

  /// 空の GeoPackage を作成して親ノードに追加。作成失敗時は null
  static Future<GeoPackageNode?> createGeoPackage(FolderNode parent, String name) async {
    final dir = parent.getAbsoluteFilePath();
    final fileName = name.endsWith('.gpkg') ? name : '$name.gpkg';
    final path = p.join(dir ?? '', fileName);

    if (File(path).existsSync()) {
      throw StateError(t.services.gpkgAlreadyExists);
    }

    final gpkgFile = GeoPackageFile([fileName], absolutePath: path);
    final node = GeoPackageNode(gpkgFile, visible: true, parent: parent);
    parent.addChild(node);

    if (!await gpkgFile.createEmptyDatabase()) {
      parent.removeChild(node);
      return null;
    }
    return node;
  }

  /// GeoPackage をリネーム。新しいファイル名を返す
  static Future<String> renameGeoPackage(
    GeoPackageNode node,
    String newName, {
    required String projectRootDir,
  }) async {
    final oldPath = node.getAbsoluteFilePath();
    final newFileName = await node.rename(newName, projectRootDir: projectRootDir);
    if (oldPath != null) {
      final newPath = p.join(p.dirname(oldPath), newFileName);
      await notifySyncedPathChange(node, oldPath, newPath);
    }
    if (node.parent != null) await node.parent!.updateChildren();
    return newFileName;
  }

  // ---------- 写真 ----------

  /// 写真をリネーム
  static Future<void> renamePhoto(ImageNode node, String newName) async {
    final oldPath = node.filePath;
    await node.rename(newName);
    final ext = p.extension(oldPath);
    final newFileName = newName.endsWith(ext) ? newName : '$newName$ext';
    final newPath = p.join(p.dirname(oldPath), newFileName);
    await notifySyncedPathChange(node, oldPath, newPath);
    if (node.parent != null) await node.parent!.updateChildren();
  }

  // ---------- ヘルパー ----------

  /// DriveFolderNodeの祖先を探す
  static DriveFolderNode? findDriveRoot(LayerTreeNode? node) {
    LayerTreeNode? current = node;
    while (current != null) {
      if (current is DriveFolderNode) return current;
      if (current is GlobalFolderNode) return null;
      current = current.parent;
    }
    return null;
  }

  /// ローカルリネーム/移動時にsyncedFilesのパスを更新
  static Future<void> notifySyncedPathChange(
    LayerTreeNode node,
    String oldAbsPath,
    String newAbsPath,
  ) async {
    final driveRoot = findDriveRoot(node);
    if (driveRoot == null) return;
    final rootPath = driveRoot.getAbsoluteFilePath();
    if (rootPath == null) return;

    final oldRel = p.relative(oldAbsPath, from: rootPath).replaceAll('\\', '/');
    final newRel = p.relative(newAbsPath, from: rootPath).replaceAll('\\', '/');
    if (oldRel == newRel) return;

    await KMetaService.instance.renameSyncedFiles(rootPath, oldRel, newRel);
  }

  static Future<void> _reloadRecursive(LayerTreeNode node) async {
    await node.updateChildren();
    for (final child in node.children) {
      if (child is FolderNode) {
        await _reloadRecursive(child);
      } else if (child is GeoPackageNode) {
        await child.updateChildren();
      }
    }
  }
}
