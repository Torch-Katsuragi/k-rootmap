import 'package:flutter/material.dart';

/// 通知の重要度レベル
enum NotificationLevel {
  info(Icons.info_outline, Colors.blue),
  success(Icons.check_circle_outline, Colors.green),
  warning(Icons.warning_amber_rounded, Colors.orange),
  error(Icons.error_outline, Colors.red);

  final IconData icon;
  final Color color;
  const NotificationLevel(this.icon, this.color);
}

/// アプリ内通知データ
class AppNotification {
  final String id;
  final String title;
  final String? detail;
  final NotificationLevel level;
  final DateTime timestamp;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    this.detail,
    this.level = NotificationLevel.info,
    DateTime? timestamp,
    this.isRead = false,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isExpandable => detail != null && detail!.isNotEmpty;
}
