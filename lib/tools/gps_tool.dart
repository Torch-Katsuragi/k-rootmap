// lib/tools/gps_tool.dart
// GPS関連機能を扱うツール（GPS測量機能対応）
import 'package:flutter/material.dart';
import 'map_tool.dart';
import 'pan_tool.dart';
import '../utils/global_config.dart';
import '../services/gps_manager_service.dart';
import '../models/layer_tree_node.dart';
import 'package:latlong2/latlong.dart';

/// GPS関連機能を扱うツール
///
/// GPS測量機能を提供し、現在位置を記録してフィーチャを作成します:
/// - 現在位置の記録によるPoint/Line/Polygonフィーチャ作成
/// - GPS精度情報の記録・表示
/// - GPS測量データの履歴管理
/// - パンツール機能の継承
///
/// Features:
/// - GPS測量機能（Point/Line/Polygon作成）
/// - GPS位置データの詳細記録（精度、時刻、データソース）
/// - パンツールへのプロキシパターン実装
/// - リアルタイムプレビュー表示
class GpsTool extends MapTool {
  @override
  String get name => 'GPS';

  @override
  IconData get icon => Icons.gps_fixed;

  /// パンツールインスタンスへの参照（GlobalConfigから取得）
  PanTool get _panTool => GlobalConfig.instance.panTool;

  /// GPS管理サービスインスタンス
  final GpsManagerService _gpsManager = GpsManagerService();

  /// GPS測量中の描画データ
  final List<LatLng> _surveyLine = [];
  final List<LatLng> _surveyPolygon = [];
  final List<Map<String, dynamic>> _surveyGpsData = [];

  /// プレビュー用の点座標
  LatLng? _pointPreview;

  /// GPS測量機能のgetters
  List<LatLng> get surveyLine => List.unmodifiable(_surveyLine);
  List<LatLng> get surveyPolygon => List.unmodifiable(_surveyPolygon);
  List<Map<String, dynamic>> get surveyGpsData =>
      List.unmodifiable(_surveyGpsData);
  LatLng? get pointPreview => _pointPreview;

  /// ツール有効化時の初期化処理
  /// パンツールの初期化を呼び出し、GPS関連の初期化も行う
  @override
  void onActivate() {
    _panTool.onActivate();
    _initializeGpsFeatures();
  }

  /// ツール無効化時の終了処理
  /// パンツールの終了処理を呼び出し、GPS関連のクリーンアップも行う
  @override
  void onDeactivate() {
    _panTool.onDeactivate();
    _cleanupGpsFeatures();
  }

