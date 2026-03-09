/// 背景地図管理サービス
/// 背景地図の選択、切り替え、オフラインキャッシュ機能を提供
library;
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:image/image.dart' as img;
import '../models/basemap_provider.dart';
import 'tile_cache_geopackage.dart';

/// Isolateで実行するための画像処理関数（トップレベル関数）
Future<Uint8List?> _processTileExtraction(Map<String, dynamic> params) async {
  try {
    final parentTileData = params['parentTileData'] as Uint8List;
    final targetZ = params['targetZ'] as int;
    final targetX = params['targetX'] as int;
    final targetY = params['targetY'] as int;
    final parentZ = params['parentZ'] as int;
    final parentX = params['parentX'] as int;
    final parentY = params['parentY'] as int;

    // 親タイル画像をデコード
    final parentImage = img.decodeImage(parentTileData);
    if (parentImage == null) {
      return null;
    }

    // ズーム差を計算
    final zoomDiff = targetZ - parentZ;
    final scale = 1 << zoomDiff; // 2^(zoom差)

    // 親タイル内での相対座標を計算
    final relativeX = targetX - parentX * scale;
    final relativeY = targetY - parentY * scale;

    // 切り出し範囲を計算（親タイルのサイズを基準）
    final parentTileSize = parentImage.width;
    final cropSize = parentTileSize ~/ scale;
    final cropX = relativeX * cropSize;
    final cropY = relativeY * cropSize;

    // 範囲チェック
    if (cropX < 0 ||
        cropY < 0 ||
        cropX + cropSize > parentTileSize ||
        cropY + cropSize > parentTileSize) {
      // 範囲外の場合は親タイル全体をスケールして返す
      final resizedImage = img.copyResize(
        parentImage,
        width: 256,
        height: 256,
      );
      return Uint8List.fromList(img.encodePng(resizedImage));
    }

    // 指定領域を切り出し
    final croppedImage = img.copyCrop(
      parentImage,
      x: cropX,
      y: cropY,
      width: cropSize,
      height: cropSize,
    );

    // 256x256にリサイズ
    final resizedImage = img.copyResize(
      croppedImage,
      width: 256,
      height: 256,
      interpolation: img.Interpolation.linear,
    );

    // PNG形式でエンコード
    return Uint8List.fromList(img.encodePng(resizedImage));
  } catch (e) {
    AppLogger.debug('[TILE-ISO] ❌ Scaling error: $e');
    return null;
  }
}

/// 背景地図管理サービス
class BaseMapService extends ChangeNotifier {
  static final BaseMapService _instance = BaseMapService._internal();
  factory BaseMapService() => _instance;
  BaseMapService._internal();

  /// 透明なタイル（256x256 PNG）
  static final Uint8List transparentTile = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
    0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x01, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x08, 0x04, 0x00, 0x00, 0x00, 0x5C,
    0x72, 0xA8, 0x66, 0x00, 0x00, 0x00, 0x0B, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0xF8, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x01, 0x02, 0x9A, 0x65, 0x1C, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  BaseMapProvider _currentProvider = BaseMapProvider.defaultProvider;
  bool _isOfflineMode = false;
  String? _cacheDirectory;
  TileCacheGeoPackage? _tileCacheDb;
  
  // ネットワーク状態監視
  final Connectivity _connectivity = Connectivity();
  bool _isNetworkAvailable = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // キャンセルトークン用
  bool _isDownloading = false;
  bool _cancelDownload = false;

  /// 現在の背景地図プロバイダー
  BaseMapProvider get currentProvider => _currentProvider;

  /// オフラインモードかどうか
  bool get isOfflineMode => _isOfflineMode;

  /// ダウンロード中かどうか
  bool get isDownloading => _isDownloading;

  /// 利用可能なプロバイダー一覧
  List<BaseMapProvider> get availableProviders =>
      BaseMapProvider.availableProviders;

