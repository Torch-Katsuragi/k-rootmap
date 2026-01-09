// K-MAPS: レイヤ移植サービス
// LayerNodeから移植処理を分離し、単一責任原則に従う
// GeoPackage間のレイヤ・フィーチャの移動/複製を担当

import 'package:latlong2/latlong.dart';
import '../utils/app_logger.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/geopackage/geopackage_file.dart';
import '../models/geometry_type.dart';

/// レイヤ移植結果
class LayerMigrationResult {
  /// 移植成功かどうか
  final bool success;
  
  /// 移植されたレイヤノード（成功時のみ）
  final LayerNode? migratedLayer;
  
  /// 移植されたフィーチャ数
  final int featureCount;
  
  /// エラーメッセージ（失敗時のみ）
  final String? errorMessage;
  
  /// スキップされたフィーチャ数
  final int skippedCount;

  LayerMigrationResult._({
    required this.success,
    this.migratedLayer,
    this.featureCount = 0,
    this.errorMessage,
    this.skippedCount = 0,
  });

  factory LayerMigrationResult.success({
    required LayerNode migratedLayer,
    required int featureCount,
    int skippedCount = 0,
  }) {
    return LayerMigrationResult._(
      success: true,
      migratedLayer: migratedLayer,
      featureCount: featureCount,
      skippedCount: skippedCount,
    );
  }

  factory LayerMigrationResult.failure(String message) {
    return LayerMigrationResult._(
      success: false,
      errorMessage: message,
    );
  }
}

/// レイヤ移植サービス
/// 
/// GeoPackage間でレイヤを移動/複製する機能を提供
/// LayerNodeからの責務分離により、テスト容易性と再利用性を向上
class LayerMigrationService {
  LayerMigrationService._();
  
  /// シングルトンインスタンス
  static final LayerMigrationService instance = LayerMigrationService._();

  /// レイヤを別のGeoPackageに移植
  /// 
  /// [sourceLayer] 移植元のレイヤノード
  /// [targetGeoPackage] 移植先のGeoPackageNode
  /// [newLayerName] 移植先での新しいレイヤ名（省略時は現在のレイヤ名を使用）
  /// [moveLayer] trueの場合は移植元を削除（移動）、falseの場合は複製
  Future<LayerMigrationResult> migrateLayer({
    required LayerNode sourceLayer,
    required GeoPackageNode targetGeoPackage,
    String? newLayerName,
    bool moveLayer = true,
  }) async {
    try {
      AppLogger.debug(
        '[LayerMigrationService] 移植開始: ${sourceLayer.layerName} → ${targetGeoPackage.name}',
      );

      // 移植先のレイヤ名を決定
      final targetLayerName = newLayerName ?? sourceLayer.layerName;

      // 移植先に同名のレイヤが存在するかチェック
      final existingLayers =
          await targetGeoPackage.geoPackageFile.getLayerNames();
      if (existingLayers.contains(targetLayerName)) {
        return LayerMigrationResult.failure(
          'レイヤ名 "$targetLayerName" は既に存在します',
        );
      }

      // 移植元のジオメトリタイプを取得
      final geometryType = await sourceLayer.geoPackageFile.getGeometryType(
        sourceLayer.layerName,
      );
      if (geometryType == null) {
        return LayerMigrationResult.failure('ジオメトリタイプを取得できません');
      }

      // 移植先に新しいレイヤを作成
      await targetGeoPackage.geoPackageFile.addLayer(
        targetLayerName,
        geometryType,
      );
      AppLogger.debug(
        '[LayerMigrationService] 移植先レイヤ作成完了: $targetLayerName (${geometryType.value})',
      );

      // 属性スキーマを移植
      await _migrateAttributeSchema(
        sourceLayer.geoPackageFile,
        sourceLayer.layerName,
        targetGeoPackage.geoPackageFile,
        targetLayerName,
      );

      // フィーチャデータを移植
      final migrationStats = await _migrateFeatureData(
        sourceLayer.geoPackageFile,
        sourceLayer.layerName,
        targetGeoPackage.geoPackageFile,
        targetLayerName,
        geometryType,
      );

      AppLogger.debug(
        '[LayerMigrationService] フィーチャ移植完了: ${migrationStats.successCount}個成功, ${migrationStats.skippedCount}個スキップ',
      );

      // 移植先のレイヤツリーを更新
      await targetGeoPackage.updateChildren();

      // 移植されたレイヤノードを取得
      final migratedLayerNode = targetGeoPackage.children
          .whereType<LayerNode>()
          .where((layer) => layer.layerName == targetLayerName)
          .firstOrNull;

      if (migratedLayerNode == null) {
        return LayerMigrationResult.failure('移植先レイヤノードが見つかりません');
      }

      // 移植されたレイヤのフィーチャを読み込み
      await migratedLayerNode.updateChildren();

      // 移植元を削除（移動の場合）
      if (moveLayer) {
        await sourceLayer.dispose();
        await sourceLayer.geoPackageNode.updateChildren();
        AppLogger.debug('[LayerMigrationService] 移植元レイヤ削除完了');
      }

      AppLogger.debug(
        '[LayerMigrationService] 移植成功: ${migrationStats.successCount}個のフィーチャを移植',
      );

      return LayerMigrationResult.success(
        migratedLayer: migratedLayerNode,
        featureCount: migrationStats.successCount,
        skippedCount: migrationStats.skippedCount,
      );
    } catch (e, stack) {
      AppLogger.debug('[LayerMigrationService] 移植エラー: $e');
      AppLogger.debug('[LayerMigrationService] スタックトレース: $stack');
      return LayerMigrationResult.failure(e.toString());
    }
  }

