// K-MAPS: レイヤツリー共通ノード基底クラス
// FolderNode, GeoPackageGroup, Layerの共通実装

import 'dart:io';
import 'dart:convert'; // JSON処理のため追加
import 'package:path/path.dart' as p;
import '../utils/global_config.dart';
// import 'package:sqlite3/sqlite3.dart' as sql; // sqfliteに移行のため削除
import 'geopackage_file.dart';
import 'geometry_type.dart'; // ジオメトリタイプenumをインポート
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:latlong2/latlong.dart';
import '../utils/feature_calc_utils.dart'; // centroid計算用

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
    // 初期化時に非同期でupdateChildrenを呼ぶ（1回のみ） - コメントアウトして問題を修正
    // _initializeChildren();
  }

  /// 初期化フラグ（重複実行を防ぐ）
  bool _initialized = false;

  /// 明示的に子ノードを初期化（遅延初期化パターン）
  /// 通常はUIから初回アクセス時に呼び出される
  Future<void> ensureInitialized() async {
    if (_initialized) return; // 既に初期化済みなら何もしない
    _initialized = true;
    await updateChildren();
  }

  /// 非同期で子ノードを初期化（従来の_initializeChildrenをリネーム）
  /// @deprecated ensureInitialized()を使用してください
  void _initializeChildren() async {
    if (_initialized) return; // 既に初期化済みなら何もしない
    _initialized = true;
    await updateChildren();
  }

  /// ノードのリソース解放・削除処理（サブクラスで必ずsuper.dispose()を呼ぶこと）
  @mustCallSuper
  Future<void> dispose() async {
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

  /// 可視状態のLayerNodeリストを再帰的に取得（高速化用）
  List<LayerNode> getVisibleLayerNodes() {
    final result = <LayerNode>[];
    _collectVisibleLayerNodes(result);
    return result;
  }

  /// 可視状態のLayerNodeを再帰的に収集（内部メソッド）
  void _collectVisibleLayerNodes(List<LayerNode> result) {
    if (!isVisibleRecursive()) return;

    if (this is LayerNode) {
      result.add(this as LayerNode);
    } else {
      for (final child in children) {
        child._collectVisibleLayerNodes(result);
      }
    }
  }

  /// 展開状態（デフォルトはtrue）
  bool get expanded => true;

  /// ファイル構造を参照して自分のchildrenを更新する（非同期化）
  /// サブクラスで必ずoverrideすること
  Future<void> updateChildren() async {}

  /// 子ノードを追加。childrenTypeに合致しない場合は警告を出してスキップ
  void addChild(LayerTreeNode child) {
    children.add(child);
    child.parent = this;
  }

  /// 子ノードを削除
  void removeChild(LayerTreeNode child) {
    children.remove(child);
    child.parent = null;
  }

  /// 同名・同型の子ノードが存在しない場合のみ追加
  /// 既存ノードがある場合はそのノードを返し、ない場合は新規追加して返す
  LayerTreeNode addChildIfNotExists(LayerTreeNode newChild) {
    final existing = getChild(newChild.name, nodeType: newChild.nodeType);
    if (existing != null) {
      // 既存ノードを返す（重複を避ける）
      return existing;
    }
    // 新規追加
    addChild(newChild);
    return newChild;
  }

  bool isVisibleRecursive() {
    if (!visible) {
      return false;
    } else {
      if (parent == null) {
        return true;
      } else {
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
    return null;
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

  /// （サブクラスでoverride推奨）親ノード直下の自分型インスタンスリストを返す（非同期化）
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    // 基底クラスでは空のリストを返す
    // 各サブクラス（FolderNode、GeoPackageNode、LayerNode）で具体的な実装をする
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

  /// このGeoPackage内のLayerNodeのみ生成（非同期化）
  @override
  Future<void> updateChildren() async {
    // DBから現在のレイヤ構造を取得
    final nodes = await LayerNode.loadNodes(this);

    // 現在のDBに存在するレイヤ名のセットを作成
    final currentLayerNames = nodes.map((n) => n.name).toSet();

    // 既存の子ノードで、DBに存在しないものを削除
    children.removeWhere((child) {
      final shouldRemove = !currentLayerNames.contains(child.name);
      if (shouldRemove) {
        print(
          '[DEBUG] GeoPackageNode.updateChildren: removing layer ${child.name} (no longer exists)',
        );
        child.parent = null; // 親子関係を切断
      }
      return shouldRemove;
    });

    // 新しいレイヤノードを追加（既存ノードは再利用）
    for (final node in nodes) {
      addChildIfNotExists(node);
    }

    print(
      '[DEBUG] GeoPackageNode.updateChildren: ${children.length} layers after update',
    );
  }

  /// （サブクラスでoverride推奨）親ノード直下の自分型インスタンスリストを返す（非同期化）
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    print(
      '[DEBUG] GeoPackageNode.loadNodes: called with parent=${parent?.name}',
    );
    final nodes = <LayerTreeNode>[];
    if (parent is! FolderNode) return nodes;

    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) {
      print(
        '[DEBUG] GeoPackageNode.loadNodes: absPath is null for parent ${parent.name}',
      );
      return nodes;
    }

    final dir = Directory(absPath);
    if (!dir.existsSync()) {
      print(
        '[DEBUG] GeoPackageNode.loadNodes: directory does not exist: $absPath',
      );
      return nodes;
    }

    print('[DEBUG] GeoPackageNode.loadNodes: scanning directory: $absPath');
    // ディレクトリ内の.gpkgファイルをスキャン
    for (var entity in dir.listSync()) {
      if (entity is File && entity.path.endsWith('.gpkg')) {
        final fileName = p.basename(entity.path);
        print('[DEBUG] GeoPackageNode.loadNodes: found .gpkg file: $fileName');
        final parentPathSegments = parent.getAbsolutePathSegments();
        final pathList = [...parentPathSegments, fileName];
        final gpkgFile = GeoPackageFile(pathList);

        nodes.add(GeoPackageNode(gpkgFile, visible: true, parent: parent));
        print(
          '[DEBUG] GeoPackageNode.loadNodes: created GeoPackageNode for $fileName',
        );
      }
    }
    print(
      '[DEBUG] GeoPackageNode.loadNodes: found ${nodes.length} .gpkg files, returning',
    );
    return nodes;
  }

  /// GeoPackageファイルを含む削除処理（ファイル自体も削除）
  @override
  Future<void> dispose() async {
    print('[DEBUG] GeoPackageNode.dispose: disposing ${name}');

    try {
      // ファイル自体を削除
      final success = await geoPackageFile.deleteFile();
      if (success) {
        print('[DEBUG] GeoPackageNode.dispose: ファイル削除成功 - ${name}');
      } else {
        print('[DEBUG] GeoPackageNode.dispose: ファイル削除失敗 - ${name}');
      }
    } catch (e) {
      print('[ERROR] GeoPackageNode.dispose: ファイル削除エラー - $e');
    }

    // 基底クラスの処理（親子関係切断）
    await super.dispose();

    print('[DEBUG] GeoPackageNode.dispose: dispose完了 - ${name}');
  }
}

/// レイヤノード（LayerNode）: GeoPackage内のフィーチャテーブル＋FeatureNodeコレクション
abstract class LayerNode extends LayerTreeNode {
  /// GeoPackageファイル管理クラスへの参照
  final GeoPackageFile geoPackageFile;

  /// レイヤ名（DBテーブル名）
  final String layerName;

  /// このレイヤに含まれるFeatureNodeリスト（非同期取得）
  Future<List<FeatureNode>> get features async {
    return <FeatureNode>[];
  }

  /// コンストラクタ
  LayerNode(
    this.geoPackageFile,
    this.layerName, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(layerName, visible: visible, parent: parent, nodeType: "layer");

  /// （サブクラスでoverride推奨）親ノード直下の自分型インスタンスリストを返す（非同期化）
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    final nodes = <LayerTreeNode>[];
    if (parent is! GeoPackageNode) return nodes;
    final gpkgNode = parent;
    final tableNames = await gpkgNode.geoPackageFile.getLayerNames();
    for (final tableName in tableNames) {
      final type = await gpkgNode.geoPackageFile.getGeometryType(tableName);
      if (type == GeometryType.point) {
        nodes.add(
          PointLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      } else if (type == GeometryType.linestring) {
        nodes.add(
          LineLayerNode(
            gpkgNode.geoPackageFile,
            tableName,
            visible: true,
            parent: parent,
          ),
        );
      } else if (type == GeometryType.polygon) {
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
  Future<void> dispose() async {
    // レイヤ（DBテーブル）削除
    await geoPackageFile.removeLayer(layerName);
    await super.dispose();
  }

  @override
  Future<void> updateChildren() async {
    children.clear();
    // featuresからFeatureNodeをchildrenに追加
    final featureList = await features;
    for (final node in featureList) {
      addChild(node);
    }
  }
}

class PointLayerNode extends LayerNode {
  PointLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> get features async {
    final feats = await geoPackageFile.getFeatures(layerName);
    return feats.where((f) => (f)["points"] != null && (f)["name"] != null).map(
      (f) {
        final map = f;
        return PointFeatureNode(
          map["points"] as List<LatLng>,
          map["name"] as String,
          parent: this,
          rowId: map["id"] ?? 0,
          description: map["description"] as String?,
          metadata: map["metadata"] as Map<String, dynamic>?,
        );
      },
    ).toList();
  }

  @override
  IconData get baseIcon => Icons.scatter_plot;
  @override
  Color get baseIconColor => Colors.blue;

  /// 指定したGeoPackageNodeの下に新しいPointレイヤを作成し、PointLayerNodeインスタンスを返す
  static Future<PointLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    final exists = existingLayers.contains(name);
    if (exists) return null;
    await gpkgFile.addLayer(name, GeometryType.point);
    final node = PointLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

class LineLayerNode extends LayerNode {
  LineLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> get features async {
    final feats = await geoPackageFile.getFeatures(layerName);
    return feats.where((f) => (f)["lines"] != null && (f)["name"] != null).map((
      f,
    ) {
      final map = f;
      return LineFeatureNode(
        map["lines"] as List<LatLng>,
        map["name"] as String,
        parent: this,
        rowId: map["id"] ?? 0,
        description: map["description"] as String?,
        metadata: map["metadata"] as Map<String, dynamic>?,
      );
    }).toList();
  }

  @override
  IconData get baseIcon => Icons.show_chart;
  @override
  Color get baseIconColor => Colors.green;

  /// 指定したGeoPackageNodeの下に新しいLineレイヤを作成し、LineLayerNodeインスタンスを返す
  static Future<LineLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    final exists = existingLayers.contains(name);
    if (exists) return null;
    await gpkgFile.addLayer(name, GeometryType.linestring);
    final node = LineLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

class PolygonLayerNode extends LayerNode {
  PolygonLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> get features async {
    final feats = await geoPackageFile.getFeatures(layerName);
    return feats
        .where((f) => (f)["polygons"] != null && (f)["name"] != null)
        .map((f) {
          final map = f;
          return PolygonFeatureNode(
            map["polygons"] as List<List<LatLng>>,
            map["name"] as String,
            parent: this,
            rowId: map["id"] ?? 0,
            description: map["description"] as String?,
            metadata: map["metadata"] as Map<String, dynamic>?,
          );
        })
        .toList();
  }

  @override
  IconData get baseIcon => Icons.terrain;
  @override
  Color get baseIconColor => Colors.deepOrange;

  /// 指定したGeoPackageNodeの下に新しいPolygonレイヤを作成し、PolygonLayerNodeインスタンスを返す
  static Future<PolygonLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    final exists = existingLayers.contains(name);
    if (exists) return null;
    await gpkgFile.addLayer(name, GeometryType.polygon);
    final node = PolygonLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

class FolderNode extends LayerTreeNode {
  FolderNode(super.name, {super.visible, super.parent, super.children})
    : super(nodeType: "folder");

  @override
  IconData get baseIcon => Icons.folder;
  @override
  Color get baseIconColor => Colors.amber;

  /// このフォルダ直下のFolderNode, GeoPackageNodeのみ生成
  @override
  Future<void> updateChildren() async {
    // ファイルシステムから現在の構造を取得
    final folderNodes = await FolderNode.loadNodes(this);
    final gpkgNodes = await GeoPackageNode.loadNodes(this);

    // 現在のファイルシステムに存在するノード名のセットを作成
    final currentFolderNames = folderNodes.map((n) => n.name).toSet();
    final currentGpkgNames = gpkgNodes.map((n) => n.name).toSet();
    final allCurrentNames = {...currentFolderNames, ...currentGpkgNames};

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

/// フィーチャノード基底クラス
/// LayerNodeの子としてfeature単位で生成される
abstract class FeatureNode extends LayerTreeNode {
  /// 属性値
  @override
  String name;
  String? description;

  /// メタデータ（構造化されたデータ）
  Map<String, dynamic>? metadata;

  /// DB上のrowId（主キー）
  final int rowId;

  /// フィーチャの重心座標
  final LatLng centroid;

  /// 詳細情報（項目名と値のペア、順序付き）
  List<MapEntry<String, String>> get detailEntries => [
    MapEntry('name', name),
    if (description != null && description!.isNotEmpty)
      MapEntry('description', description!),
    if (metadata != null && metadata!.isNotEmpty)
      ...metadata!.entries.map(
        (e) => MapEntry('metadata.${e.key}', e.value.toString()),
      ),
    MapEntry('id', rowId.toString()),
    MapEntry('latitude', centroid.latitude.toStringAsFixed(6)),
    MapEntry('longitude', centroid.longitude.toStringAsFixed(6)),
  ];

  /// 指定した属性名に対応する値をDBから取得
  Future<dynamic> getAttributeValue(String attributeName) async {
    // geoPackageFileから都度取得
    return await geoPackageFile.getFeatureAttribute(
      layerName,
      rowId,
      attributeName,
    );
  }

  /// フィーチャ削除（親子関係切断・UI更新の最適化）
  /// DBからの削除は各サブクラスで実装（ジオメトリ型に応じた適切な削除処理）
  @override
  Future<void> dispose() async {
    print('[DEBUG] FeatureNode.dispose: disposing ${name} (${runtimeType})');

    // 即座に親子関係を切断（UI更新を優先）
    if (parent != null) {
      parent!.children.remove(this);
      print('[DEBUG] FeatureNode.dispose: removed from parent children');
    }

    // 選択状態からも除去
    final globalConfig = GlobalConfig.instance;
    if (globalConfig.selectedFeatures.contains(this)) {
      globalConfig.selectedFeatures.remove(this);
      print('[DEBUG] FeatureNode.dispose: removed from selected features');
    }

    // parentを切断
    parent = null;

    // 子ノードはFeatureNodeにはないが、安全のためクリア
    children.clear();

    print('[DEBUG] FeatureNode.dispose: base dispose completed for ${name}');
  }

  /// ジオメトリ型ごとのデータ参照（点・線・面）
  Object get geometry;

  /// 親LayerNode
  @override
  final LayerNode parent;

  FeatureNode({
    required this.name,
    this.description,
    this.metadata,
    required this.parent,
    required this.rowId,
    required this.centroid,
  }) : super(
         name,
         visible: parent.visible,
         parent: parent,
         children: [],
         nodeType: 'feature',
       );

  /// GeoPackageFile参照
  GeoPackageFile get geoPackageFile => parent.geoPackageFile;

  /// レイヤ名
  String get layerName => parent.layerName;

  /// 指定した属性名の値をDB上で編集
  Future<void> editAttribute(String attributeName, dynamic newValue) async {
    await geoPackageFile.updateFeatureAttribute(
      layerName,
      rowId,
      attributeName,
      newValue,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FeatureNode &&
        other.rowId == rowId &&
        other.layerName == layerName &&
        other.geoPackageFile == geoPackageFile;
  }

  @override
  int get hashCode => Object.hash(rowId, layerName, geoPackageFile);
}

/// PointFeatureNode: 点フィーチャ用
class PointFeatureNode extends FeatureNode {
  final List<LatLng> points;
  PointFeatureNode(
    this.points,
    String name, {
    required super.parent,
    required super.rowId,
    super.description,
    super.metadata,
  }) : super(name: name, centroid: GeometryCalc.calcPointsCentroid(points));

  @override
  List<MapEntry<String, String>> get detailEntries {
    return [...super.detailEntries];
  }

  @override
  Object get geometry => points;

  @override
  Future<void> dispose() async {
    print('[DEBUG] PointFeatureNode.dispose: disposing point feature ${name}');

    // 基底クラスの処理（親子関係切断・選択状態クリア）を先に実行
    await super.dispose();

    // DBからの削除を非同期で実行（UIには影響させない）
    if (points.isNotEmpty) {
      geoPackageFile
          .removePoint(layerName, points.first)
          .then((_) {
            print(
              '[DEBUG] PointFeatureNode.dispose: DB deletion completed for ${name}',
            );
          })
          .catchError((e) {
            print(
              '[ERROR] PointFeatureNode.dispose: DB deletion failed for ${name}: $e',
            );
          });
    }

    print('[DEBUG] PointFeatureNode.dispose: point feature dispose completed');
  }

  @override
  IconData get baseIcon => Icons.location_on;
  @override
  Color get baseIconColor => Colors.red;
  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  /// 指定したPointLayerNodeの下に新しい点フィーチャを作成し、PointFeatureNodeインスタンスを返す
  /// DBへの保存は非同期で実行し、FeatureNodeは即座に作成・追加される
  static Future<PointFeatureNode?> createIn(
    LayerNode parent,
    LatLng point,
    String name,
    String? description, {
    Map<String, dynamic>? metadata,
  }) async {
    if (parent is! PointLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;

    // 仮のrowIdを生成（実際のDBへの保存は非同期で実行）
    final tempRowId = DateTime.now().millisecondsSinceEpoch;

    // FeatureNodeを即座に作成（地図表示用）
    final node = PointFeatureNode(
      [point],
      name,
      parent: parent,
      rowId: tempRowId,
      description: description,
      metadata: metadata,
    );
    parent.addChild(node);

    // DBへの保存を非同期で実行（UIには影響しない）
    gpkgFile
        .addPoint(
          layerName,
          point,
          name: name ?? '',
          description: description ?? '',
          metadata: metadata,
        )
        .then((_) {
          print('[DEBUG] PointFeatureNode: DB保存完了 - $name');
        })
        .catchError((e) {
          print('[ERROR] PointFeatureNode: DB保存エラー - $e');
        });

    return node;
  }
}

/// LineFeatureNode: 線フィーチャ用
class LineFeatureNode extends FeatureNode {
  /// 単一の線分（頂点リスト）
  final List<LatLng> line;
  LineFeatureNode(
    this.line,
    String name, {
    required super.parent,
    required super.rowId,
    super.description,
    super.metadata,
  }) : super(
         name: name,
         centroid:
             line.isNotEmpty
                 ? GeometryCalc.calcLineCentroid(line)
                 : LatLng(0, 0),
       );

  @override
  List<MapEntry<String, String>> get detailEntries {
    final len = GeometryCalc.calcLineLength(line);
    String lengthStr;
    if (len >= 10000) {
      lengthStr = '${(len / 1000).toStringAsFixed(2)} km';
    } else {
      lengthStr = '${len.toStringAsFixed(2)} m';
    }
    return [
      ...super.detailEntries,
      MapEntry('length', lengthStr),
      MapEntry('vertex_count', '${line.length}'),
    ];
  }

  @override
  Object get geometry => line;

  @override
  Future<void> dispose() async {
    print('[DEBUG] LineFeatureNode.dispose: disposing line feature ${name}');

    // 基底クラスの処理（親子関係切断・選択状態クリア）を先に実行
    await super.dispose();

    // DBから該当線を削除（非同期で実行、UIには影響させない）
    geoPackageFile
        .removeLine(layerName, rowId)
        .then((_) {
          print(
            '[DEBUG] LineFeatureNode.dispose: DB deletion completed for ${name}',
          );
        })
        .catchError((e) {
          print(
            '[ERROR] LineFeatureNode.dispose: DB deletion failed for ${name}: $e',
          );
        });

    print('[DEBUG] LineFeatureNode.dispose: line feature dispose completed');
  }

  @override
  IconData get baseIcon => Icons.timeline;
  @override
  Color get baseIconColor => Colors.blueGrey;
  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  /// 指定したLineLayerNodeの下に新しい線フィーチャを作成し、LineFeatureNodeインスタンスを返す
  /// DBへの保存は非同期で実行し、FeatureNodeは即座に作成・追加される
  static Future<LineFeatureNode?> createIn(
    LayerNode parent,
    List<LatLng> line,
    String name,
    String? description, {
    Map<String, dynamic>? metadata,
  }) async {
    if (parent is! LineLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;

    // 仮のrowIdを生成（実際のDBへの保存は非同期で実行）
    final tempRowId = DateTime.now().millisecondsSinceEpoch;

    // FeatureNodeを即座に作成（地図表示用）
    final node = LineFeatureNode(
      line,
      name,
      parent: parent,
      rowId: tempRowId,
      description: description,
      metadata: metadata,
    );
    parent.addChild(node);

    // DBへの保存を非同期で実行（UIには影響しない）
    gpkgFile
        .addLine(
          layerName,
          line,
          name: name ?? '',
          description: description ?? '',
          metadata: metadata,
        )
        .then((_) {
          print('[DEBUG] LineFeatureNode: DB保存完了 - $name');
        })
        .catchError((e) {
          print('[ERROR] LineFeatureNode: DB保存エラー - $e');
        });

    return node;
  }
}

/// PolygonFeatureNode: 面フィーチャ用
class PolygonFeatureNode extends FeatureNode {
  /// 単一のポリゴン（外環＋穴リスト）
  final List<List<LatLng>> polygon;
  PolygonFeatureNode(
    this.polygon,
    String name, {
    required super.parent,
    required super.rowId,
    super.description,
    super.metadata,
  }) : super(
         name: name,
         centroid:
             (polygon.isNotEmpty && polygon[0].isNotEmpty)
                 ? GeometryCalc.calcPolygonCentroid(polygon)
                 : LatLng(0, 0),
       );

  @override
  List<MapEntry<String, String>> get detailEntries {
    final areaDeg2 = GeometryCalc.calcPolygonArea(polygon);
    final centroid = this.centroid;
    final areaM2 = DegreeMeterConverter.convertAreaToMeters2(
      areaDeg2,
      centroid.latitude,
    );
    String areaStr;
    if (areaM2 >= 10000) {
      areaStr = '${(areaM2 / 10000).toStringAsFixed(2)} ha';
    } else {
      areaStr = '${areaM2.toStringAsFixed(2)} m²';
    }
    return [...super.detailEntries, MapEntry('area', areaStr)];
  }

  @override
  Object get geometry => polygon;

  @override
  Future<void> dispose() async {
    print(
      '[DEBUG] PolygonFeatureNode.dispose: disposing polygon feature ${name}',
    );

    // 基底クラスの処理（親子関係切断・選択状態クリア）を先に実行
    await super.dispose();

    // DBから該当ポリゴンを削除（非同期で実行、UIには影響させない）
    geoPackageFile
        .removePolygon(layerName, rowId)
        .then((_) {
          print(
            '[DEBUG] PolygonFeatureNode.dispose: DB deletion completed for ${name}',
          );
        })
        .catchError((e) {
          print(
            '[ERROR] PolygonFeatureNode.dispose: DB deletion failed for ${name}: $e',
          );
        });

    print(
      '[DEBUG] PolygonFeatureNode.dispose: polygon feature dispose completed',
    );
  }

  @override
  IconData get baseIcon => Icons.crop_square;
  @override
  Color get baseIconColor => Colors.orange;
  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  /// 指定したPolygonLayerNodeの下に新しい面フィーチャを作成し、PolygonFeatureNodeインスタンスを返す
  /// DBへの保存は非同期で実行し、FeatureNodeは即座に作成・追加される
  static Future<PolygonFeatureNode?> createIn(
    LayerNode parent,
    List<List<LatLng>> polygon,
    String name,
    String? description, {
    Map<String, dynamic>? metadata,
  }) async {
    if (parent is! PolygonLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;
    if (polygon.isEmpty) return null;

    // 仮のrowIdを生成（実際のDBへの保存は非同期で実行）
    final tempRowId = DateTime.now().millisecondsSinceEpoch;

    // FeatureNodeを即座に作成（地図表示用）
    final node = PolygonFeatureNode(
      polygon,
      name,
      parent: parent,
      rowId: tempRowId,
      description: description,
      metadata: metadata,
    );
    parent.addChild(node);

    // DBへの保存を非同期で実行（UIには影響しない）
    gpkgFile
        .addPolygon(
          layerName,
          polygon,
          name: name ?? '',
          description: description ?? '',
          metadata: metadata,
        )
        .then((_) {
          print('[DEBUG] PolygonFeatureNode: DB保存完了 - $name');
        })
        .catchError((e) {
          print('[ERROR] PolygonFeatureNode: DB保存エラー - $e');
        });

    return node;
  }
}
