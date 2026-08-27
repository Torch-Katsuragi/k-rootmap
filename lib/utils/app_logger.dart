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
import 'package:flutter/foundation.dart';

/// アプリケーション全体のロギングを管理するクラス
class AppLogger {
  /// リリースビルドでもログを出すか（`--dart-define=K_LOG=true`）
  ///
  /// ⚠ **web のリリースビルドは `kDebugMode` が false** なので、既定だと
  /// ログが1行も出ない。ブラウザでしか再現しない不具合を追うときは
  /// これを付けてビルドし、devtools のコンソールを読むこと。
  /// 2026-08-26 と 08-27 に、これが無くて2回とも当て推量で時間を溶かした。
  static const bool _forceLog = bool.fromEnvironment('K_LOG');

  /// ログを出す条件
  static bool get _enabled => kDebugMode || _forceLog;

  /// 一般的なログ出力
  static void log(Object? message) {
    if (_enabled) {
      debugPrint('[LOG] $message');
    }
  }

  /// エラーログ出力
  static void error(Object? message, [dynamic error, StackTrace? stackTrace]) {
    if (_enabled) {
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
    if (_enabled) {
      debugPrint('[DEBUG] $message');
    }
  }
}
