// K-MAPS: メタデータパーサーユーティリティ
// kmaps_metadataカラムの内容をパースして表形式データに変換

import 'dart:convert';
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

      print(
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

      print(
        '[MetadataParser] XY座標計算結果: X=${xyCoordinates['x']}, Y=${xyCoordinates['y']}',
      );

      // データ形式に応じてXY座標を追加
      if (baseData.headers.length == 2 &&
          baseData.headers[0] == 'キー' &&
          baseData.headers[1] == '値') {
        // キー・値形式の場合
        return _addXYCoordinatesToKeyValueFormat(
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
      print('[MetadataParser] XY座標追加エラー: $e');
      return parseMetadata(metadata);
    }
  }

  /// 座標系選択肢を生成
  static Future<Map<String, String>> _generateCoordinateSystemOptions(
    LatLng point,
  ) async {
    final options = <String, String>{};

    print(
      '[MetadataParser] 座標系選択肢生成開始: (${point.latitude}, ${point.longitude})',
    );

    // UTM座標系（デフォルト）- 動的に生成
    final zoneNumber = CoordinateConverter.calculateUTMZone(point.longitude);
    final utmEpsg = 'EPSG:326${zoneNumber.toString().padLeft(2, '0')}';
    final utmName = 'UTM Zone ${zoneNumber}N';
    options[utmEpsg] = utmName;

    print('[MetadataParser] UTM座標系選択肢追加: $utmName ($utmEpsg)');

    // 住所を取得して日本かどうか判定
    try {
      print('[MetadataParser] 住所取得開始...');
      final address = await AddressConverter.getAddressFromLatLng(point);
      print('[MetadataParser] 住所取得結果: ${address?.displayName ?? "null"}');

      if (address != null) {
        final isJapan = _isJapanAddress(address);
        print('[MetadataParser] 日本住所判定: $isJapan');

        if (isJapan) {
          print('[MetadataParser] JGD2011座標系取得開始...');
          // 日本平面直角座標系の選択肢を追加
          final jgd2011System =
              await CoordinateConverter.getBestCoordinateSystem(point);
          print(
            '[MetadataParser] JGD2011座標系取得結果: ${jgd2011System?.name} (${jgd2011System?.epsgCode})',
          );

          if (jgd2011System != null && jgd2011System.epsgCode != utmEpsg) {
            options[jgd2011System.epsgCode] = jgd2011System.name;
            print(
              '[MetadataParser] JGD2011座標系選択肢追加: ${jgd2011System.name} (${jgd2011System.epsgCode})',
            );
          } else {
            print(
              '[MetadataParser] JGD2011座標系が追加されませんでした - システム: ${jgd2011System?.epsgCode}, UTM: $utmEpsg',
            );
          }
        }
      } else {
        print('[MetadataParser] 住所がnullのため、JGD2011座標系をスキップ');
      }
    } catch (e) {
      print('[MetadataParser] 住所取得エラー: $e');
    }

    print('[MetadataParser] 最終的な座標系選択肢: $options');
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
    print('[MetadataParser] XY座標計算開始: EPSG=$epsgCode');

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

        print(
          '[MetadataParser] UTM座標系使用: ${coordinateSystem.name} (${coordinateSystem.epsgCode})',
        );
      } else if (epsgCode.startsWith('667')) {
        // JGD2011座標系 - 指定されたEPSGコードから直接座標系を作成
        print('[MetadataParser] JGD2011座標系処理開始: $epsgCode');
        coordinateSystem = await _getJGD2011CoordinateSystem(
          epsgCode,
          point,
          cachedState: cachedState,
        );
        print(
          '[MetadataParser] JGD2011座標系取得結果: ${coordinateSystem?.name} (${coordinateSystem?.epsgCode})',
        );

        if (coordinateSystem == null) {
          print('[MetadataParser] JGD2011座標系がnullです - EPSGコードから直接作成を試行');
          coordinateSystem = _createJGD2011CoordinateSystemFromEpsg(epsgCode);
          print('[MetadataParser] EPSGコードから作成結果: ${coordinateSystem?.name}');
        }
      } else {
        // その他の座標系 - 自動判定
        print('[MetadataParser] その他の座標系 - 自動判定開始');
        coordinateSystem = await CoordinateConverter.getBestCoordinateSystem(
          point,
          cachedState: cachedState,
        );
        print(
          '[MetadataParser] 自動判定座標系使用: ${coordinateSystem?.name} (${coordinateSystem?.epsgCode})',
        );
      }

      if (coordinateSystem != null) {
        print('[MetadataParser] 座標変換開始: ${coordinateSystem.epsgCode}');
        final xy = CoordinateConverter.latLngToXY(
          point,
          coordinateSystem: coordinateSystem,
        );

        print(
          '[MetadataParser] XY座標計算成功: X=${xy.x.toStringAsFixed(3)}, Y=${xy.y.toStringAsFixed(3)}',
        );
        return {'x': xy.x.toStringAsFixed(3), 'y': xy.y.toStringAsFixed(3)};
      } else {
        print('[MetadataParser] 座標系がnullです');
      }
    } catch (e) {
      print('[MetadataParser] XY座標計算エラー: $e');
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
      print('[MetadataParser] キャッシュされたstate使用: $cachedState');
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
    print('[MetadataParser] XY座標再計算開始');
    print('[MetadataParser] 元のEPSG: ${originalData.selectedCoordinateSystem}');
    print('[MetadataParser] 新しいEPSG: $newEpsgCode');
    print('[MetadataParser] 座標: (${point.latitude}, ${point.longitude})');

    // 新しい座標系でXY座標を計算
    final newXY = await _calculateXYCoordinates(point, newEpsgCode);
    print('[MetadataParser] 新しいXY座標: X=${newXY['x']}, Y=${newXY['y']}');

    // 新しい座標系名を取得
    final newCoordinateSystemName =
        originalData.coordinateSystemOptions?[newEpsgCode] ?? 'Unknown';
    print('[MetadataParser] 新しい座標系名: $newCoordinateSystemName');

    // データ形式に応じてXY座標を更新
    List<List<String>> updatedRows;
    if (originalData.headers.length == 2 &&
        originalData.headers[0] == 'キー' &&
        originalData.headers[1] == '値') {
      // キー・値形式の場合
      updatedRows = _updateXYInKeyValueRows(
        originalData.rows,
        newXY['x']!,
        newXY['y']!,
      );
      print('[MetadataParser] キー・値形式でXY座標更新完了');
    } else {
      // 通常の表形式の場合
      updatedRows = await _updateXYInRows(
        originalData.rows,
        originalData.headers,
        newXY['x']!,
        newXY['y']!,
        point,
        newEpsgCode,
      );
      print('[MetadataParser] 表形式でXY座標更新完了');
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

    print('[MetadataParser] XY座標再計算完了');
    return updatedData;
  }

  /// キー・値形式の行データのXY座標を更新
  static List<List<String>> _updateXYInKeyValueRows(
    List<List<String>> originalRows,
    String newX,
    String newY,
  ) {
    final newRows = <List<String>>[];

    for (final row in originalRows) {
      if (row.length >= 2) {
        if (row[0] == 'X座標') {
          // X座標行を更新
          newRows.add([row[0], newX]);
        } else if (row[0] == 'Y座標') {
          // Y座標行を更新
          newRows.add([row[0], newY]);
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

  /// 行データのXY座標を更新
  static Future<List<List<String>>> _updateXYInRows(
    List<List<String>> originalRows,
    List<String> headers,
    String newX,
    String newY,
    LatLng point,
    String epsgCode,
  ) async {
    final newRows = <List<String>>[];

    // 緯度・経度列のインデックスを探す
    int? latIndex, lngIndex, xIndex, yIndex;
    for (int i = 0; i < headers.length; i++) {
      if (headers[i] == '緯度') {
        latIndex = i;
      } else if (headers[i] == '経度') {
        lngIndex = i;
      } else if (headers[i] == 'X座標') {
        xIndex = i;
      } else if (headers[i] == 'Y座標') {
        yIndex = i;
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

          print('[MetadataParser] 更新時の最初の座標でstate取得: ($lat, $lng)');
          final address = await AddressConverter.getAddressFromLatLng(
            firstPoint,
          );
          if (address != null) {
            cachedState = CoordinateConverter.getStateFromAddress(address);
            print('[MetadataParser] 更新時のキャッシュされたstate: $cachedState');
          }
        }
      } catch (e) {
        print('[MetadataParser] 更新時のstate取得エラー: $e');
      }
    }

    for (int rowIndex = 0; rowIndex < originalRows.length; rowIndex++) {
      final row = originalRows[rowIndex];
      final newRow = <String>[];

      // 各行の緯度経度を取得してXY座標を計算
      String xCoord = newX; // デフォルト値
      String yCoord = newY; // デフォルト値

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
          xCoord = rowXY['x'] ?? 'N/A';
          yCoord = rowXY['y'] ?? 'N/A';

          print(
            '[MetadataParser] 行${rowIndex + 1}更新: 緯度=$lat, 経度=$lng -> X=$xCoord, Y=$yCoord',
          );
        } catch (e) {
          print('[MetadataParser] 行${rowIndex + 1}更新エラー: $e');
        }
      }

      // 新しい行を構築
      for (int i = 0; i < headers.length; i++) {
        if (headers[i] == 'X座標') {
          newRow.add(xCoord);
        } else if (headers[i] == 'Y座標') {
          newRow.add(yCoord);
        } else {
          newRow.add(row[i]);
        }
      }

      newRows.add(newRow);
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

  /// キー・値形式のデータにXY座標を追加
  static MetadataTableData _addXYCoordinatesToKeyValueFormat(
    MetadataTableData baseData,
    Map<String, String> xyCoordinates,
    Map<String, String> coordinateOptions,
    String defaultEpsg,
  ) {
    print('[MetadataParser] キー・値形式でXY座標追加開始');

    final newRows = <List<String>>[];

    // 既存の行をコピー
    newRows.addAll(baseData.rows);

    // 緯度行の後にX座標を追加
    int latitudeIndex = -1;
    for (int i = 0; i < baseData.rows.length; i++) {
      if (baseData.rows[i][0] == '緯度') {
        latitudeIndex = i;
        break;
      }
    }

    if (latitudeIndex >= 0) {
      // 緯度の次にX座標を挿入
      newRows.insert(latitudeIndex + 1, ['X座標', xyCoordinates['x'] ?? 'N/A']);
      print('[MetadataParser] X座標を緯度の後に追加: ${xyCoordinates['x']}');
    } else {
      // 緯度が見つからない場合は最後に追加
      newRows.add(['X座標', xyCoordinates['x'] ?? 'N/A']);
      print('[MetadataParser] X座標を最後に追加: ${xyCoordinates['x']}');
    }

    // 経度行の後にY座標を追加
    int longitudeIndex = -1;
    for (int i = 0; i < newRows.length; i++) {
      if (newRows[i][0] == '経度') {
        longitudeIndex = i;
        break;
      }
    }

    if (longitudeIndex >= 0) {
      // 経度の次にY座標を挿入
      newRows.insert(longitudeIndex + 1, ['Y座標', xyCoordinates['y'] ?? 'N/A']);
      print('[MetadataParser] Y座標を経度の後に追加: ${xyCoordinates['y']}');
    } else {
      // 経度が見つからない場合は最後に追加
      newRows.add(['Y座標', xyCoordinates['y'] ?? 'N/A']);
      print('[MetadataParser] Y座標を最後に追加: ${xyCoordinates['y']}');
    }

    print('[MetadataParser] キー・値形式でXY座標追加完了: 行数=${newRows.length}');

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
    print('[MetadataParser] 表形式でXY座標追加開始');

    // 緯度・経度列のインデックスを探す
    int? latIndex, lngIndex;
    for (int i = 0; i < baseData.headers.length; i++) {
      if (baseData.headers[i] == '緯度') {
        latIndex = i;
      } else if (baseData.headers[i] == '経度') {
        lngIndex = i;
      }
    }

    // 新しいヘッダーと行を作成（緯度経度の次にXY座標を挿入）
    final newHeaders = <String>[];
    final newRows = <List<String>>[];

    for (int i = 0; i < baseData.headers.length; i++) {
      newHeaders.add(baseData.headers[i]);

      // 緯度の次にX座標、経度の次にY座標を追加
      if (baseData.headers[i] == '緯度') {
        newHeaders.add('X座標');
      } else if (baseData.headers[i] == '経度') {
        newHeaders.add('Y座標');
      }
    }

    print('[MetadataParser] 新しいヘッダー: $newHeaders');

    // 最初の行からstateを取得してキャッシュ
    String? cachedState;
    if (latIndex != null && lngIndex != null && baseData.rows.isNotEmpty) {
      try {
        final firstRow = baseData.rows[0];
        if (latIndex < firstRow.length && lngIndex < firstRow.length) {
          final lat = double.parse(firstRow[latIndex]);
          final lng = double.parse(firstRow[lngIndex]);
          final firstPoint = LatLng(lat, lng);

          print('[MetadataParser] 最初の座標でstate取得: ($lat, $lng)');
          final address = await AddressConverter.getAddressFromLatLng(
            firstPoint,
          );
          if (address != null) {
            cachedState = CoordinateConverter.getStateFromAddress(address);
            print('[MetadataParser] キャッシュされたstate: $cachedState');
          }
        }
      } catch (e) {
        print('[MetadataParser] state取得エラー: $e');
      }
    }

    // 各行を処理
    for (int rowIndex = 0; rowIndex < baseData.rows.length; rowIndex++) {
      final originalRow = baseData.rows[rowIndex];
      final newRow = <String>[];

      // 各行の緯度経度を取得してXY座標を計算
      String xCoord = 'N/A';
      String yCoord = 'N/A';

      if (latIndex != null &&
          lngIndex != null &&
          latIndex < originalRow.length &&
          lngIndex < originalRow.length) {
        try {
          final latStr = originalRow[latIndex];
          final lngStr = originalRow[lngIndex];
          final lat = double.parse(latStr);
          final lng = double.parse(lngStr);

          print('[MetadataParser] 行${rowIndex + 1}: 緯度=$lat, 経度=$lng');

          // この行の座標でXY座標を計算（キャッシュされたstateを使用）
          final rowPoint = LatLng(lat, lng);
          final rowXY = await _calculateXYCoordinates(
            rowPoint,
            defaultEpsg,
            cachedState: cachedState,
          );
          xCoord = rowXY['x'] ?? 'N/A';
          yCoord = rowXY['y'] ?? 'N/A';

          print('[MetadataParser] 行${rowIndex + 1}: X=$xCoord, Y=$yCoord');
        } catch (e) {
          print('[MetadataParser] 行${rowIndex + 1}: 座標解析エラー: $e');
        }
      }

      // 新しい行を構築
      for (int i = 0; i < originalRow.length; i++) {
        newRow.add(originalRow[i]);

        // 緯度の次にX座標、経度の次にY座標を追加
        if (i == latIndex) {
          newRow.add(xCoord);
        } else if (i == lngIndex) {
          newRow.add(yCoord);
        }
      }

      newRows.add(newRow);
    }

    print('[MetadataParser] 表形式でXY座標追加完了: 行数=${newRows.length}');

    return MetadataTableData(
      headers: newHeaders,
      rows: newRows,
      type: baseData.type,
      title: '${baseData.title} (${coordinateOptions[defaultEpsg]})',
      coordinateSystemOptions: coordinateOptions,
      selectedCoordinateSystem: defaultEpsg,
    );
  }
}
