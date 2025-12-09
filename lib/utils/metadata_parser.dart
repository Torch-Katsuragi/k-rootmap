// K-MAPS: メタデータパーサーユーティリティ
// kmaps_metadataカラムの内容をパースして表形式データに変換

import 'dart:convert';
import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';
import '../utils/coordinate_converter.dart';
import '../utils/address_converter.dart';

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

  /// 座標系選択肢（EPSGコード -> 座標系名のマップ）
  final Map<String, String>? coordinateSystemOptions;

  /// 現在選択されている座標系のEPSGコード
  final String? selectedCoordinateSystem;

  const MetadataTableData({
    required this.headers,
    required this.rows,
    required this.type,
    required this.title,
    this.coordinateSystemOptions,
    this.selectedCoordinateSystem,
  });

  /// 座標系を変更した新しいMetadataTableDataを作成
  MetadataTableData copyWithCoordinateSystem(String newEpsgCode) {
    return MetadataTableData(
      headers: headers,
      rows: rows,
      type: type,
      title: title,
      coordinateSystemOptions: coordinateSystemOptions,
      selectedCoordinateSystem: newEpsgCode,
    );
  }
}

/// メタデータパーサークラス
class MetadataParser {
  /// メタデータをパースして表形式データに変換（XY座標自動追加機能付き）
  static Future<MetadataTableData?> parseMetadataWithCoordinates(
    Map<String, dynamic> metadata,
    LatLng? featureLatLng, {
    String? selectedEpsgCode,
  }) async {
    try {
      final baseData = parseMetadata(metadata);
      if (baseData == null || featureLatLng == null) {
        return baseData;
      }

      AppLogger.debug(
        '[MetadataParser] 基本データ: ヘッダー=${baseData.headers}, 行数=${baseData.rows.length}',
      );

      // 座標系選択肢を生成
      final coordinateOptions = await _generateCoordinateSystemOptions(
        featureLatLng,
      );
      final defaultEpsg = selectedEpsgCode ?? coordinateOptions.keys.first;

      // XY座標を計算
      final xyCoordinates = await _calculateXYCoordinates(
        featureLatLng,
        defaultEpsg,
      );

      AppLogger.debug(
        '[MetadataParser] XY座標計算結果: X=${xyCoordinates['x']}, Y=${xyCoordinates['y']}',
      );

      // データ形式に応じてXY座標を追加
      if (baseData.headers.length == 2 &&
          baseData.headers[0] == 'キー' &&
          baseData.headers[1] == '値') {
        // キー・値形式の場合
        return await _addXYCoordinatesToKeyValueFormat(
          baseData,
          xyCoordinates,
          coordinateOptions,
          defaultEpsg,
        );
      } else {
        // 通常の表形式の場合
        return await _addXYCoordinatesToTableFormat(
          baseData,
          xyCoordinates,
          coordinateOptions,
          defaultEpsg,
        );
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標追加エラー: $e');
      return parseMetadata(metadata);
    }
  }

  /// 座標系選択肢を生成
  static Future<Map<String, String>> _generateCoordinateSystemOptions(
    LatLng point,
  ) async {
    final options = <String, String>{};

    AppLogger.debug(
      '[MetadataParser] 座標系選択肢生成開始: (${point.latitude}, ${point.longitude})',
    );

    // UTM座標系（デフォルト）- 動的に生成
    final zoneNumber = CoordinateConverter.calculateUTMZone(point.longitude);
    final utmEpsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
    final utmName = 'UTM Zone ${zoneNumber}N';
    options[utmEpsg] = utmName;

    AppLogger.debug('[MetadataParser] UTM座標系選択肢追加: $utmName ($utmEpsg)');

    // 住所を取得して日本かどうか判定
    try {
      AppLogger.debug('[MetadataParser] 住所取得開始...');
      final address = await AddressConverter.getAddressFromLatLng(point);
      AppLogger.debug('[MetadataParser] 住所取得結果: ${address?.displayName ?? "null"}');

      if (address != null) {
        final isJapan = _isJapanAddress(address);
        AppLogger.debug('[MetadataParser] 日本住所判定: $isJapan');

        if (isJapan) {
          AppLogger.debug('[MetadataParser] JGD2011座標系取得開始...');
          // 日本平面直角座標系の選択肢を追加
          final jgd2011System =
              await CoordinateConverter.getBestCoordinateSystem(point);
          AppLogger.debug(
            '[MetadataParser] JGD2011座標系取得結果: ${jgd2011System?.name} (${jgd2011System?.epsgCode})',
          );

          if (jgd2011System != null && jgd2011System.epsgCode != utmEpsg) {
            options[jgd2011System.epsgCode] = jgd2011System.name;
            AppLogger.debug(
              '[MetadataParser] JGD2011座標系選択肢追加: ${jgd2011System.name} (${jgd2011System.epsgCode})',
            );
          } else {
            AppLogger.debug(
              '[MetadataParser] JGD2011座標系が追加されませんでした - システム: ${jgd2011System?.epsgCode}, UTM: $utmEpsg',
            );
          }
        }
      } else {
        AppLogger.debug('[MetadataParser] 住所がnullのため、JGD2011座標系をスキップ');
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] 住所取得エラー: $e');
    }

    AppLogger.debug('[MetadataParser] 最終的な座標系選択肢: $options');
    return options;
  }

  /// 住所が日本かどうかを判定
  static bool _isJapanAddress(Address address) {
    return address.country?.toLowerCase() == 'japan' ||
        address.countryCode?.toLowerCase() == 'jp' ||
        address.displayName.contains('日本') ||
        address.displayName.contains('Japan');
  }

  /// XY座標を計算
  static Future<Map<String, String>> _calculateXYCoordinates(
    LatLng point,
    String epsgCode, {
    String? cachedState,
  }) async {
    AppLogger.debug('[MetadataParser] XY座標計算開始: EPSG=$epsgCode');

    try {
      CoordinateSystem? coordinateSystem;

      if (epsgCode.startsWith('326') || epsgCode.startsWith('327')) {
        // UTM座標系 - EPSGコードから直接座標系を作成
        final zoneNumber = CoordinateConverter.calculateUTMZone(
          point.longitude,
        );
        final expectedEpsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
        final proj4String =
            '+proj=utm +zone=$zoneNumber +datum=WGS84 +units=m +no_defs';

        coordinateSystem = CoordinateSystem(
          name: 'UTM Zone ${zoneNumber}N',
          epsgCode: expectedEpsg,
          proj4String: proj4String,
        );

        AppLogger.debug(
          '[MetadataParser] UTM座標系使用: ${coordinateSystem.name} (${coordinateSystem.epsgCode})',
        );
      } else if (epsgCode.startsWith('667')) {
        // JGD2011座標系 - 指定されたEPSGコードから直接座標系を作成
        AppLogger.debug('[MetadataParser] JGD2011座標系処理開始: $epsgCode');
        coordinateSystem = await _getJGD2011CoordinateSystem(
          epsgCode,
          point,
          cachedState: cachedState,
        );
        AppLogger.debug(
          '[MetadataParser] JGD2011座標系取得結果: ${coordinateSystem?.name} (${coordinateSystem?.epsgCode})',
        );

        if (coordinateSystem == null) {
          AppLogger.debug('[MetadataParser] JGD2011座標系がnullです - EPSGコードから直接作成を試行');
          coordinateSystem = _createJGD2011CoordinateSystemFromEpsg(epsgCode);
          AppLogger.debug('[MetadataParser] EPSGコードから作成結果: ${coordinateSystem?.name}');
        }
      } else {
        // その他の座標系 - 自動判定
        AppLogger.debug('[MetadataParser] その他の座標系 - 自動判定開始');
        coordinateSystem = await CoordinateConverter.getBestCoordinateSystem(
          point,
          cachedState: cachedState,
        );
        AppLogger.debug(
          '[MetadataParser] 自動判定座標系使用: ${coordinateSystem?.name} (${coordinateSystem?.epsgCode})',
        );
      }

      if (coordinateSystem != null) {
        AppLogger.debug('[MetadataParser] 座標変換開始: ${coordinateSystem.epsgCode}');
        final xy = CoordinateConverter.latLngToXY(
          point,
          coordinateSystem: coordinateSystem,
        );

        AppLogger.debug(
          '[MetadataParser] XY座標計算成功: X=${xy.x.toStringAsFixed(3)}, Y=${xy.y.toStringAsFixed(3)}',
        );
        return {'x': xy.x.toStringAsFixed(3), 'y': xy.y.toStringAsFixed(3)};
      } else {
        AppLogger.debug('[MetadataParser] 座標系がnullです');
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標計算エラー: $e');
    }

    return {'x': 'N/A', 'y': 'N/A'};
  }

  /// JGD2011座標系を取得
  static Future<CoordinateSystem?> _getJGD2011CoordinateSystem(
    String epsgCode,
    LatLng point, {
    String? cachedState,
  }) async {
    // キャッシュされたstateがある場合はそれを使用
    if (cachedState != null) {
      AppLogger.debug('[MetadataParser] キャッシュされたstate使用: $cachedState');
      final jgd2011Zone = CoordinateConverter.getJGD2011ZoneFromState(
        cachedState,
      );
      if (jgd2011Zone != null && jgd2011Zone.epsgCode == epsgCode) {
        return jgd2011Zone;
      }
    }

    // キャッシュがない場合は住所から取得
    final address = await AddressConverter.getAddressFromLatLng(point);
    if (address != null) {
      final jgd2011Zone = CoordinateConverter.getJGD2011ZoneFromAddress(
        address,
      );
      if (jgd2011Zone != null && jgd2011Zone.epsgCode == epsgCode) {
        return jgd2011Zone;
      }
    }

    // 住所から取得できない場合は、EPSGコードから直接作成
    return _createJGD2011CoordinateSystemFromEpsg(epsgCode);
  }

  /// EPSGコードからJGD2011座標系を作成
  static CoordinateSystem? _createJGD2011CoordinateSystemFromEpsg(
    String epsgCode,
  ) {
    switch (epsgCode) {
      case 'EPSG:6669':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS I',
          epsgCode: 'EPSG:6669',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=129.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6670':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS II',
          epsgCode: 'EPSG:6670',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=131 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6671':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS III',
          epsgCode: 'EPSG:6671',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=132.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6672':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IV',
          epsgCode: 'EPSG:6672',
          proj4String:
              '+proj=tmerc +lat_0=33 +lon_0=133.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6673':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS V',
          epsgCode: 'EPSG:6673',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=134.333333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6674':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VI',
          epsgCode: 'EPSG:6674',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=136 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs +type=crs',
        );
      case 'EPSG:6675':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VII',
          epsgCode: 'EPSG:6675',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=137.166666666667 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6676':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS VIII',
          epsgCode: 'EPSG:6676',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=138.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6677':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS IX',
          epsgCode: 'EPSG:6677',
          proj4String:
              '+proj=tmerc +lat_0=36 +lon_0=139.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6678':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS X',
          epsgCode: 'EPSG:6678',
          proj4String:
              '+proj=tmerc +lat_0=40 +lon_0=140.833333333333 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6679':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS XI',
          epsgCode: 'EPSG:6679',
          proj4String:
              '+proj=tmerc +lat_0=44 +lon_0=140.25 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      case 'EPSG:6683':
        return CoordinateSystem(
          name: 'JGD2011 / Japan Plane Rectangular CS XV',
          epsgCode: 'EPSG:6683',
          proj4String:
              '+proj=tmerc +lat_0=26 +lon_0=127.5 +k=0.9999 +x_0=0 +y_0=0 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
        );
      default:
        return null;
    }
  }

  /// XY座標を再計算
  static Future<MetadataTableData> recalculateXYCoordinates(
    MetadataTableData originalData,
    LatLng point,
    String newEpsgCode,
  ) async {
    AppLogger.debug('[MetadataParser] XY座標再計算開始');
    AppLogger.debug('[MetadataParser] 元のEPSG: ${originalData.selectedCoordinateSystem}');
    AppLogger.debug('[MetadataParser] 新しいEPSG: $newEpsgCode');
    AppLogger.debug('[MetadataParser] 座標: (${point.latitude}, ${point.longitude})');

    // 新しい座標系でXY座標を計算
    final newXY = await _calculateXYCoordinates(point, newEpsgCode);
    AppLogger.debug('[MetadataParser] 新しいXY座標: X=${newXY['x']}, Y=${newXY['y']}');

    // 新しい座標系名を取得
    final newCoordinateSystemName =
        originalData.coordinateSystemOptions?[newEpsgCode] ?? 'Unknown';
    AppLogger.debug('[MetadataParser] 新しい座標系名: $newCoordinateSystemName');

    // 新しいXY座標をすべて計算
    final allNewXYCoordinates = await _calculateAllXYCoordinates(
      originalData,
      newXY,
      newEpsgCode,
    );

    // データ形式に応じてXY座標を更新
    List<List<String>> updatedRows;
    if (originalData.headers.length == 2 &&
        originalData.headers[0] == 'キー' &&
        originalData.headers[1] == '値') {
      // キー・値形式の場合
      updatedRows = _updateXYInKeyValueRowsAll(
        originalData.rows,
        allNewXYCoordinates,
      );
      AppLogger.debug('[MetadataParser] キー・値形式でXY座標更新完了');
    } else {
      // 通常の表形式の場合
      updatedRows = await _updateXYInRowsAll(
        originalData.rows,
        originalData.headers,
        allNewXYCoordinates,
        point,
        newEpsgCode,
      );
      AppLogger.debug('[MetadataParser] 表形式でXY座標更新完了');
    }

    // テーブルデータを更新
    final updatedData = MetadataTableData(
      title:
          '${originalData.type == 'measurement_log' ? 'GPS測量ログ' : 'メタデータ'} ($newCoordinateSystemName)',
      headers: originalData.headers,
      rows: updatedRows,
      type: originalData.type,
      selectedCoordinateSystem: newEpsgCode,
      coordinateSystemOptions: originalData.coordinateSystemOptions,
    );

    AppLogger.debug('[MetadataParser] XY座標再計算完了');
    return updatedData;
  }

  /// キー・値形式の行データのXY座標をすべて更新
  static List<List<String>> _updateXYInKeyValueRowsAll(
    List<List<String>> originalRows,
    Map<String, String> allXYCoordinates,
  ) {
    final newRows = <List<String>>[];

    for (final row in originalRows) {
      if (row.length >= 2) {
        // 新しいXY座標形式に対応
        if (row[0] == 'X座標（最初）') {
          newRows.add([row[0], allXYCoordinates['x_first'] ?? 'N/A']);
        } else if (row[0] == 'Y座標（最初）') {
          newRows.add([row[0], allXYCoordinates['y_first'] ?? 'N/A']);
        } else if (row[0] == 'X座標（最後）') {
          newRows.add([row[0], allXYCoordinates['x_last'] ?? 'N/A']);
        } else if (row[0] == 'Y座標（最後）') {
          newRows.add([row[0], allXYCoordinates['y_last'] ?? 'N/A']);
        } else if (row[0] == 'X座標（平均）') {
          newRows.add([row[0], allXYCoordinates['x_avg'] ?? 'N/A']);
        } else if (row[0] == 'Y座標（平均）') {
          newRows.add([row[0], allXYCoordinates['y_avg'] ?? 'N/A']);
        } else {
          // その他の行はそのまま
          newRows.add(List.from(row));
        }
      } else {
        // 不正な行はそのまま
        newRows.add(List.from(row));
      }
    }

    return newRows;
  }

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

  /// 元データから直接最初・最後・平均のXY座標をすべて計算
  static Future<Map<String, String>> _calculateAllXYCoordinatesFromOriginalData(
    MetadataTableData baseData,
    Map<String, String> avgXYCoordinates,
    String epsgCode,
  ) async {
    try {
      // 元データから直接usedGpsDataを抽出
      List<dynamic>? usedGpsData;

      if (baseData.type == 'measurement_log') {
        // 表形式の場合：元の「元データ」列を探す
        int? originalDataColumnIndex;
        for (int i = 0; i < baseData.headers.length; i++) {
          if (baseData.headers[i] == '元データ') {
            originalDataColumnIndex = i;
            break;
          }
        }

        AppLogger.debug('[MetadataParser] 元データ列検索: インデックス=$originalDataColumnIndex');

        if (originalDataColumnIndex != null && baseData.rows.isNotEmpty) {
          final firstRow = baseData.rows[0];
          if (originalDataColumnIndex < firstRow.length) {
            final usedGpsDataString = firstRow[originalDataColumnIndex];
            AppLogger.debug(
              '[MetadataParser] 元データ文字列取得成功: 長さ=${usedGpsDataString.length}',
            );
            usedGpsData = _parseUsedGpsDataString(usedGpsDataString);
          }
        }
      }

      // usedGpsDataが取得できた場合、最初と最後のXY座標を計算
      if (usedGpsData != null && usedGpsData.isNotEmpty) {
        AppLogger.debug('[MetadataParser] usedGpsData取得成功: ${usedGpsData.length}件');

        final firstGps = usedGpsData.first as Map<String, dynamic>;
        final lastGps = usedGpsData.last as Map<String, dynamic>;

        final firstPoint = LatLng(
          (firstGps['latitude'] as num).toDouble(),
          (firstGps['longitude'] as num).toDouble(),
        );
        final lastPoint = LatLng(
          (lastGps['latitude'] as num).toDouble(),
          (lastGps['longitude'] as num).toDouble(),
        );

        final firstXY = await _calculateXYCoordinates(firstPoint, epsgCode);
        final lastXY = await _calculateXYCoordinates(lastPoint, epsgCode);

        return {
          'x_first': firstXY['x'] ?? 'N/A',
          'y_first': firstXY['y'] ?? 'N/A',
          'x_last': lastXY['x'] ?? 'N/A',
          'y_last': lastXY['y'] ?? 'N/A',
          'x_avg': avgXYCoordinates['x'] ?? 'N/A',
          'y_avg': avgXYCoordinates['y'] ?? 'N/A',
        };
      } else {
        AppLogger.debug('[MetadataParser] usedGpsDataが取得できないため平均値のみ使用');
        return {
          'x_first': avgXYCoordinates['x'] ?? 'N/A',
          'y_first': avgXYCoordinates['y'] ?? 'N/A',
          'x_last': avgXYCoordinates['x'] ?? 'N/A',
          'y_last': avgXYCoordinates['y'] ?? 'N/A',
          'x_avg': avgXYCoordinates['x'] ?? 'N/A',
          'y_avg': avgXYCoordinates['y'] ?? 'N/A',
        };
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標計算エラー: $e');
      return {
        'x_first': 'N/A',
        'y_first': 'N/A',
        'x_last': 'N/A',
        'y_last': 'N/A',
        'x_avg': avgXYCoordinates['x'] ?? 'N/A',
        'y_avg': avgXYCoordinates['y'] ?? 'N/A',
      };
    }
  }

  /// 最初・最後・平均のXY座標をすべて計算
  static Future<Map<String, String>> _calculateAllXYCoordinates(
    MetadataTableData baseData,
    Map<String, String> avgXYCoordinates,
    String epsgCode,
  ) async {
    try {
      // 元データを探す - 元のメタデータから直接取得を試行
      List<dynamic>? usedGpsData;

      // GPS測量ログの場合は、元のメタデータから直接usedGpsDataを取得
      if (baseData.type == 'measurement_log') {
        // 元データの辞書構造から直接取得を試行
        usedGpsData = _extractUsedGpsDataFromOriginalMetadata(baseData);

        if (usedGpsData != null && usedGpsData.isNotEmpty) {
          AppLogger.debug(
            '[MetadataParser] 元のメタデータからusedGpsDataを直接取得成功: ${usedGpsData.length}件',
          );
        }
      }

      // 直接取得できない場合は、表示されている文字列から解析
      if (usedGpsData == null || usedGpsData.isEmpty) {
        String? usedGpsDataString;
        for (final row in baseData.rows) {
          if (row.length >= 2 && row[0] == '元データ') {
            usedGpsDataString = row[1];
            break;
          }
        }

        if (usedGpsDataString == null ||
            usedGpsDataString == 'null' ||
            usedGpsDataString.isEmpty) {
          AppLogger.debug('[MetadataParser] usedGpsDataが見つからないため平均値のみ使用');
          return {
            'x_first': avgXYCoordinates['x'] ?? 'N/A',
            'y_first': avgXYCoordinates['y'] ?? 'N/A',
            'x_last': avgXYCoordinates['x'] ?? 'N/A',
            'y_last': avgXYCoordinates['y'] ?? 'N/A',
            'x_avg': avgXYCoordinates['x'] ?? 'N/A',
            'y_avg': avgXYCoordinates['y'] ?? 'N/A',
          };
        }

        // usedGpsDataをパース
        try {
          // 文字列からリストをパース
          final cleaned = usedGpsDataString.replaceAll('null', 'null');
          usedGpsData = _parseUsedGpsDataString(cleaned);
        } catch (e) {
          AppLogger.debug('[MetadataParser] usedGpsDataパースエラー: $e');
          usedGpsData = null;
        }

        if (usedGpsData == null || usedGpsData.isEmpty) {
          AppLogger.debug('[MetadataParser] usedGpsDataが空のため平均値のみ使用');
          return {
            'x_first': avgXYCoordinates['x'] ?? 'N/A',
            'y_first': avgXYCoordinates['y'] ?? 'N/A',
            'x_last': avgXYCoordinates['x'] ?? 'N/A',
            'y_last': avgXYCoordinates['y'] ?? 'N/A',
            'x_avg': avgXYCoordinates['x'] ?? 'N/A',
            'y_avg': avgXYCoordinates['y'] ?? 'N/A',
          };
        }
      }

      // 最初と最後のGPSデータを取得
      final firstGps = usedGpsData.first as Map<String, dynamic>;
      final lastGps = usedGpsData.last as Map<String, dynamic>;

      AppLogger.debug(
        '[MetadataParser] 最初のGPS: ${firstGps['latitude']}, ${firstGps['longitude']}',
      );
      AppLogger.debug(
        '[MetadataParser] 最後のGPS: ${lastGps['latitude']}, ${lastGps['longitude']}',
      );

      // XY座標を計算
      final firstPoint = LatLng(
        (firstGps['latitude'] as num).toDouble(),
        (firstGps['longitude'] as num).toDouble(),
      );
      final lastPoint = LatLng(
        (lastGps['latitude'] as num).toDouble(),
        (lastGps['longitude'] as num).toDouble(),
      );

      final firstXY = await _calculateXYCoordinates(firstPoint, epsgCode);
      final lastXY = await _calculateXYCoordinates(lastPoint, epsgCode);

      return {
        'x_first': firstXY['x'] ?? 'N/A',
        'y_first': firstXY['y'] ?? 'N/A',
        'x_last': lastXY['x'] ?? 'N/A',
        'y_last': lastXY['y'] ?? 'N/A',
        'x_avg': avgXYCoordinates['x'] ?? 'N/A',
        'y_avg': avgXYCoordinates['y'] ?? 'N/A',
      };
    } catch (e) {
      AppLogger.debug('[MetadataParser] XY座標計算エラー: $e');
      return {
        'x_first': 'N/A',
        'y_first': 'N/A',
        'x_last': 'N/A',
        'y_last': 'N/A',
        'x_avg': avgXYCoordinates['x'] ?? 'N/A',
        'y_avg': avgXYCoordinates['y'] ?? 'N/A',
      };
    }
  }

  /// usedGpsDataの文字列をパース
  static List<dynamic>? _parseUsedGpsDataString(String str) {
    try {
      // まずJSON形式でパース
      final parsed = jsonDecode(str);
      if (parsed is List) {
        return parsed;
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] JSON形式での解析失敗: $e');

      // Dartマップ形式の文字列として解析を試行
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
      // 文字列をJSONに変換するために、Dartの記法をJSONの記法に変換
      String jsonStr = str;

      // 1. 最初に日付時刻を一時的なプレースホルダーに置換（衝突を避けるため）
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

      // 2. キーを引用符で囲む（プレースホルダーには影響しない）
      jsonStr = jsonStr.replaceAllMapped(
        RegExp(r'([{,]\s*)(\w+):'),
        (match) => '${match.group(1)}"${match.group(2)}":',
      );

      // 3. 数値以外の文字列を引用符で囲む（プレースホルダー以外、日本語含む）
      jsonStr = jsonStr.replaceAllMapped(RegExp(r': ([^":\d][^,}]*?)([,}])'), (
        match,
      ) {
        final value = match.group(1)!.trim();
        // プレースホルダーや数値でない場合のみ引用符で囲む
        if (!value.startsWith('___TIMESTAMP_') &&
            !RegExp(r'^\d+\.?\d*$').hasMatch(value) &&
            !value.startsWith('"')) {
          return ': "$value"${match.group(2)}';
        }
        return match.group(0)!;
      });

      // 4. プレースホルダーを実際の日付時刻文字列に戻す
      timestampMap.forEach((placeholder, timestamp) {
        jsonStr = jsonStr.replaceAll(placeholder, timestamp);
      });

      AppLogger.debug(
        '[MetadataParser] 変換後のJSON文字列（最初の200文字）: ${jsonStr.substring(0, jsonStr.length > 200 ? 200 : jsonStr.length)}...',
      );

      final parsed = jsonDecode(jsonStr);
      if (parsed is List) {
        AppLogger.debug('[MetadataParser] Dartマップ形式の解析成功: ${parsed.length}件');
        return parsed;
      }
    } catch (e) {
      AppLogger.debug('[MetadataParser] Dartマップ形式解析エラー: $e');

      // 最後の手段として正規表現で座標データを抽出
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

    // より詳細なパターンマッチング - latitude, longitude, altitude, accuracy などを抽出
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

    // フォールバック：基本的な座標のみのパターン
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
      AppLogger.debug('[MetadataParser] 正規表現による座標抽出成功: ${coordinates.length}件');
      return coordinates;
    }

    return null;
  }

  /// キー・値形式のデータにXY座標を追加
  static Future<MetadataTableData> _addXYCoordinatesToKeyValueFormat(
    MetadataTableData baseData,
    Map<String, String> xyCoordinates,
    Map<String, String> coordinateOptions,
    String defaultEpsg,
  ) async {
    AppLogger.debug('[MetadataParser] キー・値形式でXY座標追加開始');

    final newRows = <List<String>>[];

    // 既存の行をコピー
    newRows.addAll(baseData.rows);

    // 最初・最後・平均のXY座標を計算
    final allXYCoordinates = await _calculateAllXYCoordinates(
      baseData,
      xyCoordinates,
      defaultEpsg,
    );

    // 緯度行と経度行のインデックスを探す
    int latitudeIndex = -1;
    int longitudeIndex = -1;
    for (int i = 0; i < baseData.rows.length; i++) {
      if (baseData.rows[i][0] == '緯度') {
        latitudeIndex = i;
      } else if (baseData.rows[i][0] == '経度') {
        longitudeIndex = i;
      }
    }

    // 列順序を変更: 緯度 → 経度 → X座標（最初・最後・平均）→ Y座標（最初・最後・平均）
    int insertIndex = 0;

    // 経度の次にXY座標を挿入
    if (longitudeIndex >= 0) {
      insertIndex = longitudeIndex + 1;
    } else if (latitudeIndex >= 0) {
      insertIndex = latitudeIndex + 1;
    } else {
      insertIndex = newRows.length;
    }

    // X座標を順番に挿入
    newRows.insert(insertIndex++, [
      'X座標（最初）',
      allXYCoordinates['x_first'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'Y座標（最初）',
      allXYCoordinates['y_first'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'X座標（最後）',
      allXYCoordinates['x_last'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'Y座標（最後）',
      allXYCoordinates['y_last'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'X座標（平均）',
      allXYCoordinates['x_avg'] ?? 'N/A',
    ]);
    newRows.insert(insertIndex++, [
      'Y座標（平均）',
      allXYCoordinates['y_avg'] ?? 'N/A',
    ]);

    AppLogger.debug('[MetadataParser] キー・値形式でXY座標追加完了: 行数=${newRows.length}');

    return MetadataTableData(
      headers: baseData.headers, // ヘッダーはそのまま
      rows: newRows,
      type: baseData.type,
      title: '${baseData.title} (${coordinateOptions[defaultEpsg]})',
      coordinateSystemOptions: coordinateOptions,
      selectedCoordinateSystem: defaultEpsg,
    );
  }

  /// 通常の表形式のデータにXY座標を追加
  static Future<MetadataTableData> _addXYCoordinatesToTableFormat(
    MetadataTableData baseData,
    Map<String, String> xyCoordinates,
    Map<String, String> coordinateOptions,
    String defaultEpsg,
  ) async {
    AppLogger.debug('[MetadataParser] 表形式でXY座標追加開始');

    // 緯度・経度列のインデックスを探す
    int? latIndex, lngIndex;
    for (int i = 0; i < baseData.headers.length; i++) {
      if (baseData.headers[i] == '緯度') {
        latIndex = i;
      } else if (baseData.headers[i] == '経度') {
        lngIndex = i;
      }
    }

    // 新しいヘッダーと行を作成（緯度→経度→XY座標の順序に変更）
    final newHeaders = <String>[];
    final newRows = <List<String>>[];

    for (int i = 0; i < baseData.headers.length; i++) {
      newHeaders.add(baseData.headers[i]);

      // 経度の次にXY座標を追加（列順序変更）
      if (baseData.headers[i] == '経度') {
        newHeaders.addAll([
          'X座標（最初）',
          'Y座標（最初）',
          'X座標（最後）',
          'Y座標（最後）',
          'X座標（平均）',
          'Y座標（平均）',
        ]);
      }
    }

    AppLogger.debug('[MetadataParser] 新しいヘッダー: $newHeaders');

    // 最初・最後・平均のXY座標をすべて計算（元データから直接）
    final allXYCoordinates = await _calculateAllXYCoordinatesFromOriginalData(
      baseData,
      xyCoordinates,
      defaultEpsg,
    );

    // 最初の行からstateを取得してキャッシュ
    String? cachedState;
    if (latIndex != null && lngIndex != null && baseData.rows.isNotEmpty) {
      try {
        final firstRow = baseData.rows[0];
        if (latIndex < firstRow.length && lngIndex < firstRow.length) {
          final lat = double.parse(firstRow[latIndex]);
          final lng = double.parse(firstRow[lngIndex]);
          final firstPoint = LatLng(lat, lng);

          AppLogger.debug('[MetadataParser] 最初の座標でstate取得: ($lat, $lng)');
          final address = await AddressConverter.getAddressFromLatLng(
            firstPoint,
          );
          if (address != null) {
            cachedState = CoordinateConverter.getStateFromAddress(address);
            AppLogger.debug('[MetadataParser] キャッシュされたstate: $cachedState');
          }
        }
      } catch (e) {
        AppLogger.debug('[MetadataParser] state取得エラー: $e');
      }
    }

    // 元データ列のインデックスを取得
    int? originalDataColumnIndex;
    for (int i = 0; i < baseData.headers.length; i++) {
      if (baseData.headers[i] == '元データ') {
        originalDataColumnIndex = i;
        break;
      }
    }

    // 各行を処理
    for (int rowIndex = 0; rowIndex < baseData.rows.length; rowIndex++) {
      final originalRow = baseData.rows[rowIndex];
      final newRow = <String>[];

      // デフォルト値（全体の最初・最後・平均）
      String xFirstCoord = allXYCoordinates['x_first'] ?? 'N/A';
      String yFirstCoord = allXYCoordinates['y_first'] ?? 'N/A';
      String xLastCoord = allXYCoordinates['x_last'] ?? 'N/A';
      String yLastCoord = allXYCoordinates['y_last'] ?? 'N/A';
      String xAvgCoord = allXYCoordinates['x_avg'] ?? 'N/A';
      String yAvgCoord = allXYCoordinates['y_avg'] ?? 'N/A';

      // 各行の元データから個別のXY座標を計算
      if (originalDataColumnIndex != null &&
          originalDataColumnIndex < originalRow.length) {
        try {
          final rowUsedGpsDataString = originalRow[originalDataColumnIndex];
          final rowUsedGpsData = _parseUsedGpsDataString(rowUsedGpsDataString);

          if (rowUsedGpsData != null && rowUsedGpsData.isNotEmpty) {
            AppLogger.debug(
              '[MetadataParser] 行${rowIndex + 1}: 個別GPS データ${rowUsedGpsData.length}件',
            );

            // この行の最初と最後のGPSデータを取得
            final rowFirstGps = rowUsedGpsData.first as Map<String, dynamic>;
            final rowLastGps = rowUsedGpsData.last as Map<String, dynamic>;

            final rowFirstPoint = LatLng(
              (rowFirstGps['latitude'] as num).toDouble(),
              (rowFirstGps['longitude'] as num).toDouble(),
            );
            final rowLastPoint = LatLng(
              (rowLastGps['latitude'] as num).toDouble(),
              (rowLastGps['longitude'] as num).toDouble(),
            );

            // XY座標を計算
            final rowFirstXY = await _calculateXYCoordinates(
              rowFirstPoint,
              defaultEpsg,
              cachedState: cachedState,
            );
            final rowLastXY = await _calculateXYCoordinates(
              rowLastPoint,
              defaultEpsg,
              cachedState: cachedState,
            );

            xFirstCoord = rowFirstXY['x'] ?? 'N/A';
            yFirstCoord = rowFirstXY['y'] ?? 'N/A';
            xLastCoord = rowLastXY['x'] ?? 'N/A';
            yLastCoord = rowLastXY['y'] ?? 'N/A';

            AppLogger.debug(
              '[MetadataParser] 行${rowIndex + 1}: 最初XY=($xFirstCoord, $yFirstCoord), 最後XY=($xLastCoord, $yLastCoord)',
            );
          }
        } catch (e) {
          AppLogger.debug('[MetadataParser] 行${rowIndex + 1}: 個別GPS解析エラー: $e');
        }
      }

      // 平均座標は各行の緯度経度から計算
      if (latIndex != null &&
          lngIndex != null &&
          latIndex < originalRow.length &&
          lngIndex < originalRow.length) {
        try {
          final latStr = originalRow[latIndex];
          final lngStr = originalRow[lngIndex];
          final lat = double.parse(latStr);
          final lng = double.parse(lngStr);

          final rowPoint = LatLng(lat, lng);
          final rowXY = await _calculateXYCoordinates(
            rowPoint,
            defaultEpsg,
            cachedState: cachedState,
          );
          xAvgCoord = rowXY['x'] ?? 'N/A';
          yAvgCoord = rowXY['y'] ?? 'N/A';

          AppLogger.debug(
            '[MetadataParser] 行${rowIndex + 1}: 平均XY=($xAvgCoord, $yAvgCoord)',
          );
        } catch (e) {
          AppLogger.debug('[MetadataParser] 行${rowIndex + 1}: 平均座標計算エラー: $e');
        }
      }

      // 新しい行を構築
      for (int i = 0; i < originalRow.length; i++) {
        newRow.add(originalRow[i]);

        // 経度の次にXY座標を6つ追加
        if (i == lngIndex) {
          newRow.addAll([
            xFirstCoord,
            yFirstCoord,
            xLastCoord,
            yLastCoord,
            xAvgCoord,
            yAvgCoord,
          ]);
        }
      }

      newRows.add(newRow);
    }

    AppLogger.debug('[MetadataParser] 表形式でXY座標追加完了: 行数=${newRows.length}');

    return MetadataTableData(
      headers: newHeaders,
      rows: newRows,
      type: baseData.type,
      title: '${baseData.title} (${coordinateOptions[defaultEpsg]})',
      coordinateSystemOptions: coordinateOptions,
      selectedCoordinateSystem: defaultEpsg,
    );
  }

  /// 行データのXY座標をすべて更新
  static Future<List<List<String>>> _updateXYInRowsAll(
    List<List<String>> originalRows,
    List<String> headers,
    Map<String, String> allXYCoordinates,
    LatLng point,
    String epsgCode,
  ) async {
    final newRows = <List<String>>[];

    // 緯度・経度列のインデックスを探す
    int? latIndex, lngIndex;
    final xyIndices = <String, int>{};

    for (int i = 0; i < headers.length; i++) {
      if (headers[i] == '緯度') {
        latIndex = i;
      } else if (headers[i] == '経度') {
        lngIndex = i;
      } else if (headers[i] == 'X座標（最初）') {
        xyIndices['x_first'] = i;
      } else if (headers[i] == 'Y座標（最初）') {
        xyIndices['y_first'] = i;
      } else if (headers[i] == 'X座標（最後）') {
        xyIndices['x_last'] = i;
      } else if (headers[i] == 'Y座標（最後）') {
        xyIndices['y_last'] = i;
      } else if (headers[i] == 'X座標（平均）') {
        xyIndices['x_avg'] = i;
      } else if (headers[i] == 'Y座標（平均）') {
        xyIndices['y_avg'] = i;
      }
    }

    // 最初の行からstateを取得してキャッシュ
    String? cachedState;
    if (latIndex != null && lngIndex != null && originalRows.isNotEmpty) {
      try {
        final firstRow = originalRows[0];
        if (latIndex < firstRow.length && lngIndex < firstRow.length) {
          final lat = double.parse(firstRow[latIndex]);
          final lng = double.parse(firstRow[lngIndex]);
          final firstPoint = LatLng(lat, lng);

          AppLogger.debug('[MetadataParser] 更新時の最初の座標でstate取得: ($lat, $lng)');
          final address = await AddressConverter.getAddressFromLatLng(
            firstPoint,
          );
          if (address != null) {
            cachedState = CoordinateConverter.getStateFromAddress(address);
            AppLogger.debug('[MetadataParser] 更新時のキャッシュされたstate: $cachedState');
          }
        }
      } catch (e) {
        AppLogger.debug('[MetadataParser] 更新時のstate取得エラー: $e');
      }
    }

    for (int rowIndex = 0; rowIndex < originalRows.length; rowIndex++) {
      final row = originalRows[rowIndex];
      final newRow = <String>[];

      // 各行の緯度経度を取得してXY座標を計算
      Map<String, String> rowXYCoordinates = Map.from(allXYCoordinates);

      if (latIndex != null &&
          lngIndex != null &&
          latIndex < row.length &&
          lngIndex < row.length) {
        try {
          final latStr = row[latIndex];
          final lngStr = row[lngIndex];
          final lat = double.parse(latStr);
          final lng = double.parse(lngStr);

          // この行の座標でXY座標を計算（キャッシュされたstateを使用）
          final rowPoint = LatLng(lat, lng);
          final rowXY = await _calculateXYCoordinates(
            rowPoint,
            epsgCode,
            cachedState: cachedState,
          );

          // 表形式では平均座標として表示
          rowXYCoordinates['x_avg'] = rowXY['x'] ?? 'N/A';
          rowXYCoordinates['y_avg'] = rowXY['y'] ?? 'N/A';

          AppLogger.debug(
            '[MetadataParser] 行${rowIndex + 1}更新: 緯度=$lat, 経度=$lng -> 平均XY=${rowXYCoordinates['x_avg']}, ${rowXYCoordinates['y_avg']}',
          );
        } catch (e) {
          AppLogger.debug('[MetadataParser] 行${rowIndex + 1}更新エラー: $e');
        }
      }

      // 新しい行を構築
      for (int i = 0; i < headers.length; i++) {
        if (headers[i] == 'X座標（最初）') {
          newRow.add(rowXYCoordinates['x_first'] ?? 'N/A');
        } else if (headers[i] == 'Y座標（最初）') {
          newRow.add(rowXYCoordinates['y_first'] ?? 'N/A');
        } else if (headers[i] == 'X座標（最後）') {
          newRow.add(rowXYCoordinates['x_last'] ?? 'N/A');
        } else if (headers[i] == 'Y座標（最後）') {
          newRow.add(rowXYCoordinates['y_last'] ?? 'N/A');
        } else if (headers[i] == 'X座標（平均）') {
          newRow.add(rowXYCoordinates['x_avg'] ?? 'N/A');
        } else if (headers[i] == 'Y座標（平均）') {
          newRow.add(rowXYCoordinates['y_avg'] ?? 'N/A');
        } else {
          newRow.add(row[i]);
        }
      }

      newRows.add(newRow);
    }

    return newRows;
  }

  /// 元データからusedGpsDataを抽出
  static List<dynamic>? _extractUsedGpsDataFromOriginalMetadata(
    MetadataTableData baseData,
  ) {
    AppLogger.debug(
      '[MetadataParser] 元データ抽出開始: type=${baseData.type}, 行数=${baseData.rows.length}',
    );
    AppLogger.debug('[MetadataParser] ヘッダー: ${baseData.headers}');

    if (baseData.type == 'measurement_log') {
      // キー・値形式かどうか判定
      if (baseData.headers.length == 2 &&
          baseData.headers[0] == 'キー' &&
          baseData.headers[1] == '値') {
        // キー・値形式の場合
        for (int i = 0; i < baseData.rows.length; i++) {
          final row = baseData.rows[i];
          AppLogger.debug(
            '[MetadataParser] キー・値形式 行${i + 1}: 列数=${row.length}, キー="${row.isNotEmpty ? row[0] : "空"}"',
          );

          if (row.length >= 2 && row[0] == '元データ') {
            final usedGpsDataString = row[1];
            AppLogger.debug('[MetadataParser] 元データ発見! 文字列長=${usedGpsDataString.length}');
            AppLogger.debug(
              '[MetadataParser] 元データの最初の100文字: ${usedGpsDataString.length > 100 ? usedGpsDataString.substring(0, 100) : usedGpsDataString}...',
            );

            final result = _parseUsedGpsDataString(usedGpsDataString);
            AppLogger.debug(
              '[MetadataParser] パース結果: ${result != null ? "${result.length}件" : "null"}',
            );
            return result;
          }
        }
      } else {
        // 表形式の場合 - ヘッダーから「元データ」列のインデックスを探す
        int? dataColumnIndex;
        for (int i = 0; i < baseData.headers.length; i++) {
          if (baseData.headers[i] == '元データ') {
            dataColumnIndex = i;
            break;
          }
        }

        AppLogger.debug('[MetadataParser] 表形式: 元データ列インデックス=$dataColumnIndex');

        if (dataColumnIndex != null && baseData.rows.isNotEmpty) {
          // 最初の行から元データを取得（複数測量点の場合）
          final firstRow = baseData.rows[0];
          if (dataColumnIndex < firstRow.length) {
            final usedGpsDataString = firstRow[dataColumnIndex];
            AppLogger.debug(
              '[MetadataParser] 表形式元データ発見! 文字列長=${usedGpsDataString.length}',
            );
            AppLogger.debug(
              '[MetadataParser] 元データの最初の100文字: ${usedGpsDataString.length > 100 ? usedGpsDataString.substring(0, 100) : usedGpsDataString}...',
            );

            final result = _parseUsedGpsDataString(usedGpsDataString);
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

