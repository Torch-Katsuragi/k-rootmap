import 'package:latlong2/latlong.dart';

/// グローバルな描画状態とメタデータを管理するクラス
/// GPS測量とペンツールでの描画状態を共有する
class GlobalDrawingState {
  static final GlobalDrawingState instance = GlobalDrawingState._internal();
  factory GlobalDrawingState() => instance;
  GlobalDrawingState._internal();

  /// 線の描画点列（グローバル共有）
  final List<LatLng> _drawingLine = [];

  /// ポリゴンの描画点列（グローバル共有）
  final List<LatLng> _drawingPolygon = [];

  /// 描画点に対応するメタデータのリスト
  /// 各要素は Map<String, dynamic> またはnull（pen_toolでタップした点）
  final List<Map<String, dynamic>?> _lineMetadata = [];
  final List<Map<String, dynamic>?> _polygonMetadata = [];

  /// Getters
  List<LatLng> get drawingLine => List.unmodifiable(_drawingLine);
  List<LatLng> get drawingPolygon => List.unmodifiable(_drawingPolygon);
  List<Map<String, dynamic>?> get lineMetadata =>
      List.unmodifiable(_lineMetadata);
  List<Map<String, dynamic>?> get polygonMetadata =>
      List.unmodifiable(_polygonMetadata);

  /// プレビュー用の点座標（点描画用）
  LatLng? _pointPreview;
  LatLng? get pointPreview => _pointPreview;

  /// 線描画に点を追加
  /// [position] - 追加する座標
  /// [metadata] - GPSメタデータ（nullの場合はpen_toolによる点）
  void addLinePoint(LatLng position, Map<String, dynamic>? metadata) {
    _drawingLine.add(position);
    _lineMetadata.add(metadata);

    print(
      '[GlobalDrawingState] 線に点追加: $position, メタデータ: ${metadata != null ? 'あり' : 'なし'}',
    );
    print('[GlobalDrawingState] 現在の線の点数: ${_drawingLine.length}');
  }

  /// ポリゴン描画に点を追加
  /// [position] - 追加する座標
  /// [metadata] - GPSメタデータ（nullの場合はpen_toolによる点）
  void addPolygonPoint(LatLng position, Map<String, dynamic>? metadata) {
    _drawingPolygon.add(position);
    _polygonMetadata.add(metadata);

    print(
      '[GlobalDrawingState] ポリゴンに点追加: $position, メタデータ: ${metadata != null ? 'あり' : 'なし'}',
    );
    print('[GlobalDrawingState] 現在のポリゴンの点数: ${_drawingPolygon.length}');
  }

  /// 点プレビューの設定
  void setPointPreview(LatLng? position) {
    _pointPreview = position;
  }

  /// 線描画データをクリア
  void clearLine() {
    _drawingLine.clear();
    _lineMetadata.clear();
    print('[GlobalDrawingState] 線描画データをクリア');
  }

  /// ポリゴン描画データをクリア
  void clearPolygon() {
    _drawingPolygon.clear();
    _polygonMetadata.clear();
    print('[GlobalDrawingState] ポリゴン描画データをクリア');
  }

  /// 全描画データをクリア
  void clearAll() {
    clearLine();
    clearPolygon();
    _pointPreview = null;
    print('[GlobalDrawingState] 全描画データをクリア');
  }

  /// 線描画が進行中かチェック
  bool get isLineDrawing => _drawingLine.isNotEmpty;

  /// ポリゴン描画が進行中かチェック
  bool get isPolygonDrawing => _drawingPolygon.isNotEmpty;

  /// 何らかの描画が進行中かチェック
  bool get isDrawing => isLineDrawing || isPolygonDrawing;

  /// 線描画の最後の点を削除（Undo機能）
  void removeLastLinePoint() {
    if (_drawingLine.isNotEmpty) {
      final removedPoint = _drawingLine.removeLast();
      final removedMetadata = _lineMetadata.removeLast();
      print('[GlobalDrawingState] 線の最後の点を削除: $removedPoint');
    }
  }

  /// ポリゴン描画の最後の点を削除（Undo機能）
  void removeLastPolygonPoint() {
    if (_drawingPolygon.isNotEmpty) {
      final removedPoint = _drawingPolygon.removeLast();
      final removedMetadata = _polygonMetadata.removeLast();
      print('[GlobalDrawingState] ポリゴンの最後の点を削除: $removedPoint');
    }
  }

  /// メタデータ付きの線座標リストを取得
  /// 戻り値: List<Map<String, dynamic>> - 座標とメタデータを含む構造
  List<Map<String, dynamic>> getLineWithMetadata() {
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < _drawingLine.length; i++) {
      final point = _drawingLine[i];
      final metadata = _lineMetadata[i];

      if (metadata != null) {
        // GPS測量データの場合、既存のメタデータを使用
        result.add(metadata);
      } else {
        // pen_toolでタップした点の場合、座標のみのデータを作成
        result.add({
          'latitude': point.latitude,
          'longitude': point.longitude,
          'data_source': 'pen_tool',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
    return result;
  }

  /// メタデータ付きのポリゴン座標リストを取得
  /// 戻り値: List<Map<String, dynamic>> - 座標とメタデータを含む構造
  List<Map<String, dynamic>> getPolygonWithMetadata() {
    final result = <Map<String, dynamic>>[];
    for (int i = 0; i < _drawingPolygon.length; i++) {
      final point = _drawingPolygon[i];
      final metadata = _polygonMetadata[i];

      if (metadata != null) {
        // GPS測量データの場合、既存のメタデータを使用
        result.add(metadata);
      } else {
        // pen_toolでタップした点の場合、座標のみのデータを作成
        result.add({
          'latitude': point.latitude,
          'longitude': point.longitude,
          'data_source': 'pen_tool',
          'timestamp': DateTime.now().toIso8601String(),
        });
      }
    }
    return result;
  }

  /// デバッグ用情報出力
  void printDebugInfo() {
    print('[GlobalDrawingState] === デバッグ情報 ===');
    print('線の点数: ${_drawingLine.length}');
    print('ポリゴンの点数: ${_drawingPolygon.length}');
    print('点プレビュー: $_pointPreview');
    print('描画中: $isDrawing');
    print('================================');
  }
}