  /// 属性スキーマを移植
  Future<void> _migrateAttributeSchema(
    GeoPackageFile sourceFile,
    String sourceLayerName,
    GeoPackageFile targetFile,
    String targetLayerName,
  ) async {
    try {
      // 移植元の属性カラム情報を取得
      final sourceColumnInfo = await sourceFile.getAttributeColumnInfo(
        sourceLayerName,
        includeBuiltIn: false,
      );

      if (sourceColumnInfo.isEmpty) {
        AppLogger.debug('[LayerMigrationService] 移植する属性カラムがありません');
        return;
      }

      // 属性スキーマを作成
      final attributeSchema = <String, String>{};
      for (final columnInfo in sourceColumnInfo) {
        final columnName = columnInfo['name'] as String;
        final columnType = columnInfo['type'] as String;
        attributeSchema[columnName] = columnType;
      }

      // 移植先に属性カラムを追加
      await targetFile.addAttributeColumns(targetLayerName, attributeSchema);

      AppLogger.debug(
        '[LayerMigrationService] 属性スキーマ移植完了: ${attributeSchema.length}カラム',
      );
    } catch (e) {
      AppLogger.debug('[LayerMigrationService] 属性スキーマ移植エラー: $e');
      // エラーが発生しても継続
    }
  }

