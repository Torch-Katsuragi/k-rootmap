import 'dart:io' show Platform;

/// プラットフォーム差異を capability として集約する。
class PlatformCapabilities {
  const PlatformCapabilities._();

  static bool get supportsCompass => Platform.isAndroid || Platform.isIOS;

  static bool get supportsDriveSyncStatusCheck =>
      Platform.isAndroid || Platform.isIOS;

  static bool get supportsNativeLocationRender =>
      Platform.isAndroid || Platform.isIOS;
}
