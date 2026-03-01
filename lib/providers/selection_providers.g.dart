// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'selection_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(SelectedLayerNode)
const selectedLayerNodeProvider = SelectedLayerNodeProvider._();

final class SelectedLayerNodeProvider
    extends $NotifierProvider<SelectedLayerNode, LayerNode?> {
  const SelectedLayerNodeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedLayerNodeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedLayerNodeHash();

  @$internal
  @override
  SelectedLayerNode create() => SelectedLayerNode();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(LayerNode? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<LayerNode?>(value),
    );
  }
}

String _$selectedLayerNodeHash() => r'0c8b2be78199e601d093a1359e82fc8e9dc35a81';

abstract class _$SelectedLayerNode extends $Notifier<LayerNode?> {
  LayerNode? build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<LayerNode?, LayerNode?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<LayerNode?, LayerNode?>,
              LayerNode?,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}

@ProviderFor(SelectedFeatures)
const selectedFeaturesProvider = SelectedFeaturesProvider._();

final class SelectedFeaturesProvider
    extends $NotifierProvider<SelectedFeatures, List<LayerTreeNode>> {
  const SelectedFeaturesProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'selectedFeaturesProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$selectedFeaturesHash();

  @$internal
  @override
  SelectedFeatures create() => SelectedFeatures();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(List<LayerTreeNode> value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<List<LayerTreeNode>>(value),
    );
  }
}

String _$selectedFeaturesHash() => r'255024ac4e97223b0976e3faff8a6b02e970f524';

abstract class _$SelectedFeatures extends $Notifier<List<LayerTreeNode>> {
  List<LayerTreeNode> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final created = build();
    final ref = this.ref as $Ref<List<LayerTreeNode>, List<LayerTreeNode>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<List<LayerTreeNode>, List<LayerTreeNode>>,
              List<LayerTreeNode>,
              Object?,
              Object?
            >;
    element.handleValue(ref, created);
  }
}
