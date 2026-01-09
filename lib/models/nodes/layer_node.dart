// K-MAPS: レイヤノードクラス
// GeoPackage内のレイヤに対応するレイヤツリーノード
// turf_dartのFeatureCollectionオブジェクトをメインデータとして使用

import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';
import 'package:turf/turf.dart' as turf;
import 'layer_tree_node.dart';
import 'geopackage_node.dart';
import 'folder_node.dart';
import 'feature_node.dart';
import '../geopackage/geopackage_file.dart';
import '../geometry_type.dart';
import '../kmeta.dart';
import '../../converters/turf_converter.dart';
import '../../core/node_types.dart';

/// 重複レイヤ名のナンバリング処理ユーティリティ
class LayerNameUtils {
  /// 重複しない新しいレイヤ名を生成する
  /// 例: "道路" が既存の場合 → "道路_2"
  /// "道路_2" も既存の場合 → "道路_3" と番号を増やしていく
  static String generateUniqueLayerName(String baseName, List<String> existingNames) {
    if (!existingNames.contains(baseName)) {
      return baseName;
    }

    int number = 2;
    String candidateName;
    
    do {
      candidateName = '${baseName}_$number';
      number++;
    } while (existingNames.contains(candidateName));
    
    return candidateName;
  }
}

/// レイヤノード（LayerNode）: GeoPackage内のフィーチャテーブル＋FeatureNodeコレクション
/// turf_dartのFeatureをMap管理し、FeatureCollectionを動的生成する（Single Source of Truth）
abstract class LayerNode extends LayerTreeNode {
  /// GeoPackageファイル管理クラスへの参照
  final GeoPackageFile geoPackageFile;

  /// レイヤ名（DBテーブル名）
  final String layerName;

  /// turf_dartのFeatureをrowIdで管理するMap（真のデータソース）
  final Map<int, turf.Feature> _featureMap = {};

  /// 変更の追跡フラグ（将来的なバッチ保存最適化用に予約）
  // ignore: unused_field
  bool _isDirty = false;
  
  /// dispose済みフラグ（null参照対策）
  bool _isDisposed = false;
  
  /// updateChildren実行中フラグ（競合状態防止）
  bool _isUpdatingChildren = false;
  
  /// dispose済みかどうかを取得
  bool get isDisposed => _isDisposed;

  /// 親のGeoPackageNodeを取得
  GeoPackageNode get geoPackageNode {
    LayerTreeNode? current = parent;
    while (current != null) {
      if (current is GeoPackageNode) {
        return current;
      }
      current = current.parent;
    }
    throw StateError('LayerNode must have a GeoPackageNode parent');
  }

