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
import 'dart:convert';

import 'package:root_maps/utils/app_logger.dart';

import '../../i18n/strings.g.dart';
import 'metadata_table_data.dart';

/// メタデータの内容をパースして表形式に変換するクラス
class MetadataContentParser {
  /// メタデータをパースして表形式データに変換
  static MetadataTableData? parseMetadata(Map<String, dynamic> metadata) {
    try {
      final type = metadata['type'] as String?;
      final contents = metadata['contents'];

      if (type == null || contents == null) {
        return null;
      }

      switch (type) {
        case 'measurement_log':
          return _parseMeasurementLog(contents);
        default:
          return _parseDefault(contents, type);
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] パースエラー: $e');
      return null;
    }
  }

  /// GPS測量ログの専用パース処理
  static MetadataTableData _parseMeasurementLog(dynamic contents) {
    if (contents is String) {
      try {
        final parsed = _parseStringAsDictionary(contents);
        if (parsed != null) {
          return _parseMeasurementLogData(parsed);
        }

        return MetadataTableData(
          headers: [t.metadata.content],
          rows: [
            [contents],
          ],
          type: 'measurement_log',
          title: t.metadata.surveyLogString,
        );
      } catch (e) {
        return MetadataTableData(
          headers: [t.metadata.content],
          rows: [
            [contents],
          ],
          type: 'measurement_log',
          title: t.metadata.surveyLogString,
        );
      }
    }

    if (contents is Map<String, dynamic>) {
      return _parseMeasurementLogData(contents);
    }

    if (contents is List) {
      return _parseMeasurementLogList(contents);
    }

    return _parseDefault(contents, 'measurement_log');
  }

  /// GPS測量ログデータ（辞書形式）をパース
  static MetadataTableData _parseMeasurementLogData(
    Map<String, dynamic> data,
  ) {
    final headers = <String>[];
    final rows = <List<String>>[];

    if (data.containsKey('pointNumber')) {
      headers.add(t.metadata.pointNumber);
      rows.add(['${data['pointNumber']}']);
    }

    if (data.containsKey('sampleCount')) {
      headers.add(t.metadata.sampleCount);
      rows.add(['${data['sampleCount']}']);
    }

    if (data.containsKey('averagingDuration')) {
      headers.add(t.metadata.surveyDuration);
      rows.add(['${data['averagingDuration']}']);
    }

    if (data.containsKey('recordedAt')) {
      headers.add(t.metadata.recordedAt);
      rows.add(['${data['recordedAt']}']);
    }

    if (data.containsKey('calculatedPosition')) {
      final pos = data['calculatedPosition'] as Map<String, dynamic>;
      if (pos.containsKey('latitude')) {
        headers.add(t.metadata.latitude);
        rows.add(['${pos['latitude']}']);
      }
      if (pos.containsKey('longitude')) {
        headers.add(t.metadata.longitude);
        rows.add(['${pos['longitude']}']);
      }
      if (pos.containsKey('altitude')) {
        headers.add(t.metadata.altitude);
        rows.add(['${pos['altitude'] ?? 'N/A'}']);
      }
      if (pos.containsKey('averagedAccuracy')) {
        headers.add(t.metadata.averageAccuracy);
        rows.add(['${pos['averagedAccuracy'] ?? 'N/A'}']);
      }
    }

    if (data.containsKey('usedGpsData')) {
      headers.add(t.metadata.rawData);
      rows.add(['${data['usedGpsData']}']);
    }

    if (headers.isNotEmpty && rows.isNotEmpty) {
      return MetadataTableData(
        headers: [t.metadata.item, t.metadata.value],
        rows: List.generate(headers.length, (i) => [headers[i], rows[i][0]]),
        type: 'measurement_log',
        title: t.metadata.surveyLog,
      );
    }

    return MetadataTableData(
      headers: [t.metadata.info],
      rows: [
        [t.metadata.noData],
      ],
      type: 'measurement_log',
      title: t.metadata.surveyLog,
    );
  }

