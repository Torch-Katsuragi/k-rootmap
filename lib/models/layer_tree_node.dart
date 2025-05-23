// K-MAPS: レイヤツリー共通ノード基底クラス
// FolderNode, GeoPackageGroup, Layerの共通実装

import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/global_config.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'layer.dart';
import 'geopackage_file.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';

/// レイヤツリーのノード共通基底クラス
abstract class LayerTreeNode {
  /// ノード名（表示名）
  String name;

  /// 可視状態
  bool visible;

  /// ノード種別（"folder"/"gpkg"/"layer"）
  final String nodeType;

  /// 親ノード（ルートはnull）
  LayerTreeNode? parent;

  /// 子ノードリスト（レイヤは空リスト）
  List<LayerTreeNode> children;

  /// nodeTypeがとりうる値（固定値リスト）
  static const List<String> nodeTypeValues = ["folder", "gpkg", "layer"];

  /// ノード種別ごとのベースアイコン（UI用）
  IconData get baseIcon;
  Color get baseIconColor;

  /// コンストラクタ
  LayerTreeNode(
    this.name, {
    this.visible = true,
    this.parent,
    List<LayerTreeNode>? children,
    required this.nodeType,
  }) : children = children ?? [] {
    updateChildren();
  }

  /// ノードのリソース解放・削除処理（サブクラスで必ずsuper.dispose()を呼ぶこと）
  @mustCallSuper
  void dispose() {
    parent?.children.remove(this);
    parent = null;
  }

  /// ルートからのパスリスト（meta.json用途）
  List<String> getPathFromRoot() {
    List<String> pathList = [];
    LayerTreeNode? current = this;
    while (current != null) {
      pathList.insert(0, current.name);
      current = current.parent;
    }
    // print('getPathFromRoot result: $pathList'); // 最終結果のデバッグ出力
    return pathList;
  }

  /// ファイルシステム上の絶対パスリスト
  List<String> getAbsolutePathSegments() {
    final path = getPathFromRoot();
    return path.length > 1 ? path.sublist(1) : [];
  }

  /// 再帰的に子ノードをたどり、ノード構造を辞書形式で返す
  /// @return Map<String, dynamic> ノード構造を示す辞書
  Map<String, dynamic> toDict() {
    final Map<String, dynamic> dict = {
      'name': name,
      'type': nodeType,
      'visible': visible,
      'children': children.map((child) => child.toDict()).toList(),
    };
    return dict;
  }

  /// 指定typeの子ノードリストを返す（例: "folder", "gpkg", "layer"）
  List<LayerTreeNode> getChildrenByType(String type) {
    return children.where((c) => c.nodeType == type).toList();
  }

  /// 展開状態（デフォルトはtrue）
  bool get expanded => true;

  /// ファイル構造を参照して自分のchildrenを更新する（サブクラスで必ずoverrideすること）
  void updateChildren();

  /// 子ノードを追加。childrenTypeに合致しない場合は警告を出してスキップ
  void addChild(LayerTreeNode child) {
    children.add(child);
    child.parent = this;
  }

  bool isVisibleRecursive() {
    if (!visible)
      return false;
    else {
      if (parent == null)
        return true;
      else {
        return parent!.isVisibleRecursive();
      }
    }
  }

  /// 自分自身を含むツリー構造を再帰的に辞書(Map)として出力
  /// 例: {"ノード名": {"nodeType": "Folder", "children": [...], "visible": true}}
  Map<String, dynamic> toMap() {
    return {
      name: {
        "nodeType": nodeType,
        "children": children.map((c) => c.toMap()).toList(),
        "visible": visible,
      },
    };
  }

  /// 子ノード名と（必要なら）nodeTypeで該当ノードを取得。なければnull
  /// @param name 子ノード名
  /// @param nodeType ノード種別（省略可）
  /// @return LayerTreeNode? 一致する子ノード、なければnull
  LayerTreeNode? getChild(String name, {String? nodeType}) {
    for (final child in children) {
      if (child.name == name &&
          (nodeType == null || child.nodeType == nodeType)) {
        return child;
      }
    }
    return null;
  }

  /// パスリスト（このノードからのノード名リスト）を受け取り、該当する子孫ノードへの参照を返す
  /// 例: ["root", "folderA", "layer1"]
  /// 見つからなければnullを返す
  LayerTreeNode? getNodeByPath(List<String> pathList) {
    if (pathList.isEmpty) return null;
    if (pathList[0] != name) return null;
    if (pathList.length == 1) return this;
    for (final type in nodeTypeValues) {
      final next = getChild(pathList[1], nodeType: type);
      if (next != null) {
        return next.getNodeByPath(pathList.sublist(1));
      }
      return null;
    }
  }

  /// ノードの絶対パス（ファイルシステム上のパス）を取得
  /// projectRootDir + getAbsolutePathSegments()で構築
  String? getAbsoluteFilePath() {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) return null;
    final segments = getAbsolutePathSegments();
    if (segments.isEmpty) return root;
    return p.joinAll([root, ...segments]);
  }

  /// （サブクラスでoverride推奨）親ノード直下の自分型インスタンスリストを返す（デフォルトは空リスト）
  static List<LayerTreeNode> createNodesByType(LayerTreeNode? parent) {
    return <LayerTreeNode>[];
  }
}

/// GeoPackageファイルノード（GeoPackageFile参照型）
/// LayerTreeNodeの共通機能はoverrideせず、GeoPackageFile参照のみ追加
class GeoPackageNode extends LayerTreeNode {
  /// GeoPackageファイル管理クラスへの参照
  final GeoPackageFile geoPackageFile;

