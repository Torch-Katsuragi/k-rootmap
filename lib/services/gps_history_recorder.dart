/// GPS軌跡の常時記録サービス（ハイブリッド方式）
///
/// InternalGpsLocationStore.positionStream を購読し:
/// - Raw Buffer: AppSupport内のGeoPackageにPoint逐次追加（高速・安全）
/// - Consolidated: Global内のgps_history.gpkgにLine+正規化テーブルで定期反映
///
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
/// ハイブリッド方式:
/// - Raw記録: GPS受信ごとにPointをバッファGeoPackageにINSERT（O(1)）
/// - メモリキャッシュ: todayPointsに即時追加（表示遅延なし）
/// - Consolidation: 定期的にLineジオメトリ+詳細テーブルを更新
class GpsHistoryRecorder extends ChangeNotifier {
  static final GpsHistoryRecorder _instance = GpsHistoryRecorder._internal();
  factory GpsHistoryRecorder() => _instance;
  GpsHistoryRecorder._internal();

  static const String _logTag = 'GpsHistoryRecorder';

  // ファイル名
  static const String _historyGpkgFileName = 'gps_history.gpkg';
  static const String _rawBufferDirName = 'gps_buffer';
  static const String _rawBufferGpkgFileName = 'gps_raw_buffer.gpkg';

  // テーブル・レイヤ名
  static const String _tracksLayerName = 'gps_tracks';
  static const String _detailsTableName = 'gps_track_details';
  static const String _rawLayerPrefix = 'gps_raw_';

  // Consolidation間隔（秒）
  static const int _consolidationIntervalSeconds = 20;

  // GeoPackageファイル
  GeoPackageFile? _historyFile;
  GeoPackageFile? _rawBufferFile;

  // 日付・状態管理
  String? _currentDateKey;
  int? _todayTrackFeatureId;
  int _lastConsolidatedIndex = 0;

  // ストリーム・タイマー
  StreamSubscription<GpsPositionRecord>? _subscription;
  Timer? _consolidationTimer;

  // メモリキャッシュ
  final List<LatLng> _todayPoints = [];
  final List<GpsTrackPoint> _pendingDetails = [];
  DateTime? _lastRecordedTime;

  // フラグ
  bool _isInitialized = false;
  bool _isConsolidating = false;

  // ==============================
  // Getters
  // ==============================

  bool get isInitialized => _isInitialized;

  /// 本日分のポイント座標リスト（ポリライン表示用、メモリキャッシュ）
  List<LatLng> get todayPoints => List.unmodifiable(_todayPoints);

  /// 本日の日付キー
  String get todayDateKey => _buildDateKey(DateTime.now());

  // ==============================
  // 初期化
  // ==============================

  /// 初期化
  ///
  /// [globalFolderPath] gps_history.gpkg の配置先（グローバルフォルダ）
  /// [supportDirPath] gps_raw_buffer.gpkg の配置先（AppSupport、UI非表示）
  Future<void> initialize(
    String globalFolderPath,
    String supportDirPath,
  ) async {
    if (_isInitialized) return;

    try {
      AppLogger.debug('$_logTag: 初期化開始');

      // ディレクトリ確保
      await _ensureDirectory(globalFolderPath);
      final rawBufferDir = p.join(supportDirPath, _rawBufferDirName);
      await _ensureDirectory(rawBufferDir);

      // History GeoPackage（Line + details）
      final historyPath = p.join(globalFolderPath, _historyGpkgFileName);
      _historyFile = GeoPackageFile(
        [_historyGpkgFileName],
        absolutePath: historyPath,
      );
      if (!await File(historyPath).exists()) {
        await _historyFile!.createEmptyDatabase();
      }

      // Raw Buffer GeoPackage（Point逐次記録）
      final rawPath = p.join(rawBufferDir, _rawBufferGpkgFileName);
      _rawBufferFile = GeoPackageFile(
        [_rawBufferGpkgFileName],
        absolutePath: rawPath,
      );
      if (!await File(rawPath).exists()) {
        await _rawBufferFile!.createEmptyDatabase();
      }

      // テーブル・レイヤ確保
      await _ensureTracksLayer();
      await _ensureDetailsTable();

      _currentDateKey = _buildDateKey(DateTime.now());
      await _ensureRawLayer(_currentDateKey!);

      // 本日の既存Line → キャッシュ復元
      await _loadTodayFromHistory();

      // Raw未反映分 → 即座にconsolidate
      await _recoverUnconsolidated();

      // 古いrawデータを削除
      await _cleanupOldRawData();

      _isInitialized = true;
      AppLogger.debug(
        '$_logTag: 初期化完了 (日付: $_currentDateKey, '
        'キャッシュ: ${_todayPoints.length}点)',
      );
    } catch (e) {
      AppLogger.debug('$_logTag: 初期化エラー: $e');
    }
  }

