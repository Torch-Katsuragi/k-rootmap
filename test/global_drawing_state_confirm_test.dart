import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/utils/global_drawing_state.dart';

void main() {
  group('GlobalDrawingState 権限移譲テスト', () {
    late GlobalDrawingState drawingState;

    setUp(() {
      drawingState = GlobalDrawingState.instance;
      drawingState.clearAll();
    });

    test('統一undo処理のテスト', () {
      // 線のデータを追加
      drawingState.addLinePoint(LatLng(35.0, 139.0), null);
      drawingState.addLinePoint(LatLng(35.1, 139.1), null);
      expect(drawingState.drawingLine.length, 2);

      // 線のundo
      drawingState.undo(isLine: true);
      expect(drawingState.drawingLine.length, 1);

      // ポリゴンのデータを追加
      drawingState.addPolygonPoint(LatLng(35.0, 139.0), null);
      drawingState.addPolygonPoint(LatLng(35.1, 139.1), null);
      drawingState.addPolygonPoint(LatLng(35.1, 139.0), null);
      expect(drawingState.drawingPolygon.length, 3);

      // ポリゴンのundo
      drawingState.undo(isLine: false);
      expect(drawingState.drawingPolygon.length, 2);

      print('[TEST] 統一undo処理テスト完了');
    });

    test('統一cancel処理のテスト', () {
      // 線とポリゴンにデータを追加
      drawingState.addLinePoint(LatLng(35.0, 139.0), null);
      drawingState.addLinePoint(LatLng(35.1, 139.1), null);
      drawingState.addPolygonPoint(LatLng(35.0, 139.0), null);
      drawingState.addPolygonPoint(LatLng(35.1, 139.1), null);

      expect(drawingState.drawingLine.length, 2);
      expect(drawingState.drawingPolygon.length, 2);

      // 線のcancel
      drawingState.cancel(isLine: true);
      expect(drawingState.drawingLine.length, 0);
      expect(drawingState.drawingPolygon.length, 2); // ポリゴンはそのまま

      // ポリゴンのcancel
      drawingState.cancel(isLine: false);
      expect(drawingState.drawingPolygon.length, 0);

      print('[TEST] 統一cancel処理テスト完了');
    });

    test('描画統計情報のテスト', () {
      // GPS測量データ風のメタデータ
      final gpsMetadata1 = {
        'latitude': 35.0,
        'longitude': 139.0,
        'data_source': 'gps_survey',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final gpsMetadata2 = {
        'latitude': 35.1,
        'longitude': 139.1,
        'data_source': 'gps_survey',
        'timestamp': DateTime.now().toIso8601String(),
      };

      // 線にGPSとPenデータを混在で追加
      drawingState.addLinePoint(LatLng(35.0, 139.0), gpsMetadata1); // GPS
      drawingState.addLinePoint(LatLng(35.1, 139.1), null); // Pen
      drawingState.addLinePoint(LatLng(35.2, 139.2), gpsMetadata2); // GPS

      // ポリゴンにもデータ追加
      drawingState.addPolygonPoint(LatLng(36.0, 140.0), null); // Pen
      drawingState.addPolygonPoint(LatLng(36.1, 140.1), gpsMetadata1); // GPS

      final stats = drawingState.getDrawingStats();

      expect(stats['line_points'], 3);
      expect(stats['line_gps_points'], 2);
      expect(stats['line_pen_points'], 1);
      expect(stats['polygon_points'], 2);
      expect(stats['polygon_gps_points'], 1);
      expect(stats['polygon_pen_points'], 1);

      print('[TEST] 描画統計: $stats');
      print('[TEST] 描画統計情報テスト完了');
    });

    test('メタデータ統合のテスト', () {
      // GPS測量データとpen_toolデータを混在で追加
      final gpsMetadata = {
        'latitude': 35.0,
        'longitude': 139.0,
        'data_source': 'gps_survey',
        'accuracy': 2.5,
        'timestamp': DateTime.now().toIso8601String(),
      };

      drawingState.addLinePoint(LatLng(35.0, 139.0), gpsMetadata);
      drawingState.addLinePoint(LatLng(35.1, 139.1), null); // pen_tool

      final lineWithMetadata = drawingState.getLineWithMetadata();

      expect(lineWithMetadata.length, 2);

      // 1番目はGPSデータ
      expect(lineWithMetadata[0]['data_source'], 'gps_survey');
      expect(lineWithMetadata[0]['accuracy'], 2.5);

      // 2番目はpen_toolデータ
      expect(lineWithMetadata[1]['data_source'], 'pen_tool');
      expect(lineWithMetadata[1]['latitude'], 35.1);
      expect(lineWithMetadata[1]['longitude'], 139.1);

      print('[TEST] 線メタデータ統合: $lineWithMetadata');
      print('[TEST] メタデータ統合テスト完了');
    });

    test('描画状態チェックのテスト', () {
      expect(drawingState.isDrawing, false);
      expect(drawingState.isLineDrawing, false);
      expect(drawingState.isPolygonDrawing, false);

      // 線に点を追加
      drawingState.addLinePoint(LatLng(35.0, 139.0), null);
      expect(drawingState.isDrawing, true);
      expect(drawingState.isLineDrawing, true);
      expect(drawingState.isPolygonDrawing, false);

      // ポリゴンにも点を追加
      drawingState.addPolygonPoint(LatLng(36.0, 140.0), null);
      expect(drawingState.isDrawing, true);
      expect(drawingState.isLineDrawing, true);
      expect(drawingState.isPolygonDrawing, true);

      // 線をクリア
      drawingState.clearLine();
      expect(drawingState.isDrawing, true);
      expect(drawingState.isLineDrawing, false);
      expect(drawingState.isPolygonDrawing, true);

      // 全クリア
      drawingState.clearAll();
      expect(drawingState.isDrawing, false);
      expect(drawingState.isLineDrawing, false);
      expect(drawingState.isPolygonDrawing, false);

      print('[TEST] 描画状態チェックテスト完了');
    });
  });
}
