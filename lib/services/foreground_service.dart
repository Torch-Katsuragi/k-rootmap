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

  /// 外部GNSS設定
  static String? _gnssDeviceAddress;
  static String? _gnssDeviceName;

  /// 外部GNSS設定を保存
  static void setGnssDevice(String deviceAddress, String deviceName) {
    _gnssDeviceAddress = deviceAddress;
    _gnssDeviceName = deviceName;
    debugPrint(
      '[ForegroundService] GNSS設定保存: $_gnssDeviceName ($_gnssDeviceAddress)',
    );
  }

  /// 外部GNSS設定をクリア
  static void clearGnssDevice() {
    _gnssDeviceAddress = null;
    _gnssDeviceName = null;
    debugPrint('[ForegroundService] GNSS設定をクリア');
  }

  /// 現在のGNSS設定を取得
  static Map<String, String?> getGnssDevice() {
    return {'address': _gnssDeviceAddress, 'name': _gnssDeviceName};
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
}

/// サービスのエントリーポイント
/// この関数はIsolateで実行されるため、@pragma('vm:entry-point')が必要
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  try {
    // Isolate内でのデバッグ出力設定
    DartPluginRegistrant.ensureInitialized();

    debugPrint('[ForegroundService] GPS/GNSS追跡サービスエントリーポイント開始');

    // GPS初期設定
    Position? lastKnownPosition;
    bool isLocationServiceEnabled = false;
    LocationPermission permission = LocationPermission.denied;

    // 外部GNSS設定
    BluetoothConnection? gnssConnection;
    StreamSubscription<Uint8List>? gnssDataSubscription;
    String gnssPartialData = '';

    // GNSS位置情報
    double? gnssLatitude;
    double? gnssLongitude;
    double? gnssAltitude;
    double? gnssAccuracy;
    double? gnssSpeed;
    double? gnssBearing;
    int gnssReceivedCount = 0;
    bool isGnssConnected = false;

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

    // 外部GNSS接続を試行
    if (ForegroundServiceManager._gnssDeviceAddress != null &&
        ForegroundServiceManager._gnssDeviceName != null) {
      try {
        debugPrint(
          '[ForegroundService] 外部GNSS接続開始: ${ForegroundServiceManager._gnssDeviceName}',
        );
        gnssConnection = await BluetoothConnection.toAddress(
          ForegroundServiceManager._gnssDeviceAddress!,
        );

        if (gnssConnection.isConnected) {
          isGnssConnected = true;
          debugPrint(
            '[ForegroundService] 外部GNSS接続成功: ${ForegroundServiceManager._gnssDeviceName}',
          );

          // NMEAデータ受信開始
          gnssDataSubscription = gnssConnection.input!.listen(
            (Uint8List data) {
              try {
                String dataString = utf8.decode(data);
                gnssPartialData += dataString;

                // NMEA文を行ごとに処理
                List<String> lines = gnssPartialData.split('\n');
                gnssPartialData = lines.last; // 最後の不完全な行を保持

                for (int i = 0; i < lines.length - 1; i++) {
                  String line = lines[i].trim();
                  if (line.isNotEmpty &&
                      (line.startsWith('\$GPGGA') ||
                          line.startsWith('\$GNGGA'))) {
                    // 簡易GGA解析
                    List<String> parts = line.split(',');
                    if (parts.length >= 15 &&
                        parts[2].isNotEmpty &&
                        parts[4].isNotEmpty) {
                      try {
                        // 緯度の処理 (DDMM.MMMM形式)
                        double lat =
                            double.parse(parts[2].substring(0, 2)) +
                            double.parse(parts[2].substring(2)) / 60.0;
                        if (parts[3] == 'S') lat = -lat;

                        // 経度の処理 (DDDMM.MMMM形式)
                        double lon =
                            double.parse(parts[4].substring(0, 3)) +
                            double.parse(parts[4].substring(3)) / 60.0;
                        if (parts[5] == 'W') lon = -lon;

                        gnssLatitude = lat;
                        gnssLongitude = lon;
                        gnssAltitude = double.tryParse(parts[9]) ?? 0.0;
                        gnssAccuracy =
                            (double.tryParse(parts[8]) ?? 1.0) *
                            5.0; // HDOP × 5
                        gnssReceivedCount++;
                      } catch (e) {
                        debugPrint('[ForegroundService] NMEA解析エラー: $e');
                      }
                    }
                  }
                }
              } catch (e) {
                debugPrint('[ForegroundService] GNSS データ処理エラー: $e');
              }
            },
            onError: (error) {
              debugPrint('[ForegroundService] GNSS データ受信エラー: $error');
              isGnssConnected = false;
            },
            onDone: () {
              debugPrint('[ForegroundService] GNSS データストリーム終了');
              isGnssConnected = false;
            },
          );
        }
      } catch (e) {
        debugPrint('[ForegroundService] 外部GNSS接続エラー: $e');
        isGnssConnected = false;
      }
    }

    // サービス停止要求の監視を設定
    service.on('stopService').listen((event) {
      debugPrint('[ForegroundService] 停止要求受信');
      service.stopSelf();
    });

    // 1秒間隔のタイマー設定（GPS/GNSS情報付き）
    Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        // 位置情報取得を試行（外部GNSS優先）
        String positionInfo = "位置情報: 取得中...";
        Position? currentPosition;

        // グローバルマネージャーの接続状態を確認
        final globalGnssManager = GlobalGnssManager();
        final isGlobalGnssConnected = globalGnssManager.isConnected;
        final globalPosition = globalGnssManager.currentPosition;
        final hasGlobalPosition =
            globalPosition['latitude'] != null &&
            globalPosition['longitude'] != null;

        // グローバルGNSSまたはサービス内GNSSが接続済みで位置情報がある場合はGNSSを優先使用
        if ((isGlobalGnssConnected && hasGlobalPosition) ||
            (isGnssConnected &&
                gnssLatitude != null &&
                gnssLongitude != null)) {
          // グローバルマネージャーの位置情報を優先使用
          final useGlobalPosition = isGlobalGnssConnected && hasGlobalPosition;
          final lat =
              useGlobalPosition ? globalPosition['latitude']! : gnssLatitude!;
          final lon =
              useGlobalPosition ? globalPosition['longitude']! : gnssLongitude!;
          final alt =
              useGlobalPosition
                  ? (globalPosition['altitude'] ?? 0.0)
                  : (gnssAltitude ?? 0.0);
          final acc =
              useGlobalPosition
                  ? (globalPosition['accuracy'] ?? 5.0)
                  : (gnssAccuracy ?? 5.0);
          final spd =
              useGlobalPosition
                  ? (globalPosition['speed'] ?? 0.0)
                  : (gnssSpeed ?? 0.0);
          final brg =
              useGlobalPosition
                  ? (globalPosition['bearing'] ?? 0.0)
                  : (gnssBearing ?? 0.0);
          final statsInfo =
              useGlobalPosition
                  ? globalGnssManager.statistics
                  : {'receivedSentenceCount': gnssReceivedCount};

          positionInfo =
              "GNSS: ${lat.toStringAsFixed(6)}, "
              "${lon.toStringAsFixed(6)} "
              "(精度: ${acc.toStringAsFixed(1)}m) "
              "[外部GNSS: 受信数${statsInfo['receivedSentenceCount'] ?? gnssReceivedCount}]";

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
            'sourceType': 'GNSS',
          };
          service.invoke('addTrackPoint', pointData);
        }
        // 外部GNSSが利用できない場合は内蔵GPSを使用
        else if (isLocationServiceEnabled &&
            (permission == LocationPermission.always ||
                permission == LocationPermission.whileInUse)) {
          try {
            // 現在位置を取得（タイムアウト設定）
            currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.high,
              timeLimit: const Duration(seconds: 5),
            );

            lastKnownPosition = currentPosition;
            positionInfo =
                "GPS: ${currentPosition.latitude.toStringAsFixed(6)}, "
                "${currentPosition.longitude.toStringAsFixed(6)} "
                "(精度: ${currentPosition.accuracy.toStringAsFixed(1)}m) [内蔵GPS]";

            // 軌跡に位置情報を追加（メインIsolateに送信）
            final pointData = {
              'latitude': currentPosition.latitude,
              'longitude': currentPosition.longitude,
              'altitude': currentPosition.altitude,
              'accuracy': currentPosition.accuracy,
              'speed': currentPosition.speed,
              'bearing': currentPosition.heading,
              'timestamp': currentPosition.timestamp.toIso8601String(),
              'sourceType': 'GPS',
            };
            service.invoke('addTrackPoint', pointData);
          } catch (e) {
            // 取得に失敗した場合は最後の既知位置を使用
            if (lastKnownPosition != null) {
              positionInfo =
                  "GPS: ${lastKnownPosition!.latitude.toStringAsFixed(6)}, "
                  "${lastKnownPosition!.longitude.toStringAsFixed(6)} "
                  "(前回取得値) [内蔵GPS]";
              currentPosition = lastKnownPosition;
            } else {
              positionInfo = "GPS: 位置情報取得エラー - $e";
            }
          }
        } else {
          String gnssStatus =
              (isGlobalGnssConnected || isGnssConnected)
                  ? " / GNSS接続済み"
                  : " / GNSS未接続";
          if (isGlobalGnssConnected) {
            gnssStatus += " (グローバル管理)";
          }
          positionInfo =
              "GPS: 無効または権限なし (サービス: $isLocationServiceEnabled, 権限: $permission)$gnssStatus";
        }

        // サービス停止チェック
        if (service is AndroidServiceInstance) {
          if (await service.isForegroundService()) {
            // フォアグラウンドサービスとして実行中
            _logCurrentTimeWithGPS(
              '[ForegroundService] フォアグラウンド実行中',
              positionInfo,
            );

            // 通知内容を更新（GPS/GNSS情報付き）
            String notificationContent =
                "位置追跡中: ${DateTime.now().toString().substring(11, 19)}";
            if (currentPosition != null) {
              String sourceType =
                  (isGlobalGnssConnected || isGnssConnected) ? "GNSS" : "GPS";
              notificationContent +=
                  "\n$sourceType: ${currentPosition.latitude.toStringAsFixed(4)}, ${currentPosition.longitude.toStringAsFixed(4)}";
            }

            service.setForegroundNotificationInfo(
              title:
                  (isGlobalGnssConnected || isGnssConnected)
                      ? "K-MAPS GNSS追跡実行中"
                      : "K-MAPS GPS追跡実行中",
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
