// K-MAPS: レイヤツリー共通ノード基底クラス
// FolderNode, GeoPackageGroup, Layerの共通実装

import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/global_config.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'layer.dart';
import 'folder_node.dart';
import 'geopackage_file.dart';
import 'package:flutter/material.dart';

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

  /// このノードが持つ子ノードのnodeType（例: ["folder", "gpkg"]など）
  List<String> get childrenType => [];

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

  /// デストラクタ
  /// 子ノードの参照を解除し、メモリリークを防止
  void dispose() {
    for (final child in children) {
      child.dispose();
    }
    children.clear();
    parent?.children.remove(this);
    parent = null;
  }

  /// 再帰的に可視状態を変更（本体プロパティのみ）
  void setVisibleRecursive(bool v) {
    visible = v;
    for (final child in children) {
      child.setVisibleRecursive(v);
    }
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

  /// メタデータも含めて可視状態を変更
  /// [v]: 設定したい可視状態
  Future<void> setVisibleWithMeta(bool v, {String? type}) async {
    if (!v) {
      setVisibleRecursive(v);
    } else {
      visible = true;
      for (final child in children) {
        child.restoreVisibleRecursive();
      }
    }
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

  /// メタデータから可視状態を読み込んで本体に反映
  void readVisibleFromMeta({String? type}) {
    // This method is no longer used as per the new implementation
  }

  /// 指定typeの子ノードリストを返す（例: "folder", "gpkg", "layer"）
  List<LayerTreeNode> getChildrenByType(String type) {
    return children.where((c) => c.nodeType == type).toList();
  }

  /// GeoPackage等でファイルパスが必要な場合に返す（デフォルトはnull）
  /// GlobalConfigのbaseDirを基準にした絶対パスを返す
  String? getFilePathIfAny() {
    final baseDir = GlobalConfig.instance.projectRootDir;
    if (baseDir == null) return null;

    final pathSegments = getAbsolutePathSegments();
    if (pathSegments.isEmpty) return null;

    return p.joinAll([baseDir, ...pathSegments]);
  }

  /// 展開状態（デフォルトはtrue）
  bool get expanded => true;

  /// ファイル構造を参照して自分のchildrenを更新する（childrenTypeに基づく）
  void updateChildren() {
    print(
      '[DEBUG] updateChildren: 開始 - nodeType=$nodeType, name=$name, childrenType=$childrenType',
    );
    children.clear();

    for (final type in childrenType) {
      final nodes = LayerTreeNode.createNodesByType(
        type,
        getAbsolutePathSegments(),
        parent: this,
      );

      for (final node in nodes) {
        addChild(node);
      }
    }
  }

  /// 子ノードを追加。childrenTypeに合致しない場合は警告を出してスキップ
  void addChild(LayerTreeNode child) {
    if (!childrenType.contains(child.nodeType)) {
      print(
        '[WARN] addChild: nodeType=${child.nodeType}はchildrenType=${childrenType}に合致しないため追加をスキップ',
      );
      return;
    }
    print(
      '[DEBUG] addChild: 子ノード追加 - nodeType=${child.nodeType}, name=${child.name}, parent=${name}',
    );
    children.add(child);
    child.parent = this;
    // child.updateChildren();
  }

  /// nodeTypeと論理パス（getPathFromRoot()の返り値）を受け取り、パス直下の該当nodeTypeノードリストを返すfactory
  static List<LayerTreeNode> createNodesByType(
    String nodeType,
    List<String> logicalPath, {
    LayerTreeNode? parent,
  }) {
    print(
      '[DEBUG] createNodesByType: nodeType=$nodeType, logicalPath=$logicalPath,parent=${parent?.name}',
    );
    final nodes = <LayerTreeNode>[];
    final absPath = p.joinAll([
      GlobalConfig.instance.projectRootDir ?? '',
      ...logicalPath,
    ]);
    if (nodeType == "folder") {
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
        } else if (entity is File && entity.path.endsWith('.gpkg')) {
          // GeoPackageNodeに置換
          final gpkgFile = GeoPackageFile(entity.path);
          nodes.add(GeoPackageNode(gpkgFile, visible: true, parent: parent));
        }
      }
    } else if (nodeType == "gpkg") {
      if (File(absPath).existsSync()) {
        // GeoPackageNodeに置換
        final gpkgFile = GeoPackageFile(absPath);
        nodes.add(GeoPackageNode(gpkgFile, visible: true, parent: parent));
      }
    } else if (nodeType == "layer") {
      if (parent is GeoPackageNode) {
        final gpkgNode = parent as GeoPackageNode;
        final tableNames = gpkgNode.geoPackageFile.getLayerNames();
        print("tableNames: $tableNames");
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
      }
    }
    return nodes;
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

  /// メタデータから可視状態を再帰的に復元
  void restoreVisibleRecursive() {
    // This method is no longer used as per the new implementation
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
         geoPackageFile.path.split(Platform.pathSeparator).last,
         visible: visible,
         parent: parent,
         nodeType: "gpkg",
       );

  /// このノードが持つ子ノードのnodeType
  @override
  List<String> get childrenType => ["layer"];

  @override
  IconData get baseIcon => Icons.storage;
  @override
  Color get baseIconColor => Colors.blueGrey;
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
