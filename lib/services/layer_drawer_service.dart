/// K-MAPS: LayerDrawer 用ビジネスロジック Service
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

class LayerDrawerService {
  const LayerDrawerService._();

  // ---------- フォルダ ----------

  /// ローカルフォルダを作成して親ノードに追加。同名が存在すると [StateError]
  static FolderNode createLocalFolder(FolderNode parent, String name) {
    final dir = parent.getAbsoluteFilePath();
    final path = p.join(dir ?? '', name);
    if (Directory(path).existsSync()) {
      throw StateError('同名のフォルダが既に存在します');
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
      throw StateError('同名のフォルダが既に存在します');
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
      throw StateError('同名のGeoPackageファイルが既に存在します');
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
    final newFileName = await node.rename(newName, projectRootDir: projectRootDir);
    if (node.parent != null) await node.parent!.updateChildren();
    return newFileName;
  }

  // ---------- 写真 ----------

  /// 写真をリネーム
  static Future<void> renamePhoto(ImageNode node, String newName) async {
    await node.rename(newName);
    if (node.parent != null) await node.parent!.updateChildren();
  }

  // ---------- ヘルパー ----------

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