  /// GPS測量ログリスト（複数測量点）をパース
  static MetadataTableData _parseMeasurementLogList(List<dynamic> dataList) {
    if (dataList.isEmpty) {
      return MetadataTableData(
        headers: [t.metadata.info],
        rows: [
          [t.metadata.emptyData],
        ],
        type: 'measurement_log',
        title: t.metadata.surveyLogMultiLabel,
      );
    }

    final headers = <String>[t.metadata.pointNumber];
    final firstItem = dataList.first;

    if (firstItem is Map<String, dynamic>) {
      if (firstItem.containsKey('calculatedPosition')) {
        headers.addAll([t.metadata.latitude, t.metadata.longitude, t.metadata.altitude, t.metadata.accuracy]);
      }
      if (firstItem.containsKey('sampleCount')) {
        headers.add(t.metadata.sampleCount);
      }
      if (firstItem.containsKey('averagingDuration')) {
        headers.add(t.metadata.surveyDuration);
      }
      if (firstItem.containsKey('usedGpsData')) {
        headers.add(t.metadata.rawData);
      }
    }

    final rows = <List<String>>[];

    for (int i = 0; i < dataList.length; i++) {
      final item = dataList[i];
      final row = <String>['${i + 1}'];

      if (item is Map<String, dynamic>) {
        if (item.containsKey('calculatedPosition')) {
          final pos = item['calculatedPosition'] as Map<String, dynamic>;
          row.add('${pos['latitude'] ?? 'N/A'}');
          row.add('${pos['longitude'] ?? 'N/A'}');
          row.add('${pos['altitude'] ?? 'N/A'}');
          row.add('${pos['averagedAccuracy'] ?? 'N/A'}');
        }
        if (item.containsKey('sampleCount')) {
          row.add('${item['sampleCount']}');
        }
        if (item.containsKey('averagingDuration')) {
          row.add('${item['averagingDuration']}');
        }
        if (item.containsKey('usedGpsData')) {
          row.add('${item['usedGpsData']}');
        }
      }

      while (row.length < headers.length) {
        row.add('N/A');
      }

      rows.add(row);
    }

    return MetadataTableData(
      headers: headers,
      rows: rows,
      type: 'measurement_log',
      title: t.metadata.surveyLogMulti(count: dataList.length.toString()),
    );
  }

  /// 文字列を辞書として解析を試行
  static Map<String, dynamic>? _parseStringAsDictionary(String str) {
    try {
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (e1) {
      try {
        final cleaned = str.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleaned.startsWith('{') && cleaned.endsWith('}')) {
          return null;
        }
      } catch (e2) {
        // パースできない場合
      }
    }
    return null;
  }

  /// デフォルトのパース処理（汎用）
  static MetadataTableData _parseDefault(dynamic contents, String type) {
    if (contents is List) {
      return _parseListContents(contents, type);
    }

    if (contents is Map<String, dynamic>) {
      return _parseMapContents(contents, type);
    }

    return MetadataTableData(
      headers: [t.metadata.content],
      rows: [
        ['$contents'],
      ],
      type: type,
      title: t.metadata.title(type: type),
    );
  }

  /// リスト形式のcontentsをパース
  static MetadataTableData _parseListContents(
    List<dynamic> list,
    String type,
  ) {
    if (list.isEmpty) {
      return MetadataTableData(
        headers: [t.metadata.info],
        rows: [
          [t.metadata.emptyData],
        ],
        type: type,
        title: t.metadata.title(type: type),
      );
    }

    final firstItem = list.first;

    if (firstItem is Map<String, dynamic>) {
      final allKeys = <String>{};

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          allKeys.addAll(item.keys);
        }
      }

      final headers = allKeys.toList()..sort();
      final rows = <List<String>>[];

      for (final item in list) {
        final row = <String>[];
        if (item is Map<String, dynamic>) {
          for (final key in headers) {
            row.add('${item[key] ?? ''}');
          }
        } else {
          row.addAll(List.filled(headers.length, ''));
        }
        rows.add(row);
      }

      return MetadataTableData(
        headers: headers,
        rows: rows,
        type: type,
        title: t.metadata.titleWithCount(type: type, count: list.length.toString()),
      );
    }

    return MetadataTableData(
      headers: [t.metadata.value],
      rows: list.map((item) => ['$item']).toList(),
      type: type,
      title: t.metadata.titleList(type: type),
    );
  }

  /// 辞書形式のcontentsをパース
  static MetadataTableData _parseMapContents(
    Map<String, dynamic> map,
    String type,
  ) {
    final headers = [t.metadata.key, t.metadata.value];
    final rows =
        map.entries.map((entry) => [entry.key, '${entry.value}']).toList();

    return MetadataTableData(
      headers: headers,
      rows: rows,
      type: type,
      title: t.metadata.title(type: type),
    );
  }
}
