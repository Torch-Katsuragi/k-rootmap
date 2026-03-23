// K-MAPS: フォルダメタデータモデル
// 各フォルダに配置される.kmeta.jsonの読み書き・継承マージを担当

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/app_logger.dart';

/// .kmeta.jsonファイル名
const String kMetaFileName = '.kmeta.json';

/// 現在のスキーマバージョン
const int kMetaSchemaVersion = 2;

/// レイヤースタイル設定（個別レイヤー用）
class KMetaLayerStyle {
  final double? pointSize;
  final Color? pointColor;
  final double? lineWidth;
  final Color? lineColor;
  final double? polygonBorderWidth;
  final Color? polygonBorderColor;
  final Color? polygonFillColor;
  final double? polygonFillOpacity;
  final double? polygonBorderOpacity;
  final bool? labelEnabled;
  final String? labelProperty;
  final double? labelFontSize;
  final Color? labelColor;
  final Color? labelHaloColor;
  final double? labelOpacity;

  const KMetaLayerStyle({
    this.pointSize,
    this.pointColor,
    this.lineWidth,
    this.lineColor,
    this.polygonBorderWidth,
    this.polygonBorderColor,
    this.polygonFillColor,
    this.polygonFillOpacity,
    this.polygonBorderOpacity,
    this.labelEnabled,
    this.labelProperty,
    this.labelFontSize,
    this.labelColor,
    this.labelHaloColor,
    this.labelOpacity,
  });

  /// JSONからパース
  factory KMetaLayerStyle.fromJson(Map<String, dynamic> json) {
    return KMetaLayerStyle(
      pointSize: (json['pointSize'] as num?)?.toDouble(),
      pointColor: _parseColor(json['pointColor']),
      lineWidth: (json['lineWidth'] as num?)?.toDouble(),
      lineColor: _parseColor(json['lineColor']),
      polygonBorderWidth: (json['polygonBorderWidth'] as num?)?.toDouble(),
      polygonBorderColor: _parseColor(json['polygonBorderColor']),
      polygonFillColor: _parseColor(json['polygonFillColor']),
      polygonFillOpacity: (json['polygonFillOpacity'] as num?)?.toDouble(),
      polygonBorderOpacity: (json['polygonBorderOpacity'] as num?)?.toDouble(),
      labelEnabled: json['labelEnabled'] as bool?,
      labelProperty: json['labelProperty'] as String?,
      labelFontSize: (json['labelFontSize'] as num?)?.toDouble(),
      labelColor: _parseColor(json['labelColor']),
      labelHaloColor: _parseColor(json['labelHaloColor']),
      labelOpacity: (json['labelOpacity'] as num?)?.toDouble(),
    );
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (pointSize != null) json['pointSize'] = pointSize;
    if (pointColor != null) json['pointColor'] = _colorToHex(pointColor!);
    if (lineWidth != null) json['lineWidth'] = lineWidth;
    if (lineColor != null) json['lineColor'] = _colorToHex(lineColor!);
    if (polygonBorderWidth != null) {
      json['polygonBorderWidth'] = polygonBorderWidth;
    }
    if (polygonBorderColor != null) {
      json['polygonBorderColor'] = _colorToHex(polygonBorderColor!);
    }
    if (polygonFillColor != null) {
      json['polygonFillColor'] = _colorToHex(polygonFillColor!);
    }
    if (polygonFillOpacity != null) {
      json['polygonFillOpacity'] = polygonFillOpacity;
    }
    if (polygonBorderOpacity != null) {
      json['polygonBorderOpacity'] = polygonBorderOpacity;
    }
    if (labelEnabled != null) json['labelEnabled'] = labelEnabled;
    if (labelProperty != null) json['labelProperty'] = labelProperty;
    if (labelFontSize != null) json['labelFontSize'] = labelFontSize;
    if (labelColor != null) json['labelColor'] = _colorToHex(labelColor!);
    if (labelHaloColor != null) {
      json['labelHaloColor'] = _colorToHex(labelHaloColor!);
    }
    if (labelOpacity != null) json['labelOpacity'] = labelOpacity;
    return json;
  }

