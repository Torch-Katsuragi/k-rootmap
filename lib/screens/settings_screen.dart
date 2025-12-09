import 'package:flutter/material.dart';
import 'basemap_settings_screen.dart';
import 'gps_settings_screen.dart';

/// 設定カテゴリー定義
enum SettingsCategory {
  basemap,
  gps,
  // 将来的なカテゴリーはここに追加
  // general,
  // account,
}

extension SettingsCategoryExt on SettingsCategory {
  String get title {
    switch (this) {
      case SettingsCategory.basemap:
        return '地図・タイル';
      case SettingsCategory.gps:
        return 'GPS・測位';
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsCategory.basemap:
        return Icons.map;
      case SettingsCategory.gps:
        return Icons.gps_fixed;
    }
  }

  String get description {
    switch (this) {
      case SettingsCategory.basemap:
        return '背景地図、オフライン地図、キャッシュ管理';
      case SettingsCategory.gps:
        return 'GPSソース選択、外部GNSS接続';
    }
  }
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

  /// 狭い画面（スマホ等）用レイアウト
  Widget _buildNarrowLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: ListView(
        children: SettingsCategory.values.map((category) {
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
                    children: SettingsCategory.values.map((category) {
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
      case SettingsCategory.basemap:
        return BaseMapSettingsScreen(key: key, isEmbedded: isEmbedded);
      case SettingsCategory.gps:
        return GpsSettingsScreen(key: key, isEmbedded: isEmbedded);
    }
  }
}
