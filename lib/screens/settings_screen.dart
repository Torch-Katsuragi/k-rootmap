import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'basemap_settings_screen.dart';
import 'gps_settings_screen.dart';
import 'layer_style_settings_screen.dart';
import '../services/google_drive/auto_sync_service.dart';
import '../providers/project_providers.dart';
import '../utils/folder_utils.dart';
import '../widgets/settings_widgets.dart';
import '../models/app_notification.dart';
import '../providers/notification_providers.dart';

/// グローバルフォルダのカスタムパス用SharedPreferencesキー
const kGlobalFolderCustomPathKey = 'global_folder_custom_path';

/// 設定カテゴリー定義
enum SettingsCategory {
  general,
  basemap,
  gps,
  layerStyle,
  sync,
  feedback,
  appInfo,
}

extension SettingsCategoryExt on SettingsCategory {
  String get title => switch (this) {
    SettingsCategory.general => '一般',
    SettingsCategory.basemap => '地図・タイル',
    SettingsCategory.gps => 'GPS・測位',
    SettingsCategory.layerStyle => 'レイヤ描画',
    SettingsCategory.sync => 'Drive同期',
    SettingsCategory.feedback => 'フィードバック',
    SettingsCategory.appInfo => 'アプリ情報',
  };

  IconData get icon => switch (this) {
    SettingsCategory.general => Icons.settings,
    SettingsCategory.basemap => Icons.map,
    SettingsCategory.gps => Icons.gps_fixed,
    SettingsCategory.layerStyle => Icons.palette,
    SettingsCategory.sync => Icons.sync,
    SettingsCategory.feedback => Icons.feedback,
    SettingsCategory.appInfo => Icons.info_outline,
  };

  String get description => switch (this) {
    SettingsCategory.general => 'グローバルフォルダ設定',
    SettingsCategory.basemap => '背景地図、オフライン地図、キャッシュ管理',
    SettingsCategory.gps => 'GPSソース選択、外部GNSS接続',
    SettingsCategory.layerStyle => '点・線・ポリゴンの描画スタイル',
    SettingsCategory.sync => 'WiFi自動同期、同期間隔',
    SettingsCategory.feedback => '要望・バグ報告をお送りください',
    SettingsCategory.appInfo => 'バージョン情報、ライセンス',
  };
}

/// 統合設定画面
/// 
/// レスポンシブ対応:
/// - 横幅が狭い場合: カテゴリーリストのみ表示 -> 遷移
/// - 横幅が広い場合: 左にカテゴリーリスト、右に詳細画面 (Split View)
class SettingsScreen extends StatefulWidget {
  final SettingsCategory initialCategory;

