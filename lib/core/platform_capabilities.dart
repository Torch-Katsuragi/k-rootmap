import 'dart:io' show Platform;

/// プラットフォーム差異を capability として集約する。
class PlatformCapabilities {
  const PlatformCapabilities._();

  static bool get supportsCompass => Platform.isAndroid || Platform.isIOS;

  static bool get supportsDriveSyncStatusCheck =>
      Platform.isAndroid || Platform.isIOS;

  static bool get supportsNativeLocationRender =>
      Platform.isAndroid || Platform.isIOS;

  static bool get supportsGpsTracking => Platform.isAndroid || Platform.isIOS;

  /// GPS位置取得（マーカー・初回ジャンプ）— 全プラットフォーム対応
  static bool get supportsGpsLocation => true;

  /// Bluetooth経由の外部GNSS機器 — モバイルのみ
  static bool get supportsBluetoothGnss => Platform.isAndroid || Platform.isIOS;
}
