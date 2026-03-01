import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'project_providers.g.dart';

@Riverpod(keepAlive: true)
class ProjectRootDir extends _$ProjectRootDir {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

@Riverpod(keepAlive: true)
class GlobalFolderPath extends _$GlobalFolderPath {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}
