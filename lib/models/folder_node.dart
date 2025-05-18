import 'dart:io';
import 'package:path/path.dart' as p;
import 'layer_tree_node.dart';
import 'package:flutter/material.dart';

/// フォルダノード（childrenTypeを必ず["folder", "gpkg"]で返す）
class FolderNode extends LayerTreeNode {
  FolderNode(
    String name, {
    bool visible = true,
    LayerTreeNode? parent,
    List<LayerTreeNode>? children,
  }) : super(
         name,
         visible: visible,
         parent: parent,
         children: children,
         nodeType: "folder",
       );
  @override
  List<String> get childrenType => ["folder", "gpkg"];

  @override
  IconData get baseIcon => Icons.folder;
  @override
  Color get baseIconColor => Colors.amber;
}
