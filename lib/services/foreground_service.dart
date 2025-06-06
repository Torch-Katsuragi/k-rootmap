// K-MAPS: フォアグラウンドサービス管理クラス
// 1秒間隔でログ出力を行う最小限のフォアグラウンドサービス実装（GPS情報付き）
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

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
        initialNotificationTitle: 'K-MAPS GPS追跡実行中',
        initialNotificationContent: '1秒間隔でGPS情報をログ出力中...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // iOS向けの設定（現在は最小限）
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    debugPrint('[ForegroundService] サービス初期化完了（GPS対応）');
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
      debugPrint('[ForegroundService] GPS追跡サービス開始成功');
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
      debugPrint('[ForegroundService] GPS追跡サービス停止要求送信');
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

    debugPrint('[ForegroundService] GPS追跡サービスエントリーポイント開始');

    // GPS初期設定
    Position? lastKnownPosition;
    bool isLocationServiceEnabled = false;
    LocationPermission permission = LocationPermission.denied;

    // 位置情報サービスの確認と権限チェック
    try {
      isLocationServiceEnabled = await Geolocator.isLocationServiceEnabled();
      permission = await Geolocator.checkPermission();

      debugPrint(
        '[ForegroundService] GPS設定確認 - サービス: $isLocationServiceEnabled, 権限: $permission',
      );

      // 権限がない場合は要求（UI側で事前に取得している前提）
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
    } catch (e) {
      debugPrint('[ForegroundService] GPS初期化エラー: $e');
    }

    // サービス停止要求の監視を設定
    service.on('stopService').listen((event) {
      debugPrint('[ForegroundService] 停止要求受信');
      service.stopSelf();
    });

    // 1秒間隔のタイマー設定（GPS情報付き）
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        // GPS情報取得を試行
        String gpsInfo = "GPS: 取得中...";

        if (isLocationServiceEnabled &&
            (permission == LocationPermission.always ||
                permission == LocationPermission.whileInUse)) {
          try {
            // 現在位置を取得（タイムアウト設定）
            Position currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 5),
            );

            lastKnownPosition = currentPosition;
            gpsInfo =
                "GPS: ${currentPosition.latitude.toStringAsFixed(6)}, "
                "${currentPosition.longitude.toStringAsFixed(6)} "
                "(精度: ${currentPosition.accuracy.toStringAsFixed(1)}m)";
          } catch (e) {
            // 取得に失敗した場合は最後の既知位置を使用
            if (lastKnownPosition != null) {
              gpsInfo =
                  "GPS: ${lastKnownPosition!.latitude.toStringAsFixed(6)}, "
                  "${lastKnownPosition!.longitude.toStringAsFixed(6)} "
                  "(前回取得値)";
            } else {
              gpsInfo = "GPS: 位置情報取得エラー - $e";
            }
          }
        } else {
          gpsInfo =
              "GPS: 無効または権限なし (サービス: $isLocationServiceEnabled, 権限: $permission)";
        }

        // サービス停止チェック
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            // フォアグラウンドサービスとして実行中
            _logCurrentTimeWithGPS('[ForegroundService] フォアグラウンド実行中', gpsInfo);

            // 通知内容を更新（GPS情報付き）
            String notificationContent =
                "GPS追跡中: ${DateTime.now().toString().substring(11, 19)}";
            if (lastKnownPosition != null) {
              notificationContent +=
                  "\n位置: ${lastKnownPosition!.latitude.toStringAsFixed(4)}, ${lastKnownPosition!.longitude.toStringAsFixed(4)}";
            }

            service.setForegroundNotificationInfo(
              title: "K-MAPS GPS追跡実行中",
              content: notificationContent,
            );
          }
        } else {
          // iOS向けログ出力
          _logCurrentTimeWithGPS('[ForegroundService] iOS実行中', gpsInfo);
        }
      } catch (e) {
        debugPrint('[ForegroundService] タイマー処理エラー: $e');
        timer.cancel();
        service.stopSelf();
      }
    });

    debugPrint('[ForegroundService] GPS追跡定期実行タスク開始（1秒間隔）');
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

/// GPS情報付き現在時刻ログ出力ヘルパー関数
/// デバッグ出力の統一化とタイムスタンプ・GPS情報付加
void _logCurrentTimeWithGPS(String message, String gpsInfo) {
  final now = DateTime.now();
  final timeStr =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';

  final fullMessage = '$message - $timeStr | $gpsInfo';

  debugPrint(fullMessage);

  // 実際のprint文での出力（デバッグコンソール用）
  print(fullMessage);
}
