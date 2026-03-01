// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'service_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(baseMapService)
const baseMapServiceProvider = BaseMapServiceProvider._();

final class BaseMapServiceProvider
    extends $FunctionalProvider<BaseMapService, BaseMapService, BaseMapService>
    with $Provider<BaseMapService> {
  const BaseMapServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'baseMapServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$baseMapServiceHash();

  @$internal
  @override
  $ProviderElement<BaseMapService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  BaseMapService create(Ref ref) {
    return baseMapService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(BaseMapService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<BaseMapService>(value),
    );
  }
}

String _$baseMapServiceHash() => r'0641143a42e82b976ad00f08e256fbff40a6afa0';

@ProviderFor(gpsManagerService)
const gpsManagerServiceProvider = GpsManagerServiceProvider._();

final class GpsManagerServiceProvider
    extends
        $FunctionalProvider<
          GpsManagerService,
          GpsManagerService,
          GpsManagerService
        >
    with $Provider<GpsManagerService> {
  const GpsManagerServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gpsManagerServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gpsManagerServiceHash();

  @$internal
  @override
  $ProviderElement<GpsManagerService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GpsManagerService create(Ref ref) {
    return gpsManagerService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GpsManagerService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GpsManagerService>(value),
    );
  }
}

String _$gpsManagerServiceHash() => r'9392df877239026a8b52afa3d2523a22b19d7994';
