// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tool_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(panTool)
const panToolProvider = PanToolProvider._();

final class PanToolProvider
    extends $FunctionalProvider<PanTool, PanTool, PanTool>
    with $Provider<PanTool> {
  const PanToolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'panToolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$panToolHash();

  @$internal
  @override
  $ProviderElement<PanTool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PanTool create(Ref ref) {
    return panTool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PanTool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PanTool>(value),
    );
  }
}

String _$panToolHash() => r'bc4514a1c1efe171624ac326c3da109e6f89ee97';

@ProviderFor(penTool)
const penToolProvider = PenToolProvider._();

final class PenToolProvider
    extends $FunctionalProvider<PenTool, PenTool, PenTool>
    with $Provider<PenTool> {
  const PenToolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'penToolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$penToolHash();

  @$internal
  @override
  $ProviderElement<PenTool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  PenTool create(Ref ref) {
    return penTool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(PenTool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<PenTool>(value),
    );
  }
}

String _$penToolHash() => r'4e97f852738668bba170050a732e996b7f67b778';

@ProviderFor(selectTool)
const selectToolProvider = SelectToolProvider._();

final class SelectToolProvider
    extends $FunctionalProvider<SelectTool, SelectTool, SelectTool>
    with $Provider<SelectTool> {
  const SelectToolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectToolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectToolHash();

  @$internal
  @override
  $ProviderElement<SelectTool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  SelectTool create(Ref ref) {
    return selectTool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(SelectTool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<SelectTool>(value),
    );
  }
}

String _$selectToolHash() => r'1b9745062c4c985f4a223981d7668dcdd98bd048';

@ProviderFor(gpsTool)
const gpsToolProvider = GpsToolProvider._();

final class GpsToolProvider
    extends $FunctionalProvider<GpsTool, GpsTool, GpsTool>
    with $Provider<GpsTool> {
  const GpsToolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'gpsToolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$gpsToolHash();

  @$internal
  @override
  $ProviderElement<GpsTool> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  GpsTool create(Ref ref) {
    return gpsTool(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GpsTool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GpsTool>(value),
    );
  }
}

String _$gpsToolHash() => r'26330ed45d4842f0d361eb844fb83214781f22e1';

@ProviderFor(CurrentTool)
const currentToolProvider = CurrentToolProvider._();

final class CurrentToolProvider
    extends $NotifierProvider<CurrentTool, MapTool> {
  const CurrentToolProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'currentToolProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$currentToolHash();

  @$internal
  @override
  CurrentTool create() => CurrentTool();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MapTool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MapTool>(value),
    );
  }
}

String _$currentToolHash() => r'2f373b959389cc71c97f81f58eaeb417e5ca4297';

abstract class _$CurrentTool extends $Notifier<MapTool> {
  MapTool build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<MapTool, MapTool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MapTool, MapTool>,
              MapTool,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
