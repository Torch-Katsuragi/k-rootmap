/// Root Maps: LayerDrawer 共通ダイアログヘルパー
/// 確認ダイアログ+操作+通知パターン / リネームダイアログ
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../i18n/strings.g.dart';
import '../../models/app_notification.dart';
import '../../providers/notification_providers.dart';

/// 共通リネームダイアログ（バリデーション・Enter送信付き）
class RenameDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String currentName,
    String? label,
    String? hint,
    String submitLabel = '',
  }) {
    final effectiveSubmitLabel = submitLabel.isEmpty ? t.layerDrawer.submitRename : submitLabel;
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(labelText: label, hintText: hint),
                validator:
                    (v) =>
                        (v == null || v.trim().isEmpty)
                            ? t.common.nameCannotBeEmpty
                            : null,
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(context, controller.text.trim());
                  }
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t.common.cancel),
              ),
              TextButton(
                onPressed: () {
                  if (formKey.currentState?.validate() ?? false) {
                    Navigator.pop(context, controller.text.trim());
                  }
                },
                child: Text(effectiveSubmitLabel),
              ),
            ],
          ),
    );
  }
}

/// 確認ダイアログ → 操作実行 → 通知の共通パターン
/// [execute] が例外を投げた場合はエラー通知を表示して false を返す
Future<bool> confirmAndExecute(
  BuildContext context, {
  required String title,
  required Widget content,
  required Future<void> Function() execute,
  String? successMessage,
  String confirmLabel = '',
  Color? confirmColor,
  WidgetRef? ref,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(title),
          content: content,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t.common.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style:
                  confirmColor != null
                      ? TextButton.styleFrom(foregroundColor: confirmColor)
                      : null,
              child: Text(confirmLabel.isEmpty ? t.common.execute : confirmLabel),
            ),
          ],
        ),
  );
  if (confirmed != true) return false;

  try {
    await execute();
    if (successMessage != null && ref != null) {
      ref
          .read(notificationCenterProvider.notifier)
          .add(title: successMessage, level: NotificationLevel.success);
    }
    return true;
  } catch (e) {
    if (ref != null) {
      ref
          .read(notificationCenterProvider.notifier)
          .add(title: t.layerDrawer.errorPrefix(error: e.toString()), level: NotificationLevel.error);
    }
    return false;
  }
}
