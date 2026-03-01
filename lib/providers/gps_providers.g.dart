// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'gps_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(PreferredGpsSourceType)
const preferredGpsSourceTypeProvider = PreferredGpsSourceTypeProvider._();

final class PreferredGpsSourceTypeProvider
    extends $NotifierProvider<PreferredGpsSourceType, String?> {
  const PreferredGpsSourceTypeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'preferredGpsSourceTypeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$preferredGpsSourceTypeHash();

  @$internal
  @override
  PreferredGpsSourceType create() => PreferredGpsSourceType();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$preferredGpsSourceTypeHash() =>
    r'794528d9947f7508d12fd903cd9362c10891c8c2';

abstract class _$PreferredGpsSourceType extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(SelectedGnssDeviceAddress)
const selectedGnssDeviceAddressProvider = SelectedGnssDeviceAddressProvider._();

final class SelectedGnssDeviceAddressProvider
    extends $NotifierProvider<SelectedGnssDeviceAddress, String?> {
  const SelectedGnssDeviceAddressProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGnssDeviceAddressProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGnssDeviceAddressHash();

  @$internal
  @override
  SelectedGnssDeviceAddress create() => SelectedGnssDeviceAddress();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedGnssDeviceAddressHash() =>
    r'670472be576fab22ecff1ed9cec8973bbc27cc1b';

abstract class _$SelectedGnssDeviceAddress extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(SelectedGnssDeviceName)
const selectedGnssDeviceNameProvider = SelectedGnssDeviceNameProvider._();

final class SelectedGnssDeviceNameProvider
    extends $NotifierProvider<SelectedGnssDeviceName, String?> {
  const SelectedGnssDeviceNameProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedGnssDeviceNameProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedGnssDeviceNameHash();

  @$internal
  @override
  SelectedGnssDeviceName create() => SelectedGnssDeviceName();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$selectedGnssDeviceNameHash() =>
    r'05f36b3da1395eefa96d79fdb69ebaa24806a356';

abstract class _$SelectedGnssDeviceName extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
