// K-MAPS: GeoPackageノードクラス
// GeoPackageファイルに対応するレイヤツリーノード

import 'dart:io';
import 'package:k_maps/utils/app_logger.dart';
import 'package:path/path.dart' as p;
import 'layer_tree_node.dart';
import 'layer_node.dart';
import '../geopackage/geopackage_file.dart';
import '../kmeta.dart';
import 'folder_node.dart';
import '../../utils/global_config.dart';
import '../../core/node_types.dart';

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
         nodeType: NodeType.geopackage,
       );
  
  // UI関連（baseIcon, baseIconColor）はNodePresenterに移動

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
        AppLogger.debug(
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

    // KMetaの可視性設定をレイヤーに適用
    await _applyMetaVisibility();

    AppLogger.debug(
      '[DEBUG] GeoPackageNode.updateChildren: ${children.length} layers after update',
    );
  }

  /// 親フォルダのKMetaを取得
  Future<KMeta?> _getParentMeta() async {
    final folderParent = parent;
    if (folderParent is FolderNode) {
      return folderParent.getMeta();
    }
    return null;
  }

  /// KMetaの可視性設定をレイヤーに適用
  Future<void> _applyMetaVisibility() async {
    final meta = await _getParentMeta();
    if (meta == null) return;

    for (final child in children) {
      if (child is LayerNode) {
        final layerVisible = meta.visibility.layers[child.layerName];
        if (layerVisible != null) {
          child.visible = layerVisible;
        }
      }
    }
  }

  /// （サブクラスでoverride推奨）親ノード直下の自分型インスタンスリストを返す（非同期化）
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    AppLogger.debug(
      '[DEBUG] GeoPackageNode.loadNodes: called with parent=${parent?.name}',
    );
    final nodes = <LayerTreeNode>[];
    if (parent is! FolderNode) return nodes;

    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) {
      AppLogger.debug(
        '[DEBUG] GeoPackageNode.loadNodes: absPath is null for parent ${parent.name}',
      );
      return nodes;
    }

    final dir = Directory(absPath);
    if (!dir.existsSync()) {
      AppLogger.debug(
        '[DEBUG] GeoPackageNode.loadNodes: directory does not exist: $absPath',
      );
      return nodes;
    }

    AppLogger.debug('[DEBUG] GeoPackageNode.loadNodes: scanning directory: $absPath');
    // ディレクトリ内の.gpkgファイルをスキャンして名前順にソート
    final gpkgFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gpkg'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    
    for (var entity in gpkgFiles) {
      final fileName = p.basename(entity.path);
      AppLogger.debug('[DEBUG] GeoPackageNode.loadNodes: found .gpkg file: $fileName');
      final parentPathSegments = parent.getAbsolutePathSegments();
      final pathList = [...parentPathSegments, fileName];
      final gpkgFile = GeoPackageFile(pathList);

      nodes.add(GeoPackageNode(gpkgFile, visible: true, parent: parent));
      AppLogger.debug(
        '[DEBUG] GeoPackageNode.loadNodes: created GeoPackageNode for $fileName',
      );
    }
    AppLogger.debug(
      '[DEBUG] GeoPackageNode.loadNodes: found ${nodes.length} .gpkg files, returning',
    );
    return nodes;
  }

  /// リネーム処理
  /// 戻り値: リネーム後の新しいファイル名（拡張子付き）
  Future<String> rename(String newName) async {
    try {
      // まずコネクションを閉じる
      await geoPackageFile.dispose();

      // 現在のパスを取得
      final baseDir = GlobalConfig.instance.projectRootDir;
      if (baseDir == null) {
        throw Exception('projectRootDirが未設定です');
      }
      final currentPath = p.joinAll([baseDir, ...geoPackageFile.pathList]);
      
      final file = File(currentPath);
      if (!file.existsSync()) {
        throw Exception('ファイルが存在しません: $currentPath');
      }

      final directory = p.dirname(currentPath);
      final extension = '.gpkg';
      // 拡張子が含まれていない場合は付与
      final newFileName = newName.endsWith(extension) ? newName : '$newName$extension';
      final newPath = p.join(directory, newFileName);

      if (File(newPath).existsSync()) {
        throw Exception('同名のファイルが既に存在します: $newFileName');
      }

      // リネーム実行
      await file.rename(newPath);
      
      // 注意: parent.updateChildren()は呼び出し元で行う
      // これにより、呼び出し元で展開状態の管理などを適切に行える
      
      return newFileName;
    } catch (e) {
      AppLogger.debug('[ERROR] GeoPackageNode.rename: $e');
      rethrow;
    }
  }

  /// GeoPackageファイルを含む削除処理（ファイル自体も削除）
  @override
  Future<void> dispose() async {
    AppLogger.debug('[DEBUG] GeoPackageNode.dispose: disposing $name');

    try {
      // ファイル自体を削除
      final success = await geoPackageFile.deleteFile();
      if (success) {
        AppLogger.debug('[DEBUG] GeoPackageNode.dispose: ファイル削除成功 - $name');
      } else {
        AppLogger.debug('[DEBUG] GeoPackageNode.dispose: ファイル削除失敗 - $name');
      }
    } catch (e) {
      AppLogger.debug('[ERROR] GeoPackageNode.dispose: ファイル削除エラー - $e');
    }

    // 基底クラスの処理（親子関係切断）
    await super.dispose();

    AppLogger.debug('[DEBUG] GeoPackageNode.dispose: dispose完了 - $name');
  }
}

