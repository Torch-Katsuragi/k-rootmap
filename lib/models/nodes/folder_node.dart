// K-MAPS: フォルダノードクラス
// ファイルシステムのフォルダに対応するレイヤツリーノード

import 'dart:io';
import 'package:k_maps/utils/app_logger.dart';
import 'package:path/path.dart' as p;
import 'layer_tree_node.dart';
import 'geopackage_node.dart';
import 'image_node.dart';
import 'drive_folder_node.dart';
import '../kmeta.dart';
import '../../services/kmeta_service.dart';
import '../../core/node_types.dart';

/// フォルダノード
class FolderNode extends LayerTreeNode {
  /// マージ済みメタデータのキャッシュ
  KMeta? _cachedMeta;

  /// 展開状態（KMetaから取得、未設定時はtrue）
  bool _expanded = true;

  FolderNode(super.name, {super.visible, super.parent, super.children})
    : super(nodeType: NodeType.folder);

  /// 展開状態を取得
  @override
  bool get expanded => _expanded;

  /// 展開状態を設定（KMetaにも保存）
  set expanded(bool value) {
    _expanded = value;
    _saveExpandedState(value);
  }

  /// 展開状態をKMetaに保存
  Future<void> _saveExpandedState(bool value) async {
    final folderPath = getAbsoluteFilePath();
    if (folderPath == null) return;
    await KMetaService.instance.setExpanded(folderPath, value);
  }

  /// マージ済みメタデータを取得（キャッシュ対応）
  Future<KMeta> getMeta() async {
    if (_cachedMeta != null) return _cachedMeta!;
    final folderPath = getAbsoluteFilePath();
    if (folderPath == null) return KMeta.empty;
    _cachedMeta = await KMetaService.instance.getMergedMeta(folderPath);
    return _cachedMeta!;
  }

  /// 生メタデータを取得（このフォルダのみ、継承なし）
  Future<KMeta?> getRawMeta() async {
    final folderPath = getAbsoluteFilePath();
    if (folderPath == null) return null;
    return KMetaService.instance.getRawMeta(folderPath);
  }

  /// メタデータキャッシュをクリア
  void invalidateMetaCache() {
    _cachedMeta = null;
    final folderPath = getAbsoluteFilePath();
    if (folderPath != null) {
      KMetaService.instance.invalidateCache(folderPath);
    }
  }
  
  // UI関連（baseIcon, baseIconColor）はNodePresenterに移動

  /// このフォルダ直下のFolderNode, GeoPackageNode, ImageNodeのみ生成
  @override
  Future<void> updateChildren() async {
    // メタデータを読み込み（展開状態を復元）
    await loadMetaState();

    // ファイルシステムから現在の構造を取得
    final folderNodes = await FolderNode.loadNodes(this);
    final gpkgNodes = await GeoPackageNode.loadNodes(this);
    final photoNodes = await ImageNode.loadNodes(this);

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
    // ただし、グローバルノードはファイルシステム外に存在するため削除しない
    children.removeWhere((child) {
      // グローバルノード（GlobalFolderNode/GlobalSubFolderNode等）は保持
      if (child.isGlobalNode) {
        return false;
      }
      final shouldRemove = !allCurrentNames.contains(child.name);
      if (shouldRemove) {
        AppLogger.debug(
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

    // KMetaの可視性設定を子ノードに適用
    await applyMetaVisibility();

    AppLogger.debug(
      '[DEBUG] FolderNode.updateChildren: ${children.length} children after update',
    );
  }

  /// メタデータから状態を読み込み（サブクラスから呼び出し可能）
  Future<void> loadMetaState() async {
    invalidateMetaCache(); // キャッシュをクリアして最新を読み込み
    final meta = await getMeta();
    // 展開状態を復元
    _expanded = meta.layout.expanded ?? true;
  }

  /// メタデータの可視性設定を子ノードに適用（サブクラスから呼び出し可能）
  Future<void> applyMetaVisibility() async {
    final meta = await getMeta();
    for (final child in children) {
      if (child is GeoPackageNode) {
        // GeoPackageの可視性を適用
        final gpkgVisible = meta.visibility.geopackages[child.name];
        if (gpkgVisible != null) {
          child.visible = gpkgVisible;
        }
      }
      // LayerNodeの可視性はGeoPackageNode側で処理
    }
  }

  /// このフォルダ直下のFolderNodeリストのみ返す（名前昇順でソート）
  /// .kmeta.jsonにDrive連携情報があればDriveFolderNodeとして作成
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    final nodes = <LayerTreeNode>[];
    if (parent == null) return nodes;
    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) return nodes;
    final dir = Directory(absPath);
    
    // ディレクトリを取得して名前順にソート
    final directories = dir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    
    for (var entity in directories) {
      final folderPath = entity.path;
      final folderName = p.basename(folderPath);
      
      // .kmeta.jsonをチェックしてDrive連携情報があるか確認
      final driveNode = await _tryCreateDriveFolderNode(
        folderPath,
        folderName,
        parent,
      );
      
      if (driveNode != null) {
        nodes.add(driveNode);
      } else {
        nodes.add(
          FolderNode(
            folderName,
            visible: true,
            parent: parent,
            children: [],
          ),
        );
      }
    }
    return nodes;
  }

  /// .kmeta.jsonからDrive連携情報を読み込み、DriveFolderNodeを作成
  static Future<LayerTreeNode?> _tryCreateDriveFolderNode(
    String folderPath,
    String folderName,
    LayerTreeNode parent,
  ) async {
    try {
      final meta = await KMetaService.instance.getRawMeta(folderPath);
      if (meta == null || !meta.sync.isLinked) {
        return null;
      }
      
      final driveId = meta.sync.driveId;
      if (driveId == null) return null;
      
      // Drive連携情報がある場合はDriveFolderNodeを作成
      // 動的インポートを避けるため、ここで直接インポートが必要
      // drive_folder_node.dartをインポートする必要がある
      AppLogger.debug('[FolderNode] Drive連携フォルダを検出: $folderName (driveId: $driveId)');
      
      // DriveFolderNodeの作成は呼び出し元で行う（循環参照を避けるため）
      // ここではメタデータを持つマーカーとしてnullを返し、
      // 呼び出し元で処理する設計も考えられるが、
      // 今回は直接インポートして作成する
      return _createDriveFolderNodeFromMeta(folderName, meta, parent);
    } catch (e) {
      AppLogger.debug('[FolderNode] Drive連携チェックエラー: $e');
      return null;
    }
  }

  /// メタデータからDriveFolderNodeを作成
  static LayerTreeNode? _createDriveFolderNodeFromMeta(
    String folderName,
    KMeta meta,
    LayerTreeNode parent,
  ) {
    final driveId = meta.sync.driveId;
    if (driveId == null) return null;
    
    // KMetaSyncからDrive連携情報を取得
    final driveUrl = meta.sync.driveUrl ?? '';
    final isReadOnly = meta.sync.isReadOnly ?? false;
    
    return DriveFolderNode(
      folderName,
      driveId: driveId,
      driveUrl: driveUrl,
      isReadOnly: isReadOnly,
      lastSynced: meta.sync.lastSynced,
      visible: true,
      parent: parent,
      children: [],
    );
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

