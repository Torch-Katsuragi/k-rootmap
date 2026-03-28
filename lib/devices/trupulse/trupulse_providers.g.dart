// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trupulse_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// TruPulseServiceのシングルトンインスタンス

@ProviderFor(trupulseService)
const trupulseServiceProvider = TrupulseServiceProvider._();

/// TruPulseServiceのシングルトンインスタンス

final class TrupulseServiceProvider
    extends
        $FunctionalProvider<TruPulseService, TruPulseService, TruPulseService>
    with $Provider<TruPulseService> {
  /// TruPulseServiceのシングルトンインスタンス
  const TrupulseServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trupulseServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trupulseServiceHash();

  @$internal
  @override
  $ProviderElement<TruPulseService> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TruPulseService create(Ref ref) {
    return trupulseService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TruPulseService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TruPulseService>(value),
    );
  }
}

String _$trupulseServiceHash() => r'14d2a8d24c59fdd6ad09c9747be30b129cde450f';

/// TruPulseToolのシングルトンインスタンス

@ProviderFor(trupulseTool)
const trupulseToolProvider = TrupulseToolProvider._();

/// TruPulseToolのシングルトンインスタンス

final class TrupulseToolProvider
    extends $FunctionalProvider<TruPulseTool, TruPulseTool, TruPulseTool>
    with $Provider<TruPulseTool> {
  /// TruPulseToolのシングルトンインスタンス
  const TrupulseToolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trupulseToolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trupulseToolHash();

  @$internal
  @override
  $ProviderElement<TruPulseTool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  TruPulseTool create(Ref ref) {
    return trupulseTool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TruPulseTool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TruPulseTool>(value),
    );
  }
}

String _$trupulseToolHash() => r'bfa2b721f3c5304129de41c0bf6929a0ac2cc1dc';