  /// 親スタイルとマージ（子の設定が優先）
  KMetaLayerStyle mergeWith(KMetaLayerStyle? parent) {
    if (parent == null) return this;
    return KMetaLayerStyle(
      pointSize: pointSize ?? parent.pointSize,
      pointColor: pointColor ?? parent.pointColor,
      lineWidth: lineWidth ?? parent.lineWidth,
      lineColor: lineColor ?? parent.lineColor,
      polygonBorderWidth: polygonBorderWidth ?? parent.polygonBorderWidth,
      polygonBorderColor: polygonBorderColor ?? parent.polygonBorderColor,
      polygonFillColor: polygonFillColor ?? parent.polygonFillColor,
      polygonFillOpacity: polygonFillOpacity ?? parent.polygonFillOpacity,
      polygonBorderOpacity: polygonBorderOpacity ?? parent.polygonBorderOpacity,
      labelEnabled: labelEnabled ?? parent.labelEnabled,
      labelProperty: labelProperty ?? parent.labelProperty,
      labelFontSize: labelFontSize ?? parent.labelFontSize,
      labelColor: labelColor ?? parent.labelColor,
      labelHaloColor: labelHaloColor ?? parent.labelHaloColor,
      labelOpacity: labelOpacity ?? parent.labelOpacity,
    );
  }

  /// 空かどうか
  bool get isEmpty =>
      pointSize == null &&
      pointColor == null &&
      lineWidth == null &&
      lineColor == null &&
      polygonBorderWidth == null &&
      polygonBorderColor == null &&
      polygonFillColor == null &&
      polygonFillOpacity == null &&
      polygonBorderOpacity == null &&
      labelEnabled == null &&
      labelProperty == null &&
      labelFontSize == null &&
      labelColor == null &&
      labelHaloColor == null &&
      labelOpacity == null;
}

/// 可視性設定
class KMetaVisibility {
  /// レイヤーキー（gpkgName/layerName形式） → 可視状態
  final Map<String, bool> layers;

  /// GeoPackageファイル名 → 可視状態
  final Map<String, bool> geopackages;

  /// フォルダ名 → 可視状態
  final Map<String, bool> folders;

  /// 画像ファイル名 → 可視状態
  final Map<String, bool> images;

  const KMetaVisibility({
    this.layers = const {},
    this.geopackages = const {},
    this.folders = const {},
    this.images = const {},
  });

  /// JSONからパース
  factory KMetaVisibility.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaVisibility();
    return KMetaVisibility(
      layers: _parseBoolMap(json['layers']),
      geopackages: _parseBoolMap(json['geopackages']),
      folders: _parseBoolMap(json['folders']),
      images: _parseBoolMap(json['images']),
    );
  }

  static Map<String, bool> _parseBoolMap(dynamic value) {
    if (value is! Map<String, dynamic>) return {};
    return value.map((k, v) => MapEntry(k, v as bool));
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (layers.isNotEmpty) json['layers'] = layers;
    if (geopackages.isNotEmpty) json['geopackages'] = geopackages;
    if (folders.isNotEmpty) json['folders'] = folders;
    if (images.isNotEmpty) json['images'] = images;
    return json;
  }

  /// 親設定とマージ
  KMetaVisibility mergeWith(KMetaVisibility? parent) {
    if (parent == null) return this;
    return KMetaVisibility(
      layers: {...parent.layers, ...layers},
      geopackages: {...parent.geopackages, ...geopackages},
      folders: {...parent.folders, ...folders},
      images: {...parent.images, ...images},
    );
  }

  /// 空かどうか
  bool get isEmpty =>
      layers.isEmpty &&
      geopackages.isEmpty &&
      folders.isEmpty &&
      images.isEmpty;
}

/// スタイル設定（デフォルト＋レイヤー個別）
class KMetaStyles {
  /// デフォルトスタイル
  final KMetaLayerStyle? defaultStyle;

  /// レイヤー名 → スタイル
  final Map<String, KMetaLayerStyle> layers;

  const KMetaStyles({this.defaultStyle, this.layers = const {}});

  /// JSONからパース
  factory KMetaStyles.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaStyles();
    return KMetaStyles(
      defaultStyle:
          json['default'] != null
              ? KMetaLayerStyle.fromJson(
                json['default'] as Map<String, dynamic>,
              )
              : null,
      layers:
          (json['layers'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(
              k,
              KMetaLayerStyle.fromJson(v as Map<String, dynamic>),
            ),
          ) ??
          {},
    );
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (defaultStyle != null && !defaultStyle!.isEmpty) {
      json['default'] = defaultStyle!.toJson();
    }
    if (layers.isNotEmpty) {
      json['layers'] = layers.map((k, v) => MapEntry(k, v.toJson()));
    }
    return json;
  }

