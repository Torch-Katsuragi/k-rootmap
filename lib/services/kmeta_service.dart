// K-MAPS: フォルダメタデータサービス
// 継承チェーン解決・保存処理を担当

import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/kmeta.dart';
import '../models/nodes/layer_tree_node.dart';
import '../utils/app_logger.dart';
import '../utils/global_config.dart';

/// フォルダメタデータサービス
/// 継承チェーンを解決し、マージ済みメタデータを提供
class KMetaService {
  // シングルトン
  static final KMetaService instance = KMetaService._internal();
  factory KMetaService() => instance;
  KMetaService._internal();

  /// メタデータキャッシュ（フォルダパス → 生メタデータ）
  final Map<String, KMeta> _rawCache = {};

  /// マージ済みメタデータキャッシュ（フォルダパス → マージ済みメタデータ）
  final Map<String, KMeta> _mergedCache = {};

  /// キャッシュをクリア
  void clearCache() {
    _rawCache.clear();
    _mergedCache.clear();
    AppLogger.debug('[KMetaService] Cache cleared');
  }

  /// 特定フォルダのキャッシュをクリア（変更時に使用）
  void invalidateCache(String folderPath) {
    _rawCache.remove(folderPath);
    // マージ済みキャッシュは子フォルダも影響を受けるのでクリア
    _mergedCache.removeWhere((key, _) => key.startsWith(folderPath));
    AppLogger.debug('[KMetaService] Cache invalidated for: $folderPath');
  }

  /// フォルダの生メタデータを取得（キャッシュ対応・バージョンゲート付き）
  Future<KMeta?> getRawMeta(String folderPath) async {
    if (_rawCache.containsKey(folderPath)) {
      return _rawCache[folderPath];
    }

    final meta = await KMeta.loadFromFile(folderPath);
    if (meta == null) return null;

    // バージョンゲート: 旧バージョンはsyncのみ保持して再保存
    if (meta.version < kMetaSchemaVersion) {
      AppLogger.debug(
        '[KMetaService] 旧バージョン(v${meta.version})検出、マイグレーション実行: $folderPath',
      );
      final migrated = KMeta(sync: meta.sync);
      await saveMeta(folderPath, migrated);
      _rawCache[folderPath] = migrated;
      return migrated;
    }

    _rawCache[folderPath] = meta;
    return meta;
  }

  /// フォルダのマージ済みメタデータを取得（継承チェーン解決済み）
  Future<KMeta> getMergedMeta(String folderPath) async {
    // キャッシュ確認
    if (_mergedCache.containsKey(folderPath)) {
      return _mergedCache[folderPath]!;
    }

    // 継承チェーンを解決
    final mergedMeta = await _resolveInheritanceChain(folderPath);
    _mergedCache[folderPath] = mergedMeta;
    return mergedMeta;
  }

  /// LayerTreeNodeからマージ済みメタデータを取得
  Future<KMeta> getMergedMetaForNode(LayerTreeNode node) async {
    final folderPath = node.getAbsoluteFilePath();
    if (folderPath == null) {
      return KMeta.empty;
    }
    return getMergedMeta(folderPath);
  }

  /// 継承チェーンを解決してマージ
  Future<KMeta> _resolveInheritanceChain(String folderPath) async {
    final projectRoot = GlobalConfig.instance.projectRootDir;
    if (projectRoot == null) {
      return await getRawMeta(folderPath) ?? KMeta.empty;
    }

    // 正規化されたパス
    final normalizedPath = p.normalize(folderPath);
    final normalizedRoot = p.normalize(projectRoot);

    // ルートからこのフォルダまでのパスを構築
    final ancestorPaths = <String>[];
    String currentPath = normalizedPath;

    while (currentPath.length >= normalizedRoot.length) {
      ancestorPaths.insert(0, currentPath);
      final parentPath = p.dirname(currentPath);
      if (parentPath == currentPath) break; // ルートに到達
      currentPath = parentPath;
    }

    // ルートから順にマージ
    KMeta? mergedMeta;
    for (final ancestorPath in ancestorPaths) {
      final rawMeta = await getRawMeta(ancestorPath);
      if (rawMeta != null) {
        mergedMeta = rawMeta.mergeWith(mergedMeta);
      } else if (mergedMeta != null) {
        // このフォルダにはメタデータがないが、親からの継承は維持
        mergedMeta = mergedMeta;
      }
    }

    return mergedMeta ?? KMeta.empty;
  }

  /// メタデータを保存
  Future<bool> saveMeta(String folderPath, KMeta meta) async {
    final success = await meta.saveToFile(folderPath);
    if (success) {
      _rawCache[folderPath] = meta;
      // マージ済みキャッシュを無効化（子フォルダにも影響）
      _mergedCache.removeWhere((key, _) => key.startsWith(folderPath));
    }
    return success;
  }

