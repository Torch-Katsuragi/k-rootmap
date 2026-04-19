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
/// グローバルGNSS接続管理クラス
///
/// BluetoothGnssServiceのインスタンスをアプリ全体で共有し、
/// 画面遷移時でも接続を維持できるようにします。
///
/// Features:
/// - シングルトンパターンによる単一インスタンス管理
/// - 画面ライフサイクルから独立した接続維持
/// - フォアグラウンドサービスとの連携
/// - 接続状態の集約管理
library;

import 'package:root_maps/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import '../models/bluetooth_gnss_service.dart';

class GlobalGnssManager {
  // シングルトンインスタンス
  static final GlobalGnssManager _instance = GlobalGnssManager._internal();
  factory GlobalGnssManager() => _instance;
  GlobalGnssManager._internal();

  /// 全体で共有するGNSSサービスインスタンス
  BluetoothGnssService? _gnssService;

  /// 全体共有のGNSSサービスインスタンスを取得
  /// 初回アクセス時に自動で作成される
  BluetoothGnssService get gnssService {
    _gnssService ??= BluetoothGnssService();
    return _gnssService!;
  }

  /// 接続状態を取得
  bool get isConnected => _gnssService?.isConnected ?? false;

  /// 接続中状態を取得
  bool get isConnecting => _gnssService?.isConnecting ?? false;

  /// 接続されたデバイス情報を取得
  String? get connectedDeviceName => _gnssService?.connectedDevice?.name;

  /// 接続されたデバイスアドレスを取得
  String? get connectedDeviceAddress => _gnssService?.connectedDevice?.address;

  /// 現在の位置情報を取得
  Map<String, dynamic> get currentPosition {
    final service = _gnssService;
    if (service == null) return {};

    return {
      'latitude': service.latitude,
      'longitude': service.longitude,
      'altitude': service.altitude,
      'accuracy': service.accuracy,
      'speed': service.speed,
      'bearing': service.bearing,
      'timestamp': service.timestamp,
    };
  }

  /// 統計情報を取得
  Map<String, dynamic> get statistics {
    final service = _gnssService;
    if (service == null) return {};

    return {
      'receivedSentenceCount': service.receivedSentenceCount,
      'validPositionCount': service.validPositionCount,
      'lastPositionUpdate': service.lastPositionUpdate,
    };
  }

  /// 接続状態変更通知用のリスナーを追加
  void addListener(VoidCallback listener) {
    _gnssService?.addListener(listener);
  }

  /// リスナーを削除
  void removeListener(VoidCallback listener) {
    _gnssService?.removeListener(listener);
  }

  /// アプリ終了時のクリーンアップ
  /// 通常のdisposeではなく、明示的な切断時のみ使用
  void dispose() {
    AppLogger.debug('[GlobalGnssManager] 明示的な切断・クリーンアップを実行');
    _gnssService?.dispose();
    _gnssService = null;
  }

  /// デバッグ情報出力
  void printDebugInfo() {
    final service = _gnssService;
    if (service == null) {
      AppLogger.debug('[GlobalGnssManager] GNSSサービス未初期化');
      return;
    }

    AppLogger.debug('''
[GlobalGnssManager] デバッグ情報:
  - 接続状態: ${service.isConnected}
  - 接続中: ${service.isConnecting}
  - デバイス: ${service.connectedDevice?.name ?? 'None'}
  - 最新位置: (${service.latitude?.toStringAsFixed(6)}, ${service.longitude?.toStringAsFixed(6)})
  - 受信回数: ${service.receivedSentenceCount}
''');
  }
}