  /// サービス初期化
  Future<void> initialize() async {
    try {
      // キャッシュディレクトリの設定
      await _initializeCacheDirectory();

      // GeoPackageキャッシュの初期化
      await _initializeTileCacheDatabase();

      // 設定の読み込み
      await _loadSettings();

      // ネットワーク状態の監視開始
      _initConnectivity();
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Init error: $e');
      _currentProvider = BaseMapProvider.defaultProvider;
    }
  }

  /// ネットワーク状態の監視初期化
  void _initConnectivity() async {
    try {
      final result = await _connectivity.checkConnectivity();
      _updateConnectionStatus(result);
      
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(_updateConnectionStatus);
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Connectivity init error: $e');
    }
  }

  /// 接続状態更新
  void _updateConnectionStatus(List<ConnectivityResult> result) {
    final hasConnection = !result.contains(ConnectivityResult.none);
    if (_isNetworkAvailable != hasConnection) {
      _isNetworkAvailable = hasConnection;
      AppLogger.debug('[BaseMapService] Network status changed: ${_isNetworkAvailable ? "Online" : "Offline (No Interface)"}');
      notifyListeners();
    }
  }

  /// キャッシュディレクトリの初期化
  Future<void> _initializeCacheDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = path.join(appDir.path, 'k_maps_tiles');

