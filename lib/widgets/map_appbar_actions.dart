// 地図画面のAppBarアクションボタン群
import 'package:flutter/material.dart';
import '../screens/basemap_settings_screen.dart';
import '../screens/gps_settings_screen.dart';

/// 地図画面AppBarの右側アクションボタン群を生成する関数
List<Widget> buildMapAppBarActions({
  required BuildContext context,
  required bool showAttributeTable,
  required bool drawerOpen,
  required VoidCallback onAttributeTableToggle,
  required VoidCallback onDrawerToggle,
}) {
  return [
      // 背景地図設定ボタン
      IconButton(
        icon: const Icon(Icons.map_outlined),
        tooltip: '背景地図設定',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const BaseMapSettingsScreen(),
            ),
          );
        },
      ),
      // GPS設定ボタン
      IconButton(
        icon: const Icon(Icons.gps_fixed),
        tooltip: 'GPS設定',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const GpsSettingsScreen(),
            ),
          );
        },
      ),
      // 属性テーブルボタン
      IconButton(
        icon: Icon(
          Icons.table_view,
          color: showAttributeTable ? Colors.blue : null,
        ),
        tooltip: showAttributeTable ? '属性テーブルを閉じる' : '属性テーブルを開く',
        onPressed: onAttributeTableToggle,
      ),
      // レイヤードロワーボタン
      IconButton(
        icon: Icon(
          Icons.layers,
          color: drawerOpen ? Colors.blue : null,
        ),
        tooltip: drawerOpen ? 'Close Layer Drawer' : 'Open Layer Drawer',
        onPressed: onDrawerToggle,
      ),
  ];
}

