import 'package:flutter/foundation.dart';

/// アプリケーション全体のロギングを管理するクラス
class AppLogger {
  /// 一般的なログ出力
  static void log(Object? message) {
    if (kDebugMode) {
      debugPrint('[LOG] $message');
    }
  }

  /// エラーログ出力
  static void error(Object? message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[ERROR] $message');
      if (error != null) {
        debugPrint(error.toString());
      }
      if (stackTrace != null) {
        debugPrint(stackTrace.toString());
      }
    }
  }

  /// デバッグ用ログ出力
  static void debug(Object? message) {
    if (kDebugMode) {
      debugPrint('[DEBUG] $message');
    }
  }
}
