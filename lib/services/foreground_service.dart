// K-MAPS: フォアグラウンドサービス管理クラス
// 1秒間隔でログ出力を行う最小限のフォアグラウンドサービス実装（内蔵GPS専用）
import 'dart:async';
import 'dart:ui';
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import '../models/gps_track.dart';
import 'gps_manager_service.dart';

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

  /// メインIsolate側のトラックポイント受信リスナー
  StreamSubscription<Map<String, dynamic>?>? _trackPointSubscription;

  /// 現在のGNSS設定を取得（統合GPS管理サービスから取得）
  static Map<String, String?> getGnssDevice() {
    final gpsManager = GpsManagerService();
    final sources = gpsManager.getAvailableGpsSources();

    // 選択されている外部GNSS機器を探す
    final selectedExternal =
        sources
            .where(
              (source) =>
                  source['type'] == GpsSourceType.external &&
                  source['isSelected'] == true,
            )
            .firstOrNull;

    if (selectedExternal != null) {
      return {
        'address': selectedExternal['device']?.address,
        'name': selectedExternal['name'],
      };
    }

    return {'address': null, 'name': null};
  }

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
        initialNotificationTitle: 'K-MAPS 位置追跡実行中',
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
  }

  /// サービス開始
  Future<void> startService() async {
    if (_isServiceRunning) {
      return;
    }

    try {
      // 統合GPS管理サービスに追跡開始を通知
      GpsManagerService().notifyForegroundTrackingStarted();

      // GPS軌跡追跡開始
      GpsTrackManager().startTracking();

      // 既存のリスナーがあればキャンセル（二重登録防止）
      await _trackPointSubscription?.cancel();

      // バックグラウンドサービスからのメッセージ受信設定（リスナーを保存）
      _trackPointSubscription = FlutterBackgroundService()
          .on('addTrackPoint')
          .listen((event) {
        if (event != null) {
          try {
            final pointData = Map<String, dynamic>.from(event);
            final point = GpsTrackPoint(
              latitude: pointData['latitude'].toDouble(),
              longitude: pointData['longitude'].toDouble(),
              altitude: pointData['altitude']?.toDouble(),
              accuracy: pointData['accuracy']?.toDouble(),
              speed: pointData['speed']?.toDouble(),
              bearing: pointData['bearing']?.toDouble(),
              timestamp: DateTime.parse(pointData['timestamp']),
              sourceType: pointData['sourceType'] ?? 'GPS',
            );
            GpsTrackManager().addPoint(point);
          } catch (e) {
            AppLogger.debug('[ForegroundService] 軌跡ポイント追加エラー: $e');
          }
        }
      });

      await FlutterBackgroundService().startService();
      _isServiceRunning = true;
      AppLogger.debug('[ForegroundService] GPS追跡サービス開始');
    } catch (e) {
      AppLogger.debug('[ForegroundService] サービス開始エラー: $e');
      AppLogger.debug('[ForegroundService] エラー詳細: ${e.toString()}');
      rethrow;
    }
  }

  /// サービス停止
  Future<void> stopService() async {
    if (!_isServiceRunning) {
      return;
    }

    try {
      // 統合GPS管理サービスに追跡停止を通知
      GpsManagerService().notifyForegroundTrackingStopped();

      // メインIsolate側のリスナーをキャンセル
      await _trackPointSubscription?.cancel();
      _trackPointSubscription = null;

      FlutterBackgroundService().invoke("stopService");
      _isServiceRunning = false;
      AppLogger.debug('[ForegroundService] GPS追跡サービス停止');
    } catch (e) {
      AppLogger.debug('[ForegroundService] サービス停止エラー: $e');
    }
  }

  /// アプリ終了時のクリーンアップ（強制停止）
  Future<void> dispose() async {
    await _trackPointSubscription?.cancel();
    _trackPointSubscription = null;
    if (_isServiceRunning) {
      FlutterBackgroundService().invoke("stopService");
      _isServiceRunning = false;
    }
    AppLogger.debug('[ForegroundService] クリーンアップ完了');
  }

  /// 軌跡追跡を停止して軌跡データを取得
  GpsTrack? stopTrackingAndGetTrack() {
    final track = GpsTrackManager().stopTracking();
    if (track != null) {
      final stats = track.getStatistics();
      AppLogger.debug(
        '[ForegroundService] 軌跡記録完了: ${stats['pointCount']}ポイント、距離: ${(stats['totalDistance'] / 1000).toStringAsFixed(2)}km',
      );
    }
    return track;
  }

  /// サービス実行状態取得
  bool get isServiceRunning => _isServiceRunning;
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
    Timer? periodicTimer; // タイマー参照を保持

    // 内蔵GPS位置情報ストリームを開始
    positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((position) {
      lastPosition = position;
    });

    // サービス停止要求の監視を設定（タイマーもキャンセル）
    service.on('stopService').listen((event) {
      periodicTimer?.cancel(); // タイマーをキャンセル
      positionSubscription?.cancel();
      service.stopSelf();
    });

    // 1秒間隔のタイマー設定（内蔵GPSのみ使用）
    periodicTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        Position? currentPosition = lastPosition;

        if (currentPosition != null) {
          // 軌跡に位置情報を追加（メインIsolateに送信）
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
          service.invoke('addTrackPoint', pointData);
        }

        // Android通知更新
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            try {
              String notificationContent =
                  "位置追跡中: ${DateTime.now().toString().substring(11, 19)}";
              if (currentPosition != null) {
                notificationContent +=
                    "\nGPS: ${currentPosition.latitude.toStringAsFixed(4)}, ${currentPosition.longitude.toStringAsFixed(4)}";
              }
              service.setForegroundNotificationInfo(
                title: "K-MAPS GPS追跡実行中",
                content: notificationContent,
              );
            } catch (_) {
              // 通知更新エラーは無視（GPS追跡継続）
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


