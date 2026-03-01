import 'dart:convert';

import 'package:k_maps/utils/app_logger.dart';

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
          headers: ['内容'],
          rows: [
            [contents],
          ],
          type: 'measurement_log',
          title: 'GPS測量ログ（文字列形式）',
        );
      } catch (e) {
        return MetadataTableData(
          headers: ['内容'],
          rows: [
            [contents],
          ],
          type: 'measurement_log',
          title: 'GPS測量ログ（文字列形式）',
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
      headers.add('測量点番号');
      rows.add(['${data['pointNumber']}']);
    }

    if (data.containsKey('sampleCount')) {
      headers.add('サンプル数');
      rows.add(['${data['sampleCount']}']);
    }

    if (data.containsKey('averagingDuration')) {
      headers.add('測量時間');
      rows.add(['${data['averagingDuration']}']);
    }

    if (data.containsKey('recordedAt')) {
      headers.add('記録日時');
      rows.add(['${data['recordedAt']}']);
    }

    if (data.containsKey('calculatedPosition')) {
      final pos = data['calculatedPosition'] as Map<String, dynamic>;
      if (pos.containsKey('latitude')) {
        headers.add('緯度');
        rows.add(['${pos['latitude']}']);
      }
      if (pos.containsKey('longitude')) {
        headers.add('経度');
        rows.add(['${pos['longitude']}']);
      }
      if (pos.containsKey('altitude')) {
        headers.add('標高');
        rows.add(['${pos['altitude'] ?? 'N/A'}']);
      }
      if (pos.containsKey('averagedAccuracy')) {
        headers.add('平均精度');
        rows.add(['${pos['averagedAccuracy'] ?? 'N/A'}']);
      }
    }

    if (data.containsKey('usedGpsData')) {
      headers.add('元データ');
      rows.add(['${data['usedGpsData']}']);
    }

    if (headers.isNotEmpty && rows.isNotEmpty) {
      return MetadataTableData(
        headers: ['項目', '値'],
        rows: List.generate(headers.length, (i) => [headers[i], rows[i][0]]),
        type: 'measurement_log',
        title: 'GPS測量ログ',
      );
    }

    return MetadataTableData(
      headers: ['情報'],
      rows: [
        ['データが見つかりません'],
      ],
      type: 'measurement_log',
      title: 'GPS測量ログ',
    );
  }

  /// GPS測量ログリスト（複数測量点）をパース
  static MetadataTableData _parseMeasurementLogList(List<dynamic> dataList) {
    if (dataList.isEmpty) {
      return MetadataTableData(
        headers: ['情報'],
        rows: [
          ['データが空です'],
        ],
        type: 'measurement_log',
        title: 'GPS測量ログ（複数点）',
      );
    }

    final headers = <String>['点番号'];
    final firstItem = dataList.first;

    if (firstItem is Map<String, dynamic>) {
      if (firstItem.containsKey('calculatedPosition')) {
        headers.addAll(['緯度', '経度', '標高', '精度']);
      }
      if (firstItem.containsKey('sampleCount')) {
        headers.add('サンプル数');
      }
      if (firstItem.containsKey('averagingDuration')) {
        headers.add('測量時間');
      }
      if (firstItem.containsKey('usedGpsData')) {
        headers.add('元データ');
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
      title: 'GPS測量ログ（${dataList.length}点）',
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
      headers: ['内容'],
      rows: [
        ['$contents'],
      ],
      type: type,
      title: 'メタデータ ($type)',
    );
  }

  /// リスト形式のcontentsをパース
  static MetadataTableData _parseListContents(
    List<dynamic> list,
    String type,
  ) {
    if (list.isEmpty) {
      return MetadataTableData(
        headers: ['情報'],
        rows: [
          ['データが空です'],
        ],
        type: type,
        title: 'メタデータ ($type)',
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
        title: 'メタデータ ($type) - ${list.length}件',
      );
    }

    return MetadataTableData(
      headers: ['値'],
      rows: list.map((item) => ['$item']).toList(),
      type: type,
      title: 'メタデータ ($type) - リスト',
    );
  }

  /// 辞書形式のcontentsをパース
  static MetadataTableData _parseMapContents(
    Map<String, dynamic> map,
    String type,
  ) {
    final headers = ['キー', '値'];
    final rows =
        map.entries.map((entry) => [entry.key, '${entry.value}']).toList();

    return MetadataTableData(
      headers: headers,
      rows: rows,
      type: type,
      title: 'メタデータ ($type)',
    );
  }
}
