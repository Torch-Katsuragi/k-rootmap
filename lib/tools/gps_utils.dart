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
// lib/tools/gps_utils.dart
// GPSユーティリティークラス（マルチプラットフォーム対応: Android/iOS/Windows）
// 位置情報取得、NMEAパース、衛星情報取得、権限管理などを提供
//
// Windowsではgeolocatorやnmeaが未対応の場合、将来的な拡張やモック実装も考慮

import 'dart:async';
import 'dart:io' show Platform;

import 'package:root_maps/utils/app_logger.dart';
import 'package:nmea/nmea.dart'; // NMEA0183パーサ
import 'package:geolocator/geolocator.dart';
// geolocator, permission_handler等はpubspec.yamlに追加済み
// import 'package:root_maps/utils/app_logger.dart';
// Sentence型もここでimportされる（nmeaパッケージの主要型）

/// 衛星情報モデル
class SatelliteInfo {
  /// 衛星ID
  final int id;

  /// 信号強度（SNR）
  final double snr;

  /// 使用中か
  final bool inUse;
  SatelliteInfo({required this.id, required this.snr, required this.inUse});
}

/// NMEAセンテンスモデル（必要に応じて拡張）
class NmeaSentence {
  final String raw;
  NmeaSentence(this.raw);
  // TODO: 必要なパース処理を追加
}

/// 位置情報モデル（GGA文などから取得）
class GpsPosition {
  final double latitude;
  final double longitude;
  final double altitude;
  final int satellites;
  final double hdop;
  GpsPosition({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.satellites,
    required this.hdop,
  });
}

/// NMEA GGA文から位置情報を抽出
GpsPosition? parseGgaSentence(TalkerSentence sentence) {
  if (sentence.type.name != 'GGA') return null;
  final fields = sentence.fields;
  if (fields.length < 10) return null;
  final lat = _parseLat(fields[2], fields[3]);
  final lng = _parseLng(fields[4], fields[5]);
  final alt = double.tryParse(fields[9]) ?? 0.0;
  final sats = int.tryParse(fields[7]) ?? 0;
  final hdop = double.tryParse(fields[8]) ?? 0.0;
  return GpsPosition(
    latitude: lat,
    longitude: lng,
    altitude: alt,
    satellites: sats,
    hdop: hdop,
  );
}

/// NMEAの度分表記→10進変換
/// 例: 3150.788156, 'N' → 31.846469
///     11711.922383, 'E' → 117.198706
// 緯度: DDMM.MMMMM, 経度: DDDMM.MMMMM
// N/S, E/Wで符号反転

double _parseLat(String dm, String ns) {
  if (dm.isEmpty) return 0.0;
  final d = double.tryParse(dm) ?? 0.0;
  final deg = d ~/ 100;
  final min = d - deg * 100;
  double lat = deg + min / 60.0;
  if (ns == 'S') lat = -lat;
  return lat;
}

double _parseLng(String dm, String ew) {
  if (dm.isEmpty) return 0.0;
  final d = double.tryParse(dm) ?? 0.0;
  final deg = d ~/ 100;
  final min = d - deg * 100;
  double lng = deg + min / 60.0;
  if (ew == 'W') lng = -lng;
  return lng;
}

/// GPSユーティリティークラス
///
/// プラットフォームごとに実装を分岐し、
/// Android/iOS/Windowsでの動作を考慮する。
class GpsUtils {
  // シングルトン化（必要なら）
  static final GpsUtils instance = GpsUtils._internal();
  GpsUtils._internal();