  const SettingsScreen({
    super.key,
    this.initialCategory = SettingsCategory.basemap,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late SettingsCategory _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 横幅600以上をワイド画面（Split View）とする
        final isWide = constraints.maxWidth >= 600;

        if (isWide) {
          return _buildWideLayout();
        } else {
          return _buildNarrowLayout();
        }
      },
    );
  }

  List<SettingsCategory> get _visibleCategories => SettingsCategory.values
      .where((c) => c != SettingsCategory.sync || _isMobile)
      .toList();

  static bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// 狭い画面（スマホ等）用レイアウト
  Widget _buildNarrowLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: _visibleCategories.map((category) {
          return ListTile(
            leading: Icon(category.icon, color: Colors.blueGrey),
            title: Text(category.title),
            subtitle: Text(category.description, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => _buildSettingsContent(category, isEmbedded: false),
                ),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  /// 広い画面（タブレット・PC等）用レイアウト
  Widget _buildWideLayout() {
    return Scaffold(
      body: Row(
        children: [
          // 左側: カテゴリーリスト
          SizedBox(
            width: 280,
            child: Column(
              children: [
                AppBar(
                  title: const Text('設定'),
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  automaticallyImplyLeading: true, // 戻るボタンを表示
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: _visibleCategories.map((category) {
                      final isSelected = category == _selectedCategory;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: isSelected
                            ? BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              )
                            : null,
                        child: ListTile(
                          leading: Icon(
                            category.icon,
                            color: isSelected
                                ? Theme.of(context).colorScheme.onPrimaryContainer
                                : Colors.blueGrey,
                          ),
                          title: Text(
                            category.title,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.onPrimaryContainer
                                  : null,
                            ),
                          ),
                          onTap: () {
                            setState(() {
                              _selectedCategory = category;
                            });
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          
          // 境界線
          const VerticalDivider(width: 1),
          
          // 右側: 詳細コンテンツ
          Expanded(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: _buildSettingsContent(_selectedCategory, isEmbedded: true),
            ),
          ),
        ],
      ),
    );
  }

  /// カテゴリーに対応する設定画面を返す
  Widget _buildSettingsContent(SettingsCategory category, {required bool isEmbedded}) {
    // Note: キーを付与することで、カテゴリー切り替え時にWidgetを再構築させる
    // これによりスクロール位置や状態のリセットが適切に行われる
    final key = ValueKey('settings_${category.name}');
    
    switch (category) {
      case SettingsCategory.general:
        return GeneralSettingsScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.basemap:
        return BaseMapSettingsScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.gps:
        return GpsSettingsScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.layerStyle:
        return LayerStyleSettingsScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.sync:
        return SyncSettingsScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.feedback:
        return FeedbackScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.appInfo:
        return AppInfoScreen(key: key, isEmbedded: isEmbedded);
    }
  }
}

/// フィードバック画面
class FeedbackScreen extends ConsumerWidget {
  final bool isEmbedded;
  
  /// Google Forms フィードバックURL
  static const _feedbackUrl = 'https://forms.gle/zQEHoHt1d9nXzW5x7';

  const FeedbackScreen({
    super.key,
    this.isEmbedded = false,
  });

  Future<void> _openFeedbackForm(WidgetRef ref) async {
    final uri = Uri.parse(_feedbackUrl);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        ref.read(notificationCenterProvider.notifier).add(
              title: 'ブラウザを開けませんでした',
              level: NotificationLevel.error,
            );
      }
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
            title: 'エラーが発生しました: $e',
            level: NotificationLevel.error,
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsScaffold(
      title: 'フィードバック',
      isEmbedded: isEmbedded,
      body: SettingsBody(
        sections: [
          SettingsHighlightSection(
            title: 'ご意見・ご要望をお聞かせください',
            icon: Icons.mail_outline,
            iconColor: Colors.blue,
            backgroundColor: Colors.blue.shade50,
            description:
                'K-MAPSをより良いアプリにするために、'
                'あなたのフィードバックをお待ちしています。\n\n'
                '機能の要望やバグ報告など、お気軽にお送りください。'
                '開発の参考にさせていただきます。',
            actionButton: ElevatedButton.icon(
              onPressed: () => _openFeedbackForm(ref),
              icon: const Icon(Icons.open_in_new),
              label: const Text('フィードバックフォームを開く'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          SettingsSection(
            title: 'フィードバックの種類',
            icon: Icons.category,
            iconColor: Colors.orange,
            children: [
              const ListTile(
                leading: Icon(Icons.lightbulb_outline, color: Colors.amber),
                title: Text('機能の要望'),
                subtitle: Text('こんな機能があったら便利！というアイデア'),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.bug_report, color: Colors.red),
                title: Text('バグ報告'),
                subtitle: Text('動作がおかしい、エラーが出るなどの問題'),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(Icons.thumb_up_outlined, color: Colors.green),
                title: Text('その他'),
                subtitle: Text('感想、質問、改善提案など何でも'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// アプリ情報画面
class AppInfoScreen extends StatefulWidget {
  final bool isEmbedded;

  const AppInfoScreen({
    super.key,
    this.isEmbedded = false,
  });

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'アプリ情報',
      isEmbedded: widget.isEmbedded,
      body: SettingsBody(
        sections: [
          SettingsSection(
            title: 'K-MAPS',
            icon: Icons.map,
            iconColor: Colors.blue,
            children: [
              ListTile(
                leading: const Icon(Icons.numbers, color: Colors.blueGrey),
                title: const Text('バージョン'),
                subtitle: Text(
                  _packageInfo != null
                      ? '${_packageInfo!.version} (ビルド ${_packageInfo!.buildNumber})'
                      : '読み込み中...',
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.android, color: Colors.green),
                title: const Text('パッケージ名'),
                subtitle: Text(_packageInfo?.packageName ?? '読み込み中...'),
              ),
            ],
          ),
          SettingsSection(
            title: '概要',
            icon: Icons.description,
            iconColor: Colors.teal,
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'K-MAPSはFlutter製のクロスプラットフォーム地図アプリケーションです。\n\n'
                  'GeoPackage形式でのデータ管理、GPS測量・軌跡記録、'
                  '外部GNSS機器連携、オフライン地図対応などの機能を提供します。',
                  style: TextStyle(height: 1.5),
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'ライセンス',
            icon: Icons.gavel,
            iconColor: Colors.orange,
            children: [
              ListTile(
                leading: const Icon(Icons.open_in_new, color: Colors.blue),
                title: const Text('オープンソースライセンス'),
                subtitle: const Text('使用しているパッケージのライセンス一覧'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'K-MAPS',
                    applicationVersion: _packageInfo?.version ?? '',
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 一般設定画面（PC専用: グローバルフォルダパス設定）
class GeneralSettingsScreen extends ConsumerStatefulWidget {
  final bool isEmbedded;
  const GeneralSettingsScreen({super.key, this.isEmbedded = false});

  @override
  ConsumerState<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends ConsumerState<GeneralSettingsScreen> {
  String? _customPath;
  String _defaultPath = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final appDir = await getApplicationDocumentsDirectory();
    _defaultPath = p.join(appDir.path, 'k_maps_global');
    _customPath = prefs.getString(kGlobalFolderCustomPathKey);
    if (mounted) setState(() => _isLoading = false);
  }

  String get _effectivePath => _customPath ?? _defaultPath;
  bool get _isCustom => _customPath != null;

  Future<void> _pickFolder() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Global Folder',
    );
    if (dir == null) return;

    // 含有関係チェック（プロジェクトフォルダが開いている場合）
    final projectDir = ref.read(projectRootDirProvider);
    if (projectDir != null) {
      final warning = checkContainmentRelation(dir, projectDir);
      if (warning != null && mounted) {
        final proceed = await _showContainmentWarning(warning);
        if (!proceed) return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kGlobalFolderCustomPathKey, dir);
    setState(() => _customPath = dir);

    // 実行中のプロバイダに反映
    ref.read(globalFolderPathProvider.notifier).set(dir);

    ref.read(notificationCenterProvider.notifier).add(
          title: 'Global folder updated. Restart the app to take full effect.',
          level: NotificationLevel.info,
        );
  }

  Future<void> _resetToDefault() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kGlobalFolderCustomPathKey);
    setState(() => _customPath = null);
    ref.read(globalFolderPathProvider.notifier).set(_defaultPath);

    ref.read(notificationCenterProvider.notifier).add(
          title: 'Global folder reset to default. Restart the app to take full effect.',
          level: NotificationLevel.info,
        );
  }

  Future<bool> _showContainmentWarning(String message) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
        title: const Text('Folder Containment Warning'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use Anyway'),
          ),
        ],
      ),
    ) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: '一般',
      isEmbedded: widget.isEmbedded,
      isLoading: _isLoading,
      body: SettingsBody(
        sections: [
          SettingsSection(
            title: 'Global Folder',
            icon: Icons.folder_special,
            iconColor: Colors.blue,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'The global folder is shared across all projects.\n'
                  'GPS history, shared GeoPackages, and other global data are stored here.',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Icon(
                  _isCustom ? Icons.folder : Icons.folder_outlined,
                  color: _isCustom ? Colors.blue : Colors.blueGrey,
                ),
                title: Text(_isCustom ? 'Custom Path' : 'Default Path'),
                subtitle: Text(
                  _effectivePath,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _pickFolder,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Change Folder'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    if (_isCustom) ...[
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _resetToDefault,
                        icon: const Icon(Icons.restore),
                        label: const Text('Reset'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Info',
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Changing the global folder does not migrate existing data.\n'
                  'The new folder will be created automatically if it does not exist.\n\n'
                  'The global folder and project folder must not overlap '
                  '(one containing the other).',
                  style: TextStyle(height: 1.5, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Drive同期設定画面
class SyncSettingsScreen extends StatefulWidget {
  final bool isEmbedded;
  const SyncSettingsScreen({super.key, this.isEmbedded = false});

  @override
  State<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends State<SyncSettingsScreen> {
  bool _autoSyncEnabled = true;
  int _intervalMinutes = kAutoSyncDefaultInterval;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoSyncEnabled = prefs.getBool(kAutoSyncEnabledKey) ?? true;
      _intervalMinutes =
          prefs.getInt(kAutoSyncIntervalKey) ?? kAutoSyncDefaultInterval;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: 'Drive同期',
      isEmbedded: widget.isEmbedded,
      body: SettingsBody(
        sections: [
          SettingsSection(
            title: 'Auto Sync',
            icon: Icons.sync,
            iconColor: Colors.blue,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.wifi, color: Colors.blue),
                title: const Text('WiFi Auto Sync'),
                subtitle: const Text('Sync automatically when connected to WiFi'),
                value: _autoSyncEnabled,
                onChanged: (v) async {
                  setState(() => _autoSyncEnabled = v);
                  await AutoSyncService.instance.setEnabled(v);
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.timer, color: Colors.blueGrey),
                title: const Text('Sync Interval'),
                subtitle: Text('Every $_intervalMinutes min'),
                trailing: DropdownButton<int>(
                  value: _intervalMinutes,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('1 min')),
                    DropdownMenuItem(value: 3, child: Text('3 min')),
                    DropdownMenuItem(value: 5, child: Text('5 min')),
                    DropdownMenuItem(value: 10, child: Text('10 min')),
                    DropdownMenuItem(value: 30, child: Text('30 min')),
                  ],
                  onChanged: (v) async {
                    if (v == null) return;
                    setState(() => _intervalMinutes = v);
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt(kAutoSyncIntervalKey, v);
                  },
                ),
              ),
            ],
          ),
          SettingsSection(
            title: 'Info',
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            children: const [
              Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Auto sync runs only over WiFi to save mobile data.\n\n'
                  'When both local and Drive have changes to the same file '
                  '(conflict), sync pauses and shows a warning on the folder. '
                  'Tap the subtitle to resolve manually.',
                  style: TextStyle(height: 1.5, color: Colors.grey),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