      final cacheDir = Directory(_cacheDirectory!);
      if (!cacheDir.existsSync()) {
        cacheDir.createSync(recursive: true);
      }
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Cache dir error: $e');
      rethrow;
    }
  }

  /// タイルキャッシュデータベースの初期化
  Future<void> _initializeTileCacheDatabase() async {
    try {
      _tileCacheDb = TileCacheGeoPackage();
      await _tileCacheDb!.initialize(_cacheDirectory!);
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ TileDB init error: $e');
      rethrow;
    }
  }

  /// 設定の読み込み
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final providerId = prefs.getString('basemap_provider_id');
      _isOfflineMode = prefs.getBool('basemap_offline_mode') ?? false;

      if (providerId != null) {
        final provider = BaseMapProvider.getProviderById(providerId);
        if (provider != null) {
          _currentProvider = provider;
        }
      }
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Settings load error: $e');
    }
  }

  /// 設定の保存
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('basemap_provider_id', _currentProvider.id);
      await prefs.setBool('basemap_offline_mode', _isOfflineMode);
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Settings save error: $e');
    }
  }

  /// 背景地図プロバイダーを変更
  Future<void> setProvider(BaseMapProvider provider) async {
    if (_currentProvider != provider) {
      _currentProvider = provider;
      await _saveSettings();
      notifyListeners();
    }
  }

  /// オフラインモードの切り替え
  Future<void> setOfflineMode(bool offline) async {
    if (_isOfflineMode != offline) {
      _isOfflineMode = offline;
      await _saveSettings();
      notifyListeners();
    }
  }

  /// タイルをキャッシュに保存
  Future<void> _cacheTile(
    String providerId,
    int z,
    int x,
    int y,
    Uint8List data,
  ) async {
    if (_tileCacheDb == null) return;
    
    try {
      await _tileCacheDb!.saveTile(
        providerId: providerId,
        z: z,
        x: x,
        y: y,
        data: data,
      );
    } catch (e) {
      AppLogger.debug('[TILE] ❌ Cache save error: $e');
    }
  }

  /// キャッシュからタイルを取得
  Future<Uint8List?> _getCachedTile(
    String providerId,
    int z,
    int x,
    int y, {
    bool allowCrossPlatformCache = false,
  }) async {
    if (_tileCacheDb == null) return null;
    
    try {
      // 指定プロバイダーのキャッシュを取得
      final data = await _tileCacheDb!.getTile(
        providerId: providerId,
        z: z,
        x: x,
        y: y,
      );
      
      if (data != null) {
        // データサイズチェック
        if (data.length < 100) {
          AppLogger.debug('[TILE] ⚠️ Corrupted cache (too small)');
          return null;
        }
        
        // PNGヘッダーチェック
        if (data.length >= 8) {
          // ヘッダーチェックは行わず、データサイズのみで簡易チェックとする
          // サーバーによっては異なるフォーマット（WebPなど）を返す可能性や、
          // ヘッダーが微妙に異なる場合も考慮して、厳密なチェックは廃止する。
          // decodeImageで失敗すれば最終的に弾かれるため問題ない。
        }
        
        return data;
      }
      
      return null;
    } catch (e) {
      AppLogger.debug('[TILE] ❌ Cache read error: $e');
      return null;
    }
  }

  /// タイルをダウンロード（キャッシュ機能付き・フォールバック対応）
  Future<Uint8List?> getTile(
    BaseMapProvider provider,
    int z,
    int x,
    int y,
  ) async {
    // プロバイダーの最大ズームレベルを超えている場合は直接フォールバック
    if (z > provider.maxZoom) {
      return await _getTileWithFallback(provider, z, x, y);
    }

    // まず通常のタイル取得を試行
    final normalTile = await _getTileInternal(provider, z, x, y);
    if (normalTile != null) {
      return normalTile;
    }

    // 通常のタイル取得に失敗した場合、フォールバック機能を使用
    return await _getTileWithFallback(provider, z, x, y);
  }

  /// 内部用のタイル取得メソッド（フォールバックなし）
  Future<Uint8List?> _getTileInternal(
    BaseMapProvider provider,
    int z,
    int x,
    int y, {
    bool allowNetworkAccess = true,
    int retryCount = 0,
  }) async {
    try {
      // まずキャッシュから取得を試行
      final cachedData = await _getCachedTile(provider.id, z, x, y);
      if (cachedData != null) {
        return cachedData;
      }

      // オフラインモードまたはネットワークアクセス禁止の場合はここで終了
      if (_isOfflineMode || !allowNetworkAccess) {
        return null;
      }
      
      // ネットワークインターフェースがない場合は即座に終了（無駄なリクエスト防止）
      if (!_isNetworkAvailable) {
        // AppLogger.debug('[TILE] ⚠️ No network interface');
        return null;
      }

      // ネットワークからダウンロード（リトライ機能付き）
      final url = provider.urlTemplate
          .replaceAll('{z}', z.toString())
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString());

      final response = await http
          .get(
            Uri.parse(url),
            headers: {
              if (provider.userAgentPackageName != null)
                'User-Agent': provider.userAgentPackageName!,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final data = response.bodyBytes;
        
        // ダウンロードデータの妥当性チェック
        if (data.length < 100) {
          return null;
        }
        
        // PNGヘッダーチェック
        if (data.length >= 8) {
          // ヘッダーチェックは行わず、データサイズのみで簡易チェックとする
          // サーバーによっては異なるフォーマット（WebPなど）を返す可能性や、
          // ヘッダーが微妙に異なる場合も考慮して、厳密なチェックは廃止する。
          // decodeImageで失敗すれば最終的に弾かれるため問題ない。
        }

        // キャッシュに保存
        await _cacheTile(provider.id, z, x, y, data);
        AppLogger.debug('[TILE] 📥 Downloaded: ${provider.id}');

        return data;
      } else {
        // ネットワーク取得失敗時にキャッシュを再確認（別プロバイダーや古いキャッシュの可能性）
        final fallbackCachedData = await _getCachedTile(
          provider.id,
          z,
          x,
          y,
          allowCrossPlatformCache: true,
        );
        if (fallbackCachedData != null) {
          return fallbackCachedData;
        }

        // リトライ機能（最大2回）
        if (retryCount < 2) {
          final delayMs = 500 * (retryCount + 1);
          await Future.delayed(Duration(milliseconds: delayMs));
          return await _getTileInternal(
            provider,
            z,
            x,
            y,
            allowNetworkAccess: allowNetworkAccess,
            retryCount: retryCount + 1,
          );
        }

        return null;
      }
    } catch (e) {
      AppLogger.debug('[TILE] ❌ Network error');
      
      // エラー時もキャッシュを確認（ネットワークエラーでもキャッシュがあれば利用）
      final errorFallbackData = await _getCachedTile(
        provider.id,
        z,
        x,
        y,
        allowCrossPlatformCache: true,
      );
      if (errorFallbackData != null) {
        return errorFallbackData;
      }

      // リトライ機能（エラー時も適用）
      if (retryCount < 1 && allowNetworkAccess) {
        await Future.delayed(Duration(milliseconds: 1000));
        return await _getTileInternal(
          provider,
          z,
          x,
          y,
          allowNetworkAccess: allowNetworkAccess,
          retryCount: retryCount + 1,
        );
      }

      return null;
    }
  }

  /// フォールバック機能付きタイル取得
  Future<Uint8List?> _getTileWithFallback(
    BaseMapProvider provider,
    int z,
    int x,
    int y, {
    int maxFallbackLevels = 5,
  }) async {
    // 最小ズームレベルまで下がった場合、または最大フォールバック回数に達した場合は諦める
    if (z <= provider.minZoom || maxFallbackLevels <= 0) {
      return null;
    }

    // 1段階下のズームレベルを計算
    final parentZ = z - 1;
    final parentX = x ~/ 2;
    final parentY = y ~/ 2;

    // 下位ズームレベルのタイルを取得
    final parentTileData = await _getTileInternal(
      provider,
      parentZ,
      parentX,
      parentY,
      allowNetworkAccess: !_isOfflineMode,
    );

    if (parentTileData != null) {
      // 親タイルから適切な領域を切り出してスケールアップ
      final scaledTile = await _extractAndScaleTile(
        parentTileData,
        z,
        x,
        y,
        parentZ,
        parentX,
        parentY,
      );

      if (scaledTile != null) {
        // スケールアップしたタイルをキャッシュに保存
        await _cacheTile(provider.id, z, x, y, scaledTile);
        return scaledTile;
      }
    }

    // さらに下位ズームレベルで再帰的に試行
    return await _getTileWithFallback(
      provider,
      parentZ,
      parentX,
      parentY,
      maxFallbackLevels: maxFallbackLevels - 1,
    );
  }

  /// 親タイルから指定領域を切り出してスケールアップ
  /// 
  /// 画像処理はCPU負荷が高いため、compute関数を使用して別Isolateで実行します。
  Future<Uint8List?> _extractAndScaleTile(
    Uint8List parentTileData,
    int targetZ,
    int targetX,
    int targetY,
    int parentZ,
    int parentX,
    int parentY,
  ) async {
    try {
      return await compute(_processTileExtraction, {
        'parentTileData': parentTileData,
        'targetZ': targetZ,
        'targetX': targetX,
        'targetY': targetY,
        'parentZ': parentZ,
        'parentX': parentX,
        'parentY': parentY,
      });
    } catch (e) {
      AppLogger.debug('[TILE] ❌ Scaling error (compute): $e');
      return null;
    }
  }

  /// キャッシュサイズを取得（MB単位）
  Future<double> getCacheSizeMB() async {
    if (_tileCacheDb == null) return 0.0;
    
    try {
      final sizeBytes = await _tileCacheDb!.getCacheSize();
      return sizeBytes / (1024 * 1024);
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Size error: $e');
      return 0.0;
    }
  }

  /// キャッシュクリア
  Future<void> clearCache({String? providerId}) async {
    if (_tileCacheDb == null) return;
    
    try {
      await _tileCacheDb!.clearCache(providerId: providerId);
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Clear error: $e');
    }
  }

  /// キャッシュされているタイル数を取得
  int getCachedTileCount({String? providerId}) {
    return 0;
  }

  /// プロバイダー別のキャッシュ統計を取得
  Future<Map<String, int>> getCacheStatistics() async {
    if (_tileCacheDb == null) return {};
    
    try {
      return await _tileCacheDb!.getStatistics();
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Stats error: $e');
      return {};
    }
  }

  /// 詳細なキャッシュ統計を取得（デバッグ用）
  Future<Map<String, Map<String, dynamic>>> getDetailedCacheStatistics() async {
    if (_tileCacheDb == null) return {};
    
    try {
      final stats = await _tileCacheDb!.getStatistics();
      
      final detailedStats = <String, Map<String, dynamic>>{};
      for (final entry in stats.entries) {
        detailedStats[entry.key] = {
          'count': entry.value,
          'provider': BaseMapProvider.getProviderById(entry.key)?.name ?? entry.key,
        };
      }
      
      return detailedStats;
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Detailed stats error: $e');
      return {};
    }
  }

  /// キャッシュ検証（破損タイルの確認・修復）
  Future<Map<String, dynamic>> validateAndRepairCache() async {
    if (_tileCacheDb == null) {
      return {
        'totalTiles': 0,
        'validTiles': 0,
        'invalidTiles': 0,
        'removedTiles': 0,
      };
    }
    
    try {
      return await _tileCacheDb!.validateAndRepair();
    } catch (e) {
      AppLogger.debug('[BaseMapService] ❌ Validation error: $e');
      return {
        'totalTiles': 0,
        'validTiles': 0,
        'invalidTiles': 0,
        'removedTiles': 0,
      };
    }
  }

  /// 緯度経度からタイル座標を取得
  math.Point<int> _getTileCoordinates(double lat, double lon, int zoom) {
    final n = math.pow(2, zoom);
    final x = ((lon + 180.0) / 360.0 * n).floor();
    final latRad = lat * math.pi / 180.0;
    final y = ((1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n).floor();
    return math.Point(x, y);
  }

  /// ダウンロードキャンセル
  void cancelDownload() {
    if (_isDownloading) {
      _cancelDownload = true;
      notifyListeners();
    }
  }

  /// エリア推定（タイル数を計算）
  Map<String, int> estimateDownloadSize({
    required LatLng center,
    required double radiusMeters,
    required int minZoom,
    required int maxZoom,
  }) {
    int totalTiles = 0;
    
    // 半径を緯度経度の差分に変換（概算）
    // 緯度1度 ≒ 111km, 経度1度 ≒ 111km * cos(lat)
    final latDiff = radiusMeters / 111000.0;
    final lonDiff = radiusMeters / (111000.0 * math.cos(center.latitude * math.pi / 180.0));

    final north = center.latitude + latDiff;
    final south = center.latitude - latDiff;
    final east = center.longitude + lonDiff;
    final west = center.longitude - lonDiff;

    for (var z = minZoom; z <= maxZoom; z++) {
      final topLeft = _getTileCoordinates(north, west, z);
      final bottomRight = _getTileCoordinates(south, east, z);
      
      final tilesX = (bottomRight.x - topLeft.x).abs() + 1;
      final tilesY = (bottomRight.y - topLeft.y).abs() + 1;
      
      totalTiles += tilesX * tilesY;
    }

    return {
      'totalTiles': totalTiles,
    };
  }

  /// エリア一括ダウンロード実行 (並列処理対応)
  Stream<Map<String, dynamic>> downloadArea({
    required LatLng center,
    required double radiusMeters,
    required int minZoom,
    required int maxZoom,
  }) async* {
    if (_isDownloading) {
      yield {'status': 'error', 'message': 'すでにダウンロードが実行中です'};
      return;
    }

    _isDownloading = true;
    _cancelDownload = false;
    notifyListeners();

    // 半径を緯度経度の差分に変換
    final latDiff = radiusMeters / 111000.0;
    final lonDiff = radiusMeters / (111000.0 * math.cos(center.latitude * math.pi / 180.0));

    final north = center.latitude + latDiff;
    final south = center.latitude - latDiff;
    final east = center.longitude + lonDiff;
    final west = center.longitude - lonDiff;

    // ダウンロード対象のタイルリストを作成
    final tilesToDownload = <_TileRequest>[];
    
    for (var z = minZoom; z <= maxZoom; z++) {
      final topLeft = _getTileCoordinates(north, west, z);
      final bottomRight = _getTileCoordinates(south, east, z);

      final minX = math.min(topLeft.x, bottomRight.x);
      final maxX = math.max(topLeft.x, bottomRight.x);
      final minY = math.min(topLeft.y, bottomRight.y);
      final maxY = math.max(topLeft.y, bottomRight.y);

      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          tilesToDownload.add(_TileRequest(z, x, y));
        }
      }
    }

    final totalTiles = tilesToDownload.length;
    int processedTiles = 0;
    int downloadedTiles = 0;
    int skippedTiles = 0;
    int errorTiles = 0;

    yield {
      'status': 'start',
      'total': totalTiles,
      'processed': 0,
    };

    final provider = _currentProvider;
    
    // 並列処理の設定
    // OpenStreetMapの推奨は最大2スレッドだが、ユーザーの要望により4スレッドまで許可
    // 待機時間を短くしてスループットを上げる
    const int maxConcurrentDownloads = 4;
    final activeFutures = <Future<void>>[];
    final queue = List<_TileRequest>.from(tilesToDownload);

    try {
      while (queue.isNotEmpty || activeFutures.isNotEmpty) {
        if (_cancelDownload) break;

        // キューから取り出して並列実行数までタスクを追加
        while (activeFutures.length < maxConcurrentDownloads && queue.isNotEmpty) {
          final tile = queue.removeAt(0);
          
          late final Future<void> future;
          future = _processSingleTile(
            provider, 
            tile, 
            (result) {
              // 完了コールバック
              processedTiles++;
              if (result == 'downloaded') {
                downloadedTiles++;
              } else if (result == 'skipped') skippedTiles++;
              else errorTiles++;
            }
          ).then((_) {
            // 完了したらリストから自分自身を削除
            activeFutures.remove(future);
          });
          
          activeFutures.add(future);
        }
        
        // スロットが空くか、全タスク完了まで待機
        if (activeFutures.isNotEmpty) {
          await Future.any(activeFutures);
          
          // 進捗通知 (高頻度すぎると重くなるので間引く)
          if (processedTiles % 5 == 0 || processedTiles == totalTiles) {
             yield {
              'status': 'progress',
              'total': totalTiles,
              'processed': processedTiles,
              'downloaded': downloadedTiles,
              'skipped': skippedTiles,
              'errors': errorTiles,
              'percent': (processedTiles / totalTiles * 100).toStringAsFixed(1),
            };
          }
        }
      }

      yield {
        'status': _cancelDownload ? 'cancelled' : 'completed',
        'total': totalTiles,
        'processed': processedTiles,
        'downloaded': downloadedTiles,
        'skipped': skippedTiles,
        'errors': errorTiles,
      };

    } catch (e) {
      AppLogger.debug('[Downloader] Critical error: $e');
      yield {
        'status': 'error',
        'message': e.toString(),
      };
    } finally {
      _isDownloading = false;
      _cancelDownload = false;
      notifyListeners();
    }
  }

  /// 単一タイルの処理（並列実行用）
  Future<void> _processSingleTile(
    BaseMapProvider provider, 
    _TileRequest tile,
    Function(String) onComplete,
  ) async {
    try {
      // キャッシュ確認
      final cached = await _getCachedTile(provider.id, tile.z, tile.x, tile.y);
      
      if (cached != null) {
        onComplete('skipped');
        return;
      }
      
      // ダウンロード実行
      final data = await _getTileInternal(
        provider, 
        tile.z, tile.x, tile.y, 
        allowNetworkAccess: true,
        retryCount: 2,
      );
      
      if (data != null) {
        // BAN対策: 短い待機時間を入れる
        // 4並列 × 50ms待機 = 理論最大80req/sec (通信時間除く)
        // 実際は通信時間があるため、サーバー負荷はそこまで高くならないはず
        await Future.delayed(const Duration(milliseconds: 50));
        onComplete('downloaded');
      } else {
        onComplete('error');
      }
    } catch (e) {
      AppLogger.debug('[Downloader] ❌ Download failed (Offline/Network Error)');
      onComplete('error');
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _tileCacheDb?.close();
    super.dispose();
  }
}

/// タイルリクエスト管理用クラス
class _TileRequest {
  final int z;
  final int x;
  final int y;
  
  _TileRequest(this.z, this.x, this.y);
}

