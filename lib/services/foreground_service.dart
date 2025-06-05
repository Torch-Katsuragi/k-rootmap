// K-MAPS: フォアグラウンドサービス管理クラス
// 1秒間隔でログ出力を行う最小限のフォアグラウンドサービス実装
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

/// フォアグラウンドサービス管理クラス
/// シングルトンパターンで実装し、サービスの開始・停止を管理
class ForegroundServiceManager {
  // シングルトンインスタンス
  static final ForegroundServiceManager _instance =
      ForegroundServiceManager._internal();
  factory ForegroundServiceManager() => _instance;
  ForegroundServiceManager._internal();

  /// サービス実行フラグ
  bool _isServiceRunning = false;

  /// サービスの初期化
  /// アプリ起動時に呼び出される
  static Future<void> initializeService() async {
    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // サービスエントリーポイント（@pragma('vm:entry-point')が必要）
        onStart: onStart,

        // オートスタート（アプリ起動時に自動開始）
        autoStart: false,

        // フォアグラウンドモードとして実行
        isForegroundMode: true,

        // 通知設定（詳細に設定）
        notificationChannelId: 'k_maps_foreground_channel',
        initialNotificationTitle: 'K-MAPS サービス実行中',
        initialNotificationContent: '1秒間隔でログ出力を行っています...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // iOS向けの設定（現在は最小限）
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    debugPrint('[ForegroundService] サービス初期化完了');
  }

  /// サービス開始
  Future<void> startService() async {
    if (_isServiceRunning) {
      debugPrint('[ForegroundService] サービスは既に実行中です');
      return;
    }

    try {
      await FlutterBackgroundService().startService();
      _isServiceRunning = true;
      debugPrint('[ForegroundService] サービス開始成功');
    } catch (e) {
      debugPrint('[ForegroundService] サービス開始エラー: $e');
    }
  }

  /// サービス停止
  Future<void> stopService() async {
    if (!_isServiceRunning) {
      debugPrint('[ForegroundService] サービスは実行中ではありません');
      return;
    }

    try {
      FlutterBackgroundService().invoke("stopService");
      _isServiceRunning = false;
      debugPrint('[ForegroundService] サービス停止要求送信');
    } catch (e) {
      debugPrint('[ForegroundService] サービス停止エラー: $e');
    }
  }

  /// サービス実行状態取得
  bool get isServiceRunning => _isServiceRunning;
}

/// サービスのエントリーポイント
/// この関数はIsolateで実行されるため、@pragma('vm:entry-point')が必要
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  try {
    // Isolate内でのデバッグ出力設定
    DartPluginRegistrant.ensureInitialized();

    debugPrint('[ForegroundService] サービスエントリーポイント開始');

    // サービス停止要求の監視を設定
    service.on('stopService').listen((event) {
      debugPrint('[ForegroundService] 停止要求受信');
      service.stopSelf();
    });

    // 1秒間隔のタイマー設定
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        // サービス停止チェック
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            // フォアグラウンドサービスとして実行中
            _logCurrentTime('[ForegroundService] フォアグラウンド実行中');

            // 通知内容を更新（現在時刻を表示）
            service.setForegroundNotificationInfo(
              title: "K-MAPS サービス実行中",
              content: "実行時刻: ${DateTime.now().toString().substring(11, 19)}",
            );
          }
        } else {
          // iOS向けログ出力
          _logCurrentTime('[ForegroundService] iOS実行中');
        }
      } catch (e) {
        debugPrint('[ForegroundService] タイマー処理エラー: $e');
        timer.cancel();
        service.stopSelf();
      }
    });

    debugPrint('[ForegroundService] 定期実行タスク開始（1秒間隔）');
  } catch (e) {
    debugPrint('[ForegroundService] エントリーポイントエラー: $e');
    service.stopSelf();
  }
}

/// iOS向けバックグラウンド処理
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  debugPrint('[ForegroundService] iOS バックグラウンド処理');
  return true;
}

/// 現在時刻付きログ出力ヘルパー関数
/// デバッグ出力の統一化とタイムスタンプ付加
void _logCurrentTime(String message) {
  final now = DateTime.now();
  final timeStr =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';

  debugPrint('$message - $timeStr');

  // 実際のprint文での出力（デバッグコンソール用）
  print('$message - $timeStr');
}