  /// 親のFolderNodeを取得
  FolderNode? get folderNode {
    LayerTreeNode? current = parent;
    while (current != null) {
      if (current is FolderNode) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  /// レイヤーの一意キー（gpkgName/layerName形式）
  /// 同一フォルダ内の異なるGeoPackageの同名レイヤーを区別するため
  String get layerKey {
    if (_isDisposed) {
      throw StateError('Cannot access layerKey on disposed LayerNode: $layerName');
    }
    final gpkg = geoPackageNode;
    return '${gpkg.name}/$layerName';
  }

  /// KMetaスタイルキャッシュ
  KMetaLayerStyle? _cachedKmetaStyle;
  bool _kmetaStyleLoaded = false;

  /// このレイヤーのKMetaスタイルを取得（キャッシュ対応）
  /// layerKey（gpkgName/layerName形式）を使用して一意に識別
  Future<KMetaLayerStyle?> getKmetaStyle() async {
    if (_kmetaStyleLoaded) return _cachedKmetaStyle;
    _kmetaStyleLoaded = true;

    final folder = folderNode;
    if (folder == null) return null;

    try {
      final meta = await folder.getMeta();
      final key = layerKey;
      _cachedKmetaStyle = meta.getLayerStyle(key);
      return _cachedKmetaStyle;
    } catch (e) {
      AppLogger.debug('[LayerNode] Error getting KMeta style: $e');
      return null;
    }
  }

  /// KMetaスタイルキャッシュをクリア
  void invalidateKmetaStyleCache() {
    _cachedKmetaStyle = null;
    _kmetaStyleLoaded = false;
  }

  /// キャッシュ済みのKMetaスタイルを同期的に取得（描画用）
  /// キャッシュされていない場合はnullを返す
  KMetaLayerStyle? get cachedKmetaStyle => _cachedKmetaStyle;

  /// KMetaスタイルがキャッシュ済みかどうか
  bool get isKmetaStyleLoaded => _kmetaStyleLoaded;

  /// turf_dartのFeatureCollectionオブジェクトを取得
  /// _featureMapから動的に生成（常に最新の状態を反映）
  turf.FeatureCollection get turfFeatureCollection {
    if (_isDisposed) {
      throw StateError('LayerNode is disposed');
    }
    return TurfConverter.createFeatureCollection(
      _featureMap.values.toList(),
    );
  }
  
  /// rowIdでFeatureを取得（null安全）
  turf.Feature? getFeatureById(int rowId) {
    if (_isDisposed) return null;
    return _featureMap[rowId];
  }
  
  /// Featureを追加（FeatureNodeから呼ばれる、null参照対策含む）
  void addFeatureToMap(int rowId, turf.Feature feature) {
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode is disposed, cannot add feature');
      return;
    }
    _featureMap[rowId] = feature;
    _markDirty();
  }
  
  /// Featureを削除（内部用、null参照対策含む）
  void _removeFeatureFromMap(int rowId) {
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode is disposed, cannot remove feature');
      return;
    }
    _featureMap.remove(rowId);
    _markDirty();
  }
  
  /// Featureの属性を更新（内部用、null参照対策含む）
  bool updateFeatureAttribute(int rowId, String key, dynamic value) {
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode is disposed, cannot update attribute');
      return false;
    }
    final feature = _featureMap[rowId];
    if (feature == null) return false;
    
