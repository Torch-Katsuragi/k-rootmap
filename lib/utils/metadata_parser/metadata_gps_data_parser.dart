import 'dart:convert';

import 'package:root_maps/utils/app_logger.dart';

import 'metadata_table_data.dart';
import '../../i18n/strings.g.dart';

/// GPSデータ文字列のパースと抽出を扱うクラス
class MetadataGpsDataParser {
  /// usedGpsDataの文字列をパース
  static List<dynamic>? parseUsedGpsDataString(String str) {
    try {
      final parsed = jsonDecode(str);
      if (parsed is List) {
        return parsed;
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] JSON形式での解析失敗: $e');

      try {
        return _parseDartMapListString(str);
      } catch (e2) {
        AppLogger.debug('[MetadataParser] Dartマップ形式での解析失敗: $e2');
      }
    }
    return null;
  }

  /// Dartマップ形式のリスト文字列をパース
  static List<dynamic>? _parseDartMapListString(String str) {
    if (str.trim().isEmpty || str == 'null') {
      return null;
    }

    try {
      String jsonStr = str;

      final timestampMap = <String, String>{};
      int timestampCounter = 0;
      jsonStr = jsonStr.replaceAllMapped(
        RegExp(r': (\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+)([,}])'),
        (match) {
          final placeholder = '___TIMESTAMP_${timestampCounter++}___';
          timestampMap[placeholder] = '"${match.group(1)}"';
          return ': $placeholder${match.group(2)}';
        },
      );

      jsonStr = jsonStr.replaceAllMapped(
        RegExp(r'([{,]\s*)(\w+):'),
        (match) => '${match.group(1)}"${match.group(2)}":',
      );

      jsonStr = jsonStr.replaceAllMapped(
        RegExp(r': ([^":\d][^,}]*?)([,}])'),
        (match) {
          final value = match.group(1)!.trim();
          if (!value.startsWith('___TIMESTAMP_') &&
              !RegExp(r'^\d+\.?\d*$').hasMatch(value) &&
              !value.startsWith('"')) {
            return ': "$value"${match.group(2)}';
          }
          return match.group(0)!;
        },
      );

      timestampMap.forEach((placeholder, timestamp) {
        jsonStr = jsonStr.replaceAll(placeholder, timestamp);
      });

      AppLogger.debug(
        '[MetadataParser] 変換後のJSON文字列（最初の200文字）: ${jsonStr.substring(0, jsonStr.length > 200 ? 200 : jsonStr.length)}...',
      );

      final parsed = jsonDecode(jsonStr);
      if (parsed is List) {
        AppLogger.debug(
          '[MetadataParser] Dartマップ形式の解析成功: ${parsed.length}件',
        );
        return parsed;
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] Dartマップ形式解析エラー: $e');

      try {
        return _extractCoordinatesWithRegex(str);
      } catch (e2) {
        AppLogger.debug('[MetadataParser] 正規表現による抽出も失敗: $e2');
      }
    }

    return null;
  }

  /// 正規表現を使って座標データと詳細情報を抽出
  static List<dynamic>? _extractCoordinatesWithRegex(String str) {
    final coordinates = <Map<String, dynamic>>[];

    final regex = RegExp(
      r'\{latitude:\s*([\d.]+),\s*longitude:\s*([\d.]+),\s*altitude:\s*([\d.]+),\s*accuracy:\s*([\d.]+)',
    );
    final matches = regex.allMatches(str);

    for (final match in matches) {
      final lat = double.tryParse(match.group(1)!);
      final lng = double.tryParse(match.group(2)!);
      final alt = double.tryParse(match.group(3)!);
      final acc = double.tryParse(match.group(4)!);

      if (lat != null && lng != null) {
        coordinates.add({
          'latitude': lat,
          'longitude': lng,
          'altitude': alt,
          'accuracy': acc,
        });
      }
    }

    if (coordinates.isEmpty) {
      final basicRegex = RegExp(
        r'latitude:\s*([\d.]+),\s*longitude:\s*([\d.]+)',
      );
      final basicMatches = basicRegex.allMatches(str);

      for (final match in basicMatches) {
        final lat = double.tryParse(match.group(1)!);
        final lng = double.tryParse(match.group(2)!);

        if (lat != null && lng != null) {
          coordinates.add({'latitude': lat, 'longitude': lng});
        }
      }
    }

    if (coordinates.isNotEmpty) {
      AppLogger.debug(
        '[MetadataParser] 正規表現による座標抽出成功: ${coordinates.length}件',
      );
      return coordinates;
    }

    return null;
  }

  /// 元データからusedGpsDataを抽出
  static List<dynamic>? extractUsedGpsDataFromOriginalMetadata(
    MetadataTableData baseData,
  ) {
    AppLogger.debug(
      '[MetadataParser] 元データ抽出開始: type=${baseData.type}, 行数=${baseData.rows.length}',
    );
    AppLogger.debug('[MetadataParser] ヘッダー: ${baseData.headers}');

    if (baseData.type == 'measurement_log') {
      if (baseData.headers.length == 2 &&
          baseData.headers[0] == t.metadata.key &&
          baseData.headers[1] == t.metadata.value) {
        for (int i = 0; i < baseData.rows.length; i++) {
          final row = baseData.rows[i];
          AppLogger.debug(
            '[MetadataParser] キー・値形式 行${i + 1}: 列数=${row.length}, キー="${row.isNotEmpty ? row[0] : "空"}"',
          );

          if (row.length >= 2 && row[0] == t.metadata.rawData) {
            final usedGpsDataString = row[1];
            AppLogger.debug(
              '[MetadataParser] 元データ発見! 文字列長=${usedGpsDataString.length}',
            );
            AppLogger.debug(
              '[MetadataParser] 元データの最初の100文字: ${usedGpsDataString.length > 100 ? usedGpsDataString.substring(0, 100) : usedGpsDataString}...',
            );

            final result = parseUsedGpsDataString(usedGpsDataString);
            AppLogger.debug(
              '[MetadataParser] パース結果: ${result != null ? "${result.length}件" : "null"}',
            );
            return result;
          }
        }
      } else {
        int? dataColumnIndex;
        for (int i = 0; i < baseData.headers.length; i++) {
          if (baseData.headers[i] == t.metadata.rawData) {
            dataColumnIndex = i;
            break;
          }
        }

        AppLogger.debug(
          '[MetadataParser] 表形式: 元データ列インデックス=$dataColumnIndex',
        );

        if (dataColumnIndex != null && baseData.rows.isNotEmpty) {
          final firstRow = baseData.rows[0];
          if (dataColumnIndex < firstRow.length) {
            final usedGpsDataString = firstRow[dataColumnIndex];
            AppLogger.debug(
              '[MetadataParser] 表形式元データ発見! 文字列長=${usedGpsDataString.length}',
            );
            AppLogger.debug(
              '[MetadataParser] 元データの最初の100文字: ${usedGpsDataString.length > 100 ? usedGpsDataString.substring(0, 100) : usedGpsDataString}...',
            );

            final result = parseUsedGpsDataString(usedGpsDataString);
            AppLogger.debug(
              '[MetadataParser] パース結果: ${result != null ? "${result.length}件" : "null"}',
            );
            return result;
          } else {
            AppLogger.debug(
              '[MetadataParser] 行の列数が不足: 期待=${dataColumnIndex + 1}, 実際=${firstRow.length}',
            );
          }
        }
      }

      AppLogger.debug('[MetadataParser] 元データ列が見つかりませんでした');
    } else {
      AppLogger.debug('[MetadataParser] measurement_logではないためスキップ');
    }
    return null;
  }
}