  /// 親設定とマージ
  /// 注意: layersは継承しない（各フォルダで独立管理）
  /// defaultStyleのみ親から継承される
  KMetaStyles mergeWith(KMetaStyles? parent) {
    if (parent == null) return this;
    return KMetaStyles(
      defaultStyle:
          defaultStyle?.mergeWith(parent.defaultStyle) ?? parent.defaultStyle,
      layers: layers, // 継承しない（自フォルダの設定のみ）
    );
  }

  /// 空かどうか
  bool get isEmpty =>
      (defaultStyle == null || defaultStyle!.isEmpty) && layers.isEmpty;
}

/// レイアウト設定
class KMetaLayout {
  /// 並び順（レイヤー/GeoPackage/フォルダ名のリスト）
  final List<String>? sortOrder;

  /// 展開状態
  final bool? expanded;

  const KMetaLayout({this.sortOrder, this.expanded});

  /// JSONからパース
  factory KMetaLayout.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaLayout();
    return KMetaLayout(
      sortOrder: (json['sortOrder'] as List<dynamic>?)?.cast<String>(),
      expanded: json['expanded'] as bool?,
    );
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (sortOrder != null) json['sortOrder'] = sortOrder;
    if (expanded != null) json['expanded'] = expanded;
    return json;
  }

  /// 親設定とマージ
  KMetaLayout mergeWith(KMetaLayout? parent) {
    if (parent == null) return this;
    return KMetaLayout(
      sortOrder: sortOrder ?? parent.sortOrder,
      expanded: expanded ?? parent.expanded,
    );
  }

  /// 空かどうか
  bool get isEmpty => sortOrder == null && expanded == null;
}

/// 同期対象ファイルの情報
class KMetaSyncFile {
  /// DriveファイルID
  final String driveFileId;

  /// 最終同期時刻（同期完了時点のDateTime.now()）
  final DateTime? lastSyncedTime;

  const KMetaSyncFile({
    required this.driveFileId,
    this.lastSyncedTime,
  });

  factory KMetaSyncFile.fromJson(Map<String, dynamic> json) {
    // 後方互換性：古いlastSyncedModifiedTimeも読み込む
    final legacyTime =
        json['lastSyncedModifiedTime'] != null
            ? DateTime.tryParse(json['lastSyncedModifiedTime'] as String)
            : null;
    // expectedParentId は廃止済み（読み捨て）
    return KMetaSyncFile(
      driveFileId: json['driveFileId'] as String,
      lastSyncedTime:
          json['lastSyncedTime'] != null
              ? DateTime.tryParse(json['lastSyncedTime'] as String)
              : legacyTime, // フォールバック
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'driveFileId': driveFileId};
    if (lastSyncedTime != null) {
      json['lastSyncedTime'] = lastSyncedTime!.toIso8601String();
    }
    return json;
  }

  /// コピーを作成（一部フィールドを更新）
  KMetaSyncFile copyWith({
    String? driveFileId,
    DateTime? lastSyncedTime,
  }) {
    return KMetaSyncFile(
      driveFileId: driveFileId ?? this.driveFileId,
      lastSyncedTime: lastSyncedTime ?? this.lastSyncedTime,
    );
  }
}

/// 同期設定（Google Drive連携用）
class KMetaSync {
  /// Google DriveのフォルダID
  final String? driveId;

  /// Driveフォルダ名（表示用）
  final String? driveFolderName;

  /// Drive共有URL（元のURL）
  final String? driveUrl;

  /// 読み取り専用か
  final bool? isReadOnly;

  /// 最終同期日時
  final DateTime? lastSynced;

  /// 最後に同期したDriveリビジョンID
  final String? driveRevisionId;

  /// このデバイスの識別子（ローカル専用、同期対象外）
  final String? deviceId;

  /// 同期対象ファイル（ファイル名 → ファイル情報）
  final Map<String, KMetaSyncFile> files;

  const KMetaSync({
    this.driveId,
    this.driveFolderName,
    this.driveUrl,
    this.isReadOnly,
    this.lastSynced,
    this.driveRevisionId,
    this.deviceId,
    this.files = const {},
  });

