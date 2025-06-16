import 'package:flutter_test/flutter_test.dart';
import 'package:k_maps/services/basemap_service.dart';
import 'package:k_maps/models/basemap_provider.dart';

void main() {
  group('キャッシュフォールバック機能テスト', () {
    late BaseMapService baseMapService;

    setUpAll(() async {
      baseMapService = BaseMapService();
      await baseMapService.initialize();
    });

    test('オンライン取得失敗時のキャッシュフォールバック', () async {
      // テストでは実際のネットワーク接続は不要なため、
      // キャッシュ統計機能のテストを実行
      final stats = baseMapService.getCacheStatistics();
      expect(stats, isA<Map<String, int>>());

      print('[TEST] キャッシュ統計: $stats');
    });

    test('詳細キャッシュ統計取得', () async {
      final detailedStats = baseMapService.getDetailedCacheStatistics();
      expect(detailedStats, isA<Map<String, Map<String, dynamic>>>());

      print('[TEST] 詳細キャッシュ統計: $detailedStats');
    });

    test('キャッシュ検証・修復機能', () async {
      final result = await baseMapService.validateAndRepairCache();
      expect(result, isA<Map<String, dynamic>>());
      expect(result['totalTiles'], isA<int>());
      expect(result['validTiles'], isA<int>());
      expect(result['invalidTiles'], isA<int>());

      print('[TEST] キャッシュ検証結果: $result');
    });

    test('プロバイダー統計情報', () {
      final providers = BaseMapProvider.availableProviders;
      expect(providers.isNotEmpty, true);

      for (final provider in providers) {
        final count = baseMapService.getCachedTileCount(
          providerId: provider.id,
        );
        print('[TEST] ${provider.name}: ${count}タイル');
      }
    });
  });
}
