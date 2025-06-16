/// 背景地図管理サービス
/// 背景地図の選択、切り替え、オフラインキャッシュ機能を提供
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'package:image/image.dart' as img;
import '../models/basemap_provider.dart';

/// オフラインタイルキャッシュエントリ
class CachedTile {
  final int x;
  final int y;
  final int z;
  final String providerId;
  final DateTime cachedAt;
  final String filePath;

  CachedTile({
    required this.x,
    required this.y,
    required this.z,
    required this.providerId,
    required this.cachedAt,
    required this.filePath,
  });

  /// キャッシュキーを生成
  String get cacheKey => '${providerId}_${z}_${x}_$y';

  /// JSON形式に変換
  Map<String, dynamic> toJson() => {
    'x': x,
    'y': y,
    'z': z,
    'providerId': providerId,
    'cachedAt': cachedAt.millisecondsSinceEpoch,
    'filePath': filePath,
  };

  /// JSONから復元
  static CachedTile fromJson(Map<String, dynamic> json) => CachedTile(
    x: json['x'],
    y: json['y'],
    z: json['z'],
    providerId: json['providerId'],
    cachedAt: DateTime.fromMillisecondsSinceEpoch(json['cachedAt']),
    filePath: json['filePath'],
  );
}

/// 背景地図管理サービス
class BaseMapService extends ChangeNotifier {
  static final BaseMapService _instance = BaseMapService._internal();
  factory BaseMapService() => _instance;
  BaseMapService._internal();

  BaseMapProvider _currentProvider = BaseMapProvider.defaultProvider;
  final Map<String, CachedTile> _tileCache = {};
  bool _isOfflineMode = false;
  String? _cacheDirectory;

  /// 現在の背景地図プロバイダー
  BaseMapProvider get currentProvider => _currentProvider;

  /// オフラインモードかどうか
  bool get isOfflineMode => _isOfflineMode;

  /// 利用可能なプロバイダー一覧
  List<BaseMapProvider> get availableProviders =>
      BaseMapProvider.availableProviders;

