// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// sub_table属性の編集ヘルパー
///
/// ライン/ポリゴンフィーチャのsub_table（GeoJSON FeatureCollection / 旧2D配列）を
/// トリム・簡略化操作に合わせて更新する。
library;

import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../../../models/nodes/feature_node.dart';
import '../../../utils/app_logger.dart';

/// sub_tableのトリム/フィルタを行うヘルパー
class SubTableHelper {
  /// sub_table JSON 文字列を解析し、インデックス指定で部分抽出する。
  ///
  /// [originalLine] トリム前の元のライン座標
  /// [startIndex] 切り取り開始インデックス（0-based, inclusive）
  /// [endIndex] 切り取り終了インデックス（0-based, inclusive）
  ///
  /// sub_tableの各エントリは元ラインの頂点と1:1対応しているため、
  /// 同じインデックス範囲で切り出す。
  static String? trimSubTable(
    String subTableJson,
    int startIndex,
    int endIndex,
  ) {
    try {
      final decoded = jsonDecode(subTableJson);

      // GeoJSON FeatureCollection 形式
      if (decoded is Map && decoded['type'] == 'FeatureCollection') {
        final features = decoded['features'] as List;
        if (features.isEmpty) return subTableJson;

        final clampedStart = startIndex.clamp(0, features.length - 1);
        final clampedEnd = (endIndex + 1).clamp(0, features.length);
        if (clampedStart >= clampedEnd) return subTableJson;

        final trimmed = features.sublist(clampedStart, clampedEnd);
        return jsonEncode({
          'type': 'FeatureCollection',
          'features': trimmed,
        });
      }

      // 旧フォーマット: [[headers], [row1], ...]
      if (decoded is List && decoded.isNotEmpty && decoded.first is List) {
        final header = decoded.first;
        // データ行は index 1 から始まる（headerの次）
        final dataRows = decoded.skip(1).toList();
        if (dataRows.isEmpty) return subTableJson;

        final clampedStart = startIndex.clamp(0, dataRows.length - 1);
        final clampedEnd = (endIndex + 1).clamp(0, dataRows.length);
        if (clampedStart >= clampedEnd) return subTableJson;

        final trimmedRows = dataRows.sublist(clampedStart, clampedEnd);
        return jsonEncode([header, ...trimmedRows]);
      }
    } catch (e) {
      AppLogger.debug('[SubTableHelper] trimSubTable error: $e');
    }
    return null;
  }

  /// sub_table JSON 文字列を解析し、簡略化後の頂点に対応するエントリのみを残す。
  ///
  /// [originalLine] 簡略化前の元のライン座標
  /// [simplifiedLine] 簡略化後のライン座標
  ///
  /// 簡略化後の各頂点に最も近い元ラインの頂点インデックスを求め、
  /// そのインデックスに対応するsub_tableエントリのみを保持する。
  static String? filterSubTableBySimplification(
    String subTableJson,
    List<LatLng> originalLine,
    List<LatLng> simplifiedLine,
  ) {
    if (originalLine.isEmpty || simplifiedLine.isEmpty) return null;

    // 簡略化後の各頂点に対応する元ラインのインデックスを求める
    final matchedIndices = _matchIndicesToOriginal(
      originalLine,
      simplifiedLine,
    );

    try {
      final decoded = jsonDecode(subTableJson);

      // GeoJSON FeatureCollection 形式
      if (decoded is Map && decoded['type'] == 'FeatureCollection') {
        final features = decoded['features'] as List;
        if (features.isEmpty) return subTableJson;

        final filtered = <dynamic>[];
        for (final idx in matchedIndices) {
          if (idx >= 0 && idx < features.length) {
            filtered.add(features[idx]);
          }
        }

        return jsonEncode({
          'type': 'FeatureCollection',
          'features': filtered,
        });
      }

      // 旧フォーマット: [[headers], [row1], ...]
      if (decoded is List && decoded.isNotEmpty && decoded.first is List) {
        final header = decoded.first;
        final dataRows = decoded.skip(1).toList();
        if (dataRows.isEmpty) return subTableJson;

        final filtered = <dynamic>[];
        for (final idx in matchedIndices) {
          if (idx >= 0 && idx < dataRows.length) {
            filtered.add(dataRows[idx]);
          }
        }

        return jsonEncode([header, ...filtered]);
      }
    } catch (e) {
      AppLogger.debug('[SubTableHelper] filterSubTableBySimplification error: $e');
    }
    return null;
  }

  /// 簡略化後の各頂点に最も近い元ライン頂点のインデックスを返す。
  /// 重複しないように、前方検索で順序を保証する。
  static List<int> _matchIndicesToOriginal(
    List<LatLng> original,
    List<LatLng> simplified,
  ) {
    final indices = <int>[];
    int searchStart = 0;

    for (final sp in simplified) {
      int bestIdx = searchStart;
      double bestDist = _sqDist(sp, original[searchStart]);

      // 前方のみ検索（順序保証のため）
      for (int i = searchStart + 1; i < original.length; i++) {
        final d = _sqDist(sp, original[i]);
        if (d < bestDist) {
          bestDist = d;
          bestIdx = i;
        }
        // 完全一致なら即決定
        if (bestDist == 0) break;
      }

      indices.add(bestIdx);
      // 次の検索は見つかったインデックスの次から（順序保証）
      searchStart = bestIdx + 1;
      if (searchStart >= original.length) {
        searchStart = original.length - 1;
      }
    }

    return indices;
  }

  /// 2点間の二乗距離（比較用なのでsqrtは不要）
  static double _sqDist(LatLng a, LatLng b) {
    final dx = a.latitude - b.latitude;
    final dy = a.longitude - b.longitude;
    return dx * dx + dy * dy;
  }

  /// フィーチャからsub_table JSON文字列を取得する。
  /// 存在しない場合はnullを返す。
  static Future<String?> getSubTableJson(FeatureNode feature) async {
    try {
      final value = await feature.getAttributeValue('sub_table');
      if (value is String && value.isNotEmpty) {
        return value;
      }
    } catch (e) {
      AppLogger.debug('[SubTableHelper] getSubTableJson error: $e');
    }
    return null;
  }

  /// フィーチャのsub_table属性を更新する。
  static Future<void> setSubTableJson(
    FeatureNode feature,
    String subTableJson,
  ) async {
    try {
      await feature.setAttributeValue('sub_table', subTableJson);
      AppLogger.debug('[SubTableHelper] sub_table更新完了');
    } catch (e) {
      AppLogger.debug('[SubTableHelper] setSubTableJson error: $e');
    }
  }
}