  /// レイヤーの可視状態を更新
  /// [layerKey] はgpkgName/layerName形式（例: "survey.gpkg/points"）
  Future<bool> setLayerVisibility(
    String folderPath,
    String layerKey,
    bool visible,
  ) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final v = rawMeta.visibility;
    final updatedMeta = rawMeta.copyWith(
      visibility: KMetaVisibility(
        layers: {...v.layers, layerKey: visible},
        geopackages: v.geopackages,
        folders: v.folders,
        images: v.images,
      ),
    );
    return saveMeta(folderPath, updatedMeta);
  }

  /// GeoPackageの可視状態を更新
  Future<bool> setGeoPackageVisibility(
    String folderPath,
    String gpkgName,
    bool visible,
  ) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final v = rawMeta.visibility;
    final updatedMeta = rawMeta.copyWith(
      visibility: KMetaVisibility(
        layers: v.layers,
        geopackages: {...v.geopackages, gpkgName: visible},
        folders: v.folders,
        images: v.images,
      ),
    );
    return saveMeta(folderPath, updatedMeta);
  }

  /// フォルダの可視状態を更新
  Future<bool> setFolderVisibility(
    String folderPath,
    String folderName,
    bool visible,
  ) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final v = rawMeta.visibility;
    final updatedMeta = rawMeta.copyWith(
      visibility: KMetaVisibility(
        layers: v.layers,
        geopackages: v.geopackages,
        folders: {...v.folders, folderName: visible},
        images: v.images,
      ),
    );
    return saveMeta(folderPath, updatedMeta);
  }

  /// 画像の可視状態を更新
  Future<bool> setImageVisibility(
    String folderPath,
    String imageName,
    bool visible,
  ) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final v = rawMeta.visibility;
    final updatedMeta = rawMeta.copyWith(
      visibility: KMetaVisibility(
        layers: v.layers,
        geopackages: v.geopackages,
        folders: v.folders,
        images: {...v.images, imageName: visible},
      ),
    );
    return saveMeta(folderPath, updatedMeta);
  }

  /// レイヤースタイルを更新
  /// [layerKey] はgpkgName/layerName形式（例: "survey.gpkg/points"）
  Future<bool> setLayerStyle(
    String folderPath,
    String layerKey,
    KMetaLayerStyle style,
  ) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final updatedStyles = KMetaStyles(
      defaultStyle: rawMeta.styles.defaultStyle,
      layers: {...rawMeta.styles.layers, layerKey: style},
    );
    final updatedMeta = rawMeta.copyWith(styles: updatedStyles);
    return saveMeta(folderPath, updatedMeta);
  }

  /// デフォルトスタイルを更新
  Future<bool> setDefaultStyle(String folderPath, KMetaLayerStyle style) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final updatedStyles = KMetaStyles(
      defaultStyle: style,
      layers: rawMeta.styles.layers,
    );
    final updatedMeta = rawMeta.copyWith(styles: updatedStyles);
    return saveMeta(folderPath, updatedMeta);
  }

  /// レイアウトの並び順を更新
  Future<bool> setSortOrder(String folderPath, List<String> sortOrder) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final updatedLayout = KMetaLayout(
      sortOrder: sortOrder,
      expanded: rawMeta.layout.expanded,
    );
    final updatedMeta = rawMeta.copyWith(layout: updatedLayout);
    return saveMeta(folderPath, updatedMeta);
  }

  /// 展開状態を更新
  Future<bool> setExpanded(String folderPath, bool expanded) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final updatedLayout = KMetaLayout(
      sortOrder: rawMeta.layout.sortOrder,
      expanded: expanded,
    );
    final updatedMeta = rawMeta.copyWith(layout: updatedLayout);
    return saveMeta(folderPath, updatedMeta);
  }

  /// Google Drive同期情報を更新
  Future<bool> setDriveSync(
    String folderPath, {
    String? driveId,
    String? driveFolderName,
    String? driveUrl,
    bool? isReadOnly,
    DateTime? lastSynced,
    String? driveRevisionId,
    String? deviceId,
    Map<String, KMetaSyncFile>? files,
  }) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    final updatedSync = KMetaSync(
      driveId: driveId ?? rawMeta.sync.driveId,
      driveFolderName: driveFolderName ?? rawMeta.sync.driveFolderName,
      driveUrl: driveUrl ?? rawMeta.sync.driveUrl,
      isReadOnly: isReadOnly ?? rawMeta.sync.isReadOnly,
      lastSynced: lastSynced ?? rawMeta.sync.lastSynced,
      driveRevisionId: driveRevisionId ?? rawMeta.sync.driveRevisionId,
      deviceId: deviceId ?? rawMeta.sync.deviceId,
      files: files ?? rawMeta.sync.files,
    );
    final updatedMeta = rawMeta.copyWith(sync: updatedSync);
    return saveMeta(folderPath, updatedMeta);
  }

  /// Drive連携を解除
  Future<bool> unlinkDrive(String folderPath) async {
    final rawMeta = await getRawMeta(folderPath) ?? KMeta.empty;
    // deviceIdは維持し、Drive関連フィールドのみクリア
    final updatedSync = KMetaSync(deviceId: rawMeta.sync.deviceId);
    final updatedMeta = rawMeta.copyWith(sync: updatedSync);
    return saveMeta(folderPath, updatedMeta);
  }

  /// フォルダが.kmeta.jsonを持っているか確認
  Future<bool> hasMetaFile(String folderPath) async {
    final file = File('$folderPath/$kMetaFileName');
    return file.exists();
  }

  /// 新しい.kmeta.jsonを初期化（存在しない場合のみ）
  Future<KMeta?> initializeMetaIfNeeded(String folderPath) async {
    if (await hasMetaFile(folderPath)) {
      return getRawMeta(folderPath);
    }
    const newMeta = KMeta();
    if (await saveMeta(folderPath, newMeta)) {
      return newMeta;
    }
    return null;
  }
}
