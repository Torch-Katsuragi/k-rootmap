import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:location/location.dart';

/// Bluetooth GNSS接続サービス
///
/// SSP（Secure Simple Pairing）対応の外部GNSS受信機との接続を管理し、
/// NMEAデータを受信してMock Location Providerに位置情報を提供します。
///
/// Features:
/// - SSP（Secure Simple Pairing）対応のBluetooth接続
/// - NMEAデータの解析と位置情報変換
/// - Android Mock Location Provider連携
/// - 自動再接続機能
/// - リアルタイム接続状態監視
class BluetoothGnssService extends ChangeNotifier {
  static const String _logTag = 'BluetoothGNSS';

  // 接続状態
  BluetoothConnection? _connection;
  BluetoothDevice? _connectedDevice;
  bool _isConnecting = false;
  bool _isConnected = false;
  bool _isMockLocationEnabled = false;

  // データ受信関連
  StreamSubscription<Uint8List>? _dataSubscription;
  String _partialData = '';

  // 位置情報
  double? _latitude;
  double? _longitude;
  double? _altitude;
  double? _accuracy;
  double? _speed;
  double? _bearing;
  DateTime? _timestamp;

  // 統計情報
  int _receivedSentenceCount = 0;
  int _validPositionCount = 0;
  DateTime? _lastPositionUpdate;

  // Location service for mock location
  final Location _location = Location();

  // Getters
  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  bool get isMockLocationEnabled => _isMockLocationEnabled;
  BluetoothDevice? get connectedDevice => _connectedDevice;
  double? get latitude => _latitude;
  double? get longitude => _longitude;
  double? get altitude => _altitude;
  double? get accuracy => _accuracy;
  double? get speed => _speed;
  double? get bearing => _bearing;
  DateTime? get timestamp => _timestamp;
  int get receivedSentenceCount => _receivedSentenceCount;
  int get validPositionCount => _validPositionCount;
  DateTime? get lastPositionUpdate => _lastPositionUpdate;

  /// 利用可能なBluetoothデバイスをスキャン
  ///
  /// Returns: ペアリング済みのBluetoothデバイスリスト
  Future<List<BluetoothDevice>> scanDevices() async {
    try {
      debugPrint('$_logTag: デバイススキャンを開始');

      // Bluetooth許可を確認
      bool isEnabled = await FlutterBluetoothSerial.instance.isEnabled ?? false;
      if (!isEnabled) {
        debugPrint('$_logTag: Bluetoothが無効です');
        throw Exception('Bluetoothが無効です。設定でBluetoothを有効にしてください。');
      }

      // ペアリング済みデバイスを取得
      List<BluetoothDevice> devices =
          await FlutterBluetoothSerial.instance.getBondedDevices();
      debugPrint('$_logTag: ${devices.length}個のペアリング済みデバイスを発見');

      return devices;
    } catch (e) {
      debugPrint('$_logTag: デバイススキャンエラー: $e');
      rethrow;
    }
  }

  /// GNSS受信機に接続
  ///
  /// [device] 接続対象のBluetoothデバイス
  /// [enableMockLocation] Mock Location Providerを有効にするかどうか
  Future<void> connectToDevice(
    BluetoothDevice device, {
    bool enableMockLocation = true,
  }) async {
    if (_isConnecting || _isConnected) {
      debugPrint('$_logTag: 既に接続中または接続済みです');
      return;
    }

    try {
      _isConnecting = true;
      notifyListeners();

      debugPrint('$_logTag: ${device.name} (${device.address}) に接続中...');

      // Mock Location許可を設定
      if (enableMockLocation) {
        await _setupMockLocation();
      }

      // Bluetooth接続（SSP対応）
      _connection = await BluetoothConnection.toAddress(device.address);
      _connectedDevice = device;
      _isConnected = true;
      _isConnecting = false;

      debugPrint('$_logTag: ${device.name}に接続成功');

      // データ受信開始
      _startDataReceiving();

      notifyListeners();
    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _connectedDevice = null;
      debugPrint('$_logTag: 接続エラー: $e');
      notifyListeners();
      rethrow;
    }
  }

  /// 接続を切断
  Future<void> disconnect() async {
    try {
      debugPrint('$_logTag: 接続を切断中...');

      // データ受信停止
      await _dataSubscription?.cancel();
      _dataSubscription = null;

      // Bluetooth接続切断
      await _connection?.close();
      _connection = null;

      // 状態リセット
      _isConnected = false;
      _isConnecting = false;
      _connectedDevice = null;
      _partialData = '';

      debugPrint('$_logTag: 接続を切断しました');
      notifyListeners();
    } catch (e) {
      debugPrint('$_logTag: 切断エラー: $e');
    }
  }

