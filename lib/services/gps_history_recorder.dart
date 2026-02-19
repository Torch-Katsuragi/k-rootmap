/// GPS軌跡の常時記録サービス
///
/// InternalGpsLocationStore.positionStream を購読し、
/// グローバルフォルダ内の gps_history.gpkg に日付別レイヤで常時記録する。
/// 本日分のポイントはメモリキャッシュで保持し、地図上にリアルタイム表示可能。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;

import '../models/geopackage/geopackage_file.dart';
import '../models/geometry_type.dart';
import '../models/gps_position_record.dart';
import '../models/gps_track.dart';
import '../utils/app_logger.dart';

/// GPS履歴レコーダー（シングルトン、ChangeNotifier）
///
/// 常時稼働し、GPS位置をGeoPackageに記録。
/// [todayPoints] でリアルタイムのポリライン表示をサポート。
class GpsHistoryRecorder extends ChangeNotifier {
  static final GpsHistoryRecorder _instance = GpsHistoryRecorder._internal();
  factory GpsHistoryRecorder() => _instance;
  GpsHistoryRecorder._internal();

  static const String _logTag = 'GpsHistoryRecorder';
  static const String _gpkgFileName = 'gps_history.gpkg';
  static const String _layerPrefix = 'gps_log_';

  // GeoPackageファイル
  GeoPackageFile? _gpkgFile;

  // 現在の日付レイヤ名
  String? _currentDayLayerName;

  // positionStream の購読
  StreamSubscription<GpsPositionRecord>? _subscription;

  // 最終記録時刻（重複防止）
  DateTime? _lastRecordedTime;

  // 本日分のポイントキャッシュ（ポリライン表示用）
  final List<LatLng> _todayPoints = [];

  // 初期化済みフラグ
  bool _isInitialized = false;

  // ==============================
  // Getters
  // ==============================

  /// 初期化済みか
  bool get isInitialized => _isInitialized;

  /// 本日分のポイント座標リスト（ポリライン表示用、メモリキャッシュ）
  List<LatLng> get todayPoints => List.unmodifiable(_todayPoints);

  /// 本日の日付レイヤ名
  String get todayLayerName => _buildLayerName(DateTime.now());

  // ==============================
  // 初期化
  // ==============================

  /// 初期化（グローバルフォルダパスから gps_history.gpkg を作成/オープン）
  Future<void> initialize(String globalFolderPath) async {
    if (_isInitialized) return;

    try {
      AppLogger.debug('$_logTag: 初期化開始');

      // グローバルフォルダが存在しない場合は作成
      final dir = Directory(globalFolderPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      // GeoPackageファイルの絶対パス
      final gpkgPath = p.join(globalFolderPath, _gpkgFileName);

      // GeoPackageFile インスタンス作成（絶対パスモード）
      _gpkgFile = GeoPackageFile([_gpkgFileName], absolutePath: gpkgPath);

      // ファイルが存在しない場合は空のDBを作成
      final file = File(gpkgPath);
      if (!await file.exists()) {
        AppLogger.debug('$_logTag: gps_history.gpkg を新規作成');
        await _gpkgFile!.createEmptyDatabase();
      }

      // 本日の日付レイヤを確認/作成
      await _ensureTodayLayer();

      // 本日の既存ポイントをキャッシュに読み込み
      await _loadTodayPointsToCache();

      _isInitialized = true;
      AppLogger.debug(
        '$_logTag: 初期化完了 (本日レイヤ: $_currentDayLayerName, '
        'キャッシュ: ${_todayPoints.length}点)',
      );
    } catch (e) {
      AppLogger.debug('$_logTag: 初期化エラー: $e');
    }
  }

  // ==============================
  // 記録の開始/停止
  // ==============================

  /// positionStream の購読開始
  void startRecording(Stream<GpsPositionRecord> positionStream) {
    _subscription?.cancel();
    _subscription = positionStream.listen(
      _onPositionReceived,
      onError: (error) {
        AppLogger.debug('$_logTag: ストリームエラー: $error');
      },
    );
    AppLogger.debug('$_logTag: 記録開始');
  }

  /// 停止
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    AppLogger.debug('$_logTag: 記録停止');
  }

