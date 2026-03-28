/// 外部計測機器サービスの抽象基底クラス
///
/// Bluetooth等で接続する外部機器（レーザー距離計、トータルステーション等）の
/// 共通インターフェースを定義。各機器実装はこのクラスを継承する。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

abstract class ExternalDeviceService extends ChangeNotifier {
  /// 機器の表示名（例: "TruPulse 360R"）
  String get deviceTypeName;

  /// 接続済みかどうか
  bool get isConnected;

  /// 接続処理中かどうか
  bool get isConnecting;

  /// 機器固有のステータス情報（UIパネル表示用）
  Map<String, dynamic> get statusInfo;

  /// ペアリング済みの互換デバイスを列挙
  Future<List<BluetoothDevice>> scanDevices();

  /// 機器に接続
  Future<void> connectToDevice(BluetoothDevice device);

  /// 接続を切断
  Future<void> disconnect();
}
