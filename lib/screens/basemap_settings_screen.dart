/// 背景地図設定画面
/// 背景地図プロバイダーの選択とオフライン機能の管理
library;
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/basemap_provider.dart';
import '../services/basemap_service.dart';
import '../models/app_notification.dart';
import '../providers/notification_providers.dart';
import '../widgets/settings_widgets.dart';
import '../providers/ui_state_providers.dart';

class BaseMapSettingsScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;

  const BaseMapSettingsScreen({
    super.key,
    this.isEmbedded = false,
  });

  @override
  ConsumerState<BaseMapSettingsScreen> createState() => _BaseMapSettingsScreenState();
}

class _BaseMapSettingsScreenState extends ConsumerState<BaseMapSettingsScreen> {
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
      AppLogger.debug('[ERROR] BaseMapSettingsScreen: キャッシュ情報読み込みエラー: $e');
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

      ref.read(notificationCenterProvider.notifier).add(
            title: '背景地図を「${provider.name}」に変更しました',
            level: NotificationLevel.success,
          );
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: '背景地図の変更に失敗しました: $e',
            level: NotificationLevel.error,
          );
    }
  }

  /// オフラインモード切り替え
  Future<void> _toggleOfflineMode(bool value) async {
    try {
      await _baseMapService.setOfflineMode(value);

      ref.read(notificationCenterProvider.notifier).add(
            title: value ? 'オフラインモードを有効にしました' : 'オフラインモードを無効にしました',
            level: value ? NotificationLevel.warning : NotificationLevel.info,
          );
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'オフラインモードの変更に失敗しました: $e',
            level: NotificationLevel.error,
          );
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
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('クリア'),
                ),
              ],
            ),
      );

      if (confirmed == true) {
        await _baseMapService.clearCache(providerId: providerId);
        await _loadCacheInfo(); // キャッシュ情報を再読み込み

        ref.read(notificationCenterProvider.notifier).add(
              title: 'キャッシュをクリアしました',
              level: NotificationLevel.success,
            );
      }
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'キャッシュクリアに失敗しました: $e',
            level: NotificationLevel.error,
          );
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

        ref.read(notificationCenterProvider.notifier).add(
              title: 'キャッシュ検証完了: ${result['removedTiles']}個のファイルを修復',
              level: NotificationLevel.info,
            );
      }
    } catch (e) {
      // エラー時はダイアログを閉じる
      if (mounted) {
        Navigator.pop(context);
      }
      ref.read(notificationCenterProvider.notifier).add(
            title: 'キャッシュ検証に失敗しました: $e',
            level: NotificationLevel.error,
          );
    }
  }

  /// ダウンロード設定ダイアログを表示
  Future<void> _showDownloadDialog() async {
    // 現在の地図中心座標を取得
    LatLng center;
    try {
      final mapController = ref.read(mapControllerHolderProvider);
      if (mapController != null) {
        center = mapController.camera.center;
      } else {
        center = const LatLng(35.681236, 139.767125);
      }
    } catch (e) {
      center = const LatLng(35.681236, 139.767125);
    }

    final provider = _baseMapService.currentProvider;
    
    // デフォルト設定
    // 初期ズーム範囲: 現在のズームレベル前後
    double currentZoom = 15.0;
    try {
      final mapController = ref.read(mapControllerHolderProvider);
      if (mapController != null) {
        currentZoom = mapController.camera.zoom;
      }
    } catch (_) {}

    double minZoom = (currentZoom - 2).clamp(provider.minZoom.toDouble(), provider.maxZoom.toDouble());
    double maxZoom = (currentZoom + 2).clamp(provider.minZoom.toDouble(), provider.maxZoom.toDouble());
    if (minZoom > maxZoom) minZoom = maxZoom;

    RangeValues zoomRange = RangeValues(minZoom, maxZoom);
    double radius = 1000; // 1km

    // ダイアログ表示
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadSettingsDialog(
        center: center,
        provider: provider,
        initialRadius: radius,
        initialZoomRange: zoomRange,
        baseMapService: _baseMapService,
        onStartDownload: (r, zMin, zMax) {
            Navigator.pop(context); // 設定ダイアログを閉じる
            _startDownload(center, r, zMin, zMax); // ダウンロード開始
        },
      ),
    );
  }

  /// ダウンロード実行と進捗ダイアログ
  void _startDownload(LatLng center, double radius, int minZoom, int maxZoom) {
    showDialog(
      context: context,
      barrierDismissible: false, // 背景タップで閉じない
      builder: (context) => _DownloadProgressDialog(
        center: center,
        radius: radius,
        minZoom: minZoom,
        maxZoom: maxZoom,
        baseMapService: _baseMapService,
      ),
    ).then((_) {
        // ダイアログが閉じたらキャッシュ情報を更新
        _loadCacheInfo();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '背景地図設定',
      isEmbedded: widget.isEmbedded,
      isLoading: _isLoading,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'キャッシュ情報を更新',
          onPressed: _loadCacheInfo,
        ),
      ],
      body: SettingsBody(
        spacing: 24,
        sections: [
          _buildCurrentSettingsSection(),
          _buildDownloadSection(),
          _buildProviderSelectionSection(),
          _buildOfflineSettingsSection(),
          _buildCacheManagementSection(),
        ],
      ),
    );
  }

  /// 一括ダウンロードセクション
  Widget _buildDownloadSection() {
    return SettingsHighlightSection(
      title: '地図の一括ダウンロード',
      icon: Icons.download_for_offline,
      iconColor: Colors.blue,
      backgroundColor: Colors.blue[50]!,
      description:
          '現在表示している場所を中心に、指定した範囲の地図データを一括で保存します。オフライン環境に行く前に実行してください。',
      actionButton: ElevatedButton.icon(
        onPressed: _showDownloadDialog,
        icon: const Icon(Icons.download),
        label: const Text('ダウンロード設定を開く'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  /// 現在の設定セクション
  Widget _buildCurrentSettingsSection() {
    final currentProvider = _baseMapService.currentProvider;

    return SettingsSection(
      title: '現在の設定',
      children: [
        SettingsTile(
          leadingIcon: currentProvider.icon,
          leadingIconColor: Colors.blue,
          title: currentProvider.name,
          subtitle: currentProvider.description,
          trailing: _baseMapService.isOfflineMode
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
    );
  }

  /// 背景地図選択セクション
  Widget _buildProviderSelectionSection() {
    final currentProvider = _baseMapService.currentProvider;

    return SettingsSection(
      title: '背景地図の選択',
      children: BaseMapProvider.availableProviders.map((provider) {
        final isSelected = provider.id == currentProvider.id;
        final cachedTileCount = _cacheStats[provider.id] ?? 0;
        final subtitleText = cachedTileCount > 0
            ? '${provider.description}\nキャッシュ: $cachedTileCountタイル'
            : provider.description;

        return SettingsSelectionTile(
          leadingIcon: provider.icon,
          leadingIconColor: Colors.blue,
          title: provider.name,
          subtitle: subtitleText,
          isSelected: isSelected,
          onTap: () => _changeProvider(provider),
        );
      }).toList(),
    );
  }

  /// オフライン設定セクション
  Widget _buildOfflineSettingsSection() {
    return SettingsSection(
      title: 'オフライン設定',
      children: [
        SettingsSwitchTile(
          leadingIcon:
              _baseMapService.isOfflineMode ? Icons.wifi_off : Icons.wifi,
          activeIconColor: Colors.orange,
          inactiveIconColor: Colors.green,
          title: 'オフラインモード',
          subtitle: 'ネットワークを使用せず、キャッシュされた地図のみを表示',
          value: _baseMapService.isOfflineMode,
          onChanged: _toggleOfflineMode,
        ),
      ],
    );
  }

  /// キャッシュ管理セクション
  Widget _buildCacheManagementSection() {
    return SettingsSection(
      title: 'キャッシュ管理',
      trailing: Text(
        '合計: ${_cacheSizeMB.toStringAsFixed(1)} MB',
        style: const TextStyle(fontSize: 14, color: Colors.grey),
      ),
      children: [
        // キャッシュ検証・修復
        SettingsActionTile(
          leadingIcon: Icons.build,
          leadingIconColor: Colors.blue,
          title: 'キャッシュを検証・修復',
          subtitle: '破損したキャッシュを自動検出して削除',
          buttonLabel: '検証',
          buttonColor: Colors.blue,
          onPressed: _cacheStats.isNotEmpty ? _validateAndRepairCache : null,
          enabled: _cacheStats.isNotEmpty,
        ),
        const Divider(),

        // 全キャッシュクリア
        SettingsActionTile(
          leadingIcon: Icons.delete_sweep,
          leadingIconColor: Colors.red,
          title: '全キャッシュをクリア',
          subtitle:
              '${_cacheStats.values.fold(0, (sum, count) => sum + count)}タイル',
          buttonLabel: 'クリア',
          buttonColor: Colors.red,
          onPressed: _cacheStats.isNotEmpty ? () => _clearCache() : null,
          enabled: _cacheStats.isNotEmpty,
        ),
        const Divider(),

        // プロバイダー別キャッシュ情報
        const Padding(
          padding: EdgeInsets.only(left: 16, top: 8),
          child: Text(
            'プロバイダー別キャッシュ',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        if (_cacheStats.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'キャッシュされた地図データはありません',
              style: TextStyle(color: Colors.grey),
            ),
          )
        else
          ..._cacheStats.entries.map((entry) {
            final provider = BaseMapProvider.getProviderById(entry.key);
            if (provider == null) return const SizedBox.shrink();

            return SettingsTile(
              leadingIcon: provider.icon,
              leadingIconColor: Colors.grey,
              title: provider.name,
              subtitle: '${entry.value}タイル',
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'このプロバイダーのキャッシュをクリア',
                onPressed: () => _clearCache(providerId: entry.key),
              ),
            );
          }),
      ],
    );
  }
}

/// ダウンロード設定ダイアログ
class _DownloadSettingsDialog extends StatefulWidget {
  final LatLng center;
  final BaseMapProvider provider;
  final double initialRadius;
  final RangeValues initialZoomRange;
  final BaseMapService baseMapService;
  final Function(double, int, int) onStartDownload;

  const _DownloadSettingsDialog({
    required this.center,
    required this.provider,
    required this.initialRadius,
    required this.initialZoomRange,
    required this.baseMapService,
    required this.onStartDownload,
  });

  @override
  State<_DownloadSettingsDialog> createState() => _DownloadSettingsDialogState();
}

class _DownloadSettingsDialogState extends State<_DownloadSettingsDialog> {
  late double _radius;
  late RangeValues _zoomRange;
  int _estimatedTiles = 0;

  @override
  void initState() {
    super.initState();
    _radius = widget.initialRadius;
    _zoomRange = widget.initialZoomRange;
    _calculateTiles();
  }

  void _calculateTiles() {
    final result = widget.baseMapService.estimateDownloadSize(
      center: widget.center,
      radiusMeters: _radius,
      minZoom: _zoomRange.start.round(),
      maxZoom: _zoomRange.end.round(),
    );
    setState(() {
      _estimatedTiles = result['totalTiles'] ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('ダウンロード設定'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('地図: ${widget.provider.name}'),
            const SizedBox(height: 4),
            Text('中心: ${widget.center.latitude.toStringAsFixed(4)}, ${widget.center.longitude.toStringAsFixed(4)}'),
            const Divider(),
            
            const Text('範囲 (半径)', style: TextStyle(fontWeight: FontWeight.bold)),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    value: _radius,
                    min: 100,
                    max: 10000,
                    divisions: 99,
                    label: '${(_radius / 1000).toStringAsFixed(1)} km',
                    onChanged: (value) {
                      setState(() {
                        _radius = value;
                      });
                      _calculateTiles();
                    },
                  ),
                ),
                Text('${(_radius / 1000).toStringAsFixed(1)} km'),
              ],
            ),
            
            const Text('ズームレベル範囲', style: TextStyle(fontWeight: FontWeight.bold)),
            RangeSlider(
              values: _zoomRange,
              min: widget.provider.minZoom.toDouble(),
              max: widget.provider.maxZoom.toDouble(),
              divisions: widget.provider.maxZoom - widget.provider.minZoom,
              labels: RangeLabels(
                _zoomRange.start.round().toString(),
                _zoomRange.end.round().toString(),
              ),
              onChanged: (values) {
                setState(() {
                  _zoomRange = values;
                });
                _calculateTiles();
              },
            ),
            Center(child: Text('${_zoomRange.start.round()} 〜 ${_zoomRange.end.round()}')),
            
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.image, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  '推定タイル数: $_estimatedTiles 枚',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _estimatedTiles > 1000 ? Colors.red : Colors.black,
                  ),
                ),
              ],
            ),
            if (_estimatedTiles > 1000)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '注意: タイル数が多すぎます。時間がかかり、サーバー負荷の原因となります。範囲かズームレベルを絞ってください。',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('キャンセル'),
        ),
        ElevatedButton(
          onPressed: _estimatedTiles > 0 && _estimatedTiles < 5000 
            ? () => widget.onStartDownload(
                _radius, 
                _zoomRange.start.round(), 
                _zoomRange.end.round()
              ) 
            : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          child: const Text('ダウンロード開始', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

/// ダウンロード進捗ダイアログ
class _DownloadProgressDialog extends StatefulWidget {
  final LatLng center;
  final double radius;
  final int minZoom;
  final int maxZoom;
  final BaseMapService baseMapService;

  const _DownloadProgressDialog({
    required this.center,
    required this.radius,
    required this.minZoom,
    required this.maxZoom,
    required this.baseMapService,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  Map<String, dynamic> _status = {};
  bool _isFinished = false;
  
  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  void _startDownload() async {
    final stream = widget.baseMapService.downloadArea(
      center: widget.center,
      radiusMeters: widget.radius,
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
    );

    stream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
        });
        
        if (status['status'] == 'completed' || 
            status['status'] == 'cancelled' || 
            status['status'] == 'error') {
          setState(() {
            _isFinished = true;
          });
        }
      }
    }, onError: (e) {
      if (mounted) {
        setState(() {
          _status = {'status': 'error', 'message': e.toString()};
          _isFinished = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = _status['total'] as int? ?? 0;
    final processed = _status['processed'] as int? ?? 0;
    final downloaded = _status['downloaded'] as int? ?? 0;
    final skipped = _status['skipped'] as int? ?? 0;
    final errors = _status['errors'] as int? ?? 0;
    final percent = total > 0 ? processed / total : 0.0;
    final statusStr = _status['status'] as String? ?? 'init';

    return AlertDialog(
      title: const Text('ダウンロード中...'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isFinished) ...[
            LinearProgressIndicator(value: percent, minHeight: 10),
            const SizedBox(height: 8),
            Text('${(percent * 100).toStringAsFixed(1)}% 完了 ($processed / $total)'),
          ],
          const SizedBox(height: 16),
          
          if (statusStr == 'completed')
            const Center(
              child: Text(
                'ダウンロード完了！', 
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            )
          else if (statusStr == 'cancelled')
            const Center(
              child: Text(
                'キャンセルされました', 
                style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            )
          else if (statusStr == 'error')
             Text(
                'エラーが発生しました: ${_status['message']}', 
                style: const TextStyle(color: Colors.red),
              ),
              
          const Divider(),
          _buildStatRow('成功 (ダウンロード)', downloaded.toString(), Colors.blue),
          _buildStatRow('済み (スキップ)', skipped.toString(), Colors.grey),
          _buildStatRow('エラー', errors.toString(), Colors.red),
        ],
      ),
      actions: [
        if (!_isFinished)
          TextButton(
            onPressed: () {
              widget.baseMapService.cancelDownload();
            },
            child: const Text('キャンセル', style: TextStyle(color: Colors.red)),
          )
        else
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('閉じる'),
          ),
      ],
    );
  }
  
  Widget _buildStatRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }
}

