// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_providers.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ProjectRootDir)
const projectRootDirProvider = ProjectRootDirProvider._();

final class ProjectRootDirProvider
    extends $NotifierProvider<ProjectRootDir, String?> {
  const ProjectRootDirProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'projectRootDirProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$projectRootDirHash();

  @$internal
  @override
  ProjectRootDir create() => ProjectRootDir();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$projectRootDirHash() => r'3d287359e8c1e22d0dfd3ce4fab5cd0d32b5001e';

abstract class _$ProjectRootDir extends $Notifier<String?> {
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

@ProviderFor(GlobalFolderPath)
const globalFolderPathProvider = GlobalFolderPathProvider._();

final class GlobalFolderPathProvider
    extends $NotifierProvider<GlobalFolderPath, String?> {
  const GlobalFolderPathProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'globalFolderPathProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$globalFolderPathHash();

  @$internal
  @override
  GlobalFolderPath create() => GlobalFolderPath();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$globalFolderPathHash() => r'30ffba3208a214183b7f035f11b556e67a664298';

abstract class _$GlobalFolderPath extends $Notifier<String?> {
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