  /// リソース解放
  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _gpkgFile?.dispose();
    _gpkgFile = null;
    _isInitialized = false;
    super.dispose();
  }

  // ==============================
  // 位置記録
  // ==============================

  /// 位置更新の受信と記録
  Future<void> _onPositionReceived(GpsPositionRecord record) async {
    if (!_isInitialized || _gpkgFile == null) return;

    // 最低1秒間隔フィルタ
    if (_lastRecordedTime != null &&
        record.timestamp.difference(_lastRecordedTime!).inMilliseconds < 1000) {
      return;
    }

    try {
      // 日付変更チェック
      await _checkAndRotateDay();

      if (_currentDayLayerName == null) return;

      // GeoPackageに書き込み
      await _gpkgFile!.addPointWithAttributes(
        _currentDayLayerName!,
        LatLng(record.latitude, record.longitude),
        {
          'timestamp': record.timestamp.toIso8601String(),
          'altitude': record.altitude,
          'accuracy': record.accuracy,
          'speed': record.speed,
          'bearing': record.bearing,
          'source_type': 'GPS',
        },
      );

      _lastRecordedTime = record.timestamp;

      // メモリキャッシュに追加
      _todayPoints.add(LatLng(record.latitude, record.longitude));

      // UI更新通知（頻度を抑える: 10点ごと、または最初の数点）
      if (_todayPoints.length <= 5 || _todayPoints.length % 10 == 0) {
        notifyListeners();
      }
    } catch (e) {
      AppLogger.debug('$_logTag: 記録エラー: $e');
    }
  }

  // ==============================
  // 日付管理
  // ==============================

  /// 日付レイヤ名を生成
  String _buildLayerName(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$_layerPrefix${y}_${m}_$d';
  }

  /// 本日の日付レイヤが存在するか確認し、なければ作成
  Future<void> _ensureTodayLayer() async {
    if (_gpkgFile == null) return;

    final layerName = _buildLayerName(DateTime.now());
    _currentDayLayerName = layerName;

    // レイヤ一覧を取得
    final existingLayers = await _gpkgFile!.getLayerNames();

    if (!existingLayers.contains(layerName)) {
      AppLogger.debug('$_logTag: 日付レイヤ作成: $layerName');

      // ポイントレイヤを追加
      await _gpkgFile!.addLayer(layerName, GeometryType.point);

      // 属性カラムを追加
      await _gpkgFile!.addAttributeColumns(layerName, {
        'timestamp': 'TEXT',
        'altitude': 'REAL',
        'accuracy': 'REAL',
        'speed': 'REAL',
        'bearing': 'REAL',
        'source_type': 'TEXT',
      });
    }
  }

  /// 日付変更時に新しいレイヤを作成
  Future<void> _checkAndRotateDay() async {
    final todayLayer = _buildLayerName(DateTime.now());
    if (todayLayer != _currentDayLayerName) {
      AppLogger.debug('$_logTag: 日付変更検出: $_currentDayLayerName → $todayLayer');

      // 新しい日付レイヤを作成
      _currentDayLayerName = todayLayer;
      await _ensureTodayLayer();

      // メモリキャッシュをクリア
      _todayPoints.clear();
      notifyListeners();
    }
  }

  /// 本日の既存ポイントをキャッシュに読み込み
  Future<void> _loadTodayPointsToCache() async {
    if (_gpkgFile == null || _currentDayLayerName == null) return;

    try {
      final features = await _gpkgFile!.getFeatures(_currentDayLayerName!);
      _todayPoints.clear();

      for (final feature in features) {
        // getFeatures は geom をBLOBで返すので、
        // getAllFeatureAttributes で座標情報を取れないため
        // getFeature で個別にパースする
        final id = feature['id'];
        if (id != null) {
          final detail = await _gpkgFile!.getFeature(
            _currentDayLayerName!,
            id is int ? id : int.tryParse(id.toString()) ?? 0,
          );
          if (detail != null && detail['geometry'] != null) {
            final geom = detail['geometry'];
            if (geom is List && geom.isNotEmpty && geom.first is LatLng) {
              _todayPoints.add(geom.first as LatLng);
            }
          }
        }
      }

      AppLogger.debug(
        '$_logTag: 本日キャッシュ読み込み: ${_todayPoints.length}点',
      );
    } catch (e) {
      AppLogger.debug('$_logTag: キャッシュ読み込みエラー: $e');
    }
  }

  // ==============================
  // クエリ（ダイアログ用）
  // ==============================

  /// 利用可能な日付レイヤのリストを取得（新しい順）
  Future<List<String>> getAvailableDates() async {
    if (_gpkgFile == null) return [];

    try {
      final layers = await _gpkgFile!.getLayerNames();
      final dateLayers = layers
          .where((name) => name.startsWith(_layerPrefix))
          .toList()
        ..sort((a, b) => b.compareTo(a)); // 新しい日付順
      return dateLayers;
    } catch (e) {
      AppLogger.debug('$_logTag: 日付リスト取得エラー: $e');
      return [];
    }
  }

  /// 日付レイヤ名を人間が読みやすい形式に変換
  /// 例: gps_log_2026_02_06 → 2026/02/06
  static String formatLayerNameAsDate(String layerName) {
    final datePart = layerName.replaceFirst(_layerPrefix, '');
    return datePart.replaceAll('_', '/');
  }

  /// 特定日付レイヤの全ポイントを取得
  Future<List<GpsTrackPoint>> getPointsForDate(String layerName) async {
    if (_gpkgFile == null) return [];

    try {
      final features = await _gpkgFile!.getFeatures(layerName);
      final points = <GpsTrackPoint>[];

      for (final feature in features) {
        final id = feature['id'];
        if (id == null) continue;

        final detail = await _gpkgFile!.getFeature(
          layerName,
          id is int ? id : int.tryParse(id.toString()) ?? 0,
        );
        if (detail == null || detail['geometry'] == null) continue;

        final geom = detail['geometry'];
        LatLng? latLng;
        if (geom is List && geom.isNotEmpty && geom.first is LatLng) {
          latLng = geom.first as LatLng;
        }
        if (latLng == null) continue;

        points.add(GpsTrackPoint(
          latitude: latLng.latitude,
          longitude: latLng.longitude,
          altitude: (detail['altitude'] as num?)?.toDouble(),
          accuracy: (detail['accuracy'] as num?)?.toDouble(),
          speed: (detail['speed'] as num?)?.toDouble(),
          bearing: (detail['bearing'] as num?)?.toDouble(),
          timestamp: detail['timestamp'] != null
              ? DateTime.tryParse(detail['timestamp'].toString()) ??
                  DateTime.now()
              : DateTime.now(),
          sourceType: detail['source_type']?.toString() ?? 'GPS',
        ));
      }

      // タイムスタンプ順にソート
      points.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return points;
    } catch (e) {
      AppLogger.debug('$_logTag: ポイント取得エラー ($layerName): $e');
      return [];
    }
  }

  /// 特定時間範囲のポイントを取得（日付レイヤ内）
  Future<List<GpsTrackPoint>> getPointsInRange(
    String layerName,
    DateTime start,
    DateTime end,
  ) async {
    final allPoints = await getPointsForDate(layerName);
    return allPoints
        .where((p) =>
            !p.timestamp.isBefore(start) && !p.timestamp.isAfter(end))
        .toList();
  }
}
