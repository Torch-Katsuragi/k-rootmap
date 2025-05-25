// K-MAPS: レイヤツリー共通ノード基底クラス
// FolderNode, GeoPackageGroup, Layerの共通実装

import 'dart:io';
import 'package:path/path.dart' as p;
import '../utils/global_config.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'geopackage_file.dart';
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
  static List<LayerTreeNode> loadNodes(LayerTreeNode? parent) {
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
    final nodes = LayerNode.loadNodes(this);
    for (final node in nodes) {
      addChild(node);
    }
  }

  /// このフォルダ直下のGeoPackageNodeリストのみ返す
  static List<LayerTreeNode> loadNodes(LayerTreeNode? parent) {
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

  /// 指定したparentフォルダの下に新しいGeoPackageファイルを作成し、GeoPackageNodeインスタンスを返す
  /// 失敗時はnullを返す
  static GeoPackageNode? createIn(LayerTreeNode parent, String fileName) {
    if (parent is! FolderNode) return null;
    final parentPath = parent.getAbsoluteFilePath();
    if (parentPath == null) return null;
    final filePath = p.join(parentPath, fileName);
    if (!filePath.endsWith('.gpkg')) return null;
    final gpkgFile = GeoPackageFile([
      ...parent.getAbsolutePathSegments(),
      fileName,
    ]);
    gpkgFile.createIfNotExists();
    final node = GeoPackageNode(gpkgFile, parent: parent);
    parent.addChild(node);
    return node;
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

  /// このレイヤの全FeatureNodeリストを返す
  List<FeatureNode> get features;

  /// このレイヤの属性名一覧を返す（DBカラムから動的取得）
  List<String> getAttributeNames() {
    return geoPackageFile.getColumnNames(layerName);
  }

  /// parentがGeoPackageNodeなら、そのGeoPackage内のLayerNodeサブクラス(Point/Line/Polygon)のみ返す
  static List<LayerTreeNode> loadNodes(LayerTreeNode? parent) {
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
    children.clear();
    // featuresからFeatureNodeをchildrenに追加
    for (final node in features) {
      addChild(node);
    }
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
  List<FeatureNode> get features {
    final feats = geoPackageFile.getFeatures(layerName);
    if (feats == null) return [];
    return feats
        .where(
          (f) =>
              f != null &&
              (f as Map<String, dynamic>)["points"] != null &&
              (f as Map<String, dynamic>)["name"] != null,
        )
        .map((f) {
          final map = f as Map<String, dynamic>;
          return PointFeatureNode(
            map["points"] as List<LatLng>,
            map["name"] as String,
            parent: this,
            rowId: map["id"] ?? 0,
            description: map["description"] as String?,
          );
        })
        .toList();
  }

  @override
  IconData get baseIcon => Icons.scatter_plot;
  @override
  Color get baseIconColor => Colors.blue;

  /// 指定したGeoPackageNodeの下に新しいPointレイヤを作成し、PointLayerNodeインスタンスを返す
  static PointLayerNode? createIn(LayerTreeNode parent, String name) {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final exists = gpkgFile.getLayerNames().contains(name);
    if (exists) return null;
    gpkgFile.addLayer(name, "MULTIPOINT");
    final node = PointLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

class LineLayerNode extends LayerNode {
  LineLayerNode(
    GeoPackageFile file,
    String name, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(file, name, visible: visible, parent: parent);

  @override
  List<FeatureNode> get features {
    final feats = geoPackageFile.getFeatures(layerName);
    if (feats == null) return [];
    return feats
        .where(
          (f) =>
              f != null &&
              (f as Map<String, dynamic>)["lines"] != null &&
              (f as Map<String, dynamic>)["name"] != null,
        )
        .map((f) {
          final map = f as Map<String, dynamic>;
          return LineFeatureNode(
            map["lines"] as List<LatLng>,
            map["name"] as String,
            parent: this,
            rowId: map["id"] ?? 0,
            description: map["description"] as String?,
          );
        })
        .toList();
  }

  @override
  IconData get baseIcon => Icons.show_chart;
  @override
  Color get baseIconColor => Colors.green;

  /// 指定したGeoPackageNodeの下に新しいLineレイヤを作成し、LineLayerNodeインスタンスを返す
  static LineLayerNode? createIn(LayerTreeNode parent, String name) {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final exists = gpkgFile.getLayerNames().contains(name);
    if (exists) return null;
    gpkgFile.addLayer(name, "MULTILINESTRING");
    final node = LineLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
}

class PolygonLayerNode extends LayerNode {
  PolygonLayerNode(
    GeoPackageFile file,
    String name, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(file, name, visible: visible, parent: parent);

  @override
  List<FeatureNode> get features {
    final feats = geoPackageFile.getFeatures(layerName);
    if (feats == null) return [];
    return feats
        .where(
          (f) =>
              f != null &&
              (f as Map<String, dynamic>)["polygons"] != null &&
              (f as Map<String, dynamic>)["name"] != null,
        )
        .map((f) {
          final map = f as Map<String, dynamic>;
          return PolygonFeatureNode(
            map["polygons"] as List<List<LatLng>>,
            map["name"] as String,
            parent: this,
            rowId: map["id"] ?? 0,
            description: map["description"] as String?,
          );
        })
        .toList();
  }

  @override
  IconData get baseIcon => Icons.terrain;
  @override
  Color get baseIconColor => Colors.deepOrange;

  /// 指定したGeoPackageNodeの下に新しいPolygonレイヤを作成し、PolygonLayerNodeインスタンスを返す
  static PolygonLayerNode? createIn(LayerTreeNode parent, String name) {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final exists = gpkgFile.getLayerNames().contains(name);
    if (exists) return null;
    gpkgFile.addLayer(name, "MULTIPOLYGON");
    final node = PolygonLayerNode(gpkgFile, name, parent: parent);
    parent.addChild(node);
    return node;
  }
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
    final folderNodes = FolderNode.loadNodes(this);
    final gpkgNodes = GeoPackageNode.loadNodes(this);
    for (final node in folderNodes) {
      addChild(node);
    }
    for (final node in gpkgNodes) {
      addChild(node);
    }
  }

  /// このフォルダ直下のFolderNodeリストのみ返す
  static List<LayerTreeNode> loadNodes(LayerTreeNode? parent) {
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
  String name;
  String? description;

  /// DB上のrowId（主キー）
  final int rowId;

  /// フィーチャの重心座標
  final LatLng centroid;

  /// 詳細情報（項目名と値のペア、順序付き）
  List<MapEntry<String, String>> get detailEntries => [
    MapEntry('name', name),
    if (description != null && description!.isNotEmpty)
      MapEntry('description', description!),
    MapEntry('id', rowId.toString()),
    MapEntry('latitude', centroid.latitude.toStringAsFixed(6)),
    MapEntry('longitude', centroid.longitude.toStringAsFixed(6)),
  ];

  /// 指定した属性名に対応する値をDBから取得
  dynamic getAttributeValue(String attributeName) {
    // geoPackageFileから都度取得
    return geoPackageFile.getFeatureAttribute(layerName, rowId, attributeName);
  }

  /// フィーチャ削除（DBからも削除）
  @override
  void dispose();

  /// ジオメトリ型ごとのデータ参照（点・線・面）
  Object get geometry;

  /// 親LayerNode
  @override
  final LayerNode parent;

  FeatureNode({
    required this.name,
    this.description,
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
  void editAttribute(String attributeName, dynamic newValue) {
    geoPackageFile.updateFeatureAttribute(
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
    required LayerNode parent,
    required int rowId,
    String? description,
  }) : super(
         name: name,
         parent: parent,
         rowId: rowId,
         description: description,
         centroid: GeometryCalc.calcPointsCentroid(points),
       );

  @override
  List<MapEntry<String, String>> get detailEntries {
    return [...super.detailEntries];
  }

  @override
  Object get geometry => points;

  @override
  void dispose() {
    if (points.isNotEmpty) {
      geoPackageFile.removePoint(layerName, points.first);
    }
    super.dispose();
  }

  @override
  IconData get baseIcon => Icons.location_on;
  @override
  Color get baseIconColor => Colors.red;
  @override
  void updateChildren() {
    children.clear();
  }

  /// 指定したPointLayerNodeの下に新しい点フィーチャを作成し、PointFeatureNodeインスタンスを返す
  static PointFeatureNode? createIn(
    LayerNode parent,
    LatLng point,
    String name,
    String? description,
  ) {
    if (parent is! PointLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;
    gpkgFile.addPoint(
      layerName,
      point,
      name: name ?? '',
      description: description ?? '',
    );
    final features = gpkgFile.getFeatures(layerName);
    final rowId = features.isNotEmpty ? features.last['id'] ?? 0 : 0;
    final node = PointFeatureNode(
      [point],
      name,
      parent: parent,
      rowId: rowId,
      description: description,
    );
    parent.addChild(node);
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
    required LayerNode parent,
    required int rowId,
    String? description,
  }) : super(
         name: name,
         parent: parent,
         rowId: rowId,
         description: description,
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
  void dispose() {
    // TODO: DBから該当線を削除
    super.dispose();
  }

  @override
  IconData get baseIcon => Icons.timeline;
  @override
  Color get baseIconColor => Colors.blueGrey;
  @override
  void updateChildren() {
    children.clear();
  }

  /// 指定したLineLayerNodeの下に新しい線フィーチャを作成し、LineFeatureNodeインスタンスを返す
  static LineFeatureNode? createIn(
    LayerNode parent,
    List<LatLng> line,
    String name,
    String? description,
  ) {
    if (parent is! LineLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;
    gpkgFile.addLine(
      layerName,
      line,
      name: name ?? '',
      description: description ?? '',
    );
    final features = gpkgFile.getFeatures(layerName);
    final rowId = features.isNotEmpty ? features.last['id'] ?? 0 : 0;
    final node = LineFeatureNode(
      line,
      name,
      parent: parent,
      rowId: rowId,
      description: description,
    );
    parent.addChild(node);
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
    required LayerNode parent,
    required int rowId,
    String? description,
  }) : super(
         name: name,
         parent: parent,
         rowId: rowId,
         description: description,
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
  void dispose() {
    // TODO: DBから該当ポリゴンを削除
    super.dispose();
  }

  @override
  IconData get baseIcon => Icons.crop_square;
  @override
  Color get baseIconColor => Colors.orange;
  @override
  void updateChildren() {
    children.clear();
  }

  /// 指定したPolygonLayerNodeの下に新しい面フィーチャを作成し、PolygonFeatureNodeインスタンスを返す
  static PolygonFeatureNode? createIn(
    LayerNode parent,
    List<List<LatLng>> polygon,
    String name,
    String? description,
  ) {
    if (parent is! PolygonLayerNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final layerName = parent.layerName;
    if (polygon.isEmpty) return null;
    gpkgFile.addPolygon(
      layerName,
      polygon,
      name: name ?? '',
      description: description ?? '',
    );
    final features = gpkgFile.getFeatures(layerName);
    final rowId = features.isNotEmpty ? features.last['id'] ?? 0 : 0;
    final node = PolygonFeatureNode(
      polygon,
      name,
      parent: parent,
      rowId: rowId,
      description: description,
    );
    parent.addChild(node);
    return node;
  }
}