  /// タップイベント - パンツールに丸投げ
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    _panTool.onTap(details, mapState);
    _handleGpsTap(details, mapState);
  }

  /// スケール開始イベント - パンツールに丸投げ
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    _panTool.onScaleStart(details, mapState);
    _handleGpsScaleStart(details, mapState);
  }

  /// スケール更新イベント - パンツールに丸投げ
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    _panTool.onScaleUpdate(details, mapState);
    _handleGpsScaleUpdate(details, mapState);
  }

  /// スケール終了イベント - パンツールに丸投げ
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    _panTool.onScaleEnd(details, mapState);
    _handleGpsScaleEnd(details, mapState);
  }

  /// バッファへの座標追加 - パンツールのバッファと同期
  @override
  void addPointerToBuffer(Offset offset) {
    super.addPointerToBuffer(offset);
    _panTool.addPointerToBuffer(offset);
  }

  /// バッファクリア - パンツールのバッファと同期
  @override
  void clearPointerBuffer() {
    super.clearPointerBuffer();
    _panTool.clearPointerBuffer();
  }

  /// バッファ内容取得 - パンツールのバッファを返す
  @override
  List<Offset> getPointerBuffer() {
    return _panTool.getPointerBuffer();
  }

  // --- GPS測量機能実装 ---

  /// GPS機能の初期化
  void _initializeGpsFeatures() {
    // GPS測量データの初期化
    clearSurveyData();
    debugPrint('[GpsTool] GPS測量機能を初期化しました');
  }

  /// GPS機能のクリーンアップ
  void _cleanupGpsFeatures() {
    // GPS測量データのクリア
    clearSurveyData();
    debugPrint('[GpsTool] GPS測量機能をクリーンアップしました');
  }

  /// 現在のGPS位置を記録
  Future<bool> recordCurrentGpsPosition() async {
    try {
      // GPS測量専用開始（位置取得まで待機）
      final gpsInfo = await _gpsManager.startGpsSurveyWithWait();

      if (gpsInfo == null || !gpsInfo['isActive']) {
        debugPrint('[GpsTool] GPS位置情報が利用できません。位置情報の許可が必要です。');
        return false;
      }

      final latitude = gpsInfo['latitude'] as double;
      final longitude = gpsInfo['longitude'] as double;
      final position = LatLng(latitude, longitude);

      // GPS詳細データを記録
      final gpsDetailData = {
        'latitude': latitude,
        'longitude': longitude,
        'altitude': gpsInfo['altitude'],
        'accuracy': gpsInfo['accuracy'],
        'speed': gpsInfo['speed'],
        'bearing': gpsInfo['bearing'],
        'timestamp': gpsInfo['timestamp'],
        'sourceType': gpsInfo['sourceType'],
        'sourceName': gpsInfo['sourceName'],
        'selectedDevice': gpsInfo['selectedDevice'],
        'recordedAt': DateTime.now().toIso8601String(),
      };

      // 現在選択中のレイヤーに応じてデータを追加
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected is PointLayerNode) {
        _pointPreview = position;
        _surveyGpsData.clear();
        _surveyGpsData.add(gpsDetailData);
      } else if (selected is LineLayerNode) {
        _surveyLine.add(position);
        _surveyGpsData.add(gpsDetailData);
      } else if (selected is PolygonLayerNode) {
        _surveyPolygon.add(position);
        _surveyGpsData.add(gpsDetailData);
      }

      debugPrint(
        '[GpsTool] GPS位置を記録: Lat ${latitude.toStringAsFixed(6)}, '
        'Lon ${longitude.toStringAsFixed(6)}, '
        'Accuracy ${gpsInfo['accuracy']?.toStringAsFixed(1) ?? 'N/A'}m',
      );

      return true;
    } catch (e) {
      debugPrint('[GpsTool] GPS位置記録エラー: $e');
      return false;
    }
  }

  /// GPS測量データをクリア
  void clearSurveyData() {
    _surveyLine.clear();
    _surveyPolygon.clear();
    _surveyGpsData.clear();
    _pointPreview = null;
    debugPrint('[GpsTool] GPS測量データをクリアしました');
  }

  /// GPS測量をキャンセル（GPS停止付き）
  Future<void> cancelSurveyWithGpsStop() async {
    clearSurveyData();
    await _gpsManager.stopGpsSurvey();
    debugPrint('[GpsTool] GPS測量をキャンセルしてGPS停止しました');
  }

  /// 1つ取り消し
  void undoLastPoint() {
    if (_surveyLine.isNotEmpty) {
      _surveyLine.removeLast();
      _surveyGpsData.removeLast();
    } else if (_surveyPolygon.isNotEmpty) {
      _surveyPolygon.removeLast();
      _surveyGpsData.removeLast();
    }
    debugPrint('[GpsTool] 最後のGPS測量ポイントを取り消しました');
  }

  /// GPS測量フィーチャを確定作成
  Future<bool> confirmSurveyFeature({
    required String name,
    required String description,
    required void Function(void Function()) setState,
    required List<LatLng> Function(List<LatLng>) closeRing,
  }) async {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) return false;

    try {
      // GPS詳細データを文字列として記述に追加
      final gpsDataDescription = _formatGpsDataForDescription();
      final fullDescription =
          description.isNotEmpty
              ? '$description\n\n--- GPS測量データ ---\n$gpsDataDescription'
              : '--- GPS測量データ ---\n$gpsDataDescription';

      if (selected is PointLayerNode && _pointPreview != null) {
        await PointFeatureNode.createIn(
          selected,
          _pointPreview!,
          name.isNotEmpty ? name : 'GPS測量ポイント',
          fullDescription,
        );
        setState(() {
          clearSurveyData();
        });
        await _gpsManager.stopGpsSurvey();
        debugPrint('[GpsTool] GPS測量ポイントフィーチャを作成してGPS停止しました');
        return true;
      } else if (selected is LineLayerNode && _surveyLine.length >= 2) {
        await LineFeatureNode.createIn(
          selected,
          List<LatLng>.from(_surveyLine),
          name.isNotEmpty ? name : 'GPS測量ライン',
          fullDescription,
        );
        setState(() {
          clearSurveyData();
        });
        await _gpsManager.stopGpsSurvey();
        debugPrint('[GpsTool] GPS測量ラインフィーチャを作成してGPS停止しました');
        return true;
      } else if (selected is PolygonLayerNode && _surveyPolygon.length >= 3) {
        final closed = closeRing(_surveyPolygon);
        await PolygonFeatureNode.createIn(
          selected,
          List<List<LatLng>>.from([closed]),
          name.isNotEmpty ? name : 'GPS測量ポリゴン',
          fullDescription,
        );
        setState(() {
          clearSurveyData();
        });
        await _gpsManager.stopGpsSurvey();
        debugPrint('[GpsTool] GPS測量ポリゴンフィーチャを作成してGPS停止しました');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[GpsTool] GPS測量フィーチャ作成エラー: $e');
      return false;
    }
  }

  /// GPS測量データを文字列形式でフォーマット
  String _formatGpsDataForDescription() {
    if (_surveyGpsData.isEmpty) return 'GPS測量データなし';

    final buffer = StringBuffer();

    for (int i = 0; i < _surveyGpsData.length; i++) {
      final data = _surveyGpsData[i];
      buffer.writeln('ポイント ${i + 1}:');
      buffer.writeln(
        '  位置: ${(data['latitude'] as double).toStringAsFixed(8)}, ${(data['longitude'] as double).toStringAsFixed(8)}',
      );
      if (data['altitude'] != null) {
        buffer.writeln(
          '  高度: ${(data['altitude'] as double).toStringAsFixed(2)}m',
        );
      }
      if (data['accuracy'] != null) {
        buffer.writeln(
          '  精度: ${(data['accuracy'] as double).toStringAsFixed(2)}m',
        );
      }
      if (data['speed'] != null) {
        buffer.writeln(
          '  速度: ${(data['speed'] as double).toStringAsFixed(2)}m/s',
        );
      }
      if (data['bearing'] != null) {
        buffer.writeln(
          '  方位: ${(data['bearing'] as double).toStringAsFixed(1)}°',
        );
      }
      buffer.writeln('  データソース: ${data['sourceName']} (${data['sourceType']})');
      if (data['selectedDevice'] != null) {
        buffer.writeln('  接続機器: ${data['selectedDevice']}');
      }
      buffer.writeln('  記録時刻: ${data['recordedAt']}');

      if (i < _surveyGpsData.length - 1) {
        buffer.writeln();
      }
    }

    return buffer.toString();
  }

  /// GPSタップイベント処理
  void _handleGpsTap(TapUpDetails details, dynamic mapState) {
    // TODO: 将来実装
    // - タップ位置でのGPS情報表示
    // - GPS中心移動のトグル
    // - 位置情報の詳細ポップアップ
    debugPrint('[GpsTool] GPSタップ処理（将来実装予定）');
  }

  /// GPSスケール開始イベント処理
  void _handleGpsScaleStart(ScaleStartDetails details, dynamic mapState) {
    // TODO: 将来実装
    // - GPS追跡中の自動フォロー無効化
    debugPrint('[GpsTool] GPSスケール開始（将来実装予定）');
  }

  /// GPSスケール更新イベント処理
  void _handleGpsScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    // TODO: 将来実装
    // - ズームレベルに応じた精度表示の調整
    debugPrint('[GpsTool] GPSスケール更新（将来実装予定）');
  }

  /// GPSスケール終了イベント処理
  void _handleGpsScaleEnd(ScaleEndDetails details, dynamic mapState) {
    // TODO: 将来実装
    // - GPS追跡の再開確認
    debugPrint('[GpsTool] GPSスケール終了（将来実装予定）');
  }

  // --- 将来実装予定のGPS専用機能 ---

  /// GPS中心移動の有効/無効切り替え
  void toggleGpsTracking() {
    // TODO: 将来実装
    debugPrint('[GpsTool] GPS追跡トグル（将来実装予定）');
  }

  /// GPS軌跡表示の有効/無効切り替え
  void toggleTrackDisplay() {
    // TODO: 将来実装
    debugPrint('[GpsTool] 軌跡表示トグル（将来実装予定）');
  }

  /// GPS精度の可視化切り替え
  void toggleAccuracyDisplay() {
    // TODO: 将来実装
    debugPrint('[GpsTool] 精度表示トグル（将来実装予定）');
  }

  /// 現在位置への自動移動
  void centerOnCurrentLocation() {
    // TODO: 将来実装
    debugPrint('[GpsTool] 現在位置中心移動（将来実装予定）');
  }
}