  /// JSONからパース
  factory KMetaSync.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaSync();

    // filesフィールドをパース
    final filesJson = json['files'] as Map<String, dynamic>?;
    final files = <String, KMetaSyncFile>{};
    if (filesJson != null) {
      for (final entry in filesJson.entries) {
        files[entry.key] = KMetaSyncFile.fromJson(
          entry.value as Map<String, dynamic>,
        );
      }
    }

    return KMetaSync(
      driveId: json['driveId'] as String?,
      driveFolderName: json['driveFolderName'] as String?,
      driveUrl: json['driveUrl'] as String?,
      isReadOnly: json['isReadOnly'] as bool?,
      lastSynced:
          json['lastSynced'] != null
              ? DateTime.tryParse(json['lastSynced'] as String)
              : null,
      driveRevisionId: json['driveRevisionId'] as String?,
      deviceId: json['deviceId'] as String?,
      files: files,
    );
  }

  /// JSONへシリアライズ（全フィールド含む）
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (driveId != null) json['driveId'] = driveId;
    if (driveFolderName != null) json['driveFolderName'] = driveFolderName;
    if (driveUrl != null) json['driveUrl'] = driveUrl;
    if (isReadOnly != null) json['isReadOnly'] = isReadOnly;
    if (lastSynced != null) json['lastSynced'] = lastSynced!.toIso8601String();
    if (driveRevisionId != null) json['driveRevisionId'] = driveRevisionId;
    if (deviceId != null) json['deviceId'] = deviceId;
    if (files.isNotEmpty) {
      json['files'] = files.map((k, v) => MapEntry(k, v.toJson()));
    }
    return json;
  }

  /// 同期用JSONへシリアライズ（deviceIdを除外）
  /// Driveにアップロードする際はこちらを使用
  Map<String, dynamic> toJsonForSync() {
    final json = <String, dynamic>{};
    if (driveId != null) json['driveId'] = driveId;
    if (driveFolderName != null) json['driveFolderName'] = driveFolderName;
    if (driveUrl != null) json['driveUrl'] = driveUrl;
    if (isReadOnly != null) json['isReadOnly'] = isReadOnly;
    if (lastSynced != null) json['lastSynced'] = lastSynced!.toIso8601String();
    if (driveRevisionId != null) json['driveRevisionId'] = driveRevisionId;
    // deviceIdは同期対象外なので含めない
    if (files.isNotEmpty) {
      json['files'] = files.map((k, v) => MapEntry(k, v.toJson()));
    }
    return json;
  }

  /// 親設定とマージ（同期設定は継承しない = 各フォルダ独立）
  KMetaSync mergeWith(KMetaSync? parent) => this;

  /// 空かどうか
  bool get isEmpty =>
      driveId == null &&
      driveFolderName == null &&
      lastSynced == null &&
      driveRevisionId == null &&
      deviceId == null &&
      files.isEmpty;

  /// Drive連携済みかどうか
  bool get isLinked => driveId != null;

  /// コピーを作成（一部設定を変更）
  KMetaSync copyWith({
    String? driveId,
    String? driveFolderName,
    String? driveUrl,
    bool? isReadOnly,
    DateTime? lastSynced,
    String? driveRevisionId,
    String? deviceId,
    Map<String, KMetaSyncFile>? files,
  }) {
    return KMetaSync(
      driveId: driveId ?? this.driveId,
      driveFolderName: driveFolderName ?? this.driveFolderName,
      driveUrl: driveUrl ?? this.driveUrl,
      isReadOnly: isReadOnly ?? this.isReadOnly,
      lastSynced: lastSynced ?? this.lastSynced,
      driveRevisionId: driveRevisionId ?? this.driveRevisionId,
      deviceId: deviceId ?? this.deviceId,
      files: files ?? this.files,
    );
  }
}

/// フォルダメタデータ（.kmeta.json）
class KMeta {
  /// スキーマバージョン
  final int version;

  /// 可視性設定
  final KMetaVisibility visibility;

  /// スタイル設定
  final KMetaStyles styles;

  /// レイアウト設定
  final KMetaLayout layout;

  /// 同期設定
  final KMetaSync sync;