    feature.properties ??= {};
    feature.properties![key] = value;
    _markDirty();
    return true;
  }

  /// このレイヤに含まれるFeatureNodeリスト（型安全なchildren、dispose済みを除外）
  List<FeatureNode> get features =>
      super.children
          .whereType<FeatureNode>()
          .where((f) => !f.isDisposed)  // dispose済みを除外
          .toList();

  /// position型の座標データを取得（全フィーチャの重心座標リスト）
  List<List<double>> get positions {
    return features.map((feature) => feature.position).toList();
  }

  /// 変更フラグをセット
  void _markDirty() {
    if (_isDisposed) return;
    _isDirty = true;
    // FeatureCollectionは動的生成なのでキャッシュクリア不要
  }

  /// 属性テーブルのカラム名キャッシュ
  List<String>? _cachedColumnNames;
  
  /// PRIMARY KEYスキップ時のカラム名キャッシュ
  List<String>? _cachedColumnNamesWithoutPK;

  /// 属性テーブルのカラム名を取得（キャッシュ機能付き）
  /// [skipPrimaryKey] trueの場合、PRIMARY KEYカラムを除外（属性テーブル表示用）
  Future<List<String>> getAttributeColumnNames({
    bool getAll = false,
    bool skipPrimaryKey = false,
  }) async {
    if (skipPrimaryKey) {
      _cachedColumnNamesWithoutPK ??= await geoPackageFile.getColumnNames(
        layerName,
        getAll: getAll,
        skipPrimaryKey: true,
      );
      return _cachedColumnNamesWithoutPK!;
    }
    _cachedColumnNames ??= await geoPackageFile.getColumnNames(
        layerName,
        getAll: getAll,
      );
    return _cachedColumnNames!;
  }

  /// 属性テーブルのカラム名キャッシュをクリア
  void clearColumnNamesCache() {
    _cachedColumnNames = null;
    _cachedColumnNamesWithoutPK = null;
  }

  /// データベースからFeatureNodeを非同期で読み込み（プライベートメソッド）
  /// サブクラスでoverrideして具体的な実装を提供する
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    return <FeatureNode>[];
  }

  /// FeatureNodeを安全に追加するメソッド
  void addFeature(FeatureNode feature) {
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode is disposed, cannot add feature');
      return;
    }
    super.addChild(feature);
    // _featureMapにも追加（FeatureNodeが持つturfFeatureを登録）
    addFeatureToMap(feature.rowId, feature.turfFeature);
  }

  /// FeatureNodeを安全に削除するメソッド
  void removeFeature(FeatureNode feature) {
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode is disposed, cannot remove feature');
      return;
    }
    super.removeChild(feature);
    // _featureMapからも削除
    _removeFeatureFromMap(feature.rowId);
  }

  /// rowIdに該当するFeatureNodeを検索
  FeatureNode? findFeatureByRowId(int rowId) {
    for (final feature in features) {
      if (feature.rowId == rowId) {
        return feature;
      }
    }
    return null;
  }

  /// childrenから属性値辞書を取得し、属性テーブルの2次元配列を返す
  /// [columns] 取得するカラム名のリスト（nullの場合は全カラム取得）
  /// 戻り値: List<List<dynamic>> - [ヘッダー行, データ行1, データ行2, ...]
  Future<List<List<dynamic>>> getAttributeTableData({
    List<String>? columns,
    bool getAll = false,
  }) async {
    // カラム名を取得
    final columnNames =
        columns ?? await getAttributeColumnNames(getAll: getAll);

    // ヘッダー行
    final table = <List<dynamic>>[columnNames];

    // 各FeatureNodeから属性値を取得してデータ行を作成
    for (final feature in features) {
      final row = <dynamic>[];

      for (final columnName in columnNames) {
        // FeatureNodeのcachedAttributesから値を取得
        final value = await feature.getAttributeValue(columnName);
        row.add(value);
      }

      table.add(row);
    }

    return table;
  }

  /// 属性テーブルデータを辞書形式で取得（UI表示用）
  /// 戻り値: Map<String, List<dynamic>> - カラム名をキーとした列データのマップ
  Future<Map<String, List<dynamic>>> getAttributeTableMap({
    List<String>? columns,
    bool getAll = false,
  }) async {
    // カラム名を取得
    final columnNames =
        columns ?? await getAttributeColumnNames(getAll: getAll);

    // 各カラムの値リストを初期化
    final tableMap = <String, List<dynamic>>{};
    for (final columnName in columnNames) {
      tableMap[columnName] = <dynamic>[];
    }

    // 各FeatureNodeから属性値を取得
    for (final feature in features) {
      for (final columnName in columnNames) {
        final value = await feature.getAttributeValue(columnName);
        tableMap[columnName]!.add(value);
      }
    }

    return tableMap;
  }

  /// コンストラクタ
  LayerNode(
    this.geoPackageFile,
    this.layerName, {
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(layerName, visible: visible, parent: parent, nodeType: NodeType.layer);

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
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode already disposed');
      return;
    }
    
    // 先に子のFeatureNodeを全てdispose（_isDisposed = trueを設定する前に）
    // これにより、子がparent.removeFeature()を呼んだ時に正常に_featureMapから削除される
    await super.dispose();
    
    // 子のdispose完了後にdispose済みフラグを設定
    _isDisposed = true;
    
    // レイヤ（DBテーブル）削除
    await geoPackageFile.removeLayer(layerName);
    
    // Mapをクリア（メモリ解放）
    _featureMap.clear();
  }

  @override
  Future<void> updateChildren() async {
    if (_isDisposed) {
      AppLogger.debug('[WARNING] LayerNode is disposed, cannot update children');
      return;
    }
    
    // 競合状態を防止：既に実行中の場合はスキップ
    if (_isUpdatingChildren) {
      AppLogger.debug('[LayerNode] updateChildren already in progress for $layerName, skipping');
      return;
    }
    
    _isUpdatingChildren = true;
    
    try {
      AppLogger.debug('[LayerNode] updateChildren開始: $layerName');
      
      children.clear();
      _featureMap.clear();  // Mapもクリア
      
      AppLogger.debug('[LayerNode] children.clear()完了: $layerName');
      
      // _loadFeaturesFromDBからFeatureNodeをchildrenに追加
      final featureList = await _loadFeaturesFromDB();
      AppLogger.debug('[LayerNode] DBから読み込み: ${featureList.length}個のフィーチャ ($layerName)');
      
      for (final node in featureList) {
        addChild(node);
        // _featureMapにも追加
        addFeatureToMap(node.rowId, node.turfFeature);
      }
      
      AppLogger.debug('[LayerNode] updateChildren完了: $layerName (${children.length}個)');
      
      // 子ノードの変更があったためキャッシュをクリア
      clearColumnNamesCache();
      _markDirty();
    } finally {
      _isUpdatingChildren = false;
    }
  }

  /// レイヤを別のGeoPackageに移植
  /// [targetGeoPackage] 移植先のGeoPackageNode
  /// [newLayerName] 移植先での新しいレイヤ名（省略時は現在のレイヤ名を使用）
  /// [moveLayer] trueの場合は移植元を削除（移動）、falseの場合は複製
  /// 戻り値: 移植に成功したLayerNode（移植先）
  Future<LayerNode?> migrateToGeoPackage(
    GeoPackageNode targetGeoPackage, {
    String? newLayerName,
    bool moveLayer = true,
  }) async {
    try {
      AppLogger.debug('[LayerNode] レイヤ移植開始: $layerName → ${targetGeoPackage.name}');

      // 移植先のレイヤ名を決定
      final targetLayerName = newLayerName ?? layerName;

      // 移植先に同名のレイヤが存在するかチェック
      final existingLayers =
          await targetGeoPackage.geoPackageFile.getLayerNames();
      if (existingLayers.contains(targetLayerName)) {
        AppLogger.debug('[LayerNode] 移植失敗: レイヤ名 "$targetLayerName" は既に存在します');
        return null;
      }

      // 移植元のジオメトリタイプを取得
      final geometryType = await geoPackageFile.getGeometryType(layerName);
      if (geometryType == null) {
        AppLogger.debug('[LayerNode] 移植失敗: ジオメトリタイプを取得できません');
        return null;
      }

      // 移植先に新しいレイヤを作成
      await targetGeoPackage.geoPackageFile.addLayer(
        targetLayerName,
        geometryType,
      );
      AppLogger.debug('[LayerNode] 移植先レイヤ作成完了: $targetLayerName (${geometryType.value})');

      // 移植元の属性スキーマを取得して移植先に適用
      await _migrateAttributeSchema(targetGeoPackage, targetLayerName);

      // すべてのフィーチャデータを移植
      final migratedFeatureCount = await _migrateFeatureData(
        targetGeoPackage,
        targetLayerName,
        geometryType,
      );

      AppLogger.debug('[LayerNode] フィーチャデータ移植完了: $migratedFeatureCount個のフィーチャ');

      // 移植先のレイヤツリーを更新
      AppLogger.debug('[LayerNode] 移植先レイヤツリー更新開始');
      await targetGeoPackage.updateChildren();

      // 移植されたレイヤノードを取得
      AppLogger.debug(
        '[LayerNode] 移植先の子ノード確認: ${targetGeoPackage.children.map((c) => c.name).toList()}',
      );
      final migratedLayerNode =
          targetGeoPackage.children
              .whereType<LayerNode>()
              .where((layer) => layer.layerName == targetLayerName)
              .firstOrNull;

      if (migratedLayerNode == null) {
        AppLogger.debug('[LayerNode] 移植失敗: 移植先レイヤノードが見つかりません');
        AppLogger.debug('[LayerNode] 期待されるレイヤ名: $targetLayerName');
        AppLogger.debug(
          '[LayerNode] 利用可能なレイヤ: ${targetGeoPackage.children.whereType<LayerNode>().map((l) => l.layerName).toList()}',
        );
        return null;
      }

      // 移植されたレイヤのフィーチャを読み込み
      AppLogger.debug('[LayerNode] 移植されたレイヤのフィーチャ読み込み開始');
      await migratedLayerNode.updateChildren();
      AppLogger.debug(
        '[LayerNode] 移植されたレイヤのフィーチャ数: ${migratedLayerNode.features.length}',
      );

      // 移植元を削除（移動の場合）
      if (moveLayer) {
        await _removeSelfFromParent();
        AppLogger.debug('[LayerNode] 移植元レイヤ削除完了');
      }

      AppLogger.debug('[LayerNode] レイヤ移植成功: $migratedFeatureCount個のフィーチャを移植');
      return migratedLayerNode;
    } catch (e, stack) {
      AppLogger.debug('[LayerNode] レイヤ移植エラー: $e');
      AppLogger.debug('スタックトレース: $stack');
      return null;
    }
  }

  /// 属性スキーマを移植先に適用
  Future<void> _migrateAttributeSchema(
    GeoPackageNode targetGeoPackage,
    String targetLayerName,
  ) async {
    try {
      // 移植元の属性カラム情報を取得
      final sourceColumnInfo = await geoPackageFile.getAttributeColumnInfo(
        layerName,
        includeBuiltIn: false, // 組み込みカラムは除外
      );

      if (sourceColumnInfo.isEmpty) {
        AppLogger.debug('[LayerNode] 移植する属性カラムがありません');
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
      await targetGeoPackage.geoPackageFile.addAttributeColumns(
        targetLayerName,
        attributeSchema,
      );

      // 移植先のカラムを確認し、不足カラムがあれば警告
      final targetColumns = await targetGeoPackage.geoPackageFile.getTableColumns(targetLayerName);
      final targetColumnSet = targetColumns.map((c) => c.toLowerCase()).toSet();
      final missingColumns = attributeSchema.keys
          .where((c) => !targetColumnSet.contains(c.toLowerCase()))
          .toList();

      if (missingColumns.isNotEmpty) {
        AppLogger.debug('[LayerNode] 追加されなかったカラム: $missingColumns');
      }

      AppLogger.debug('[LayerNode] 属性スキーマ移植完了: ${attributeSchema.length}個中${targetColumns.length - 2}個のカラム追加');
    } catch (e) {
      AppLogger.debug('[LayerNode] 属性スキーマ移植エラー: $e');
      // エラーが発生しても継続（基本的な属性は移植可能）
    }
  }

  /// フィーチャデータを移植先に書き込み
  Future<int> _migrateFeatureData(
    GeoPackageNode targetGeoPackage,
    String targetLayerName,
    GeometryType geometryType,
  ) async {
    try {
      // 移植元のすべてのフィーチャを取得
      final sourceFeatures = await geoPackageFile.getFeatures(layerName);

      if (sourceFeatures.isEmpty) {
        AppLogger.debug('[LayerNode] 移植するフィーチャがありません');
        return 0;
      }

      AppLogger.debug('[LayerNode] 移植対象フィーチャ数: ${sourceFeatures.length}個');

      // バッチ処理でフィーチャを移植
      final batchData = <Map<String, dynamic>>[];
      const batchSize = 1000; // 1000個ずつバッチ処理
      int migratedCount = 0;
      int skippedCount = 0;

      for (final sourceFeature in sourceFeatures) {
        final featureId = sourceFeature['id'] as int?;
        if (featureId == null) {
          AppLogger.debug('[LayerNode] フィーチャIDがnull: $sourceFeature');
          skippedCount++;
          continue;
        }

        // 完全なフィーチャデータを取得（geometry変換済み）
        final completeFeature = await geoPackageFile.getFeature(
          layerName,
          featureId,
        );
        if (completeFeature == null) {
          AppLogger.debug('[LayerNode] フィーチャ取得失敗 ID=$featureId');
          skippedCount++;
          continue;
        }

        AppLogger.debug('[LayerNode] フィーチャ詳細 ID=$featureId: ${completeFeature.keys}');

        // ジオメトリデータを取得
        final geometryData = _extractGeometryData(
          completeFeature,
          geometryType,
        );
        if (geometryData == null) {
          AppLogger.debug('[LayerNode] ジオメトリ抽出失敗 ID=$featureId, type=$geometryType');
          AppLogger.debug('[LayerNode] フィーチャ内容: $completeFeature');
          skippedCount++;
          continue;
        }

        AppLogger.debug('[LayerNode] 抽出されたジオメトリ: $geometryData');

        // 属性データを取得（idとgeomを除く）
        final attributes = Map<String, dynamic>.from(completeFeature);
        attributes.remove('id');
        attributes.remove('geom');
        attributes.remove('geometry'); // 変換済みgeometryも除外
        attributes.remove('points'); // 変換済みpointsも除外
        attributes.remove('lines'); // 変換済みlinesも除外
        attributes.remove('polygons'); // 変換済みpolygonsも除外

        AppLogger.debug('[LayerNode] 抽出された属性: $attributes');

        // バッチデータに追加
        final batchItem = {...geometryData, ...attributes};
        batchData.add(batchItem);
        AppLogger.debug('[LayerNode] バッチアイテム: $batchItem');

        // バッチサイズに達したら処理
        if (batchData.length >= batchSize) {
          final processedCount = await _processMigrationBatch(
            targetGeoPackage,
            targetLayerName,
            geometryType,
            batchData,
          );
          migratedCount += processedCount;
          batchData.clear();

          if (migratedCount % 5000 == 0) {
            AppLogger.debug('[LayerNode] 移植進捗: $migratedCount個完了');
          }
        }
      }

      // 残りのバッチを処理
      if (batchData.isNotEmpty) {
        final processedCount = await _processMigrationBatch(
          targetGeoPackage,
          targetLayerName,
          geometryType,
          batchData,
        );
        migratedCount += processedCount;
      }

      AppLogger.debug('[LayerNode] 移植完了: $migratedCount個成功, $skippedCount個スキップ');
      return migratedCount;
    } catch (e, stack) {
      AppLogger.debug('[LayerNode] フィーチャデータ移植エラー: $e');
      AppLogger.debug('[LayerNode] スタックトレース: $stack');
      return 0;
    }
  }

  /// ジオメトリデータを抽出
  Map<String, dynamic>? _extractGeometryData(
    Map<String, dynamic> feature,
    GeometryType geometryType,
  ) {
    try {
      AppLogger.debug(
        '[LayerNode] ジオメトリ抽出開始: type=$geometryType, 利用可能なキー=${feature.keys}',
      );

      // getFeatureメソッドは'geometry'キーにデータを格納する
      final geometryData = feature['geometry'];
      AppLogger.debug(
        '[LayerNode] geometryデータ: $geometryData (型: ${geometryData.runtimeType})',
      );

      switch (geometryType) {
        case GeometryType.point:
          // ポイントの場合：[LatLng] の配列で返される
          if (geometryData is List<LatLng> && geometryData.isNotEmpty) {
            AppLogger.debug('[LayerNode] ポイント抽出成功: ${geometryData.first}');
            return {'point': geometryData.first};
          }
          // 旧形式との互換性
          final points = feature['points'] as List<LatLng>?;
          if (points != null && points.isNotEmpty) {
            AppLogger.debug('[LayerNode] ポイント抽出成功（旧形式）: ${points.first}');
            return {'point': points.first};
          }
          break;

        case GeometryType.linestring:
          // ラインの場合：List<LatLng> で返される
          if (geometryData is List<LatLng> && geometryData.isNotEmpty) {
            AppLogger.debug('[LayerNode] ライン抽出成功: ${geometryData.length}個の頂点');
            return {'line': geometryData};
          }
          // 旧形式との互換性
          final lines = feature['lines'] as List<LatLng>?;
          if (lines != null && lines.isNotEmpty) {
            AppLogger.debug('[LayerNode] ライン抽出成功（旧形式）: ${lines.length}個の頂点');
            return {'line': lines};
          }
          break;

        case GeometryType.polygon:
          // ポリゴンの場合：List<List<LatLng>> で返される
          if (geometryData is List<List<LatLng>> && geometryData.isNotEmpty) {
            AppLogger.debug('[LayerNode] ポリゴン抽出成功: ${geometryData.length}個のリング');
            return {'rings': geometryData};
          }
          // 旧形式との互換性
          final polygons = feature['polygons'] as List<List<LatLng>>?;
          if (polygons != null && polygons.isNotEmpty) {
            AppLogger.debug('[LayerNode] ポリゴン抽出成功（旧形式）: ${polygons.length}個のリング');
            return {'rings': polygons};
          }
          break;
      }

      AppLogger.debug('[LayerNode] ジオメトリデータの抽出に失敗');
      return null;
    } catch (e, stack) {
      AppLogger.debug('[LayerNode] ジオメトリデータ抽出エラー: $e');
      AppLogger.debug('[LayerNode] スタックトレース: $stack');
      return null;
    }
  }

  /// バッチデータを移植先に書き込み
  Future<int> _processMigrationBatch(
    GeoPackageNode targetGeoPackage,
    String targetLayerName,
    GeometryType geometryType,
    List<Map<String, dynamic>> batchData,
  ) async {
    try {
      AppLogger.debug(
        '[LayerNode] バッチ処理開始: ${batchData.length}個のフィーチャ, タイプ=$geometryType',
      );

      List<int> insertedIds = [];

      switch (geometryType) {
        case GeometryType.point:
          AppLogger.debug('[LayerNode] ポイントバッチ処理実行');
          insertedIds = await targetGeoPackage.geoPackageFile.addPointsBatch(
            targetLayerName,
            batchData,
          );
          break;

        case GeometryType.linestring:
          AppLogger.debug('[LayerNode] ラインバッチ処理実行');
          insertedIds = await targetGeoPackage.geoPackageFile.addLinesBatch(
            targetLayerName,
            batchData,
          );
          break;

        case GeometryType.polygon:
          AppLogger.debug('[LayerNode] ポリゴンバッチ処理実行');
          insertedIds = await targetGeoPackage.geoPackageFile.addPolygonsBatch(
            targetLayerName,
            batchData,
          );
          break;
      }

      AppLogger.debug('[LayerNode] バッチ処理完了: ${insertedIds.length}個挿入');
      AppLogger.debug('[LayerNode] 挿入されたID: $insertedIds');

      return insertedIds.length;
    } catch (e, stack) {
      AppLogger.debug('[LayerNode] バッチ処理エラー: $e');
      AppLogger.debug('[LayerNode] バッチデータサンプル: ${batchData.take(3).toList()}');
      AppLogger.debug('[LayerNode] スタックトレース: $stack');
      rethrow;
    }
  }

  /// 自分自身を親から削除
  Future<void> _removeSelfFromParent() async {
    try {
      // 親のGeoPackageNodeを取得
      final parentGeoPackage = geoPackageNode;

      // レイヤを削除
      await dispose();

      // 親のレイヤツリーを更新
      await parentGeoPackage.updateChildren();
    } catch (e) {
      AppLogger.debug('[LayerNode] 自己削除エラー: $e');
      rethrow;
    }
  }
}