  /// コンストラクタ
  GeoPackageNode(
    this.geoPackageFile, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(
         geoPackageFile.pathList.isNotEmpty ? geoPackageFile.pathList.last : '',
         visible: visible,
         parent: parent,
         nodeType: "gpkg",
       );

  /// ノード種別ごとのベースアイコン（UI用）
  @override
  IconData get baseIcon => Icons.storage;
  @override
  Color get baseIconColor => Colors.blueGrey;

  /// このGeoPackage内のLayerNodeのみ生成
  @override
  void updateChildren() {
    children.clear();
    final nodes = LayerNode.createNodesByType(this);
    for (final node in nodes) {
      addChild(node);
    }
  }

  /// このフォルダ直下のGeoPackageNodeリストのみ返す
  static List<LayerTreeNode> createNodesByType(LayerTreeNode? parent) {
    final nodes = <LayerTreeNode>[];
    if (parent == null) return nodes;
    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) return nodes;
    final dir = Directory(absPath);
    for (var entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.gpkg')) {
        final parentPath = parent.getAbsolutePathSegments();
        final fileName = p.basename(entity.path);
        final gpkgFile = GeoPackageFile([...parentPath, fileName]);
        nodes.add(GeoPackageNode(gpkgFile, visible: true, parent: parent));
      }
    }
    return nodes;
  }

  @override
  void dispose() {
    for (final child in children) {
      child.dispose();
    }
    children.clear();
    // GeoPackageファイル削除
    final filePath = getAbsoluteFilePath();
    if (filePath != null && File(filePath).existsSync()) {
      File(filePath).deleteSync();
    } else {
      print('GeoPackageファイルが見つかりません: $filePath');
    }
    super.dispose();
  }
}

/// LayerNodeをabstract classにし、PointLayerNode/LineLayerNode/PolygonLayerNodeサブクラスを追加
abstract class LayerNode extends LayerTreeNode {
  final GeoPackageFile geoPackageFile;
  final String layerName;
  LayerNode(
    this.geoPackageFile,
    this.layerName, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(layerName, visible: visible, parent: parent, nodeType: "layer");
  List<Feature> get features;

  /// parentがGeoPackageNodeなら、そのGeoPackage内のLayerNodeサブクラス(Point/Line/Polygon)のみ返す
  static List<LayerTreeNode> createNodesByType(LayerTreeNode? parent) {
    final nodes = <LayerTreeNode>[];
    if (parent is! GeoPackageNode) return nodes;
    final gpkgNode = parent as GeoPackageNode;
    final tableNames = gpkgNode.geoPackageFile.getLayerNames();
    for (final tableName in tableNames) {
      final type =
          gpkgNode.geoPackageFile.getGeometryType(tableName)?.toUpperCase();
      if (type == "MULTIPOINT") {
        nodes.add(
          PointLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      } else if (type == "MULTILINESTRING") {
        nodes.add(
          LineLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      } else if (type == "MULTIPOLYGON") {
        nodes.add(
          PolygonLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      }
    }
    return nodes;
  }

  @override
  void dispose() {
    // レイヤ（DBテーブル）削除
    geoPackageFile.removeLayer(layerName);
    super.dispose();
  }

  @override
  void updateChildren() {
    // レイヤノードは子ノードを持たない
    children.clear();
  }
}

class PointLayerNode extends LayerNode {
  PointLayerNode(
    GeoPackageFile file,
    String name, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(file, name, visible: visible, parent: parent);
  @override
  List<MultiPointFeature> get features =>
      geoPackageFile.getFeatures(layerName).cast<MultiPointFeature>();

  @override
  IconData get baseIcon => Icons.scatter_plot;
  @override
  Color get baseIconColor => Colors.blue;
}

class LineLayerNode extends LayerNode {
  LineLayerNode(
    GeoPackageFile file,
    String name, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(file, name, visible: visible, parent: parent);
  @override
  List<MultiLineStringFeature> get features =>
      geoPackageFile.getFeatures(layerName).cast<MultiLineStringFeature>();

  @override
  IconData get baseIcon => Icons.show_chart;
  @override
  Color get baseIconColor => Colors.green;
}

class PolygonLayerNode extends LayerNode {
  PolygonLayerNode(
    GeoPackageFile file,
    String name, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(file, name, visible: visible, parent: parent);
  @override
  List<MultiPolygonFeature> get features =>
      geoPackageFile.getFeatures(layerName).cast<MultiPolygonFeature>();

  @override
  IconData get baseIcon => Icons.terrain;
  @override
  Color get baseIconColor => Colors.deepOrange;
}

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
  IconData get baseIcon => Icons.folder;
  @override
  Color get baseIconColor => Colors.amber;

  /// このフォルダ直下のFolderNode, GeoPackageNodeのみ生成
  @override
  void updateChildren() {
    children.clear();
    final folderNodes = FolderNode.createNodesByType(this);
    final gpkgNodes = GeoPackageNode.createNodesByType(this);
    for (final node in folderNodes) {
      addChild(node);
    }
    for (final node in gpkgNodes) {
      addChild(node);
    }
  }

  /// このフォルダ直下のFolderNodeリストのみ返す
  static List<LayerTreeNode> createNodesByType(LayerTreeNode? parent) {
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
  void dispose() {
    for (final child in children) {
      child.dispose();
    }
    children.clear();
    super.dispose();
  }
}
