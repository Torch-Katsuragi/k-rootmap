import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../services/basemap_service.dart';
import '../services/gps_manager_service.dart';

part 'service_providers.g.dart';

@Riverpod(keepAlive: true)
BaseMapService baseMapService(Ref ref) => BaseMapService();

@Riverpod(keepAlive: true)
GpsManagerService gpsManagerService(Ref ref) {
  final service = GpsManagerService();
  service.setRef(ref);
  return service;
}
