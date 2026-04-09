// 地図画面のAppBarアクションボタン群
import 'package:flutter/material.dart';
import '../i18n/strings.g.dart';
import '../screens/settings_screen.dart';
import 'notification/notification_bell.dart';

/// 地図画面AppBarの右側アクションボタン群を生成する関数
List<Widget> buildMapAppBarActions({
  required BuildContext context,
  required bool showAttributeTable,
  required bool drawerOpen,
  required VoidCallback onAttributeTableToggle,
  required VoidCallback onDrawerToggle,
}) {
  return [
    const NotificationBell(),
    IconButton(
      icon: const Icon(Icons.settings),
      tooltip: t.common.settings,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SettingsScreen()),
        );
      },
    ),
    // 属性テーブルボタン
    IconButton(
      icon: Icon(
        Icons.table_view,
        color: showAttributeTable ? Colors.blue : null,
      ),
      tooltip: showAttributeTable ? t.attributeTable.closeTable : t.attributeTable.openTable,
      onPressed: onAttributeTableToggle,
    ),
    // レイヤードロワーボタン
    IconButton(
      icon: Icon(Icons.layers, color: drawerOpen ? Colors.blue : null),
      tooltip: drawerOpen ? 'Close Layer Drawer' : 'Open Layer Drawer',
      onPressed: onDrawerToggle,
    ),
  ];
}
