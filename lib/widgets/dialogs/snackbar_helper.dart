import 'package:flutter/material.dart';

/// SnackBar表示のヘルパー
/// 成功・エラー・情報メッセージのSnackBarを統一的に表示する
class SnackBarHelper {
  static void showSuccess(BuildContext context, String message) {
    _show(context, message, backgroundColor: Colors.green);
  }

  static void showError(BuildContext context, String message) {
    _show(context, message, backgroundColor: Colors.red, duration: 4);
  }

  static void showInfo(BuildContext context, String message) {
    _show(context, message);
  }

  static void showWarning(BuildContext context, String message) {
    _show(context, message, backgroundColor: Colors.orange);
  }

  static void _show(
    BuildContext context,
    String message, {
    Color? backgroundColor,
    int duration = 2,
  }) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: Duration(seconds: duration),
      ),
    );
  }
}
