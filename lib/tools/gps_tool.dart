// lib/tools/gps_tool.dart
// GPS関連機能を扱うツール（GPS測量機能対応）
import 'dart:async';
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

  /// 各測量ポイントのGPS点数を追跡
  final List<int> _surveyLineGpsCount = [];
  final List<int> _surveyPolygonGpsCount = [];

  /// 長押しGPS測量用データ
  Timer? _longPressTimer;
  Timer? _gpsCollectionTimer;
  bool _isLongPressing = false;
  final List<Map<String, dynamic>> _longPressGpsData = [];
  DateTime? _longPressStartTime;

  /// GPS測量機能のgetters
  List<LatLng> get surveyLine => List.unmodifiable(_surveyLine);
  List<LatLng> get surveyPolygon => List.unmodifiable(_surveyPolygon);
  List<Map<String, dynamic>> get surveyGpsData =>
      List.unmodifiable(_surveyGpsData);
  List<int> get surveyLineGpsCount => List.unmodifiable(_surveyLineGpsCount);
  List<int> get surveyPolygonGpsCount =>
      List.unmodifiable(_surveyPolygonGpsCount);
  bool get isLongPressing => _isLongPressing;
  int get longPressGpsCount => _longPressGpsData.length;

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

  /// 長押しGPS測量開始（位置更新ベース）
  void startLongPressGpsSurvey() {
    debugPrint('[GpsTool] 長押しGPS測量開始（位置更新ベース）');

    _isLongPressing = true;
    _longPressStartTime = DateTime.now();
    _longPressGpsData.clear();

    // GPS測量専用開始
    _gpsManager.startGpsSurveyWithWait().then((_) {
      // GPS Manager Service の連続測量機能を使用（位置更新ベース）
      _gpsManager.startContinuousSurvey(
        onPositionUpdate: _onContinuousSurveyUpdate,
      );
    });
  }

  /// 長押しGPS測量停止と平均化処理（位置更新ベース）
  Future<bool> stopLongPressGpsSurvey() async {
    debugPrint('[GpsTool] 長押しGPS測量停止 - GPS平均化処理開始（位置更新ベース）');

    _isLongPressing = false;

    // GPS Manager Service の連続測量を停止
    _gpsManager.stopContinuousSurvey();

    // 最終的なデータを取得
    final finalData = _gpsManager.getContinuousSurveyData();
    _longPressGpsData.clear();
    _longPressGpsData.addAll(finalData);

    debugPrint('[GpsTool] 位置更新ベース連続測量を停止しました');

    if (_longPressGpsData.isEmpty) {
      debugPrint('[GpsTool] 長押し中にGPSデータが取得できませんでした');
      return false;
    }

    try {
      // GPS平均化計算
      final averagedResult = _calculateAveragedGpsPosition(_longPressGpsData);
      final position = LatLng(
        averagedResult['latitude'],
        averagedResult['longitude'],
      );

      // 最適化されたdescription辞書構造を作成
      final optimizedGpsData = _createOptimizedGpsDescription(
        averagedResult,
        _longPressGpsData,
      );

      debugPrint('[GpsTool] 長押し測量 optimizedGpsData: $optimizedGpsData');

      // 現在選択中のレイヤーに応じてデータを追加
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected is PointLayerNode) {
        // GPS測量時は即座にPointフィーチャを作成（メタデータ活用）
        // optimizedGpsDataを辞書のまま保存
        final metadata = {
          'type': 'measurement_log',
          'contents': optimizedGpsData,
        };

        debugPrint('[GpsTool] 長押し測量 metadata: $metadata');
        final pointFeature = await PointFeatureNode.createIn(
          selected,
          position,
          'GPS測量ポイント',
          '', // description は空にしてメタデータを使用
          metadata: metadata,
        );

        if (pointFeature != null) {
          // UI更新（pen_toolと同様）
          if (GlobalConfig.instance.mapState != null) {
            GlobalConfig.instance.mapState.refreshFeatures();
            GlobalConfig.instance.mapState.setState(() {});
          }

          // Point測量完了後はGPS測量を停止（リソース効率化）
          await _gpsManager.stopGpsSurvey();

          // データ収集タイマーも確実に停止（念のため）
          _gpsCollectionTimer?.cancel();
          _gpsCollectionTimer = null;

          debugPrint('[GpsTool] GPS測量ポイントフィーチャを即座に作成しました（GPS停止済み・タイマー確認済み）');
          return true; // 成功
        } else {
          debugPrint('[ERROR] GPS測量ポイントフィーチャの作成に失敗しました');
          return false; // 失敗
        }
      } else if (selected is LineLayerNode) {
        _surveyLine.add(position);
        _surveyGpsData.add(optimizedGpsData);
        _surveyLineGpsCount.add(_longPressGpsData.length); // GPS点数を記録
      } else if (selected is PolygonLayerNode) {
        _surveyPolygon.add(position);
        _surveyGpsData.add(optimizedGpsData);
        _surveyPolygonGpsCount.add(_longPressGpsData.length); // GPS点数を記録
      }

      // クリーンアップ
      _longPressGpsData.clear();
      _longPressStartTime = null;
      _gpsManager.clearContinuousSurveyData();

      return true;
    } catch (e) {
      debugPrint('[GpsTool] 長押しGPS測量エラー: $e');
      return false;
    }
  }

  /// 現在のGPS位置を記録（単発版・互換性維持）
  Future<bool> recordCurrentGpsPosition() async {
    // 長押し中の場合は何もしない
    if (_isLongPressing) {
      debugPrint('[GpsTool] 長押し中のため単発GPS記録をスキップ');
      return false;
    }

    try {
      // GPS測量専用開始（位置取得まで待機）
      final gpsInfo = await _gpsManager.startGpsSurveyWithWait();
      debugPrint('[GpsTool] 単発測量 gpsInfo: $gpsInfo');

      if (gpsInfo == null || !gpsInfo['isActive']) {
        debugPrint('[GpsTool] GPS位置情報が利用できません。位置情報の許可が必要です。');
        return false;
      }

      final latitude = gpsInfo['latitude'] as double;
      final longitude = gpsInfo['longitude'] as double;
      final position = LatLng(latitude, longitude);

      // 通常測量も1つの点の平均として扱う（長押し測量と形式統一）
      final singleGpsData = {
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
        'collectedAt': DateTime.now().toIso8601String(),
      };
      debugPrint('[GpsTool] 単発測量 singleGpsData: $singleGpsData');

      // 1つの点から平均を計算（実質的には同じ値）
      final averagedResult = _calculateAveragedGpsPosition([singleGpsData]);
      debugPrint('[GpsTool] 単発測量 averagedResult: $averagedResult');

      // 長押し測量と同じ最適化された辞書構造を作成
      final optimizedGpsData = _createOptimizedGpsDescription(
        averagedResult,
        [singleGpsData],
        isSingleTap: true, // 通常測量フラグ
      );

      debugPrint('[GpsTool] 単発測量 optimizedGpsData: $optimizedGpsData');

      // 現在選択中のレイヤーに応じてデータを追加
      final selected = GlobalConfig.instance.selectedLayerNode;
      if (selected is PointLayerNode) {
        // GPS測量時は即座にPointフィーチャを作成（メタデータ活用）
        // optimizedGpsDataを辞書のまま保存
        final metadata = {
          'type': 'measurement_log',
          'contents': optimizedGpsData,
        };

        debugPrint('[GpsTool] 単発測量 metadata: $metadata');
        final pointFeature = await PointFeatureNode.createIn(
          selected,
          position,
          'GPS測量ポイント',
          '', // description は空にしてメタデータを使用
          metadata: metadata,
        );

        if (pointFeature != null) {
          // UI更新（pen_toolと同様）
          if (GlobalConfig.instance.mapState != null) {
            GlobalConfig.instance.mapState.refreshFeatures();
            GlobalConfig.instance.mapState.setState(() {});
          }

          // Point測量完了後はGPS測量を停止（リソース効率化）
          await _gpsManager.stopGpsSurvey();

          // データ収集タイマーも確実に停止（念のため）
          _gpsCollectionTimer?.cancel();
          _gpsCollectionTimer = null;

          debugPrint('[GpsTool] GPS測量ポイントフィーチャを即座に作成しました（GPS停止済み・タイマー確認済み）');
          return true; // 成功
        } else {
          debugPrint('[ERROR] GPS測量ポイントフィーチャの作成に失敗しました');
          return false; // 失敗
        }
      } else if (selected is LineLayerNode) {
        _surveyLine.add(position);
        _surveyGpsData.add(optimizedGpsData);
        _surveyLineGpsCount.add(1); // 通常測量は1点
      } else if (selected is PolygonLayerNode) {
        _surveyPolygon.add(position);
        _surveyGpsData.add(optimizedGpsData);
        _surveyPolygonGpsCount.add(1); // 通常測量は1点
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

  /// 長押し中のGPSデータ収集（位置更新ベースのため廃止）
  ///
  /// 注意: このメソッドは位置更新ベースの連続測量への移行により廃止されました。
  /// 現在は _onContinuousSurveyUpdate() を使用して位置更新のタイミングで
  /// GPS Manager Service から自動的にデータを収集します。
  @Deprecated('位置更新ベース連続測量への移行により廃止')
  Future<void> _collectGpsDataForLongPress() async {
    // 互換性維持のため空実装
    debugPrint('[GpsTool] _collectGpsDataForLongPress は廃止されました（位置更新ベース移行）');
  }

  /// GPS平均化計算
  Map<String, dynamic> _calculateAveragedGpsPosition(
    List<Map<String, dynamic>> gpsDataList,
  ) {
    if (gpsDataList.isEmpty) {
      throw Exception('GPS データが空です');
    }

    double totalLatitude = 0.0;
    double totalLongitude = 0.0;
    double totalAltitude = 0.0;
    double totalAccuracy = 0.0;
    int validAltitudeCount = 0;
    int validAccuracyCount = 0;

    for (final data in gpsDataList) {
      totalLatitude += (data['latitude'] as double);
      totalLongitude += (data['longitude'] as double);

      if (data['altitude'] != null) {
        totalAltitude += (data['altitude'] as double);
        validAltitudeCount++;
      }

      if (data['accuracy'] != null) {
        totalAccuracy += (data['accuracy'] as double);
        validAccuracyCount++;
      }
    }

    final count = gpsDataList.length;
    return {
      'latitude': totalLatitude / count,
      'longitude': totalLongitude / count,
      'altitude':
          validAltitudeCount > 0 ? totalAltitude / validAltitudeCount : null,
      'accuracy':
          validAccuracyCount > 0 ? totalAccuracy / validAccuracyCount : null,
      'sampleCount': count,
    };
  }

  /// 最適化されたGPS description辞書構造を作成
  Map<String, dynamic> _createOptimizedGpsDescription(
    Map<String, dynamic> averagedResult,
    List<Map<String, dynamic>> rawGpsDataList, {
    bool isSingleTap = false,
  }) {
    // デバッグ出力
    // debugPrint('[GpsTool] _createOptimizedGpsDescription 入力データ:');
    // debugPrint('  averagedResult: $averagedResult');
    // debugPrint('  rawGpsDataList.length: ${rawGpsDataList.length}');
    // debugPrint('  rawGpsDataList: $rawGpsDataList');

    final duration =
        _longPressStartTime != null && !isSingleTap
            ? DateTime.now().difference(_longPressStartTime!).inMilliseconds /
                1000.0
            : 0.0;

    final result = {
      'pointNumber': _getNextPointNumber(),
      'calculatedPosition': {
        'latitude': averagedResult['latitude'],
        'longitude': averagedResult['longitude'],
        'altitude': averagedResult['altitude'],
        'averagedAccuracy': averagedResult['accuracy'],
      },
      'usedGpsData': List<Map<String, dynamic>>.from(rawGpsDataList),
      'sampleCount': rawGpsDataList.length,
      'averagingDuration':
          isSingleTap ? '瞬時測量' : '${duration.toStringAsFixed(1)}秒',
      'recordedAt': DateTime.now().toIso8601String(),
    };

    // debugPrint('[GpsTool] _createOptimizedGpsDescription 結果: $result');
    return result;
  }

  /// 次のポイント番号を取得
  int _getNextPointNumber() {
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected is LineLayerNode) {
      return _surveyLine.length + 1;
    } else if (selected is PolygonLayerNode) {
      return _surveyPolygon.length + 1;
    }
    return 1; // PointLayerNode
  }

  /// GPS測量データをクリア
  void clearSurveyData() {
    _surveyLine.clear();
    _surveyPolygon.clear();
    _surveyGpsData.clear();
    _surveyLineGpsCount.clear();
    _surveyPolygonGpsCount.clear();

    // 長押し関連もクリア
    _gpsCollectionTimer?.cancel();
    _gpsCollectionTimer = null;
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _isLongPressing = false;
    _longPressGpsData.clear();
    _longPressStartTime = null;

    // GPS Manager Service の連続測量もクリア
    _gpsManager.stopContinuousSurvey();
    _gpsManager.clearContinuousSurveyData();

    debugPrint('[GpsTool] GPS測量データと連続測量をクリアしました');
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
      _surveyLineGpsCount.removeLast();
    } else if (_surveyPolygon.isNotEmpty) {
      _surveyPolygon.removeLast();
      _surveyGpsData.removeLast();
      _surveyPolygonGpsCount.removeLast();
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
      // GPS測量データをメタデータとして構造化（リスト形式で保存）
      debugPrint('[GpsTool] 線・面測量確定 _surveyGpsData: $_surveyGpsData');
      final metadata = {
        'type': 'measurement_log',
        'contents': List<Map<String, dynamic>>.from(
          _surveyGpsData.map((e) => Map<String, dynamic>.from(e)),
        ),
      };
      debugPrint('[GpsTool] 線・面測量確定 metadata: $metadata');

      if (selected is PointLayerNode) {
        // PointLayerNodeの場合は既に即座に作成済みなので、GPS停止のみ実行
        setState(() {
          clearSurveyData();
        });
        await _gpsManager.stopGpsSurvey();
        debugPrint('[GpsTool] GPS測量ポイント完了（既に作成済み）- GPS停止しました');
        return true;
      } else if (selected is LineLayerNode && _surveyLine.length >= 2) {
        await LineFeatureNode.createIn(
          selected,
          List<LatLng>.from(_surveyLine),
          name.isNotEmpty ? name : 'GPS測量ライン',
          description,
          metadata: metadata,
        );
        await _gpsManager.stopGpsSurvey();
        setState(() {
          clearSurveyData();
        });
        debugPrint('[GpsTool] GPS測量ラインフィーチャを作成してGPS停止しました');
        return true;
      } else if (selected is PolygonLayerNode && _surveyPolygon.length >= 3) {
        final closed = closeRing(_surveyPolygon);
        await PolygonFeatureNode.createIn(
          selected,
          List<List<LatLng>>.from([closed]),
          name.isNotEmpty ? name : 'GPS測量ポリゴン',
          description,
          metadata: metadata,
        );
        await _gpsManager.stopGpsSurvey();
        setState(() {
          clearSurveyData();
        });
        debugPrint('[GpsTool] GPS測量ポリゴンフィーチャを作成してGPS停止しました');
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('[GpsTool] GPS測量フィーチャ作成エラー: $e');
      return false;
    }
  }

  /// GPS測量データを文字列形式でフォーマット（最適化された辞書構造対応）
  String _formatGpsDataForDescription() {
    if (_surveyGpsData.isEmpty) return 'GPS測量データなし';

    // 最適化された辞書のlistをそのまま文字列に変換
    return _surveyGpsData.toString();
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

  /// 連続測量位置更新コールバック
  void _onContinuousSurveyUpdate() {
    // GPS Manager Service から収集されたデータを取得してローカルデータと同期
    final continuousData = _gpsManager.getContinuousSurveyData();
    _longPressGpsData.clear();
    _longPressGpsData.addAll(continuousData);

    debugPrint('[GpsTool] 連続測量位置更新 - 現在${_longPressGpsData.length}ポイント');
  }
}
