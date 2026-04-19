// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
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
