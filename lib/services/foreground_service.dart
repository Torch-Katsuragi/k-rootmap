// Root Maps: フォアグラウンドサービス管理クラス
// Android: アプリ起動時から常時稼働し、1秒間隔で位置情報をメインisolateに送信
// InternalGpsLocationStore の delegatedモード のバックエンドとして機能
import 'dart:async';
import 'dart:ui';
import 'package:root_maps/utils/app_logger.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';

/// フォアグラウンドサービス管理クラス
/// シングルトンパターンで実装し、サービスの開始・停止を管理
///
/// InternalGpsLocationStore.start() から呼び出される。
/// 直接使用せず、Store経由でアクセスすること。
class ForegroundServiceManager {
  // シングルトンインスタンス
  static final ForegroundServiceManager _instance =
      ForegroundServiceManager._internal();
  factory ForegroundServiceManager() => _instance;
  ForegroundServiceManager._internal();

  /// 初期化済みフラグ（configure()が完了したか）
  bool _isConfigured = false;

  /// サービスの初期化（configure）
  /// アプリ起動時にInternalGpsLocationStoreから呼び出される
  Future<void> initializeService() async {
    if (_isConfigured) return;

    final service = FlutterBackgroundService();

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        // サービスエントリーポイント（@pragma('vm:entry-point')が必要）
        onStart: onStart,

        // Store.start()が明示的に起動する
        autoStart: false,

        // フォアグラウンドモードとして実行
        isForegroundMode: true,

        // 通知設定
        notificationChannelId: 'k_maps_foreground_channel',
        initialNotificationTitle: 'K-RootMap GPS取得中',
        initialNotificationContent: 'GPS位置情報を取得しています...',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        // iOS向けの設定（現在は最小限）
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isConfigured = true;
    AppLogger.debug('[ForegroundService] configure完了');
  }

  /// サービス開始
  /// InternalGpsLocationStore._startDelegated() から呼び出される
  ///
  /// 重要: Dartのフラグではなく、FlutterBackgroundService.isRunning() で
  /// 実際のサービス状態を確認する。デバッグ終了後の再起動や
  /// プロセス再生成でDartフラグがリセットされても正しく動作する。
  Future<void> startService() async {
    try {
      // 実際のサービス状態を確認（Dart側のフラグではなくOS側に問い合わせ）
      final service = FlutterBackgroundService();
      final alreadyRunning = await service.isRunning();

      if (alreadyRunning) {
        // 前回のセッションからサービスが生き残っている場合
        // → まず停止して、クリーンな状態から再起動
        AppLogger.debug('[ForegroundService] 既存サービスを検出、再起動します');
        service.invoke("stopService");
        // サービス停止を少し待機
        await Future.delayed(const Duration(milliseconds: 500));
      }

      await service.startService();
      AppLogger.debug('[ForegroundService] GPS位置取得サービス開始');
    } catch (e) {
      AppLogger.debug('[ForegroundService] サービス開始エラー: $e');
      AppLogger.debug('[ForegroundService] エラー詳細: ${e.toString()}');
      rethrow;
    }
  }

  /// サービス停止
  /// InternalGpsLocationStore.stop() から呼び出される
  Future<void> stopService() async {
    try {
      final service = FlutterBackgroundService();
      final isRunning = await service.isRunning();

      if (isRunning) {
        service.invoke("stopService");
        AppLogger.debug('[ForegroundService] GPS位置取得サービス停止');
      } else {
        AppLogger.debug('[ForegroundService] サービスは既に停止済み');
      }
    } catch (e) {
      AppLogger.debug('[ForegroundService] サービス停止エラー: $e');
    }
  }

  /// アプリ終了時のクリーンアップ（強制停止）
  Future<void> dispose() async {
    try {
      FlutterBackgroundService().invoke("stopService");
    } catch (_) {}
    AppLogger.debug('[ForegroundService] クリーンアップ完了');
  }

  /// サービス実行状態取得（OS側に問い合わせ）
  Future<bool> isServiceRunning() async {
    try {
      return await FlutterBackgroundService().isRunning();
    } catch (_) {
      return false;
    }
  }
}

/// サービスのエントリーポイント
/// この関数はIsolateで実行されるため、@pragma('vm:entry-point')が必要
/// 注意: フォアグラウンドサービスは内蔵GPSのみを使用（外部GNSSはメインisolateで処理）
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  try {
    // Isolate内でのデバッグ出力設定
    DartPluginRegistrant.ensureInitialized();

    // 内蔵GPS専用の位置情報ストリーム
    StreamSubscription<Position>? positionSubscription;
    Position? lastPosition;
    Timer? periodicTimer;

    // 内蔵GPS位置情報ストリームを開始
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((position) {
      lastPosition = position;
    });

    // サービス停止要求の監視を設定
    service.on('stopService').listen((event) {
      periodicTimer?.cancel();
      positionSubscription?.cancel();
      service.stopSelf();
    });

    // 1秒間隔で位置情報をメインisolateに送信
    periodicTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final currentPosition = lastPosition;

        if (currentPosition != null) {
          // メインisolateに位置情報を送信（positionUpdateイベント）
          final pointData = {
            'latitude': currentPosition.latitude,
            'longitude': currentPosition.longitude,
            'altitude': currentPosition.altitude,
            'accuracy': currentPosition.accuracy,
            'speed': currentPosition.speed,
            'bearing': currentPosition.heading,
            'timestamp': DateTime.now().toIso8601String(),
            'sourceType': 'GPS',
          };
          service.invoke('positionUpdate', pointData);
        }

        // Android通知更新
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            try {
              String notificationContent =
                  "GPS取得中: ${DateTime.now().toString().substring(11, 19)}";
              if (currentPosition != null) {
                notificationContent +=
                    "\n${currentPosition.latitude.toStringAsFixed(4)}, ${currentPosition.longitude.toStringAsFixed(4)}";
              }
              service.setForegroundNotificationInfo(
                title: "K-RootMap GPS取得中",
                content: notificationContent,
              );
            } catch (_) {
              // 通知更新エラーは無視
            }
          }
        }
      } catch (e) {
        AppLogger.debug('[ForegroundService] タイマー処理エラー: $e');
        timer.cancel();
        positionSubscription?.cancel();
        service.stopSelf();
      }
    });
  } catch (e) {
    AppLogger.debug('[ForegroundService] エントリーポイントエラー: $e');
    service.stopSelf();
  }
}

/// iOS向けバックグラウンド処理
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}
