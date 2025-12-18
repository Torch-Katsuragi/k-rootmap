// K-MAPS: フォルダメタデータモデル
// 各フォルダに配置される.kmeta.jsonの読み書き・継承マージを担当

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/app_logger.dart';

/// .kmeta.jsonファイル名
const String kMetaFileName = '.kmeta.json';

/// 現在のスキーマバージョン
const int kMetaSchemaVersion = 1;

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
    if (polygonFillOpacity != null) json['polygonFillOpacity'] = polygonFillOpacity;
    if (polygonBorderOpacity != null) {
      json['polygonBorderOpacity'] = polygonBorderOpacity;
    }
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
      polygonBorderOpacity == null;
}

/// 可視性設定
class KMetaVisibility {
  /// レイヤー名 → 可視状態
  final Map<String, bool> layers;

  /// GeoPackageファイル名 → 可視状態
  final Map<String, bool> geopackages;

  const KMetaVisibility({
    this.layers = const {},
    this.geopackages = const {},
  });

  /// JSONからパース
  factory KMetaVisibility.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaVisibility();
    return KMetaVisibility(
      layers: (json['layers'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as bool),
          ) ??
          {},
      geopackages: (json['geopackages'] as Map<String, dynamic>?)?.map(
            (k, v) => MapEntry(k, v as bool),
          ) ??
          {},
    );
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (layers.isNotEmpty) json['layers'] = layers;
    if (geopackages.isNotEmpty) json['geopackages'] = geopackages;
    return json;
  }

  /// 親設定とマージ
  KMetaVisibility mergeWith(KMetaVisibility? parent) {
    if (parent == null) return this;
    return KMetaVisibility(
      layers: {...parent.layers, ...layers},
      geopackages: {...parent.geopackages, ...geopackages},
    );
  }

  /// 空かどうか
  bool get isEmpty => layers.isEmpty && geopackages.isEmpty;
}

/// スタイル設定（デフォルト＋レイヤー個別）
class KMetaStyles {
  /// デフォルトスタイル
  final KMetaLayerStyle? defaultStyle;

  /// レイヤー名 → スタイル
  final Map<String, KMetaLayerStyle> layers;

  const KMetaStyles({
    this.defaultStyle,
    this.layers = const {},
  });

  /// JSONからパース
  factory KMetaStyles.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaStyles();
    return KMetaStyles(
      defaultStyle: json['default'] != null
          ? KMetaLayerStyle.fromJson(json['default'] as Map<String, dynamic>)
          : null,
      layers: (json['layers'] as Map<String, dynamic>?)?.map(
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
      defaultStyle: defaultStyle?.mergeWith(parent.defaultStyle) ??
          parent.defaultStyle,
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

  const KMetaLayout({
    this.sortOrder,
    this.expanded,
  });

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

/// 同期設定（Google Drive連携用、将来拡張）
class KMetaSync {
  /// Google DriveのフォルダID
  final String? driveId;

  /// 最終同期日時
  final DateTime? lastSynced;

  const KMetaSync({
    this.driveId,
    this.lastSynced,
  });

  /// JSONからパース
  factory KMetaSync.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const KMetaSync();
    return KMetaSync(
      driveId: json['driveId'] as String?,
      lastSynced: json['lastSynced'] != null
          ? DateTime.tryParse(json['lastSynced'] as String)
          : null,
    );
  }

  /// JSONへシリアライズ
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
    if (driveId != null) json['driveId'] = driveId;
    if (lastSynced != null) json['lastSynced'] = lastSynced!.toIso8601String();
    return json;
  }

  /// 親設定とマージ（同期設定は継承しない = 各フォルダ独立）
  KMetaSync mergeWith(KMetaSync? parent) => this;

  /// 空かどうか
  bool get isEmpty => driveId == null && lastSynced == null;
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
    final json = <String, dynamic>{
      'version': version,
    };
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


