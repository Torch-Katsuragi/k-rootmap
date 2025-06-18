import 'package:latlong2/latlong.dart';
import '../models/layer_tree_node.dart';

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

  /// 追記モード関連
  /// 追記対象のFeatureNode（nullの場合は新規作成モード）
  FeatureNode? _editingFeature;

  /// 追記モードかどうか
  bool get isEditMode => _editingFeature != null;

  /// 追記対象のFeatureNode
  FeatureNode? get editingFeature => _editingFeature;

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
    _editingFeature = null; // 追記モードもクリア
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

  /// 元に戻す処理（Undo）- 統一インターフェース
  /// [isLine] - true: 線の最後の点を削除, false: ポリゴンの最後の点を削除
  void undo({required bool isLine}) {
    if (isLine && isLineDrawing) {
      removeLastLinePoint();
    } else if (!isLine && isPolygonDrawing) {
      removeLastPolygonPoint();
    } else {
      print('[GlobalDrawingState] Undo: 削除する点がありません');
    }
  }

  /// キャンセル処理 - 統一インターフェース
  /// [isLine] - true: 線描画をクリア, false: ポリゴン描画をクリア
  void cancel({required bool isLine}) {
    if (isLine) {
      clearLine();
    } else {
      clearPolygon();
    }
    print('[GlobalDrawingState] ${isLine ? '線' : 'ポリゴン'}描画をキャンセル');
  }

  /// 線フィーチャの確定作成・更新
  /// [layerNode] - 作成先のLayerNode（新規作成の場合のみ）
  /// [name] - フィーチャ名
  /// [description] - フィーチャ説明
  /// [additionalMetadata] - 追加メタデータ（GPS測量データなど）
  /// [refreshCallback] - フィーチャ作成後のUI更新コールバック
  Future<bool> confirmLineFeature({
    LineLayerNode? layerNode,
    required String name,
    required String description,
    Map<String, dynamic>? additionalMetadata,
    void Function()? refreshCallback,
  }) async {
    if (_drawingLine.length < 2) {
      print('[GlobalDrawingState] 線確定: 点数が不足しています（最低2点必要）');
      return false;
    }

    try {
      // メタデータを統合
      final metadata = <String, dynamic>{};
      if (additionalMetadata != null) {
        metadata.addAll(additionalMetadata);
      }

      // GPS測量データまたはpen_toolデータを含める
      final pointsWithMetadata = getLineWithMetadata();
      if (pointsWithMetadata.isNotEmpty) {
        metadata['drawing_points'] = pointsWithMetadata;
      }

      if (isEditMode && _editingFeature is LineFeatureNode) {
        // 追記モード：既存フィーチャを更新
        final feature = _editingFeature as LineFeatureNode;

        // updateGeometryで新しいジオメトリと属性を同時に更新
        final success = await feature.updateGeometry(
          name: name.isNotEmpty ? name : feature.name,
          description: description,
          metadata: metadata.isNotEmpty ? metadata : null,
          newGeometry: List<LatLng>.from(_drawingLine),
        );

        if (success) {
          print('[GlobalDrawingState] 線フィーチャを更新しました: $name');
        } else {
          print('[GlobalDrawingState] 線フィーチャ更新エラー');
          return false;
        }
      } else {
        // 新規作成モード
        if (layerNode == null) {
          print('[GlobalDrawingState] 新規作成にはlayerNodeが必要です');
          return false;
        }

        await LineFeatureNode.createIn(
          layerNode,
          List<LatLng>.from(_drawingLine),
          name.isNotEmpty ? name : '線フィーチャ',
          description,
          metadata: metadata.isNotEmpty ? metadata : null,
        );

        print('[GlobalDrawingState] 線フィーチャを確定作成しました: $name');
      }

      // 描画データをクリア
      clearAll();

      // UI更新（追記モードの場合はより強力な更新を実行）
      refreshCallback?.call();

      // 追記モードの場合はデバッグログ出力
      if (isEditMode) {
        print('[GlobalDrawingState] 追記モード完了 - UI強制更新を実行');
      }

      return true;
    } catch (e) {
      print('[GlobalDrawingState] 線フィーチャ処理エラー: $e');
      return false;
    }
  }

  /// ポリゴンフィーチャの確定作成・更新
  /// [layerNode] - 作成先のLayerNode（新規作成の場合のみ）
  /// [name] - フィーチャ名
  /// [description] - フィーチャ説明
  /// [closeRing] - ポリゴンを閉じる処理
  /// [additionalMetadata] - 追加メタデータ（GPS測量データなど）
  /// [refreshCallback] - フィーチャ作成後のUI更新コールバック
  Future<bool> confirmPolygonFeature({
    PolygonLayerNode? layerNode,
    required String name,
    required String description,
    required List<LatLng> Function(List<LatLng>) closeRing,
    Map<String, dynamic>? additionalMetadata,
    void Function()? refreshCallback,
  }) async {
    if (_drawingPolygon.length < 3) {
      print('[GlobalDrawingState] ポリゴン確定: 点数が不足しています（最低3点必要）');
      return false;
    }

    try {
      // ポリゴンを閉じる
      final closedPolygon = closeRing(_drawingPolygon);

      // メタデータを統合
      final metadata = <String, dynamic>{};
      if (additionalMetadata != null) {
        metadata.addAll(additionalMetadata);
      }

      // GPS測量データまたはpen_toolデータを含める
      final pointsWithMetadata = getPolygonWithMetadata();
      if (pointsWithMetadata.isNotEmpty) {
        metadata['drawing_points'] = pointsWithMetadata;
      }

      if (isEditMode && _editingFeature is PolygonFeatureNode) {
        // 追記モード：既存フィーチャを更新
        final feature = _editingFeature as PolygonFeatureNode;

        // updateGeometryで新しいジオメトリと属性を同時に更新
        final success = await feature.updateGeometry(
          name: name.isNotEmpty ? name : feature.name,
          description: description,
          metadata: metadata.isNotEmpty ? metadata : null,
          newGeometry: [closedPolygon],
        );

        if (success) {
          print('[GlobalDrawingState] ポリゴンフィーチャを更新しました: $name');
        } else {
          print('[GlobalDrawingState] ポリゴンフィーチャ更新エラー');
          return false;
        }
      } else {
        // 新規作成モード
        if (layerNode == null) {
          print('[GlobalDrawingState] 新規作成にはlayerNodeが必要です');
          return false;
        }

        await PolygonFeatureNode.createIn(
          layerNode,
          [closedPolygon],
          name.isNotEmpty ? name : 'ポリゴンフィーチャ',
          description,
          metadata: metadata.isNotEmpty ? metadata : null,
        );

        print('[GlobalDrawingState] ポリゴンフィーチャを確定作成しました: $name');
      }

      // 描画データをクリア
      clearAll();

      // UI更新（追記モードの場合はより強力な更新を実行）
      refreshCallback?.call();

      // 追記モードの場合はデバッグログ出力
      if (isEditMode) {
        print('[GlobalDrawingState] 追記モード完了 - UI強制更新を実行');
      }

      return true;
    } catch (e) {
      print('[GlobalDrawingState] ポリゴンフィーチャ処理エラー: $e');
      return false;
    }
  }

  /// 汎用的な確定処理
  /// [layerNode] - 作成先のLayerNode（新規作成の場合のみ）
  /// [name] - フィーチャ名
  /// [description] - フィーチャ説明
  /// [closeRing] - ポリゴンを閉じる処理（PolygonLayerNodeの場合のみ）
  /// [additionalMetadata] - 追加メタデータ
  /// [refreshCallback] - フィーチャ作成後のUI更新コールバック
  Future<bool> confirmCurrentFeature({
    LayerNode? layerNode,
    required String name,
    required String description,
    List<LatLng> Function(List<LatLng>)? closeRing,
    Map<String, dynamic>? additionalMetadata,
    void Function()? refreshCallback,
  }) async {
    // 追記モードの場合、layerNodeは不要
    if (isEditMode) {
      if (_editingFeature is LineFeatureNode && isLineDrawing) {
        return await confirmLineFeature(
          name: name,
          description: description,
          additionalMetadata: additionalMetadata,
          refreshCallback: refreshCallback,
        );
      } else if (_editingFeature is PolygonFeatureNode && isPolygonDrawing) {
        if (closeRing == null) {
          print('[GlobalDrawingState] ポリゴン確定: closeRing関数が必要です');
          return false;
        }
        return await confirmPolygonFeature(
          name: name,
          description: description,
          closeRing: closeRing,
          additionalMetadata: additionalMetadata,
          refreshCallback: refreshCallback,
        );
      }
    } else {
      // 新規作成モード
      if (layerNode == null) {
        print('[GlobalDrawingState] 新規作成にはlayerNodeが必要です');
        return false;
      }

      if (layerNode is LineLayerNode && isLineDrawing) {
        return await confirmLineFeature(
          layerNode: layerNode,
          name: name,
          description: description,
          additionalMetadata: additionalMetadata,
          refreshCallback: refreshCallback,
        );
      } else if (layerNode is PolygonLayerNode && isPolygonDrawing) {
        if (closeRing == null) {
          print('[GlobalDrawingState] ポリゴン確定: closeRing関数が必要です');
          return false;
        }
        return await confirmPolygonFeature(
          layerNode: layerNode,
          name: name,
          description: description,
          closeRing: closeRing,
          additionalMetadata: additionalMetadata,
          refreshCallback: refreshCallback,
        );
      }
    }

    print('[GlobalDrawingState] 確定処理: 有効な描画データまたはレイヤーがありません');
    return false;
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

  /// 描画状態の統計情報を取得
  Map<String, int> getDrawingStats() {
    return {
      'line_points': _drawingLine.length,
      'polygon_points': _drawingPolygon.length,
      'line_gps_points': _lineMetadata.where((m) => m != null).length,
      'polygon_gps_points': _polygonMetadata.where((m) => m != null).length,
      'line_pen_points': _lineMetadata.where((m) => m == null).length,
      'polygon_pen_points': _polygonMetadata.where((m) => m == null).length,
    };
  }

  /// デバッグ用情報出力
  void printDebugInfo() {
    final stats = getDrawingStats();
    print('[GlobalDrawingState] === デバッグ情報 ===');
    print(
      '線の点数: ${stats['line_points']} (GPS: ${stats['line_gps_points']}, Pen: ${stats['line_pen_points']})',
    );
    print(
      'ポリゴンの点数: ${stats['polygon_points']} (GPS: ${stats['polygon_gps_points']}, Pen: ${stats['polygon_pen_points']})',
    );
    print('点プレビュー: $_pointPreview');
    print('描画中: $isDrawing (線: $isLineDrawing, ポリゴン: $isPolygonDrawing)');
    print('================================');
  }

  /// 線フィーチャの追記を開始
  /// [feature] - 追記対象のLineFeatureNode
  void startEditingLineFeature(LineFeatureNode feature) {
    // 現在の描画データをクリア
    clearAll();

    // 追記対象を設定
    _editingFeature = feature;

    // 既存の線データを復元
    final existingLine = feature.line;
    _drawingLine.addAll(existingLine);

    // 既存のメタデータを復元（drawing_pointsから復元を試行）
    final existingMetadata = feature.metadata;
    if (existingMetadata != null &&
        existingMetadata.containsKey('drawing_points')) {
      final drawingPoints =
          existingMetadata['drawing_points'] as List<dynamic>?;
      if (drawingPoints != null) {
        // メタデータから復元
        for (final pointData in drawingPoints) {
          if (pointData is Map<String, dynamic>) {
            if (pointData['data_source'] == 'pen_tool') {
              _lineMetadata.add(null); // pen_toolの点はnull
            } else {
              _lineMetadata.add(Map<String, dynamic>.from(pointData));
            }
          } else {
            _lineMetadata.add(null); // デフォルトはpen_tool扱い
          }
        }
      }
    }

    // メタデータの数が足りない場合は補完
    while (_lineMetadata.length < _drawingLine.length) {
      _lineMetadata.add(null); // pen_tool扱いで補完
    }

    print(
      '[GlobalDrawingState] 線フィーチャの追記開始: ${feature.name} (${_drawingLine.length}点)',
    );
  }

  /// ポリゴンフィーチャの追記を開始
  /// [feature] - 追記対象のPolygonFeatureNode
  void startEditingPolygonFeature(PolygonFeatureNode feature) {
    // 現在の描画データをクリア
    clearAll();

    // 追記対象を設定
    _editingFeature = feature;

    // 既存のポリゴンデータを復元（外環のみ）
    if (feature.polygon.isNotEmpty) {
      final outerRing = feature.polygon[0];
      // 最後の点が最初の点と同じ場合（閉じられている場合）は除外
      if (outerRing.length > 1 &&
          outerRing.first.latitude == outerRing.last.latitude &&
          outerRing.first.longitude == outerRing.last.longitude) {
        _drawingPolygon.addAll(outerRing.sublist(0, outerRing.length - 1));
      } else {
        _drawingPolygon.addAll(outerRing);
      }
    }

    // 既存のメタデータを復元（drawing_pointsから復元を試行）
    final existingMetadata = feature.metadata;
    if (existingMetadata != null &&
        existingMetadata.containsKey('drawing_points')) {
      final drawingPoints =
          existingMetadata['drawing_points'] as List<dynamic>?;
      if (drawingPoints != null) {
        // メタデータから復元
        for (final pointData in drawingPoints) {
          if (pointData is Map<String, dynamic>) {
            if (pointData['data_source'] == 'pen_tool') {
              _polygonMetadata.add(null); // pen_toolの点はnull
            } else {
              _polygonMetadata.add(Map<String, dynamic>.from(pointData));
            }
          } else {
            _polygonMetadata.add(null); // デフォルトはpen_tool扱い
          }
        }
      }
    }

    // メタデータの数が足りない場合は補完
    while (_polygonMetadata.length < _drawingPolygon.length) {
      _polygonMetadata.add(null); // pen_tool扱いで補完
    }

    print(
      '[GlobalDrawingState] ポリゴンフィーチャの追記開始: ${feature.name} (${_drawingPolygon.length}点)',
    );
  }

  /// 汎用的な追記開始メソッド
  /// [feature] - 追記対象のFeatureNode
  bool startEditingFeature(FeatureNode feature) {
    if (feature is LineFeatureNode) {
      startEditingLineFeature(feature);
      return true;
    } else if (feature is PolygonFeatureNode) {
      startEditingPolygonFeature(feature);
      return true;
    } else {
      print(
        '[GlobalDrawingState] サポートされていないフィーチャタイプです: ${feature.runtimeType}',
      );
      return false;
    }
  }
}
