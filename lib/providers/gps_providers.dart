import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'gps_providers.g.dart';

@Riverpod(keepAlive: true)
class PreferredGpsSourceType extends _$PreferredGpsSourceType {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

@Riverpod(keepAlive: true)
class SelectedGnssDeviceAddress extends _$SelectedGnssDeviceAddress {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

@Riverpod(keepAlive: true)
class SelectedGnssDeviceName extends _$SelectedGnssDeviceName {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}