/// ポイントレイヤノード
class PointLayerNode extends LayerNode {
  PointLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    final rawFeatures = await geoPackageFile.getFeatures(layerName);
    final features = <FeatureNode>[];

    for (final rawRow in rawFeatures) {
      final rowId = rawRow['id'] as int?;
      if (rowId == null) continue;

      // getFeatureを使用してgeometry変換済みのrowデータを取得
      final row = await geoPackageFile.getFeature(layerName, rowId);
      if (row == null || row['geometry'] == null) continue;

      final featureNode = PointFeatureNode(row, this);
      features.add(featureNode);
    }

    return features;
  }
  
  // UI関連（baseIcon, baseIconColor）はNodePresenterに移動

  /// 指定したGeoPackageNodeの下に新しいPointレイヤを作成し、PointLayerNodeインスタンスを返す
  /// 重複名がある場合は自動的にナンバリング（例: "道路_2", "道路_3"）する
  static Future<PointLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    
    // 重複しない名前を生成
    final uniqueName = LayerNameUtils.generateUniqueLayerName(name, existingLayers);
    
    await gpkgFile.addLayer(uniqueName, GeometryType.point);
    final node = PointLayerNode(gpkgFile, uniqueName, parent: parent);
    parent.addChild(node);
    return node;
  }
}