  const KMeta({
    this.version = kMetaSchemaVersion,
    this.visibility = const KMetaVisibility(),
    this.styles = const KMetaStyles(),
    this.layout = const KMetaLayout(),
    this.sync = const KMetaSync(),
  });

  /// 空のメタデータ
  static const KMeta empty = KMeta();

  /// JSONからパース
  factory KMeta.fromJson(Map<String, dynamic> json) {
    return KMeta(
      version: json['version'] as int? ?? kMetaSchemaVersion,
      visibility: KMetaVisibility.fromJson(
        json['visibility'] as Map<String, dynamic>?,
      ),
      styles: KMetaStyles.fromJson(json['styles'] as Map<String, dynamic>?),
      layout: KMetaLayout.fromJson(json['layout'] as Map<String, dynamic>?),
      sync: KMetaSync.fromJson(json['sync'] as Map<String, dynamic>?),
    );
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{'version': version};
    if (!visibility.isEmpty) json['visibility'] = visibility.toJson();
    if (!styles.isEmpty) json['styles'] = styles.toJson();
    if (!layout.isEmpty) json['layout'] = layout.toJson();
    if (!sync.isEmpty) json['sync'] = sync.toJson();
    return json;
  }

  /// 親メタデータとマージ（継承処理）
  KMeta mergeWith(KMeta? parent) {
    if (parent == null) return this;
    return KMeta(
      version: version,
      visibility: visibility.mergeWith(parent.visibility),
      styles: styles.mergeWith(parent.styles),
      layout: layout.mergeWith(parent.layout),
      sync: sync.mergeWith(parent.sync),
    );
  }

  /// ファイルから読み込み
  static Future<KMeta?> loadFromFile(String folderPath) async {
    try {
      final file = File('$folderPath/$kMetaFileName');
      if (!await file.exists()) {
        return null;
      }
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return KMeta.fromJson(json);
    } catch (e) {
      AppLogger.debug('[KMeta] Error loading from $folderPath: $e');
      return null;
    }
  }

  /// ファイルに保存
  Future<bool> saveToFile(String folderPath) async {
    try {
      final file = File('$folderPath/$kMetaFileName');
      final json = toJson();
      final content = const JsonEncoder.withIndent('  ').convert(json);
      await file.writeAsString(content);
      AppLogger.debug('[KMeta] Saved to $folderPath');
      return true;
    } catch (e) {
      AppLogger.debug('[KMeta] Error saving to $folderPath: $e');
      return false;
    }
  }

  /// 空かどうか
  bool get isEmpty =>
      visibility.isEmpty && styles.isEmpty && layout.isEmpty && sync.isEmpty;

  /// 特定レイヤーのスタイルを取得（デフォルト適用済み）
  /// [layerKey] はgpkgName/layerName形式（例: "survey.gpkg/points"）
  KMetaLayerStyle? getLayerStyle(String layerKey) {
    final layerStyle = styles.layers[layerKey];
    if (layerStyle != null) {
      return layerStyle.mergeWith(styles.defaultStyle);
    }
    return styles.defaultStyle;
  }

  /// レイヤーの可視状態を取得
  bool? getLayerVisibility(String layerName) => visibility.layers[layerName];

  /// GeoPackageの可視状態を取得
  bool? getGeoPackageVisibility(String gpkgName) =>
      visibility.geopackages[gpkgName];

  /// コピーを作成（一部設定を変更）
  KMeta copyWith({
    int? version,
    KMetaVisibility? visibility,
    KMetaStyles? styles,
    KMetaLayout? layout,
    KMetaSync? sync,
  }) {
    return KMeta(
      version: version ?? this.version,
      visibility: visibility ?? this.visibility,
      styles: styles ?? this.styles,
      layout: layout ?? this.layout,
      sync: sync ?? this.sync,
    );
  }
}

// ========== ユーティリティ関数 ==========

/// 色文字列（#RRGGBB または #AARRGGBB）をColorに変換
Color? _parseColor(dynamic value) {
  if (value == null) return null;
  if (value is int) return Color(value);
  if (value is String) {
    final hex = value.replaceFirst('#', '');
    if (hex.length == 6) {
      return Color(int.parse('FF$hex', radix: 16));
    } else if (hex.length == 8) {
      return Color(int.parse(hex, radix: 16));
    }
  }
  return null;
}

/// Colorを#AARRGGBB形式の文字列に変換
String _colorToHex(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
}
