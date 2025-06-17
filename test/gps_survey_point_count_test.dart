import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/utils/global_config.dart';
import '../lib/utils/global_drawing_state.dart';

void main() {
  group('GPS Survey Point Count Tests', () {
    late GlobalDrawingState drawingState;

    setUp(() {
      drawingState = GlobalDrawingState();
      // グローバルシングルトンのデータをクリア
      drawingState.clearAll();
    });

    test('メタデータありGPS測量点の点数を正しく取得できる', () {
      // GPS測量でメタデータ付きの点を追加
      final testPoint = LatLng(35.681236, 139.767125);
      final metadata = {
        'data_source': 'gps_tool',
        'point_count': 5, // 5回測量
        'accuracy': 2.5,
        'timestamp': '2024-01-01T12:00:00Z',
      };

      drawingState.addLinePoint(testPoint, metadata);

      // メタデータから点数が正しく取得できることを確認
      expect(drawingState.lineMetadata.length, 1);
      expect(drawingState.lineMetadata[0]!['point_count'], 5);
    });

    test('長押し平均化GPS測量点の点数を正しく取得できる', () {
      // 長押し平均化測量でcollected_pointsを持つ点を追加
      final testPoint = LatLng(35.681236, 139.767125);
      final collectedPoints = [
        {'lat': 35.681230, 'lng': 139.767120},
        {'lat': 35.681235, 'lng': 139.767125},
        {'lat': 35.681240, 'lng': 139.767130},
      ];
      final metadata = {
        'data_source': 'gps_tool',
        'collected_points': collectedPoints,
        'averaging_duration': 3.0,
        'timestamp': '2024-01-01T12:00:00Z',
      };

      drawingState.addPolygonPoint(testPoint, metadata);

      // メタデータから収集された点数が正しく取得できることを確認
      expect(drawingState.polygonMetadata.length, 1);
      expect(
        (drawingState.polygonMetadata[0]!['collected_points'] as List).length,
        3,
      );
    });

    test('pen_toolタップ点（メタデータなし）は1を返す', () {
      // pen_toolでメタデータなしの点を追加
      final testPoint = LatLng(35.681236, 139.767125);

      drawingState.addLinePoint(testPoint, null); // メタデータなし

      // メタデータがnullであることを確認
      expect(drawingState.lineMetadata.length, 1);
      expect(drawingState.lineMetadata[0], null);
    });

    test('混在データ（GPS測量 + pen_tool）で適切に識別できる', () {
      // GPS測量点
      final gpsPoint = LatLng(35.681236, 139.767125);
      final gpsMetadata = {
        'data_source': 'gps_tool',
        'point_count': 3,
        'accuracy': 1.8,
        'timestamp': '2024-01-01T12:00:00Z',
      };

      // pen_tool点
      final tapPoint = LatLng(35.681300, 139.767200);

      drawingState.addLinePoint(gpsPoint, gpsMetadata);
      drawingState.addLinePoint(tapPoint, null); // メタデータなし

      expect(drawingState.lineMetadata.length, 2);
      expect(drawingState.lineMetadata[0]!['point_count'], 3);
      expect(drawingState.lineMetadata[1], null);
    });

    test('単発GPS測量点（point_count未指定）は1を返す', () {
      // 単発GPS測量（point_countが未指定）
      final testPoint = LatLng(35.681236, 139.767125);
      final metadata = {
        'data_source': 'gps_tool',
        'accuracy': 2.1,
        'timestamp': '2024-01-01T12:00:00Z',
        // point_countが未指定
      };

      drawingState.addPolygonPoint(testPoint, metadata);

      expect(drawingState.polygonMetadata.length, 1);
      expect(drawingState.polygonMetadata[0]!['data_source'], 'gps_tool');
      expect(
        drawingState.polygonMetadata[0]!.containsKey('point_count'),
        false,
      );
    });

    test('無効なインデックスでも例外が発生しない', () {
      // 空の状態で無効なインデックスをテスト
      expect(drawingState.lineMetadata.length, 0);
      expect(drawingState.polygonMetadata.length, 0);

      // リストが空でもアクセスエラーが起きないことを確認
      expect(drawingState.drawingLine.isEmpty, true);
      expect(drawingState.drawingPolygon.isEmpty, true);
    });
  });
}
