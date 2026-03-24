import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../models/app_notification.dart';

part 'notification_providers.g.dart';

const _maxNotifications = 100;

/// アプリ内通知の中央管理
@Riverpod(keepAlive: true)
class NotificationCenter extends _$NotificationCenter {
  @override
  List<AppNotification> build() => [];

  /// 通知を追加（先頭挿入、上限超過で末尾削除）
  void add({
    required String title,
    String? detail,
    NotificationLevel level = NotificationLevel.info,
  }) {
    final notification = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      detail: detail,
      level: level,
    );
    state = [notification, ...state.take(_maxNotifications - 1)];
  }

  void markAsRead(String id) {
    final idx = state.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    state[idx].isRead = true;
    state = [...state];
  }

  void markAllAsRead() {
    for (final n in state) {
      n.isRead = true;
    }
    state = [...state];
  }

  void clear() => state = [];
}

/// 未読通知数
@Riverpod(keepAlive: true)
int unreadNotificationCount(Ref ref) {
  final notifications = ref.watch(notificationCenterProvider);
  return notifications.where((n) => !n.isRead).length;
}
