// K-MAPS: フォアグラウンドサービス管理クラス
// 1秒間隔でログ出力を行う最小限のフォアグラウンドサービス実装（GPS + 外部GNSS対応）
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../utils/global_gnss_manager.dart';
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

  /// 外部GNSS設定を保存（統合GPS管理サービスに委譲）
  static void setGnssDevice(String deviceAddress, String deviceName) {
    debugPrint(
      '[ForegroundService] GNSS設定保存: $deviceName ($deviceAddress) - 統合GPS管理サービスに委譲',
    );
    // 実際の設定は統合GPS管理サービスで管理
  }

  /// 外部GNSS設定をクリア（統合GPS管理サービスに委譲）
  static void clearGnssDevice() {
    debugPrint('[ForegroundService] GNSS設定をクリア - 統合GPS管理サービスに委譲');
    // 実際の設定は統合GPS管理サービスで管理
  }

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

    // GPS位置レスポンス受信設定
    service.on('gpsPositionResponse').listen((event) {
      if (event != null) {
        try {
          final response = Map<String, dynamic>.from(event);
          _handleGpsResponse(response);
        } catch (e) {
          debugPrint('[ForegroundService] GPS位置レスポンス処理エラー: $e');
        }
      }
    });

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
        initialNotificationContent: '1秒間隔でGPS/GNSS情報をログ出力中...',
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
      // 統合GPS管理サービスに追跡開始を通知
      GpsManagerService().notifyForegroundTrackingStarted();

      // GPS軌跡追跡開始
      GpsTrackManager().startTracking();

      // バックグラウンドサービスからのメッセージ受信設定
      FlutterBackgroundService().on('addTrackPoint').listen((event) {
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
            debugPrint(
              '[ForegroundService] 軌跡ポイント追加: ${point.sourceType} (${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)})',
            );
          } catch (e) {
            debugPrint('[ForegroundService] 軌跡ポイント追加エラー: $e');
          }
        }
      });

      // GPS測量機能は onStart 内で実装

      await FlutterBackgroundService().startService();
      _isServiceRunning = true;
      debugPrint('[ForegroundService] GPS追跡サービス開始成功（軌跡記録開始）');
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
      // 統合GPS管理サービスに追跡停止を通知
      GpsManagerService().notifyForegroundTrackingStopped();

      FlutterBackgroundService().invoke("stopService");
      _isServiceRunning = false;
      debugPrint('[ForegroundService] GPS追跡サービス停止要求送信（軌跡記録継続中）');
    } catch (e) {
      debugPrint('[ForegroundService] サービス停止エラー: $e');
    }
  }

  /// 軌跡追跡を停止して軌跡データを取得
  GpsTrack? stopTrackingAndGetTrack() {
    final track = GpsTrackManager().stopTracking();
    if (track != null) {
      final stats = track.getStatistics();
      debugPrint(
        '[ForegroundService] 軌跡記録完了: ${stats['pointCount']}ポイント、距離: ${(stats['totalDistance'] / 1000).toStringAsFixed(2)}km',
      );
    }
    return track;
  }

  /// サービス実行状態取得
  bool get isServiceRunning => _isServiceRunning;

  /// GPS測量要求処理
  /// フォアグラウンドサービスからGPS位置情報を取得
  static final Map<String, Completer<Map<String, dynamic>>> _gpsRequests = {};

  /// GPS位置情報を要求
  Future<Map<String, dynamic>?> requestGpsPosition({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!_isServiceRunning) {
      debugPrint('[ForegroundService] サービスが実行中でないためGPS要求を拒否');
      return null;
    }

    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    final completer = Completer<Map<String, dynamic>>();
    _gpsRequests[requestId] = completer;

    try {
      debugPrint('[ForegroundService] GPS位置要求送信: $requestId');

      // タイムアウト設定
      Timer(timeout, () {
        if (!completer.isCompleted) {
          _gpsRequests.remove(requestId);
          completer.completeError('GPS位置要求タイムアウト');
        }
      });

      // フォアグラウンドサービスにGPS要求を送信
      FlutterBackgroundService().invoke('requestGpsPosition', {
        'requestId': requestId,
      });

      // レスポンス待機
      final response = await completer.future;
      debugPrint('[ForegroundService] GPS位置レスポンス受信: $requestId');
      return response;
    } catch (e) {
      debugPrint('[ForegroundService] GPS位置要求エラー: $e');
      _gpsRequests.remove(requestId);
      return null;
    }
  }

  /// GPS位置レスポンス処理（内部使用）
  static void _handleGpsResponse(Map<String, dynamic> response) {
    final requestId = response['requestId'] as String?;
    if (requestId != null && _gpsRequests.containsKey(requestId)) {
      final completer = _gpsRequests.remove(requestId)!;
      if (!completer.isCompleted) {
        completer.complete(response);
      }
    }
  }
}