  /// サービス初期化
  Future<void> initialize() async {
    print('[DEBUG] BaseMapService: 初期化開始');

    try {
      // キャッシュディレクトリの設定
      await _initializeCacheDirectory();

      // 設定の読み込み
      await _loadSettings();

      // キャッシュインデックスの読み込み
      await _loadCacheIndex();

      print(
        '[DEBUG] BaseMapService: 初期化完了 - provider: ${_currentProvider.name}',
      );
    } catch (e) {
      print('[ERROR] BaseMapService: 初期化エラー: $e');
      // エラーでもデフォルト設定で続行
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
        print('[DEBUG] BaseMapService: キャッシュディレクトリ作成: $_cacheDirectory');
      }
    } catch (e) {
      print('[ERROR] BaseMapService: キャッシュディレクトリ初期化エラー: $e');
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

      print(
        '[DEBUG] BaseMapService: 設定読み込み完了 - provider: $providerId, offline: $_isOfflineMode',
      );
    } catch (e) {
      print('[ERROR] BaseMapService: 設定読み込みエラー: $e');
    }
  }

  /// 設定の保存
  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('basemap_provider_id', _currentProvider.id);
      await prefs.setBool('basemap_offline_mode', _isOfflineMode);

      print('[DEBUG] BaseMapService: 設定保存完了');
    } catch (e) {
      print('[ERROR] BaseMapService: 設定保存エラー: $e');
    }
  }

  /// キャッシュインデックスの読み込み
  Future<void> _loadCacheIndex() async {
    try {
      final indexFile = File(path.join(_cacheDirectory!, 'cache_index.json'));
      if (indexFile.existsSync()) {
        final indexData = await indexFile.readAsString();
        final indexJson = json.decode(indexData) as Map<String, dynamic>;

        _tileCache.clear();
        for (final entry in indexJson.entries) {
          final cachedTile = CachedTile.fromJson(entry.value);
          _tileCache[entry.key] = cachedTile;
        }

        print(
          '[DEBUG] BaseMapService: キャッシュインデックス読み込み完了 (${_tileCache.length}タイル)',
        );
      }
    } catch (e) {
      print('[ERROR] BaseMapService: キャッシュインデックス読み込みエラー: $e');
      _tileCache.clear();
    }
  }

  /// キャッシュインデックスの保存
  Future<void> _saveCacheIndex() async {
    try {
      final indexFile = File(path.join(_cacheDirectory!, 'cache_index.json'));
      final indexData = <String, dynamic>{};

      for (final entry in _tileCache.entries) {
        indexData[entry.key] = entry.value.toJson();
      }

      await indexFile.writeAsString(json.encode(indexData));
      print('[DEBUG] BaseMapService: キャッシュインデックス保存完了');
    } catch (e) {
      print('[ERROR] BaseMapService: キャッシュインデックス保存エラー: $e');
    }
  }

  /// 背景地図プロバイダーを変更
  Future<void> setProvider(BaseMapProvider provider) async {
    if (_currentProvider != provider) {
      _currentProvider = provider;
      await _saveSettings();
      notifyListeners();
      print('[DEBUG] BaseMapService: プロバイダー変更: ${provider.name}');
    }
  }

  /// オフラインモードの切り替え
  Future<void> setOfflineMode(bool offline) async {
    if (_isOfflineMode != offline) {
      _isOfflineMode = offline;
      await _saveSettings();
      notifyListeners();
      print('[DEBUG] BaseMapService: オフラインモード変更: $offline');
    }
  }

  /// タイルのキャッシュファイルパスを生成
  String _getTileCacheFilePath(String providerId, int z, int x, int y) {
    final providerDir = path.join(_cacheDirectory!, providerId);
    final zoomDir = path.join(providerDir, z.toString());
    final fileName = '${x}_$y.tile';
    return path.join(zoomDir, fileName);
  }

  /// タイルをキャッシュに保存
  Future<void> _cacheTile(
    String providerId,
    int z,
    int x,
    int y,
    Uint8List data,
  ) async {
    try {
      final filePath = _getTileCacheFilePath(providerId, z, x, y);
      final file = File(filePath);

      // ディレクトリが存在しない場合は作成
      final directory = file.parent;
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }

      // タイルデータを保存
      await file.writeAsBytes(data);

      // キャッシュインデックスに追加
      final cachedTile = CachedTile(
        x: x,
        y: y,
        z: z,
        providerId: providerId,
        cachedAt: DateTime.now(),
        filePath: filePath,
      );

      _tileCache[cachedTile.cacheKey] = cachedTile;

      // 定期的にインデックスを保存
      if (_tileCache.length % 50 == 0) {
        await _saveCacheIndex();
      }
    } catch (e) {
      print('[ERROR] BaseMapService: タイルキャッシュ保存エラー: $e');
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
    try {
      // 指定プロバイダーのキャッシュを優先取得
      final cacheKey = '${providerId}_${z}_${x}_$y';
      final cachedTile = _tileCache[cacheKey];

      if (cachedTile != null) {
        final file = File(cachedTile.filePath);
        if (file.existsSync()) {
          print('[DEBUG] BaseMapService: 指定プロバイダーキャッシュヒット - $cacheKey');
          return await file.readAsBytes();
        } else {
          // ファイルが存在しない場合はキャッシュから削除
          print('[WARN] BaseMapService: キャッシュファイル不存在のため削除 - $cacheKey');
          _tileCache.remove(cacheKey);
        }
      }

      // クロスプラットフォームキャッシュ検索（他プロバイダーの同座標タイル）
      if (allowCrossPlatformCache) {
        print('[DEBUG] BaseMapService: クロスプラットフォームキャッシュ検索 - z=$z, x=$x, y=$y');
        for (final entry in _tileCache.entries) {
          final tile = entry.value;
          if (tile.z == z &&
              tile.x == x &&
              tile.y == y &&
              tile.providerId != providerId) {
            final file = File(tile.filePath);
            if (file.existsSync()) {
              print(
                '[SUCCESS] BaseMapService: クロスプラットフォームキャッシュヒット - ${tile.providerId} -> $providerId',
              );
              return await file.readAsBytes();
            }
          }
        }
      }

      return null;
    } catch (e) {
      print('[ERROR] BaseMapService: キャッシュタイル取得エラー: $e');
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
    print(
      '[DEBUG] BaseMapService.getTile: 要求 z=$z, x=$x, y=$y (プロバイダー: ${provider.name}, maxZoom: ${provider.maxZoom})',
    );

    // プロバイダーの最大ズームレベルを超えている場合は直接フォールバック
    if (z > provider.maxZoom) {
      print(
        '[DEBUG] BaseMapService.getTile: z=$z はプロバイダーの最大ズーム ${provider.maxZoom} を超えているため、フォールバック実行',
      );
      return await _getTileWithFallback(provider, z, x, y);
    }

    // まず通常のタイル取得を試行
    final normalTile = await _getTileInternal(provider, z, x, y);
    if (normalTile != null) {
      return normalTile;
    }

    // 通常のタイル取得に失敗した場合、フォールバック機能を使用
    print('[DEBUG] BaseMapService.getTile: 通常のタイル取得失敗、フォールバック試行');
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
      print('[DEBUG] BaseMapService: キャッシュからタイル取得を試行 - z=$z, x=$x, y=$y');
      final cachedData = await _getCachedTile(provider.id, z, x, y);
      if (cachedData != null) {
        print(
          '[SUCCESS] BaseMapService: キャッシュからタイル取得成功 - z=$z, x=$x, y=$y (サイズ: ${cachedData.length}バイト)',
        );
        return cachedData;
      }
      print('[DEBUG] BaseMapService: キャッシュにタイルなし - z=$z, x=$x, y=$y');

      // オフラインモードまたはネットワークアクセス禁止の場合はここで終了
      if (_isOfflineMode || !allowNetworkAccess) {
        print('[DEBUG] BaseMapService: オフラインモード/ネットワークアクセス禁止のため、ネットワーク取得をスキップ');
        return null;
      }

      // ネットワークからダウンロード（リトライ機能付き）
      final url = provider.urlTemplate
          .replaceAll('{z}', z.toString())
          .replaceAll('{x}', x.toString())
          .replaceAll('{y}', y.toString());

      print(
        '[DEBUG] BaseMapService: ネットワークからタイル取得を試行 - URL: $url (試行回数: ${retryCount + 1})',
      );

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
        print(
          '[SUCCESS] BaseMapService: ネットワークからタイル取得成功 - z=$z, x=$x, y=$y (サイズ: ${data.length}バイト)',
        );

        // キャッシュに保存
        await _cacheTile(provider.id, z, x, y, data);

        return data;
      } else {
        print(
          '[WARN] BaseMapService: ネットワークタイル取得失敗 - z=$z, x=$x, y=$y (ステータス: ${response.statusCode}, サイズ: ${response.bodyBytes.length})',
        );

        // ネットワーク取得失敗時にキャッシュを再確認（別プロバイダーや古いキャッシュの可能性）
        print('[DEBUG] BaseMapService: ネットワーク失敗後のキャッシュ再確認 - z=$z, x=$x, y=$y');
        final fallbackCachedData = await _getCachedTile(
          provider.id,
          z,
          x,
          y,
          allowCrossPlatformCache: true,
        );
        if (fallbackCachedData != null) {
          print(
            '[SUCCESS] BaseMapService: フォールバックキャッシュからタイル取得成功 - z=$z, x=$x, y=$y',
          );
          return fallbackCachedData;
        }

        // リトライ機能（最大2回）
        if (retryCount < 2) {
          print(
            '[DEBUG] BaseMapService: リトライ実行 - z=$z, x=$x, y=$y (${retryCount + 1}/2)',
          );
          await Future.delayed(
            Duration(milliseconds: 500 * (retryCount + 1)),
          ); // 徐々に遅延を増加
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
      print('[ERROR] BaseMapService: タイル取得エラー - z=$z, x=$x, y=$y - $e');

      // エラー時もキャッシュを確認（ネットワークエラーでもキャッシュがあれば利用）
      print('[DEBUG] BaseMapService: エラー後のキャッシュ確認 - z=$z, x=$x, y=$y');
      final errorFallbackData = await _getCachedTile(
        provider.id,
        z,
        x,
        y,
        allowCrossPlatformCache: true,
      );
      if (errorFallbackData != null) {
        print(
          '[SUCCESS] BaseMapService: エラー後キャッシュからタイル取得成功 - z=$z, x=$x, y=$y',
        );
        return errorFallbackData;
      }

      // リトライ機能（エラー時も適用）
      if (retryCount < 1 && allowNetworkAccess) {
        // エラー時はリトライ回数を減らす
        print('[DEBUG] BaseMapService: エラー後リトライ実行 - z=$z, x=$x, y=$y');
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
      print(
        '[DEBUG] BaseMapService: フォールバック終了 - '
        'z=$z, minZoom=${provider.minZoom}, 残り試行回数:$maxFallbackLevels',
      );
      return null;
    }

    // フォールバック条件の確認（この条件は削除し、常にフォールバックを試行）
    print(
      '[DEBUG] BaseMapService: フォールバック開始 - z=$z (プロバイダー最大: ${provider.maxZoom})',
    );

    // 1段階下のズームレベルを計算
    final parentZ = z - 1;
    final parentX = x ~/ 2;
    final parentY = y ~/ 2;

    print(
      '[DEBUG] BaseMapService: フォールバック試行 (残り${maxFallbackLevels}回): '
      'z=$z->$parentZ, x=$x->$parentX, y=$y->$parentY',
    );

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
        print(
          '[SUCCESS] BaseMapService: フォールバック成功 - '
          'z=$z, x=$x, y=$y (親タイル: z=$parentZ)',
        );
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
      // 親タイル画像をデコード
      final parentImage = img.decodeImage(parentTileData);
      if (parentImage == null) {
        print('[ERROR] BaseMapService: 親タイル画像のデコードに失敗');
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

      print(
        '[DEBUG] BaseMapService: タイル切り出し - '
        'zoom差:$zoomDiff, scale:$scale, '
        'crop位置:($cropX,$cropY), cropサイズ:$cropSize',
      );

      // 範囲チェック
      if (cropX < 0 ||
          cropY < 0 ||
          cropX + cropSize > parentTileSize ||
          cropY + cropSize > parentTileSize) {
        print('[WARN] BaseMapService: 切り出し範囲が親タイルを超えています');
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
      final resultData = Uint8List.fromList(img.encodePng(resizedImage));

      print(
        '[DEBUG] BaseMapService: タイル変換完了 - '
        '元サイズ:${parentTileSize}x${parentTileSize}, '
        '切り出し:${cropSize}x${cropSize}, '
        '結果:256x256, データサイズ:${resultData.length}バイト',
      );

      return resultData;
    } catch (e) {
      print('[ERROR] BaseMapService: タイル変換エラー: $e');
      return null;
    }
  }

  /// キャッシュサイズを取得（MB単位）
  Future<double> getCacheSizeMB() async {
    try {
      if (_cacheDirectory == null) return 0.0;

      final cacheDir = Directory(_cacheDirectory!);
      if (!cacheDir.existsSync()) return 0.0;

      int totalSize = 0;
      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          final stat = await entity.stat();
          totalSize += stat.size;
        }
      }

      return totalSize / (1024 * 1024); // MB変換
    } catch (e) {
      print('[ERROR] BaseMapService: キャッシュサイズ取得エラー: $e');
      return 0.0;
    }
  }

  /// キャッシュクリア
  Future<void> clearCache({String? providerId}) async {
    try {
      if (_cacheDirectory == null) return;

      if (providerId != null) {
        // 特定のプロバイダーのキャッシュのみクリア
        final providerDir = Directory(path.join(_cacheDirectory!, providerId));
        if (providerDir.existsSync()) {
          await providerDir.delete(recursive: true);
        }

        // キャッシュインデックスからも削除
        _tileCache.removeWhere((key, value) => value.providerId == providerId);
      } else {
        // 全キャッシュクリア
        final cacheDir = Directory(_cacheDirectory!);
        if (cacheDir.existsSync()) {
          await cacheDir.delete(recursive: true);
          await cacheDir.create(recursive: true);
        }

        _tileCache.clear();
      }

      await _saveCacheIndex();
      print('[DEBUG] BaseMapService: キャッシュクリア完了');
    } catch (e) {
      print('[ERROR] BaseMapService: キャッシュクリアエラー: $e');
    }
  }

  /// キャッシュされているタイル数を取得
  int getCachedTileCount({String? providerId}) {
    if (providerId != null) {
      return _tileCache.values
          .where((tile) => tile.providerId == providerId)
          .length;
    }
    return _tileCache.length;
  }

  /// プロバイダー別のキャッシュ統計を取得
  Map<String, int> getCacheStatistics() {
    final stats = <String, int>{};

    for (final tile in _tileCache.values) {
      stats[tile.providerId] = (stats[tile.providerId] ?? 0) + 1;
    }

    return stats;
  }

  /// 詳細なキャッシュ統計を取得（デバッグ用）
  Map<String, Map<String, dynamic>> getDetailedCacheStatistics() {
    final stats = <String, Map<String, dynamic>>{};

    for (final tile in _tileCache.values) {
      if (!stats.containsKey(tile.providerId)) {
        stats[tile.providerId] = {
          'count': 0,
          'tiles': <Map<String, dynamic>>[],
          'zoomLevels': <int, int>{},
          'lastAccessed': null,
          'totalSize': 0,
        };
      }

      final providerStats = stats[tile.providerId]!;
      providerStats['count'] = (providerStats['count'] as int) + 1;

      // ズームレベル別統計
      final zoomLevels = providerStats['zoomLevels'] as Map<int, int>;
      zoomLevels[tile.z] = (zoomLevels[tile.z] ?? 0) + 1;

      // 個別タイル情報
      final tiles = providerStats['tiles'] as List<Map<String, dynamic>>;
      tiles.add({
        'z': tile.z,
        'x': tile.x,
        'y': tile.y,
        'timestamp': tile.cachedAt,
        'filePath': tile.filePath,
        'cacheKey': tile.cacheKey,
      });

      // 最終アクセス時刻更新
      if (providerStats['lastAccessed'] == null ||
          tile.cachedAt.isAfter(providerStats['lastAccessed'] as DateTime)) {
        providerStats['lastAccessed'] = tile.cachedAt;
      }
    }

    return stats;
  }

  /// キャッシュ検証（欠損ファイルの確認・修復）
  Future<Map<String, dynamic>> validateAndRepairCache() async {
    final result = {
      'totalTiles': _tileCache.length,
      'validTiles': 0,
      'invalidTiles': 0,
      'repairedTiles': 0,
      'removedTiles': 0,
      'details': <String, dynamic>{},
    };

    final tilesToRemove = <String>[];

    for (final entry in _tileCache.entries) {
      final cacheKey = entry.key;
      final tile = entry.value;

      try {
        final file = File(tile.filePath);
        if (file.existsSync()) {
          final fileSize = await file.length();
          if (fileSize > 0) {
            result['validTiles'] = (result['validTiles'] as int) + 1;
          } else {
            print('[WARN] BaseMapService: 空のキャッシュファイル検出 - $cacheKey');
            tilesToRemove.add(cacheKey);
            result['invalidTiles'] = (result['invalidTiles'] as int) + 1;
          }
        } else {
          print('[WARN] BaseMapService: 存在しないキャッシュファイル検出 - $cacheKey');
          tilesToRemove.add(cacheKey);
          result['invalidTiles'] = (result['invalidTiles'] as int) + 1;
        }
      } catch (e) {
        print('[ERROR] BaseMapService: キャッシュ検証エラー - $cacheKey: $e');
        tilesToRemove.add(cacheKey);
        result['invalidTiles'] = (result['invalidTiles'] as int) + 1;
      }
    }

    // 無効なタイルをキャッシュから削除
    for (final cacheKey in tilesToRemove) {
      _tileCache.remove(cacheKey);
      result['removedTiles'] = (result['removedTiles'] as int) + 1;
    }

    // インデックスファイルを更新
    if (tilesToRemove.isNotEmpty) {
      await _saveCacheIndex();
    }

    result['details'] = {
      'removedKeys': tilesToRemove,
      'cacheDirectory': _cacheDirectory,
      'indexFilePath':
          _cacheDirectory != null
              ? path.join(_cacheDirectory!, 'cache_index.json')
              : null,
    };

    print(
      '[INFO] BaseMapService: キャッシュ検証完了 - 有効:${result['validTiles']}, 無効:${result['invalidTiles']}, 削除:${result['removedTiles']}',
    );

    return result;
  }

  @override
  void dispose() {
    _saveCacheIndex();
    super.dispose();
  }
}
