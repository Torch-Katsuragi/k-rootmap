// K-MAPS: レイヤツリー共通ノード基底クラス
// FolderNode, GeoPackageGroup, Layerの共通実装

// JSON処理のため追加
// EXIF処理のため追加
import 'package:path/path.dart' as p;
import '../../utils/global_config.dart';
// ジオメトリタイプenumをインポート
import 'package:flutter/material.dart';
// centroid計算用

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
  static const List<String> nodeTypeValues = [
    "folder",
    "gpkg",
    "layer",
    "photo",
  ];

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
    // AppLogger.debug('getPathFromRoot result: $pathList'); // 最終結果のデバッグ出力
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
  List<LayerTreeNode> getVisibleLayerNodes() {
    final result = <LayerTreeNode>[];
    _collectVisibleLayerNodes(result);
    return result;
  }

  /// 可視状態のLayerNodeを再帰的に収集（内部メソッド）
  void _collectVisibleLayerNodes(List<LayerTreeNode> result) {
    if (!isVisibleRecursive()) return;

    if (nodeType == "layer") {
      result.add(this);
    } else {
      for (final child in children) {
        child._collectVisibleLayerNodes(result);
      }
    }
  }

  /// 展開状態（デフォルトはtrue）
  bool get expanded => true;

  /// グローバルフォルダ関連ノードかどうか（デフォルトはfalse）
  /// GlobalFolderNode/GlobalSubFolderNodeでオーバーライドしてtrueを返す
  bool get isGlobalNode => false;

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

