import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import '../lib/utils/global_drawing_state.dart';

void main() {
  group('GlobalDrawingState Tests', () {
    late GlobalDrawingState drawingState;

    setUp(() {
      drawingState = GlobalDrawingState.instance;
      drawingState.clearAll(); // テスト開始前にクリア
    });

    test('線描画にGPS測量データを追加', () {
      // GPS測量データ（メタデータあり）
      final gpsMetadata = {
        'latitude': 35.6762,
        'longitude': 139.6503,
        'accuracy': 5.0,
        'data_source': 'gps_tool',
        'timestamp': DateTime.now().toIso8601String(),
      };

      final position = LatLng(35.6762, 139.6503);

      // GPS測量データを追加
      drawingState.addLinePoint(position, gpsMetadata);

      expect(drawingState.drawingLine.length, 1);
      expect(drawingState.lineMetadata.length, 1);
      expect(drawingState.lineMetadata[0], isNotNull);
      expect(drawingState.lineMetadata[0]!['data_source'], 'gps_tool');

      print('[TEST] GPS測量データ追加成功: ${drawingState.lineMetadata[0]}');
    });

    test('線描画にpen_toolのタップデータを追加', () {
      // pen_toolによるタップ（メタデータなし）
      final position = LatLng(35.6762, 139.6503);

      // pen_toolデータを追加
      drawingState.addLinePoint(position, null);

      expect(drawingState.drawingLine.length, 1);
      expect(drawingState.lineMetadata.length, 1);
      expect(drawingState.lineMetadata[0], isNull);

      print('[TEST] pen_toolデータ追加成功');
    });

    test('GPS測量とpen_toolの混在テスト', () {
      // 最初にpen_toolでタップ
      drawingState.addLinePoint(LatLng(35.6762, 139.6503), null);

      // 次にGPS測量
      final gpsMetadata = {
        'latitude': 35.6773,
        'longitude': 139.6514,
        'accuracy': 3.5,
        'data_source': 'gps_tool',
        'timestamp': DateTime.now().toIso8601String(),
      };
      drawingState.addLinePoint(LatLng(35.6773, 139.6514), gpsMetadata);

      // また pen_tool でタップ
      drawingState.addLinePoint(LatLng(35.6784, 139.6525), null);

      expect(drawingState.drawingLine.length, 3);
      expect(drawingState.lineMetadata.length, 3);

      // 最初の点はpen_tool（メタデータなし）
      expect(drawingState.lineMetadata[0], isNull);
      // 2番目の点はGPS測量（メタデータあり）
      expect(drawingState.lineMetadata[1], isNotNull);
      expect(drawingState.lineMetadata[1]!['data_source'], 'gps_tool');
      // 3番目の点はpen_tool（メタデータなし）
      expect(drawingState.lineMetadata[2], isNull);

      print('[TEST] 混在データ追加成功: 点数=${drawingState.drawingLine.length}');
    });

    test('メタデータ付き線座標リストの取得', () {
      // GPS測量データ
      final gpsMetadata = {
        'latitude': 35.6762,
        'longitude': 139.6503,
        'accuracy': 5.0,
        'data_source': 'gps_tool',
        'timestamp': DateTime.now().toIso8601String(),
      };
      drawingState.addLinePoint(LatLng(35.6762, 139.6503), gpsMetadata);

      // pen_toolデータ
      drawingState.addLinePoint(LatLng(35.6773, 139.6514), null);

      final lineWithMetadata = drawingState.getLineWithMetadata();

      expect(lineWithMetadata.length, 2);

      // 最初の点（GPS測量）
      expect(lineWithMetadata[0]['data_source'], 'gps_tool');
      expect(lineWithMetadata[0]['accuracy'], 5.0);

      // 2番目の点（pen_tool）
      expect(lineWithMetadata[1]['data_source'], 'pen_tool');
      expect(lineWithMetadata[1]['latitude'], 35.6773);
      expect(lineWithMetadata[1]['longitude'], 139.6514);

      print('[TEST] メタデータ付きリスト取得成功');
    });

    test('ポリゴン描画とundoテスト', () {
      // 3点のポリゴンを追加
      drawingState.addPolygonPoint(LatLng(35.6762, 139.6503), null);
      drawingState.addPolygonPoint(LatLng(35.6773, 139.6514), null);
      drawingState.addPolygonPoint(LatLng(35.6784, 139.6525), null);

      expect(drawingState.drawingPolygon.length, 3);

      // 最後の点を削除
      drawingState.removeLastPolygonPoint();
      expect(drawingState.drawingPolygon.length, 2);

      // 全クリア
      drawingState.clearPolygon();
      expect(drawingState.drawingPolygon.length, 0);
      expect(drawingState.polygonMetadata.length, 0);

      print('[TEST] ポリゴンUndo・クリア機能成功');
    });

    test('描画状態の判定テスト', () {
      expect(drawingState.isDrawing, false);
      expect(drawingState.isLineDrawing, false);
      expect(drawingState.isPolygonDrawing, false);

      // 線を開始
      drawingState.addLinePoint(LatLng(35.6762, 139.6503), null);
      expect(drawingState.isDrawing, true);
      expect(drawingState.isLineDrawing, true);
      expect(drawingState.isPolygonDrawing, false);

      // クリア
      drawingState.clearLine();
      expect(drawingState.isDrawing, false);

      // ポリゴンを開始
      drawingState.addPolygonPoint(LatLng(35.6762, 139.6503), null);
      expect(drawingState.isDrawing, true);
      expect(drawingState.isLineDrawing, false);
      expect(drawingState.isPolygonDrawing, true);

      print('[TEST] 描画状態判定成功');
    });

    test('プレビュー機能テスト', () {
      expect(drawingState.pointPreview, isNull);

      final previewPos = LatLng(35.6762, 139.6503);
      drawingState.setPointPreview(previewPos);
      expect(drawingState.pointPreview, previewPos);

      drawingState.setPointPreview(null);
      expect(drawingState.pointPreview, isNull);

      print('[TEST] プレビュー機能成功');
    });
  });
}