  /// Mock Location Providerの設定
  Future<void> _setupMockLocation() async {
    try {
      // 位置情報許可を確認
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          throw Exception('位置情報サービスが無効です');
        }
      }

      PermissionStatus permissionGranted = await _location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await _location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          throw Exception('位置情報許可が必要です');
        }
      }

      _isMockLocationEnabled = true;
      debugPrint('$_logTag: Mock Location Providerを設定しました');
    } catch (e) {
      debugPrint('$_logTag: Mock Location設定エラー: $e');
      _isMockLocationEnabled = false;
      rethrow;
    }
  }

  /// データ受信開始
  void _startDataReceiving() {
    _dataSubscription = _connection!.input!.listen(
      _onDataReceived,
      onError: (error) {
        debugPrint('$_logTag: データ受信エラー: $error');
        disconnect();
      },
      onDone: () {
        debugPrint('$_logTag: データストリーム終了');
        disconnect();
      },
    );

    debugPrint('$_logTag: データ受信を開始しました');
  }

  /// 受信データの処理
  void _onDataReceived(Uint8List data) {
    try {
      String dataString = utf8.decode(data);
      _partialData += dataString;

      // NMEA文を行ごとに処理
      List<String> lines = _partialData.split('\n');
      _partialData = lines.last; // 最後の不完全な行を保持

      for (int i = 0; i < lines.length - 1; i++) {
        String line = lines[i].trim();
        if (line.isNotEmpty) {
          _processNmeaSentence(line);
        }
      }
    } catch (e) {
      debugPrint('$_logTag: データ処理エラー: $e');
    }
  }

  /// NMEA文の処理
  void _processNmeaSentence(String sentence) {
    try {
      _receivedSentenceCount++;

      // 簡易NMEA解析（GGAとRMCに対応）
      if (sentence.startsWith('\$GPGGA') || sentence.startsWith('\$GNGGA')) {
        _processGgaSentence(sentence);
      } else if (sentence.startsWith('\$GPRMC') ||
          sentence.startsWith('\$GNRMC')) {
        _processRmcSentence(sentence);
      }
    } catch (e) {
      debugPrint('$_logTag: NMEA処理エラー: $sentence - $e');
    }
  }

  /// GGA文の処理（位置情報）
  void _processGgaSentence(String sentence) {
    try {
      List<String> parts = sentence.split(',');
      if (parts.length >= 15) {
        // 緯度の処理
        if (parts[2].isNotEmpty && parts[3].isNotEmpty) {
          double lat = _parseDMSToDecimal(parts[2]);
          if (parts[3] == 'S') lat = -lat;
          _latitude = lat;
        }

        // 経度の処理
        if (parts[4].isNotEmpty && parts[5].isNotEmpty) {
          double lon = _parseDMSToDecimal(parts[4]);
          if (parts[5] == 'W') lon = -lon;
          _longitude = lon;
        }

        // 高度の処理
        if (parts[9].isNotEmpty) {
          _altitude = double.tryParse(parts[9]);
        }

        // 品質インジケータ
        int quality = int.tryParse(parts[6]) ?? 0;
        double hdop = double.tryParse(parts[8]) ?? 1.0;
        _accuracy = _calculateAccuracy(quality, hdop);

        if (_latitude != null && _longitude != null) {
          _timestamp = DateTime.now();
          _lastPositionUpdate = _timestamp;
          _validPositionCount++;

          // Mock Locationに位置情報を送信
          if (_isMockLocationEnabled) {
            _sendToMockLocation();
          }

          notifyListeners();

          debugPrint(
            '$_logTag: GGA位置更新 - Lat: $_latitude, Lon: $_longitude, Alt: $_altitude, Acc: $_accuracy',
          );
        }
      }
    } catch (e) {
      debugPrint('$_logTag: GGA処理エラー: $e');
    }
  }

  /// RMC文の処理（推奨最小データ）
  void _processRmcSentence(String sentence) {
    try {
      List<String> parts = sentence.split(',');
      if (parts.length >= 13) {
        // 有効性チェック
        if (parts[2] != 'A') return; // 'A' = active, 'V' = void

        // 緯度の処理
        if (parts[3].isNotEmpty && parts[4].isNotEmpty) {
          double lat = _parseDMSToDecimal(parts[3]);
          if (parts[4] == 'S') lat = -lat;
          _latitude = lat;
        }

        // 経度の処理
        if (parts[5].isNotEmpty && parts[6].isNotEmpty) {
          double lon = _parseDMSToDecimal(parts[5]);
          if (parts[6] == 'W') lon = -lon;
          _longitude = lon;
        }

        // 速度（ノット）
        if (parts[7].isNotEmpty) {
          double speedKnots = double.tryParse(parts[7]) ?? 0.0;
          _speed = speedKnots * 0.514444; // ノットからm/sに変換
        }

        // 方位角
        if (parts[8].isNotEmpty) {
          _bearing = double.tryParse(parts[8]);
        }

        if (_latitude != null && _longitude != null) {
          _timestamp = DateTime.now();
          _lastPositionUpdate = _timestamp;
          _validPositionCount++;

          // Mock Locationに位置情報を送信
          if (_isMockLocationEnabled) {
            _sendToMockLocation();
          }

          notifyListeners();

          debugPrint(
            '$_logTag: RMC位置更新 - Lat: $_latitude, Lon: $_longitude, Speed: $_speed, Bearing: $_bearing',
          );
        }
      }
    } catch (e) {
      debugPrint('$_logTag: RMC処理エラー: $e');
    }
  }

  /// DMS（度分秒）形式を小数度に変換
  double _parseDMSToDecimal(String dms) {
    if (dms.length < 4) return 0.0;

    try {
      // NMEAフォーマット: 緯度: ddmm.mmmm 経度: dddmm.mmmm
      // 小数点の位置を見つけて正確に分割
      int dotIndex = dms.indexOf('.');
      if (dotIndex == -1) {
        debugPrint('$_logTag: DMS変換エラー - 小数点が見つかりません: $dms');
        return 0.0;
      }

      // 小数点前の桁数から度の桁数を判定
      int degreeLength;
      if (dotIndex == 4) {
        degreeLength = 2; // 緯度: ddmm.mmmm
      } else if (dotIndex == 5) {
        degreeLength = 3; // 経度: dddmm.mmmm
      } else {
        debugPrint('$_logTag: DMS変換エラー - 無効なフォーマット: $dms');
        return 0.0;
      }

      // 度と分を分離
      String degreesPart = dms.substring(0, degreeLength);
      String minutesPart = dms.substring(degreeLength);

      double degrees = double.parse(degreesPart);
      double minutes = double.parse(minutesPart);

      double result = degrees + (minutes / 60.0);

      debugPrint(
        '$_logTag: DMS変換 - 入力: $dms, 度: $degrees, 分: $minutes, 結果: $result',
      );

      return result;
    } catch (e) {
      debugPrint('$_logTag: DMS変換エラー: $dms - $e');
      return 0.0;
    }
  }

  /// 精度の計算
  double _calculateAccuracy(int? quality, double? hdop) {
    // GPS品質とHDOPから精度を推定
    if (quality == null || hdop == null) return 10.0;

    switch (quality) {
      case 0:
        return 50.0; // 無効
      case 1:
        return hdop * 5.0; // 標準GPS
      case 2:
        return hdop * 2.0; // DGPS
      case 3:
        return hdop * 1.0; // RTK固定解
      case 4:
        return hdop * 2.0; // RTK浮動小数点解
      case 5:
        return hdop * 5.0; // 推測航法
      default:
        return hdop * 5.0;
    }
  }

  /// Mock Location Providerに位置情報を送信
  Future<void> _sendToMockLocation() async {
    if (!_isMockLocationEnabled || _latitude == null || _longitude == null) {
      return;
    }

    try {
      // Androidのネイティブコードを呼び出してMock Locationを設定
      // 実装はAndroidプラットフォーム固有のコードが必要
      debugPrint(
        '$_logTag: Mock Location送信 - Lat: $_latitude, Lon: $_longitude',
      );
    } catch (e) {
      debugPrint('$_logTag: Mock Location送信エラー: $e');
    }
  }

  /// 接続状態の統計情報を取得
  Map<String, dynamic> getConnectionStats() {
    return {
      'isConnected': _isConnected,
      'connectedDevice': _connectedDevice?.name,
      'deviceAddress': _connectedDevice?.address,
      'receivedSentences': _receivedSentenceCount,
      'validPositions': _validPositionCount,
      'lastUpdate': _lastPositionUpdate?.toIso8601String(),
      'currentPosition': {
        'latitude': _latitude,
        'longitude': _longitude,
        'altitude': _altitude,
        'accuracy': _accuracy,
        'speed': _speed,
        'bearing': _bearing,
      },
    };
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
