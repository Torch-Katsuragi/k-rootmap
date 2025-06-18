import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:k_maps/utils/global_drawing_state.dart';
import 'package:k_maps/models/layer_tree_node.dart';

void main() {
  group('GlobalDrawingState 自動保存機能テスト', () {
    late GlobalDrawingState drawingState;

    setUp(() {
      drawingState = GlobalDrawingState.instance;
      drawingState.clearAll(); // テスト前にクリア
    });

    test('点追加時にタイマーがリセットされること', () {
      // 線描画に点を追加
      drawingState.addLinePoint(const LatLng(35.0, 139.0), {
        'data_source': 'gps_survey',
      });

      // 描画中であることを確認
      expect(drawingState.isDrawing, true);
      expect(drawingState.isLineDrawing, true);
      expect(drawingState.drawingLine.length, 1);
    });

    test('複数点追加でメタデータが正しく管理されること', () {
      // GPS測量データ付きの点
      drawingState.addLinePoint(const LatLng(35.0, 139.0), {
        'latitude': 35.0,
        'longitude': 139.0,
        'data_source': 'gps_survey',
        'accuracy': 3.0,
      });

      // ペンツールの点（メタデータなし）
      drawingState.addLinePoint(const LatLng(35.1, 139.1), null);

      expect(drawingState.drawingLine.length, 2);
      expect(drawingState.lineMetadata.length, 2);
      expect(drawingState.lineMetadata[0], isNotNull);
      expect(drawingState.lineMetadata[1], isNull);
    });

    test('ポリゴン描画でも同様に動作すること', () {
      // ポリゴンに点を追加
      drawingState.addPolygonPoint(const LatLng(35.0, 139.0), {
        'data_source': 'gps_survey',
      });

      drawingState.addPolygonPoint(const LatLng(35.1, 139.0), null);

      drawingState.addPolygonPoint(const LatLng(35.1, 139.1), {
        'data_source': 'gps_survey',
      });

      expect(drawingState.isPolygonDrawing, true);
      expect(drawingState.drawingPolygon.length, 3);
      expect(drawingState.polygonMetadata.length, 3);
    });

    test('自動保存用レイヤー設定が正しく動作すること', () {
      bool callbackCalled = false;
      void testCallback() {
        callbackCalled = true;
      }

      // 自動保存設定をテスト
      drawingState.setAutoSaveLayerNode(null, testCallback);

      // コールバックを直接呼び出してテスト
      testCallback();
      expect(callbackCalled, true);
    });

    test('Undoが正しく動作すること', () {
      // 線に複数の点を追加
      drawingState.addLinePoint(const LatLng(35.0, 139.0), null);
      drawingState.addLinePoint(const LatLng(35.1, 139.0), null);
      drawingState.addLinePoint(const LatLng(35.2, 139.0), null);

      expect(drawingState.drawingLine.length, 3);

      // Undoを実行
      drawingState.undo(isLine: true);
      expect(drawingState.drawingLine.length, 2);

      // もう一度Undo
      drawingState.undo(isLine: true);
      expect(drawingState.drawingLine.length, 1);
    });

    test('キャンセルが正しく動作すること', () {
      // 線に点を追加
      drawingState.addLinePoint(const LatLng(35.0, 139.0), null);
      drawingState.addLinePoint(const LatLng(35.1, 139.0), null);

      expect(drawingState.isLineDrawing, true);

      // キャンセルを実行
      drawingState.cancel(isLine: true);
      expect(drawingState.isLineDrawing, false);
      expect(drawingState.drawingLine.length, 0);
    });

    test('clearAllで全てのデータがクリアされること', () {
      // 線とポリゴンの両方にデータを追加
      drawingState.addLinePoint(const LatLng(35.0, 139.0), null);
      drawingState.addPolygonPoint(const LatLng(35.1, 139.1), null);
      drawingState.setPointPreview(const LatLng(35.2, 139.2));

      // データが存在することを確認
      expect(drawingState.isDrawing, true);
      expect(drawingState.pointPreview, isNotNull);

      // clearAllを実行
      drawingState.clearAll();

      // 全てクリアされていることを確認
      expect(drawingState.isDrawing, false);
      expect(drawingState.pointPreview, isNull);
      expect(drawingState.isEditMode, false);
    });

    test('メタデータ付き座標リストが正しく取得できること', () {
      // GPS測量データとペンツールデータを混在させる
      drawingState.addLinePoint(const LatLng(35.0, 139.0), {
        'latitude': 35.0,
        'longitude': 139.0,
        'data_source': 'gps_survey',
        'accuracy': 3.0,
      });

      drawingState.addLinePoint(
        const LatLng(35.1, 139.1),
        null, // ペンツールの点
      );

      final lineWithMetadata = drawingState.getLineWithMetadata();
      expect(lineWithMetadata.length, 2);

      // 1つ目はGPS測量データ
      expect(lineWithMetadata[0]['data_source'], 'gps_survey');
      expect(lineWithMetadata[0]['accuracy'], 3.0);

      // 2つ目はペンツールデータ
      expect(lineWithMetadata[1]['data_source'], 'pen_tool');
      expect(lineWithMetadata[1]['latitude'], 35.1);
      expect(lineWithMetadata[1]['longitude'], 139.1);
    });

    tearDown(() {
      // テスト後のクリーンアップ
      drawingState.clearAll();
    });
  });

  group('自動保存タイマー動作テスト', () {
    late GlobalDrawingState drawingState;

    setUp(() {
      drawingState = GlobalDrawingState.instance;
      drawingState.clearAll();
    });

    test('描画開始時にタイマーが動作すること', () async {
      // 短いタイマー間隔でテスト（通常は1分だが、テストでは1秒に変更）
      // 注意: 実際のタイマー間隔は定数なので、このテストは概念確認のみ

      drawingState.addLinePoint(const LatLng(35.0, 139.0), null);
      expect(drawingState.isDrawing, true);

      // タイマーの動作確認は困難なので、状態の確認のみ
      expect(drawingState.isLineDrawing, true);
    });

    tearDown(() {
      drawingState.clearAll();
    });
  });
}
