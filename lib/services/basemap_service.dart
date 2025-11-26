/// 背景地図管理サービス
/// 背景地図の選択、切り替え、オフラインキャッシュ機能を提供
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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
    print('[TILE-ISO] ❌ Scaling error: $e');
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

  /// 現在の背景地図プロバイダー
  BaseMapProvider get currentProvider => _currentProvider;

  /// オフラインモードかどうか
  bool get isOfflineMode => _isOfflineMode;

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
    } catch (e) {
      print('[BaseMapService] ❌ Init error: $e');
      _currentProvider = BaseMapProvider.defaultProvider;
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
      print('[BaseMapService] ❌ Cache dir error: $e');
      rethrow;
    }
  }

  /// タイルキャッシュデータベースの初期化
  Future<void> _initializeTileCacheDatabase() async {
    try {
      _tileCacheDb = TileCacheGeoPackage();
      await _tileCacheDb!.initialize(_cacheDirectory!);
    } catch (e) {
      print('[BaseMapService] ❌ TileDB init error: $e');
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
      print('[BaseMapService] ❌ Settings load error: $e');
    }
  }

  /// 設定の保存
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('basemap_provider_id', _currentProvider.id);
      await prefs.setBool('basemap_offline_mode', _isOfflineMode);
    } catch (e) {
      print('[BaseMapService] ❌ Settings save error: $e');
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
      print('[TILE] ❌ Cache save error: $e');
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
          print('[TILE] ⚠️ Corrupted cache (too small)');
          return null;
        }
        
        // PNGヘッダーチェック
        if (data.length >= 8) {
          final pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
          bool isValidPng = true;
          for (int i = 0; i < 8; i++) {
            if (data[i] != pngSignature[i]) {
              isValidPng = false;
              break;
            }
          }
          
          if (!isValidPng) {
            print('[TILE] ⚠️ Corrupted cache (invalid PNG header)');
            return null;
          }
        }
        
        return data;
      }
      
      return null;
    } catch (e) {
      print('[TILE] ❌ Cache read error: $e');
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
          final pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
          bool isValidPng = true;
          for (int i = 0; i < 8; i++) {
            if (data[i] != pngSignature[i]) {
              isValidPng = false;
              break;
            }
          }
          
          if (!isValidPng) {
            return null;
          }
        }

        // キャッシュに保存
        await _cacheTile(provider.id, z, x, y, data);
        print('[TILE] 📥 Downloaded: ${provider.id}');

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
      print('[TILE] ❌ Network error: $e');

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
      print('[TILE] ❌ Scaling error (compute): $e');
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
      print('[BaseMapService] ❌ Size error: $e');
      return 0.0;
    }
  }

  /// キャッシュクリア
  Future<void> clearCache({String? providerId}) async {
    if (_tileCacheDb == null) return;
    
    try {
      await _tileCacheDb!.clearCache(providerId: providerId);
    } catch (e) {
      print('[BaseMapService] ❌ Clear error: $e');
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
      print('[BaseMapService] ❌ Stats error: $e');
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
      print('[BaseMapService] ❌ Detailed stats error: $e');
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
      print('[BaseMapService] ❌ Validation error: $e');
      return {
        'totalTiles': 0,
        'validTiles': 0,
        'invalidTiles': 0,
        'removedTiles': 0,
      };
    }
  }

  @override
  void dispose() {
    _tileCacheDb?.close();
    super.dispose();
  }
}