  /// フィーチャデータを移植
  Future<_MigrationStats> _migrateFeatureData(
    GeoPackageFile sourceFile,
    String sourceLayerName,
    GeoPackageFile targetFile,
    String targetLayerName,
    GeometryType geometryType,
  ) async {
    // 移植元のすべてのフィーチャを取得
    final sourceFeatures = await sourceFile.getFeatures(sourceLayerName);

    if (sourceFeatures.isEmpty) {
      AppLogger.debug('[LayerMigrationService] 移植するフィーチャがありません');
      return _MigrationStats(successCount: 0, skippedCount: 0);
    }

    AppLogger.debug(
      '[LayerMigrationService] 移植対象フィーチャ数: ${sourceFeatures.length}個',
    );

    // バッチ処理でフィーチャを移植
    final batchData = <Map<String, dynamic>>[];
    const batchSize = 1000;
    int migratedCount = 0;
    int skippedCount = 0;

    for (final sourceFeature in sourceFeatures) {
      final featureId = sourceFeature['id'] as int?;
      if (featureId == null) {
        skippedCount++;
        continue;
      }

      // 完全なフィーチャデータを取得
      final completeFeature = await sourceFile.getFeature(
        sourceLayerName,
        featureId,
      );
      if (completeFeature == null) {
        skippedCount++;
        continue;
      }

      // ジオメトリデータを抽出
      final geometryData = _extractGeometryData(completeFeature, geometryType);
      if (geometryData == null) {
        skippedCount++;
        continue;
      }

      // 属性データを取得
      final attributes = Map<String, dynamic>.from(completeFeature);
      _removeBuiltInColumns(attributes);

      // バッチデータに追加
      batchData.add({...geometryData, ...attributes});

      // バッチサイズに達したら処理
      if (batchData.length >= batchSize) {
        final processed = await _processBatch(
          targetFile,
          targetLayerName,
          geometryType,
          batchData,
        );
        migratedCount += processed;
        batchData.clear();
      }
    }

    // 残りのバッチを処理
    if (batchData.isNotEmpty) {
      final processed = await _processBatch(
        targetFile,
        targetLayerName,
        geometryType,
        batchData,
      );
      migratedCount += processed;
    }

    return _MigrationStats(
      successCount: migratedCount,
      skippedCount: skippedCount,
    );
  }

  /// ジオメトリデータを抽出
  Map<String, dynamic>? _extractGeometryData(
    Map<String, dynamic> feature,
    GeometryType geometryType,
  ) {
    final geometryData = feature['geometry'];

    switch (geometryType) {
      case GeometryType.point:
        if (geometryData is List<LatLng> && geometryData.isNotEmpty) {
          return {'point': geometryData.first};
        }
        final points = feature['points'] as List<LatLng>?;
        if (points != null && points.isNotEmpty) {
          return {'point': points.first};
        }
        break;

      case GeometryType.linestring:
        if (geometryData is List<LatLng> && geometryData.isNotEmpty) {
          return {'line': geometryData};
        }
        final lines = feature['lines'] as List<LatLng>?;
        if (lines != null && lines.isNotEmpty) {
          return {'line': lines};
        }
        break;

      case GeometryType.polygon:
        if (geometryData is List<List<LatLng>> && geometryData.isNotEmpty) {
          return {'rings': geometryData};
        }
        final polygons = feature['polygons'] as List<List<LatLng>>?;
        if (polygons != null && polygons.isNotEmpty) {
          return {'rings': polygons};
        }
        break;
    }

    return null;
  }

  /// 組み込みカラムを削除
  void _removeBuiltInColumns(Map<String, dynamic> attributes) {
    attributes.remove('id');
    attributes.remove('geom');
    attributes.remove('geometry');
    attributes.remove('points');
    attributes.remove('lines');
    attributes.remove('polygons');
  }

  /// バッチデータを処理
  Future<int> _processBatch(
    GeoPackageFile targetFile,
    String targetLayerName,
    GeometryType geometryType,
    List<Map<String, dynamic>> batchData,
  ) async {
    List<int> insertedIds = [];

    switch (geometryType) {
      case GeometryType.point:
        insertedIds = await targetFile.addPointsBatch(
          targetLayerName,
          batchData,
        );
        break;

      case GeometryType.linestring:
        insertedIds = await targetFile.addLinesBatch(
          targetLayerName,
          batchData,
        );
        break;

      case GeometryType.polygon:
        insertedIds = await targetFile.addPolygonsBatch(
          targetLayerName,
          batchData,
        );
        break;
    }

    return insertedIds.length;
  }
}

/// 移植統計情報
class _MigrationStats {
  final int successCount;
  final int skippedCount;

  _MigrationStats({required this.successCount, required this.skippedCount});
}
