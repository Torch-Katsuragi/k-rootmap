// K-MAPS: メタデータパーサーユーティリティ
// kmaps_metadataカラムの内容をパースして表形式データに変換

import 'dart:convert';

/// メタデータパース結果
class MetadataTableData {
  /// テーブルのヘッダー（列名）
  final List<String> headers;

  /// テーブルのデータ行（各行は各列の値のリスト）
  final List<List<String>> rows;

  /// メタデータタイプ
  final String type;

  /// 表示用タイトル
  final String title;

  const MetadataTableData({
    required this.headers,
    required this.rows,
    required this.type,
    required this.title,
  });
}

/// メタデータパーサークラス
class MetadataParser {
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
      print('[MetadataParser] パースエラー: $e');
      return null;
    }
  }

  /// GPS測量ログの専用パース処理
  static MetadataTableData _parseMeasurementLog(dynamic contents) {
    // contentsが文字列の場合（従来形式）
    if (contents is String) {
      try {
        // 文字列を辞書として解析してみる
        final parsed = _parseStringAsDictionary(contents);
        if (parsed != null) {
          return _parseMeasurementLogData(parsed);
        }

        // 解析できない場合は文字列として表示
        return MetadataTableData(
          headers: ['内容'],
          rows: [
            ['$contents'],
          ],
          type: 'measurement_log',
          title: 'GPS測量ログ（文字列形式）',
        );
      } catch (e) {
        return MetadataTableData(
          headers: ['内容'],
          rows: [
            ['$contents'],
          ],
          type: 'measurement_log',
          title: 'GPS測量ログ（文字列形式）',
        );
      }
    }

    // contentsが辞書の場合（新形式）
    if (contents is Map<String, dynamic>) {
      return _parseMeasurementLogData(contents);
    }

    // contentsがリストの場合（複数測量点）
    if (contents is List) {
      return _parseMeasurementLogList(contents);
    }

    // その他の場合はデフォルト処理
    return _parseDefault(contents, 'measurement_log');
  }

  /// GPS測量ログデータ（辞書形式）をパース
  static MetadataTableData _parseMeasurementLogData(Map<String, dynamic> data) {
    final headers = <String>[];
    final rows = <List<String>>[];

    // 基本情報
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

    // 計算された位置情報
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

    // 元データ（usedGpsData）を文字列として追加
    if (data.containsKey('usedGpsData')) {
      headers.add('元データ');
      rows.add(['${data['usedGpsData']}']);
    }

    // データが横並びになるように転置
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

    // 最初のアイテムから列名を決定
    final headers = <String>['点番号'];
    final firstItem = dataList.first;

    if (firstItem is Map<String, dynamic>) {
      // 共通項目を抽出
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

      // 行の長さをヘッダーに合わせる
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
      // まずJSONとして解析を試行
      return jsonDecode(str) as Map<String, dynamic>;
    } catch (e1) {
      try {
        // Dart辞書形式の文字列として解析を試行（簡易パーサー）
        final cleaned = str.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (cleaned.startsWith('{') && cleaned.endsWith('}')) {
          // 簡易的なDart辞書パーサーは複雑なので、とりあえずnullを返す
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
    // contentsがリストの場合
    if (contents is List) {
      return _parseListContents(contents, type);
    }

    // contentsが辞書の場合
    if (contents is Map<String, dynamic>) {
      return _parseMapContents(contents, type);
    }

    // その他の場合は文字列として表示
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
  static MetadataTableData _parseListContents(List<dynamic> list, String type) {
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

    // リストの各要素が辞書の場合
    if (firstItem is Map<String, dynamic>) {
      final allKeys = <String>{};

      // 全ての要素からキーを収集
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
          // 辞書でない場合は空文字で埋める
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

    // リストの各要素が辞書でない場合
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
