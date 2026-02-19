/// GPS座標レコード（タイムスタンプ付き）
///
/// 内蔵GPSの位置情報を型安全に表現するモデル。
/// ForegroundServiceイベントやGeolocator Positionからの変換をサポート。
library;

import 'package:geolocator/geolocator.dart';

/// GPS座標レコード
class GpsPositionRecord {
  /// 緯度
  final double latitude;

  /// 経度
  final double longitude;

  /// 高度（メートル）
  final double? altitude;

  /// 精度（メートル）
  final double? accuracy;

  /// 速度（m/s）
  final double? speed;

  /// 方位（度）
  final double? bearing;

  /// GPS fix時刻
  final DateTime timestamp;

  /// Store受信時刻
  final DateTime receivedAt;

  const GpsPositionRecord({
    required this.latitude,
    required this.longitude,
    this.altitude,
    this.accuracy,
    this.speed,
    this.bearing,
    required this.timestamp,
    required this.receivedAt,
  });

  /// Geolocator Positionからの変換
  factory GpsPositionRecord.fromPosition(Position position) {
    return GpsPositionRecord(
      latitude: position.latitude,
      longitude: position.longitude,
      altitude: position.altitude,
      accuracy: position.accuracy,
      speed: position.speed,
      bearing: position.heading,
      timestamp: position.timestamp,
      receivedAt: DateTime.now(),
    );
  }

  /// ForegroundServiceイベント(Map)からの変換
  factory GpsPositionRecord.fromServiceEvent(Map<String, dynamic> event) {
    return GpsPositionRecord(
      latitude: (event['latitude'] as num).toDouble(),
      longitude: (event['longitude'] as num).toDouble(),
      altitude: (event['altitude'] as num?)?.toDouble(),
      accuracy: (event['accuracy'] as num?)?.toDouble(),
      speed: (event['speed'] as num?)?.toDouble(),
      bearing: (event['bearing'] as num?)?.toDouble(),
      timestamp: event['timestamp'] is String
          ? DateTime.parse(event['timestamp'] as String)
          : (event['timestamp'] as DateTime?) ?? DateTime.now(),
      receivedAt: DateTime.now(),
    );
  }

  /// Map変換（既存API互換用）
  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'altitude': altitude,
      'accuracy': accuracy,
      'speed': speed,
      'bearing': bearing,
      'timestamp': timestamp.toIso8601String(),
      'sourceType': 'GPS',
    };
  }

  @override
  String toString() =>
      'GpsPositionRecord(lat: ${latitude.toStringAsFixed(6)}, '
      'lon: ${longitude.toStringAsFixed(6)}, '
      'acc: ${accuracy?.toStringAsFixed(1)}m, '
      'ts: $timestamp)';
}

/// GPS座標リクエストのレスポンス
///
/// [requestPosition] の戻り値として使用。
/// 前回リクエスト以降のGPS更新有無を判定可能。
class GpsPositionResponse {
  /// 最新の座標レコード（nullの場合はまだ取得できていない）
  final GpsPositionRecord? position;

  /// 前回のリクエスト以降にGPS更新があったか
  final bool hasNewUpdate;

  /// 最後にGPS更新があった時刻
  final DateTime? lastUpdateTime;

  const GpsPositionResponse({
    this.position,
    required this.hasNewUpdate,
    this.lastUpdateTime,
  });

  @override
  String toString() =>
      'GpsPositionResponse(hasNew: $hasNewUpdate, '
      'lastUpdate: $lastUpdateTime, '
      'pos: $position)';
}
