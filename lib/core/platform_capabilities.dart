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
