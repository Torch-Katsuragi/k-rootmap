/// 背景地図設定画面
/// 背景地図プロバイダーの選択とオフライン機能の管理
import 'package:flutter/material.dart';
import '../models/basemap_provider.dart';
import '../services/basemap_service.dart';

class BaseMapSettingsScreen extends StatefulWidget {
  const BaseMapSettingsScreen({super.key});

  @override
  State<BaseMapSettingsScreen> createState() => _BaseMapSettingsScreenState();
}

class _BaseMapSettingsScreenState extends State<BaseMapSettingsScreen> {
  final BaseMapService _baseMapService = BaseMapService();
  Map<String, int> _cacheStats = {};
  double _cacheSizeMB = 0.0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  /// キャッシュ情報を読み込み
  Future<void> _loadCacheInfo() async {
    try {
      final stats = await _baseMapService.getCacheStatistics();
      final sizeMB = await _baseMapService.getCacheSizeMB();

      if (mounted) {
        setState(() {
          _cacheStats = stats;
          _cacheSizeMB = sizeMB;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[ERROR] BaseMapSettingsScreen: キャッシュ情報読み込みエラー: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// プロバイダー変更
  Future<void> _changeProvider(BaseMapProvider provider) async {
    try {
      await _baseMapService.setProvider(provider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('背景地図を「${provider.name}」に変更しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('背景地図の変更に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// オフラインモード切り替え
  Future<void> _toggleOfflineMode(bool value) async {
    try {
      await _baseMapService.setOfflineMode(value);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(value ? 'オフラインモードを有効にしました' : 'オフラインモードを無効にしました'),
            backgroundColor: value ? Colors.orange : Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('オフラインモードの変更に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// キャッシュクリア
  Future<void> _clearCache({String? providerId}) async {
    try {
      // 確認ダイアログ
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('キャッシュクリア'),
              content: Text(
                providerId != null
                    ? '選択したプロバイダーのキャッシュをクリアしますか？'
                    : '全ての地図キャッシュをクリアしますか？',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('クリア'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
      );

      if (confirmed == true) {
        await _baseMapService.clearCache(providerId: providerId);
        await _loadCacheInfo(); // キャッシュ情報を再読み込み

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('キャッシュをクリアしました'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('キャッシュクリアに失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// キャッシュ検証・修復
  Future<void> _validateAndRepairCache() async {
    try {
      // 進行状況ダイアログを表示
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('キャッシュを検証しています...')),
            ],
          ),
        ),
      );

      // キャッシュ検証実行
      final result = await _baseMapService.validateAndRepairCache();
      
      // ダイアログを閉じる
      if (mounted) {
        Navigator.pop(context);
      }

      // 結果を表示
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('キャッシュ検証結果'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('総タイル数: ${result['totalTiles']}'),
                Text(
                  '有効: ${result['validTiles']}',
                  style: const TextStyle(color: Colors.green),
                ),
                Text(
                  '無効: ${result['invalidTiles']}',
                  style: const TextStyle(color: Colors.orange),
                ),
                Text(
                  '削除: ${result['removedTiles']}',
                  style: const TextStyle(color: Colors.red),
                ),
                const SizedBox(height: 8),
                if (result['removedTiles'] > 0)
                  const Text(
                    '破損したキャッシュファイルを削除しました',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  )
                else
                  const Text(
                    '問題は検出されませんでした',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
        );

        // キャッシュ情報を再読み込み
        await _loadCacheInfo();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'キャッシュ検証完了: ${result['removedTiles']}個のファイルを修復',
            ),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      // エラー時はダイアログを閉じる
      if (mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('キャッシュ検証に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('背景地図設定'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'キャッシュ情報を更新',
            onPressed: _loadCacheInfo,
          ),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 現在の設定セクション
                    _buildCurrentSettingsSection(),
                    const SizedBox(height: 24),

                    // 背景地図選択セクション
                    _buildProviderSelectionSection(),
                    const SizedBox(height: 24),

                    // オフライン設定セクション
                    _buildOfflineSettingsSection(),
                    const SizedBox(height: 24),

                    // キャッシュ管理セクション
                    _buildCacheManagementSection(),
                  ],
                ),
              ),
    );
  }

  /// 現在の設定セクション
  Widget _buildCurrentSettingsSection() {
    final currentProvider = _baseMapService.currentProvider;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '現在の設定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(currentProvider.icon, color: Colors.blue),
              title: Text(currentProvider.name),
              subtitle: Text(currentProvider.description),
              trailing:
                  _baseMapService.isOfflineMode
                      ? const Chip(
                        label: Text('オフライン'),
                        backgroundColor: Colors.orange,
                      )
                      : const Chip(
                        label: Text('オンライン'),
                        backgroundColor: Colors.green,
                      ),
            ),
          ],
        ),
      ),
    );
  }

  /// 背景地図選択セクション
  Widget _buildProviderSelectionSection() {
    final currentProvider = _baseMapService.currentProvider;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '背景地図の選択',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...BaseMapProvider.availableProviders.map((provider) {
              final isSelected = provider.id == currentProvider.id;
              final cachedTileCount = _cacheStats[provider.id] ?? 0;

              return ListTile(
                leading: Icon(
                  provider.icon,
                  color: isSelected ? Colors.blue : Colors.grey,
                ),
                title: Text(
                  provider.name,
                  style: TextStyle(
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(provider.description),
                    if (cachedTileCount > 0)
                      Text(
                        'キャッシュ: ${cachedTileCount}タイル',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green[600],
                        ),
                      ),
                  ],
                ),
                trailing:
                    isSelected
                        ? const Icon(Icons.check_circle, color: Colors.blue)
                        : null,
                onTap: () => _changeProvider(provider),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  /// オフライン設定セクション
  Widget _buildOfflineSettingsSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'オフライン設定',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('オフラインモード'),
              subtitle: const Text('ネットワークを使用せず、キャッシュされた地図のみを表示'),
              value: _baseMapService.isOfflineMode,
              onChanged: _toggleOfflineMode,
              secondary: Icon(
                _baseMapService.isOfflineMode ? Icons.wifi_off : Icons.wifi,
                color:
                    _baseMapService.isOfflineMode
                        ? Colors.orange
                        : Colors.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// キャッシュ管理セクション
  Widget _buildCacheManagementSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'キャッシュ管理',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '合計: ${_cacheSizeMB.toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // キャッシュ検証・修復ボタン
            ListTile(
              leading: const Icon(Icons.build, color: Colors.blue),
              title: const Text('キャッシュを検証・修復'),
              subtitle: const Text('破損したキャッシュを自動検出して削除'),
              trailing: ElevatedButton(
                onPressed: _cacheStats.isNotEmpty ? _validateAndRepairCache : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('検証', style: TextStyle(color: Colors.white)),
              ),
            ),
            const Divider(),

            // 全キャッシュクリアボタン
            ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.red),
              title: const Text('全キャッシュをクリア'),
              subtitle: Text(
                '${_cacheStats.values.fold(0, (sum, count) => sum + count)}タイル',
              ),
              trailing: ElevatedButton(
                onPressed: _cacheStats.isNotEmpty ? () => _clearCache() : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('クリア', style: TextStyle(color: Colors.white)),
              ),
            ),
            const Divider(),

            // プロバイダー別キャッシュ情報
            const Text(
              'プロバイダー別キャッシュ',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (_cacheStats.isEmpty)
              const Text(
                'キャッシュされた地図データはありません',
                style: TextStyle(color: Colors.grey),
              )
            else
              ..._cacheStats.entries.map((entry) {
                final provider = BaseMapProvider.getProviderById(entry.key);
                if (provider == null) return const SizedBox.shrink();

                return ListTile(
                  leading: Icon(provider.icon, size: 20),
                  title: Text(provider.name),
                  subtitle: Text('${entry.value}タイル'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: 'このプロバイダーのキャッシュをクリア',
                    onPressed: () => _clearCache(providerId: entry.key),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }
}