/// サービスのエントリーポイント
/// この関数はIsolateで実行されるため、@pragma('vm:entry-point')が必要
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  try {
    // Isolate内でのデバッグ出力設定
    DartPluginRegistrant.ensureInitialized();

    debugPrint('[ForegroundService] GPS/GNSS追跡サービスエントリーポイント開始');

    // 統合GPS管理サービスを初期化
    final gpsManager = GpsManagerService();
    await gpsManager.initialize();
    await gpsManager.startGps();

    debugPrint('[ForegroundService] 統合GPS管理サービス初期化・開始完了');

    // 統合GPS管理サービスが初期化済みで動作中
    debugPrint('[ForegroundService] 統合GPS管理サービスを使用してGPS/GNSS追跡を開始');

    // サービス停止要求の監視を設定
    service.on('stopService').listen((event) {
      debugPrint('[ForegroundService] 停止要求受信');
      service.stopSelf();
    });

    // GPS測量要求の監視を設定
    service.on('requestGpsPosition').listen((event) async {
      debugPrint('[ForegroundService] GPS測量要求受信');
      try {
        final requestId = event?['requestId'] as String?;
        if (requestId != null) {
          await _handleGpsSurveyRequest(service, gpsManager, requestId);
        }
      } catch (e) {
        debugPrint('[ForegroundService] GPS測量要求処理エラー: $e');
      }
    });

    // 1秒間隔のタイマー設定（統合GPS管理サービス使用）
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        // 統合GPS管理サービスから位置情報を取得
        final gpsInfo = gpsManager.getCurrentGpsInfo();
        String positionInfo = "位置情報: 取得中...";
        Position? currentPosition;

        if (gpsInfo['isActive'] == true &&
            gpsInfo['latitude'] != null &&
            gpsInfo['longitude'] != null) {
          final lat = gpsInfo['latitude'] as double;
          final lon = gpsInfo['longitude'] as double;
          final alt = (gpsInfo['altitude'] as double?) ?? 0.0;
          final acc = (gpsInfo['accuracy'] as double?) ?? 5.0;
          final spd = (gpsInfo['speed'] as double?) ?? 0.0;
          final brg = (gpsInfo['bearing'] as double?) ?? 0.0;
          final sourceType = gpsInfo['sourceType'] as String;
          final sourceName = gpsInfo['sourceName'] as String;

          positionInfo =
              "$sourceName: ${lat.toStringAsFixed(6)}, "
              "${lon.toStringAsFixed(6)} "
              "(精度: ${acc.toStringAsFixed(1)}m) [$sourceType]";

          // 通知用に仮想Positionを作成
          currentPosition = Position(
            latitude: lat,
            longitude: lon,
            timestamp: DateTime.now(),
            accuracy: acc,
            altitude: alt,
            heading: brg,
            speed: spd,
            speedAccuracy: 1.0,
            altitudeAccuracy: 1.0,
            headingAccuracy: 1.0,
          );

          // 軌跡に位置情報を追加（メインIsolateに送信）
          final pointData = {
            'latitude': lat,
            'longitude': lon,
            'altitude': alt,
            'accuracy': acc,
            'speed': spd,
            'bearing': brg,
            'timestamp': DateTime.now().toIso8601String(),
            'sourceType': sourceType,
          };
          service.invoke('addTrackPoint', pointData);
        } else {
          positionInfo = "GPS: 位置情報取得待機中... (統合GPS管理サービス)";
        }

        // サービス停止チェック
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            // フォアグラウンドサービスとして実行中
            _logCurrentTimeWithGPS(
              '[ForegroundService] フォアグラウンド実行中',
              positionInfo,
            );

            // 通知内容を更新（統合GPS管理サービス情報付き）
            String notificationContent =
                "位置追跡中: ${DateTime.now().toString().substring(11, 19)}";
            if (currentPosition != null) {
              final sourceType = gpsInfo['sourceType'] as String? ?? 'GPS';
              notificationContent +=
                  "\n$sourceType: ${currentPosition.latitude.toStringAsFixed(4)}, ${currentPosition.longitude.toStringAsFixed(4)}";
            }

            final sourceType = gpsInfo['sourceType'] as String? ?? 'GPS';
            service.setForegroundNotificationInfo(
              title: "K-MAPS $sourceType追跡実行中",
              content: notificationContent,
            );
          }
        } else {
          // iOS向けログ出力
          _logCurrentTimeWithGPS('[ForegroundService] iOS実行中', positionInfo);
        }
      } catch (e) {
        debugPrint('[ForegroundService] タイマー処理エラー: $e');
        timer.cancel();
        service.stopSelf();
      }
    });

    debugPrint('[ForegroundService] GPS/GNSS追跡定期実行タスク開始（1秒間隔）');
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

