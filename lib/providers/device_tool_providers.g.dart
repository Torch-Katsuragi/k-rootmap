// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'device_tool_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// DeviceTool のオーバーレイ再描画トリガー
///
/// featureRefreshTriggerProvider と同パターン。
/// DeviceTool 内部状態が変わった際に trigger() を呼び、
/// map_page 側の ref.listen で triggerSetState を発火する。

@ProviderFor(DeviceToolOverlayRefresh)
const deviceToolOverlayRefreshProvider = DeviceToolOverlayRefreshProvider._();

/// DeviceTool のオーバーレイ再描画トリガー
///
/// featureRefreshTriggerProvider と同パターン。
/// DeviceTool 内部状態が変わった際に trigger() を呼び、
/// map_page 側の ref.listen で triggerSetState を発火する。
final class DeviceToolOverlayRefreshProvider
    extends $NotifierProvider<DeviceToolOverlayRefresh, int> {
  /// DeviceTool のオーバーレイ再描画トリガー
  ///
  /// featureRefreshTriggerProvider と同パターン。
  /// DeviceTool 内部状態が変わった際に trigger() を呼び、
  /// map_page 側の ref.listen で triggerSetState を発火する。
  const DeviceToolOverlayRefreshProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deviceToolOverlayRefreshProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deviceToolOverlayRefreshHash();

  @$internal
  @override
  DeviceToolOverlayRefresh create() => DeviceToolOverlayRefresh();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(int value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<int>(value),
    );
  }
}

String _$deviceToolOverlayRefreshHash() =>
    r'535f46041d4d4783583c71ee669623a4b0e6c10b';

/// DeviceTool のオーバーレイ再描画トリガー
///
/// featureRefreshTriggerProvider と同パターン。
/// DeviceTool 内部状態が変わった際に trigger() を呼び、
/// map_page 側の ref.listen で triggerSetState を発火する。

abstract class _$DeviceToolOverlayRefresh extends $Notifier<int> {
  int build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<int, int>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<int, int>,
              int,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

/// 接続済みで利用可能なDeviceToolのリストを返す
///
/// 各サービスの ChangeNotifier を addListener で購読し、
/// isConnected 変更時にプロバイダを再評価する。

@ProviderFor(connectedDeviceTools)
const connectedDeviceToolsProvider = ConnectedDeviceToolsProvider._();

/// 接続済みで利用可能なDeviceToolのリストを返す
///
/// 各サービスの ChangeNotifier を addListener で購読し、
/// isConnected 変更時にプロバイダを再評価する。

final class ConnectedDeviceToolsProvider
    extends
        $FunctionalProvider<
          List<DeviceTool>,
          List<DeviceTool>,
          List<DeviceTool>
        >
    with $Provider<List<DeviceTool>> {
  /// 接続済みで利用可能なDeviceToolのリストを返す
  ///
  /// 各サービスの ChangeNotifier を addListener で購読し、
  /// isConnected 変更時にプロバイダを再評価する。
  const ConnectedDeviceToolsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectedDeviceToolsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectedDeviceToolsHash();

  @$internal
  @override
  $ProviderElement<List<DeviceTool>> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  List<DeviceTool> create(Ref ref) {
    return connectedDeviceTools(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<DeviceTool> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<DeviceTool>>(value),
    );
  }
}

String _$connectedDeviceToolsHash() =>
    r'c3f220bbaf81fdc67ffda56c8b0bd25a106a4de9';