  /// 現在地取得
  /// Windowsでは未対応の場合nullを返す
  Future<dynamic> getCurrentPosition() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // return await Geolocator.getCurrentPosition();
      return null; // TODO: 実装
    } else if (Platform.isWindows) {
      // Windows用の実装（未対応の場合はnull）
      return null;
    } else {
      return null;
    }
  }

  /// 位置情報ストリーム購読
  Stream<dynamic> getPositionStream() {
    if (Platform.isAndroid || Platform.isIOS || Platform.isWindows) {
      // geolocatorのストリームをGpsPositionに変換
      return Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).map(
        (pos) => GpsPosition(
          latitude: pos.latitude,
          longitude: pos.longitude,
          altitude: pos.altitude,
          satellites: 0, // geolocatorからは取得不可
          hdop: 0.0, // geolocatorからは取得不可
        ),
      );
    } else {
      return const Stream.empty();
    }
  }

  /// NMEAセンテンスストリーム購読
  ///
  /// 例: シリアルやBluetooth等からNMEA文字列ストリームを受け取り、
  /// nmeaパッケージでパースして利用する
  Stream<NmeaSentence> getNmeaStream(Stream<String> nmeaRawStream) {
    // nmea.NmeaDecoderはStreamTransformer<String, Sentence>
    final decoder = NmeaDecoder(onlyAllowValid: true);
    // 例: GGA, GSV, RMCなどのカスタムセンテンス登録も可能
    // decoder.registerTalkerSentence('GGA', (line) => ...);
    // decoder.registerTalkerSentence('GSV', (line) => ...);
    // decoder.registerTalkerSentence('RMC', (line) => ...);
    //
    // ここでは汎用的にSentence型で返す
    return nmeaRawStream.transform(decoder).map((sentence) {
      // 必要に応じて型判定・パース拡張
      // if (sentence is GgaSentence) {...}
      // if (sentence is GsvSentence) {...}
      return NmeaSentence(sentence.raw);
    });
  }

  /// 衛星情報取得（NMEA GSV文などから抽出）
  ///
  /// nmeaパッケージでGSV文をパースし、衛星ID・SNR・使用中か等を抽出
  Future<List<SatelliteInfo>> getSatellitesFromNmea(
    Stream<String> nmeaRawStream,
  ) async {
    final decoder = NmeaDecoder(onlyAllowValid: true);
    final satellites = <SatelliteInfo>[];
    await for (final sentence in nmeaRawStream.transform(decoder)) {
      // nmeaパッケージのTalkerSentence型として扱う
      if (sentence is TalkerSentence && sentence.type.name == 'GSV') {
        // GSV文のfields: [総文数, 文番号, 衛星数, SV1_PRN, SV1_Elev, SV1_Azimuth, SV1_SNR, ...]
        final fields = sentence.fields;
        // 4番目以降を4つずつ（PRN, Elev, Azimuth, SNR）でパース
        for (int i = 4; i + 3 < fields.length; i += 4) {
          final id = int.tryParse(fields[i]) ?? 0;
          final snr = double.tryParse(fields[i + 3]) ?? 0.0;
          // SNRが0の場合は未受信扱い
          satellites.add(SatelliteInfo(id: id, snr: snr, inUse: snr > 0));
        }
      }
    }
    return satellites;
  }

  /// 権限確認・リクエスト
  Future<bool> checkAndRequestPermission() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        AppLogger.debug('[DEBUG] GPS: Location services are disabled.');
        return false;
      }

      // 現在の権限状態をチェック
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        // 権限が拒否されている場合、リクエスト
        permission = await Geolocator.requestPermission();
        AppLogger.debug('[DEBUG] GPS: Permission requested, result: $permission');

        if (permission == LocationPermission.denied) {
          AppLogger.debug('[DEBUG] GPS: Permissions are denied.');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        AppLogger.debug('[DEBUG] GPS: Permissions are permanently denied.');
        return false;
      }

      AppLogger.debug('[DEBUG] GPS: Permission granted: $permission');
      return true;
    } else if (Platform.isWindows) {
      return true;
    } else {
      return false;
    }
  }

  /// サービス有効化確認
  Future<bool> isLocationServiceEnabled() async {
    if (Platform.isAndroid || Platform.isIOS) {
      bool enabled = await Geolocator.isLocationServiceEnabled();
      AppLogger.debug('[DEBUG] GPS: Location service enabled: $enabled');
      return enabled;
    } else if (Platform.isWindows) {
      return true;
    } else {
      return false;
    }
  }
}

// TODO: 必要に応じてWindows用の独自実装や、
// 外部GPSデバイス対応のための拡張ポイントを追加
// nmeaパッケージの詳細: https://pub.dev/packages/nmea
// 公式サンプル: https://pub.dev/packages/nmea/example