  Future<void> _ensureDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  // ==============================
  // 記録の開始/停止
  // ==============================

  /// positionStream の購読開始 + consolidationタイマー起動
  void startRecording(Stream<GpsPositionRecord> positionStream) {
    _subscription?.cancel();
    _subscription = positionStream.listen(
      _onPositionReceived,
      onError: (error) {
        AppLogger.debug('$_logTag: ストリームエラー: $error');
      },
    );

    _consolidationTimer?.cancel();
    _consolidationTimer = Timer.periodic(
      const Duration(seconds: _consolidationIntervalSeconds),
      (_) => _consolidate(),
    );

    AppLogger.debug('$_logTag: 記録開始 (consolidation: $_consolidationIntervalSeconds秒間隔)');
  }

  /// 停止（最終consolidation実行）
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;

    _consolidationTimer?.cancel();
    _consolidationTimer = null;

    // 残りを確実に反映
    await _consolidate();

    AppLogger.debug('$_logTag: 記録停止');
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _consolidationTimer?.cancel();
    _consolidationTimer = null;
    _historyFile?.dispose();
    _historyFile = null;
    _rawBufferFile?.dispose();
    _rawBufferFile = null;
    _isInitialized = false;
    super.dispose();
  }

  // ==============================
  // 位置記録（Raw Buffer）
  // ==============================

  Future<void> _onPositionReceived(GpsPositionRecord record) async {
    if (!_isInitialized || _rawBufferFile == null) return;

    // 最低1秒間隔フィルタ
    if (_lastRecordedTime != null &&
        record.timestamp.difference(_lastRecordedTime!).inMilliseconds <
            1000) {
      return;
    }

    // 空間的重複フィルタ（直前と完全一致なら記録しない）
    if (_todayPoints.isNotEmpty) {
      final last = _todayPoints.last;
      if (last.latitude == record.latitude &&
          last.longitude == record.longitude) {
        return;
      }
    }

    try {
      await _checkAndRotateDay();
      if (_currentDateKey == null) return;

      final rawLayerName = _buildRawLayerName(_currentDateKey!);

      // Raw BufferにPoint INSERT（O(1)、高速）
      await _rawBufferFile!.addPointWithAttributes(
        rawLayerName,
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

      // メモリキャッシュに即時追加
      _todayPoints.add(LatLng(record.latitude, record.longitude));

      // Consolidation用にメタデータも保持
      _pendingDetails.add(GpsTrackPoint(
        latitude: record.latitude,
        longitude: record.longitude,
        altitude: record.altitude,
        accuracy: record.accuracy,
        speed: record.speed,
        bearing: record.bearing,
        timestamp: record.timestamp,
        sourceType: 'GPS',
      ));

      // UI更新通知（頻度を抑える）
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

  String _buildDateKey(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '${y}_${m}_$d';
  }

  String _buildRawLayerName(String dateKey) => '$_rawLayerPrefix$dateKey';

  Future<void> _ensureRawLayer(String dateKey) async {
    if (_rawBufferFile == null) return;

    final layerName = _buildRawLayerName(dateKey);
    final existingLayers = await _rawBufferFile!.getLayerNames();
    if (existingLayers.contains(layerName)) return;

    AppLogger.debug('$_logTag: Rawレイヤ作成: $layerName');
    await _rawBufferFile!.addLayer(layerName, GeometryType.point);
    await _rawBufferFile!.addAttributeColumns(layerName, {
      'timestamp': 'TEXT',
      'altitude': 'REAL',
      'accuracy': 'REAL',
      'speed': 'REAL',
      'bearing': 'REAL',
      'source_type': 'TEXT',
    });
  }

  Future<void> _ensureTracksLayer() async {
    if (_historyFile == null) return;

    final existingLayers = await _historyFile!.getLayerNames();
    if (!existingLayers.contains(_tracksLayerName)) {
      AppLogger.debug('$_logTag: gps_tracks LineLayer 作成');
      await _historyFile!.addLayer(_tracksLayerName, GeometryType.linestring);
    }

    // addLine/updateLine が name, description カラムを必要とするため確保
    final columns = await _historyFile!.getTableColumns(_tracksLayerName);
    final needed = {'name': 'TEXT', 'description': 'TEXT'};
    for (final entry in needed.entries) {
      if (!columns.contains(entry.key)) {
        await _historyFile!.addAttributeColumn(
          _tracksLayerName,
          entry.key,
          entry.value,
        );
      }
    }
  }

  Future<void> _ensureDetailsTable() async {
    if (_historyFile == null) return;

    try {
      final db = await _historyFile!.getDatabase();
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
        [_detailsTableName],
      );
      if (tables.isNotEmpty) return;

      AppLogger.debug('$_logTag: gps_track_details テーブル作成');
      await db.execute('''
        CREATE TABLE $_detailsTableName (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          track_date TEXT NOT NULL,
          point_index INTEGER NOT NULL,
          timestamp TEXT NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          altitude REAL,
          accuracy REAL,
          speed REAL,
          bearing REAL,
          source_type TEXT DEFAULT 'GPS'
        )
      ''');
      await db.execute(
        'CREATE INDEX idx_track_details_date '
        'ON $_detailsTableName(track_date)',
      );
      await db.execute(
        'CREATE INDEX idx_track_details_date_idx '
        'ON $_detailsTableName(track_date, point_index)',
      );
    } catch (e) {
      AppLogger.debug('$_logTag: detailsテーブル作成エラー: $e');
    }
  }

  Future<void> _checkAndRotateDay() async {
    final newDateKey = _buildDateKey(DateTime.now());
    if (newDateKey == _currentDateKey) return;

    AppLogger.debug('$_logTag: 日付変更検出: $_currentDateKey → $newDateKey');

    // 残りを確実に反映してから切り替え
    await _consolidate();

    _currentDateKey = newDateKey;
    _todayTrackFeatureId = null;
    _lastConsolidatedIndex = 0;
    _todayPoints.clear();
    _pendingDetails.clear();

    await _ensureRawLayer(newDateKey);

    notifyListeners();
  }

  // ==============================
  // Consolidation（定期反映）
  // ==============================

  Future<void> _consolidate() async {
    if (_isConsolidating ||
        _historyFile == null ||
        _pendingDetails.isEmpty ||
        _currentDateKey == null) {
      return;
    }

    _isConsolidating = true;
    try {
      final detailsToWrite = List<GpsTrackPoint>.from(_pendingDetails);
      _pendingDetails.clear();

      // Line ジオメトリ更新
      if (_todayPoints.length >= 2) {
        if (_todayTrackFeatureId == null) {
          // 新規作成
          final id = await _historyFile!.addLine(
            _tracksLayerName,
            _todayPoints,
            name: _currentDateKey!,
          );
          _todayTrackFeatureId = id;
          AppLogger.debug('$_logTag: gps_tracks フィーチャ作成 (id=$id)');
        } else {
          // 既存更新
          await _historyFile!.updateLine(
            _tracksLayerName,
            _todayTrackFeatureId!,
            _todayPoints,
            name: _currentDateKey!,
          );
        }
      }

      // Details テーブルにバッチINSERT
      final db = await _historyFile!.getDatabase();
      await db.transaction((txn) async {
        for (final pt in detailsToWrite) {
          await txn.insert(_detailsTableName, {
            'track_date': _currentDateKey,
            'point_index': _lastConsolidatedIndex,
            'timestamp': pt.timestamp.toIso8601String(),
            'latitude': pt.latitude,
            'longitude': pt.longitude,
            'altitude': pt.altitude,
            'accuracy': pt.accuracy,
            'speed': pt.speed,
            'bearing': pt.bearing,
            'source_type': pt.sourceType,
          });
          _lastConsolidatedIndex++;
        }
      });

      AppLogger.debug(
        '$_logTag: Consolidation完了 (${detailsToWrite.length}点反映, '
        '合計: $_lastConsolidatedIndex点)',
      );
    } catch (e) {
      AppLogger.debug('$_logTag: Consolidationエラー: $e');
    } finally {
      _isConsolidating = false;
    }
  }

  // ==============================
  // 起動時復元
  // ==============================

  /// gps_tracks からLineジオメトリを読み込み、todayPointsキャッシュを復元
  Future<void> _loadTodayFromHistory() async {
    if (_historyFile == null || _currentDateKey == null) return;

    try {
      final existingLayers = await _historyFile!.getLayerNames();
      if (!existingLayers.contains(_tracksLayerName)) return;

      // 当日のフィーチャを検索
      final features = await _historyFile!.getFeatures(_tracksLayerName);
      for (final feature in features) {
        final name = feature['name']?.toString();
        if (name != _currentDateKey) continue;

        final id = feature['id'];
        if (id == null) continue;

        final featureId = id is int ? id : int.tryParse(id.toString()) ?? 0;
        final detail = await _historyFile!.getFeature(
          _tracksLayerName,
          featureId,
        );
        if (detail == null || detail['geometry'] == null) continue;

        final geom = detail['geometry'];
        if (geom is List<LatLng>) {
          _todayPoints.addAll(geom);
        } else if (geom is List) {
          for (final pt in geom) {
            if (pt is LatLng) _todayPoints.add(pt);
          }
        }

        _todayTrackFeatureId = featureId;
        break;
      }

      // details テーブルから反映済みインデックスを算出
      final db = await _historyFile!.getDatabase();
      final countResult = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM $_detailsTableName WHERE track_date = ?',
        [_currentDateKey],
      );
      _lastConsolidatedIndex =
          (countResult.first['cnt'] as int?) ?? 0;

      AppLogger.debug(
        '$_logTag: History復元完了 '
        '(${_todayPoints.length}点, featureId=$_todayTrackFeatureId, '
        'consolidated=$_lastConsolidatedIndex)',
      );
    } catch (e) {
      AppLogger.debug('$_logTag: History復元エラー: $e');
    }
  }

  /// Raw Buffer に残っている未反映ポイントを復元してconsolidate
  Future<void> _recoverUnconsolidated() async {
    if (_rawBufferFile == null || _currentDateKey == null) return;

    try {
      final rawLayerName = _buildRawLayerName(_currentDateKey!);
      final existingLayers = await _rawBufferFile!.getLayerNames();
      if (!existingLayers.contains(rawLayerName)) return;

      final rawFeatures = await _rawBufferFile!.getFeatures(rawLayerName);
      final rawCount = rawFeatures.length;
      final alreadyInCache = _todayPoints.length;

      if (rawCount <= alreadyInCache) return;

      AppLogger.debug(
        '$_logTag: 未反映ポイント検出 '
        '(raw=$rawCount, cache=$alreadyInCache, '
        'diff=${rawCount - alreadyInCache})',
      );

      // 未反映分だけ復元
      int recovered = 0;
      for (int i = alreadyInCache; i < rawFeatures.length; i++) {
        final feature = rawFeatures[i];
        final id = feature['id'];
        if (id == null) continue;

        final featureId =
            id is int ? id : int.tryParse(id.toString()) ?? 0;
        final detail = await _rawBufferFile!.getFeature(
          rawLayerName,
          featureId,
        );
        if (detail == null || detail['geometry'] == null) continue;

        final geom = detail['geometry'];
        LatLng? latLng;
        if (geom is List && geom.isNotEmpty && geom.first is LatLng) {
          latLng = geom.first as LatLng;
        }
        if (latLng == null) continue;

        _todayPoints.add(latLng);
        _pendingDetails.add(GpsTrackPoint(
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
        recovered++;
      }

      if (recovered > 0) {
        AppLogger.debug('$_logTag: $recovered 点を復元、consolidation実行');
        await _consolidate();
      }
    } catch (e) {
      AppLogger.debug('$_logTag: 未反映復元エラー: $e');
    }
  }

  // ==============================
  // 日次クリーンアップ
  // ==============================

  /// 2日前以前のrawレイヤを削除
  Future<void> _cleanupOldRawData() async {
    if (_rawBufferFile == null) return;

    try {
      final now = DateTime.now();
      final threshold = now.subtract(const Duration(days: 2));
      final thresholdKey = _buildDateKey(threshold);

      final layers = await _rawBufferFile!.getLayerNames();
      for (final layer in layers) {
        if (!layer.startsWith(_rawLayerPrefix)) continue;
        final dateKey = layer.replaceFirst(_rawLayerPrefix, '');
        if (dateKey.compareTo(thresholdKey) < 0) {
          AppLogger.debug('$_logTag: 古いrawレイヤ削除: $layer');
          await _rawBufferFile!.removeLayer(layer);
        }
      }
    } catch (e) {
      AppLogger.debug('$_logTag: rawクリーンアップエラー: $e');
    }
  }

  // ==============================
  // クエリ（ダイアログ用）
  // ==============================

  /// 利用可能な日付キーのリストを取得（新しい順）
  Future<List<String>> getAvailableDates() async {
    if (_historyFile == null) return [];

    try {
      final dateKeys = <String>{};

      final layers = await _historyFile!.getLayerNames();
      if (layers.contains(_tracksLayerName)) {
        final features =
            await _historyFile!.getFeatures(_tracksLayerName);
        for (final f in features) {
          final name = f['name']?.toString();
          if (name != null && name.isNotEmpty) {
            dateKeys.add(name);
          }
        }
      }

      final sorted = dateKeys.toList()
        ..sort((a, b) => b.compareTo(a));
      return sorted;
    } catch (e) {
      AppLogger.debug('$_logTag: 日付リスト取得エラー: $e');
      return [];
    }
  }

  /// 日付キーを表示用にフォーマット
  /// 例: '2026_02_06' → '2026/02/06'
  static String formatDateKeyAsDate(String dateKey) {
    return dateKey.replaceAll('_', '/');
  }

  /// 日付キーを表示用にフォーマット（formatDateKeyAsDateのエイリアス）
  static String formatLayerNameAsDate(String layerName) {
    return layerName.replaceAll('_', '/');
  }

  /// 特定日付の全ポイントを取得
  Future<List<GpsTrackPoint>> getPointsForDate(String dateKey) async {
    if (_historyFile == null) return [];

    try {
      final db = await _historyFile!.getDatabase();
      final rows = await db.query(
        _detailsTableName,
        where: 'track_date = ?',
        whereArgs: [dateKey],
        orderBy: 'point_index ASC',
      );
      return rows.map((row) => GpsTrackPoint(
        latitude: (row['latitude'] as num).toDouble(),
        longitude: (row['longitude'] as num).toDouble(),
        altitude: (row['altitude'] as num?)?.toDouble(),
        accuracy: (row['accuracy'] as num?)?.toDouble(),
        speed: (row['speed'] as num?)?.toDouble(),
        bearing: (row['bearing'] as num?)?.toDouble(),
        timestamp: row['timestamp'] != null
            ? DateTime.tryParse(row['timestamp'].toString()) ??
                DateTime.now()
            : DateTime.now(),
        sourceType: row['source_type']?.toString() ?? 'GPS',
      )).toList();
    } catch (e) {
      AppLogger.debug('$_logTag: detailsテーブルクエリエラー: $e');
      return [];
    }
  }

  /// 特定時間範囲のポイントを取得
  Future<List<GpsTrackPoint>> getPointsInRange(
    String dateKey,
    DateTime start,
    DateTime end,
  ) async {
    final allPoints = await getPointsForDate(dateKey);
    return allPoints
        .where((p) =>
            !p.timestamp.isBefore(start) && !p.timestamp.isAfter(end))
        .toList();
  }
}
