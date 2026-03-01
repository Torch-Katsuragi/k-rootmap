// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'drawing_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(drawingState)
const drawingStateProvider = DrawingStateProvider._();

final class DrawingStateProvider
    extends
        $FunctionalProvider<
          GlobalDrawingState,
          GlobalDrawingState,
          GlobalDrawingState
        >
    with $Provider<GlobalDrawingState> {
  const DrawingStateProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'drawingStateProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$drawingStateHash();

  @$internal
  @override
  $ProviderElement<GlobalDrawingState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  GlobalDrawingState create(Ref ref) {
    return drawingState(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(GlobalDrawingState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<GlobalDrawingState>(value),
    );
  }
}

String _$drawingStateHash() => r'7899d4b5728892cc2aed57ef034ea4f12e859ab5';
