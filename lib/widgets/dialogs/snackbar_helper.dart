import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';

/// 通知ヘルパー（NotificationCenterへの通知追加を簡潔に記述）
class NotificationHelper {
  static void success(WidgetRef ref, String title, {String? detail}) => ref
      .read(notificationCenterProvider.notifier)
      .add(title: title, detail: detail, level: NotificationLevel.success);

  static void error(WidgetRef ref, String title, {String? detail}) => ref
      .read(notificationCenterProvider.notifier)
      .add(title: title, detail: detail, level: NotificationLevel.error);

  static void warning(WidgetRef ref, String title, {String? detail}) => ref
      .read(notificationCenterProvider.notifier)
      .add(title: title, detail: detail, level: NotificationLevel.warning);

  static void info(WidgetRef ref, String title, {String? detail}) => ref
      .read(notificationCenterProvider.notifier)
      .add(title: title, detail: detail, level: NotificationLevel.info);
}