/// ラインレイヤノード
class LineLayerNode extends LayerNode {
  LineLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    final rawFeatures = await geoPackageFile.getFeatures(layerName);
    final features = <FeatureNode>[];

    for (final rawRow in rawFeatures) {
      final rowId = rawRow['id'] as int?;
      if (rowId == null) continue;

      // getFeatureを使用してgeometry変換済みのrowデータを取得
      final row = await geoPackageFile.getFeature(layerName, rowId);
      if (row == null || row['geometry'] == null) continue;

      final featureNode = LineFeatureNode(row, this);
      features.add(featureNode);
    }

    return features;
  }
  
  // UI関連（baseIcon, baseIconColor）はNodePresenterに移動

  /// 指定したGeoPackageNodeの下に新しいLineレイヤを作成し、LineLayerNodeインスタンスを返す
  /// 重複名がある場合は自動的にナンバリング（例: "道路_2", "道路_3"）する
  static Future<LineLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    
    // 重複しない名前を生成
    final uniqueName = LayerNameUtils.generateUniqueLayerName(name, existingLayers);
    
    await gpkgFile.addLayer(uniqueName, GeometryType.linestring);
    final node = LineLayerNode(gpkgFile, uniqueName, parent: parent);
    parent.addChild(node);
    return node;
  }
}

