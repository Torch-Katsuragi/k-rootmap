/// K-MAPS: LayerDrawer 共通ダイアログヘルパー
/// 確認ダイアログ+操作+SnackBar パターン / リネームダイアログ
library;

import 'package:flutter/material.dart';

/// 共通リネームダイアログ（バリデーション・Enter送信付き）
class RenameDialog {
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String currentName,
    String? label,
    String? hint,
    String submitLabel = '変更',
  }) {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label, hintText: hint),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Name cannot be empty' : null,
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
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(submitLabel),
          ),
        ],
      ),
    );
  }
}

/// 確認ダイアログ → 操作実行 → SnackBar の共通パターン
/// [execute] が例外を投げた場合はエラーSnackBarを表示して false を返す
Future<bool> confirmAndExecute(
  BuildContext context, {
  required String title,
  required Widget content,
  required Future<void> Function() execute,
  String? successMessage,
  String confirmLabel = '実行',
  Color? confirmColor,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: content,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          style: confirmColor != null
              ? TextButton.styleFrom(foregroundColor: confirmColor)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    await execute();
    if (successMessage != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('エラー: $e'), backgroundColor: Colors.red),
      );
    }
    return false;
  }
}