/// GPS測量要求処理
/// フォアグラウンドサービス内でGPS位置情報を取得してメインプロセスに返送
@pragma('vm:entry-point')
Future<void> _handleGpsSurveyRequest(
  ServiceInstance service,
  GpsManagerService gpsManager,
  String requestId,
) async {
  try {
    debugPrint('[ForegroundService] GPS測量要求処理開始: $requestId');

    // 統合GPS管理サービスから現在の位置情報を取得
    final gpsInfo = gpsManager.getCurrentGpsInfo();

    // レスポンスデータを準備
    final responseData = {
      'requestId': requestId,
      'success': gpsInfo['isActive'] == true,
      'gpsInfo': gpsInfo,
      'timestamp': DateTime.now().toIso8601String(),
    };

    // メインプロセスにレスポンスを送信
    service.invoke('gpsPositionResponse', responseData);

    debugPrint('[ForegroundService] GPS測量レスポンス送信完了: $requestId');
  } catch (e) {
    debugPrint('[ForegroundService] GPS測量要求処理エラー: $e');

    // エラーレスポンスを送信
    final errorResponse = {
      'requestId': requestId,
      'success': false,
      'error': e.toString(),
      'timestamp': DateTime.now().toIso8601String(),
    };
    service.invoke('gpsPositionResponse', errorResponse);
  }
}

/// 位置情報付き現在時刻ログ出力ヘルパー関数
/// デバッグ出力の統一化とタイムスタンプ・GPS/GNSS情報付加
void _logCurrentTimeWithGPS(String message, String positionInfo) {
  final now = DateTime.now();
  final timeStr =
      '${now.hour.toString().padLeft(2, '0')}:'
      '${now.minute.toString().padLeft(2, '0')}:'
      '${now.second.toString().padLeft(2, '0')}';

  final fullMessage = '$message - $timeStr | $positionInfo';

  debugPrint(fullMessage);

  // 実際のprint文での出力（デバッグコンソール用）
  print(fullMessage);
}