/// ポリゴンレイヤノード
class PolygonLayerNode extends LayerNode {
  PolygonLayerNode(super.file, super.name, {super.visible, super.parent});

  @override
  Future<List<FeatureNode>> _loadFeaturesFromDB() async {
    final rawFeatures = await geoPackageFile.getFeatures(layerName);
    final features = <FeatureNode>[];

    for (final rawRow in rawFeatures) {
      final rowId = rawRow['id'] as int?;
      if (rowId == null) continue;

      // getFeatureを使用してgeometry変換済みのrowデータを取得
      final row = await geoPackageFile.getFeature(layerName, rowId);
      if (row == null || row['geometry'] == null) continue;

      final featureNode = PolygonFeatureNode(row, this);
      features.add(featureNode);
    }

    return features;
  }
  
  // UI関連（baseIcon, baseIconColor）はNodePresenterに移動

  /// 指定したGeoPackageNodeの下に新しいPolygonレイヤを作成し、PolygonLayerNodeインスタンスを返す
  /// 重複名がある場合は自動的にナンバリング（例: "道路_2", "道路_3"）する
  static Future<PolygonLayerNode?> createIn(
    LayerTreeNode parent,
    String name,
  ) async {
    if (parent is! GeoPackageNode) return null;
    final gpkgFile = parent.geoPackageFile;
    final existingLayers = await gpkgFile.getLayerNames();
    
    // 重複しない名前を生成
    final uniqueName = LayerNameUtils.generateUniqueLayerName(name, existingLayers);
    
    await gpkgFile.addLayer(uniqueName, GeometryType.polygon);
    final node = PolygonLayerNode(gpkgFile, uniqueName, parent: parent);
    parent.addChild(node);
    return node;
  }
}

