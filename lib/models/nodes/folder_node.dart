// K-MAPS: フォルダノードクラス
// ファイルシステムのフォルダに対応するレイヤツリーノード

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'layer_tree_node.dart';
import 'geopackage_node.dart';
import 'photo_node.dart';

/// フォルダノード
class FolderNode extends LayerTreeNode {
  FolderNode(super.name, {super.visible, super.parent, super.children})
    : super(nodeType: "folder");

  @override
  IconData get baseIcon => Icons.folder;
  @override
  Color get baseIconColor => Colors.amber;

  /// このフォルダ直下のFolderNode, GeoPackageNode, PhotoNodeのみ生成
  @override
  Future<void> updateChildren() async {
    // ファイルシステムから現在の構造を取得
    final folderNodes = await FolderNode.loadNodes(this);
    final gpkgNodes = await GeoPackageNode.loadNodes(this);
    final photoNodes = await PhotoNode.loadNodes(this);

    // 現在のファイルシステムに存在するノード名のセットを作成
    final currentFolderNames = folderNodes.map((n) => n.name).toSet();
    final currentGpkgNames = gpkgNodes.map((n) => n.name).toSet();
    final currentPhotoNames = photoNodes.map((n) => n.name).toSet();
    final allCurrentNames = {
      ...currentFolderNames,
      ...currentGpkgNames,
      ...currentPhotoNames,
    };

    // 既存の子ノードで、ファイルシステムに存在しないものを削除
    children.removeWhere((child) {
      final shouldRemove = !allCurrentNames.contains(child.name);
      if (shouldRemove) {
        print(
          '[DEBUG] FolderNode.updateChildren: removing ${child.name} (no longer exists)',
        );
        child.parent = null; // 親子関係を切断
      }
      return shouldRemove;
    });

    // 新しいノードを追加（既存ノードは再利用）
    for (final node in folderNodes) {
      addChildIfNotExists(node);
    }
    for (final node in gpkgNodes) {
      addChildIfNotExists(node);
    }
    for (final node in photoNodes) {
      addChildIfNotExists(node);
    }

    print(
      '[DEBUG] FolderNode.updateChildren: ${children.length} children after update',
    );
  }

  /// このフォルダ直下のFolderNodeリストのみ返す
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    final nodes = <LayerTreeNode>[];
    if (parent == null) return nodes;
    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) return nodes;
    final dir = Directory(absPath);
    for (var entity in dir.listSync()) {
      if (entity is Directory) {
        nodes.add(
          FolderNode(
            p.basename(entity.path),
            visible: true,
            parent: parent,
            children: [],
          ),
        );
      }
    }
    return nodes;
  }

  @override
  Future<void> dispose() async {
    for (final child in children) {
      await child.dispose();
    }
    children.clear();
    await super.dispose();
  }

  /// 指定したparentフォルダの下に新しいフォルダを作成し、FolderNodeインスタンスを返す
  /// 失敗時はnullを返す
  static FolderNode? createIn(LayerTreeNode parent, String name) {
    // 親がFolderNodeでなければ不可
    if (parent is! FolderNode) return null;
    final parentPath = parent.getAbsoluteFilePath();
    if (parentPath == null) return null;
    final newDir = Directory(p.join(parentPath, name));
    if (!newDir.existsSync()) {
      newDir.createSync();
    }
    final node = FolderNode(name, parent: parent);
    parent.addChild(node);
    return node;
  }
}
