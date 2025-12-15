// K-MAPS: WKBユーティリティ
// ジオメトリのWKBエンコード・デコード関数群
import 'dart:typed_data';
import 'package:k_maps/utils/app_logger.dart';
import 'package:latlong2/latlong.dart';

/// GeoPackage GPBinaryヘッダーを生成
Uint8List _createGpbHeader({
  required int wkbType,
  double? minX,
  double? maxX,
  double? minY,
  double? maxY,
}) {
  final header = BytesBuilder();

  // GPBHeader (GeoPackage仕様準拠)
  header.addByte(0x47); // G
  header.addByte(0x50); // P
  header.addByte(0x00); // Version (0)

  // Flags: エンディアン(1=little)、エンベロープタイプ、空(0)、バイナリタイプ(0=standard WKB)
  int flags = 0x01; // little endian
  if (minX != null && maxX != null && minY != null && maxY != null) {
    flags |= (1 << 1); // XY envelope present (envelope type = 1, bits 1-3)
  }
  header.addByte(flags);

  // SRS ID (4326 for WGS84)
  final srsBytes = ByteData(4)..setUint32(0, 4326, Endian.little);
  header.add(srsBytes.buffer.asUint8List());

  // エンベロープが指定されている場合は追加
  if (minX != null && maxX != null && minY != null && maxY != null) {
    final envelopeBytes = ByteData(32);
    envelopeBytes.setFloat64(0, minX, Endian.little);
    envelopeBytes.setFloat64(8, maxX, Endian.little);
    envelopeBytes.setFloat64(16, minY, Endian.little);
    envelopeBytes.setFloat64(24, maxY, Endian.little);
    header.add(envelopeBytes.buffer.asUint8List());
    AppLogger.debug(
      '[GPB] Envelope bytes added, total header size: ${header.length + 32}',
    );
  }

  return header.toBytes();
}

/// WKB(Point)生成ユーティリティ - GeoPackage対応
Uint8List createWkbPoint(double lon, double lat) {
  // 正常時のログは不要（異常時のみ出力）

  // GPBinaryヘッダー（エンベロープ付き）
  final gpbHeader = _createGpbHeader(
    wkbType: 1,
    minX: lon,
    maxX: lon,
    minY: lat,
    maxY: lat,
  );

  // 標準WKBデータ
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x01, 0x00, 0x00, 0x00]); // type=1 (POINT)
  final bdata = ByteData(16);
  bdata.setFloat64(0, lon, Endian.little); // X=lon
  bdata.setFloat64(8, lat, Endian.little); // Y=lat
  bytes.add(bdata.buffer.asUint8List());

  // GPBヘッダー + WKBデータを結合
  final result = BytesBuilder();
  result.add(gpbHeader);
  result.add(bytes.toBytes());
  return result.toBytes();
}

/// WKB(LineString)生成ユーティリティ - GeoPackage対応
Uint8List createWkbLineString(List<LatLng> line) {
  if (line.isEmpty) return Uint8List(0);

  // エンベロープ計算
  double minX = line.first.longitude;
  double maxX = line.first.longitude;
  double minY = line.first.latitude;
  double maxY = line.first.latitude;

  for (final pt in line) {
    minX = minX < pt.longitude ? minX : pt.longitude;
    maxX = maxX > pt.longitude ? maxX : pt.longitude;
    minY = minY < pt.latitude ? minY : pt.latitude;
    maxY = maxY > pt.latitude ? maxY : pt.latitude;
  }

  // GPBinaryヘッダー（エンベロープ付き）
  final gpbHeader = _createGpbHeader(
    wkbType: 2,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
  );

  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x02, 0x00, 0x00, 0x00]); // type=2 (LINESTRING)
  final n = line.length;
  final nBytes = ByteData(4)..setUint32(0, n, Endian.little);
  bytes.add(nBytes.buffer.asUint8List());
  for (final pt in line) {
    final bdata = ByteData(16);
    bdata.setFloat64(0, pt.longitude, Endian.little);
    bdata.setFloat64(8, pt.latitude, Endian.little);
    bytes.add(bdata.buffer.asUint8List());
  }

  // GPBヘッダー + WKBデータを結合
  final result = BytesBuilder();
  result.add(gpbHeader);
  result.add(bytes.toBytes());
  return result.toBytes();
}

/// WKB(Polygon)生成ユーティリティ - GeoPackage対応
Uint8List createWkbPolygon(List<List<LatLng>> rings) {
  if (rings.isEmpty || rings.first.isEmpty) return Uint8List(0);

  // エンベロープ計算（全てのリングの全ての点から）
  double minX = rings.first.first.longitude;
  double maxX = rings.first.first.longitude;
  double minY = rings.first.first.latitude;
  double maxY = rings.first.first.latitude;

  for (final ring in rings) {
    for (final pt in ring) {
      minX = minX < pt.longitude ? minX : pt.longitude;
      maxX = maxX > pt.longitude ? maxX : pt.longitude;
      minY = minY < pt.latitude ? minY : pt.latitude;
      maxY = maxY > pt.latitude ? maxY : pt.latitude;
    }
  }

  // GPBinaryヘッダー（エンベロープ付き）
  final gpbHeader = _createGpbHeader(
    wkbType: 3,
    minX: minX,
    maxX: maxX,
    minY: minY,
    maxY: maxY,
  );

  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x03, 0x00, 0x00, 0x00]); // type=3 (POLYGON)
  final nRings = rings.length;
  final nRingsBytes = ByteData(4)..setUint32(0, nRings, Endian.little);
  bytes.add(nRingsBytes.buffer.asUint8List());
  for (final ring in rings) {
    final nPts = ring.length;
    final nPtsBytes = ByteData(4)..setUint32(0, nPts, Endian.little);
    bytes.add(nPtsBytes.buffer.asUint8List());
    for (final pt in ring) {
      final bdata = ByteData(16);
      bdata.setFloat64(0, pt.longitude, Endian.little);
      bdata.setFloat64(8, pt.latitude, Endian.little);
      bytes.add(bdata.buffer.asUint8List());
    }
  }

  // GPBヘッダー + WKBデータを結合
  final result = BytesBuilder();
  result.add(gpbHeader);
  result.add(bytes.toBytes());
  return result.toBytes();
}

/// GPBinaryヘッダーをスキップしてWKBデータを取得
Uint8List _skipGpbHeader(Uint8List data) {
  // GPBinaryヘッダーの検証
  if (data.length > 8 && data[0] == 0x47 && data[1] == 0x50) {
    final flags = data[3];
    final envelopeType = (flags >> 1) & 0x07; // bits 1-3

    int headerSize = 8; // 基本サイズ（GP + Version + Flags + SRS ID）

    // エンベロープサイズを計算
    switch (envelopeType) {
      case 1: // XY
        headerSize += 32; // 4 doubles
        break;
      case 2: // XYZ
        headerSize += 48; // 6 doubles
        break;
      case 3: // XYM
        headerSize += 48; // 6 doubles
        break;
      case 4: // XYZM
        headerSize += 64; // 8 doubles
        break;
    }

    if (data.length > headerSize) {
      return data.sublist(headerSize);
    }
  }
  return data; // 既に純粋なWKBの場合
}

/// 座標値の妥当性をチェック
/// 緯度: -90 ~ 90, 経度: -180 ~ 180
bool _isValidCoordinate(double lat, double lon) {
  return lat >= -90.0 && lat <= 90.0 && 
         lon >= -180.0 && lon <= 180.0 &&
         !lat.isNaN && !lon.isNaN &&
         !lat.isInfinite && !lon.isInfinite;
}

/// WKB(Point)デコードユーティリティ - GeoPackage対応
LatLng? parseWkbPoint(Uint8List wkb) {
  try {
    final pureWkb = _skipGpbHeader(wkb);
    if (pureWkb.length < 21) {
      AppLogger.debug('[WKB] Point: データサイズ不足');
      return null;
    }
    
    // WKB Point構造: [1byte endian][4bytes type][8bytes X][8bytes Y]
    if (pureWkb[0] != 1 || pureWkb[1] != 1) {
      AppLogger.debug('[WKB] Point: 不正なWKBヘッダー');
      return null;
    }
    
    final lon = ByteData.sublistView(pureWkb, 5, 13).getFloat64(0, Endian.little);
    final lat = ByteData.sublistView(pureWkb, 13, 21).getFloat64(0, Endian.little);
    
    if (!_isValidCoordinate(lat, lon)) {
      AppLogger.debug('[WKB] Point: 無効な座標値: lat=$lat, lon=$lon');
      return null;
    }
    
    return LatLng(lat, lon);
  } catch (e) {
    AppLogger.debug('[WKB] Point解析エラー: $e');
    return null;
  }
}

/// WKB(LineString)デコードユーティリティ - GeoPackage対応
List<LatLng> parseWkbLineString(Uint8List wkb) {
  try {
    final pureWkb = _skipGpbHeader(wkb);
    if (pureWkb.length < 9) {
      AppLogger.debug('[WKB] LineString: データサイズ不足');
      return [];
    }
    
    final n = ByteData.sublistView(pureWkb, 5, 9).getUint32(0, Endian.little);
    
    // ポイント数の妥当性チェック（異常に大きい値を検出）
    if (n > 1000000) {
      AppLogger.debug('[WKB] ⚠️ 警告: LineStringのポイント数が異常です: $n');
      return [];
    }
    
    final pts = <LatLng>[];
    for (int i = 0; i < n; i++) {
      final offset = 9 + i * 16;
      if (offset + 16 > pureWkb.length) break;
      
      final lon = ByteData.sublistView(
        pureWkb,
        offset,
        offset + 8,
      ).getFloat64(0, Endian.little);
      final lat = ByteData.sublistView(
        pureWkb,
        offset + 8,
        offset + 16,
      ).getFloat64(0, Endian.little);
      
      // 座標値の妥当性チェック
      if (!_isValidCoordinate(lat, lon)) {
        AppLogger.debug('[WKB] ⚠️ 警告: 無効な座標値を検出しました（ポイント${i + 1}/$n）: lat=$lat, lon=$lon');
        AppLogger.debug('[WKB] ⚠️ このフィーチャは破損している可能性があります。スキップします。');
        return []; // 無効な座標が含まれる場合は全体を無効とする
      }
      
      pts.add(LatLng(lat, lon));
    }
    return pts;
  } catch (e) {
    AppLogger.debug('[WKB] LineString解析エラー: $e');
    return [];
  }
}

/// WKB(Polygon)デコードユーティリティ - GeoPackage対応
List<List<LatLng>> parseWkbPolygon(Uint8List wkb) {
  try {
    final pureWkb = _skipGpbHeader(wkb);
    if (pureWkb.length < 9) {
      AppLogger.debug('[WKB] Polygon: データサイズ不足');
      return [];
    }
    
    final nRings = ByteData.sublistView(
      pureWkb,
      5,
      9,
    ).getUint32(0, Endian.little);
    
    // リング数の妥当性チェック（異常に大きい値を検出）
    if (nRings > 10000) {
      AppLogger.debug('[WKB] ⚠️ 警告: Polygonのリング数が異常です: $nRings');
      return [];
    }
    
    int offset = 9;
    final rings = <List<LatLng>>[];
    for (int r = 0; r < nRings; r++) {
      if (offset + 4 > pureWkb.length) break;
      
      final nPts = ByteData.sublistView(
        pureWkb,
        offset,
        offset + 4,
      ).getUint32(0, Endian.little);
      
      // ポイント数の妥当性チェック
      if (nPts > 1000000) {
        AppLogger.debug('[WKB] ⚠️ 警告: リング${r + 1}のポイント数が異常です: $nPts');
        return [];
      }
      
      offset += 4;
      final ring = <LatLng>[];
      bool hasInvalidCoordinate = false;
      
      for (int i = 0; i < nPts; i++) {
        if (offset + 16 > pureWkb.length) break;
        
        final lon = ByteData.sublistView(
          pureWkb,
          offset,
          offset + 8,
        ).getFloat64(0, Endian.little);
        final lat = ByteData.sublistView(
          pureWkb,
          offset + 8,
          offset + 16,
        ).getFloat64(0, Endian.little);
        
        // 座標値の妥当性チェック
        if (!_isValidCoordinate(lat, lon)) {
          AppLogger.debug('[WKB] ⚠️ 警告: 無効な座標値を検出しました（リング${r + 1}, ポイント${i + 1}/$nPts）: lat=$lat, lon=$lon');
          hasInvalidCoordinate = true;
          break; // このリングは無効
        }
        
        ring.add(LatLng(lat, lon));
        offset += 16;
      }
      
      // 無効な座標が含まれる場合、このポリゴン全体をスキップ
      if (hasInvalidCoordinate) {
        AppLogger.debug('[WKB] ⚠️ このPolygonフィーチャは破損している可能性があります。スキップします。');
        return [];
      }
      
      rings.add(ring);
    }
    return rings;
  } catch (e) {
    AppLogger.debug('[WKB] Polygon解析エラー: $e');
    return [];
  }
}

/// WKBデータの妥当性を検証
bool validateWkbData(Uint8List wkb) {
  try {
    // 最小サイズチェック
    if (wkb.length < 8) {
      AppLogger.debug('[WKB検証] データサイズ不足: ${wkb.length}バイト');
      return false;
    }

    // GPBinaryヘッダーチェック
    if (wkb[0] == 0x47 && wkb[1] == 0x50) {
      // GPBinaryヘッダー検出済み（正常）
      if (wkb.length < 29) {
        // GPB(8) + WKB最小(21)
        AppLogger.debug('[WKB検証] GPBinary + WKBデータサイズ不足');
        return false;
      }

      // 正常時のSRS IDチェックログは不要
      return true;
    } else {
      // 純粋WKBデータ（正常）
      return wkb.length >= 21; // WKB最小サイズ
    }
  } catch (e) {
    AppLogger.debug('[WKB検証] エラー: $e');
    return false;
  }
}

/// WKBデータの詳細情報を出力（デバッグ用）
void debugWkbData(Uint8List wkb, String context) {
  AppLogger.debug('=== WKBデバッグ情報 [$context] ===');
  AppLogger.debug('データサイズ: ${wkb.length}バイト');
  AppLogger.debug(
    '先頭16バイト: ${wkb.take(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}',
  );

  if (wkb.length >= 8 && wkb[0] == 0x47 && wkb[1] == 0x50) {
    final srsId = ByteData.sublistView(wkb, 4, 8).getUint32(0, Endian.little);
    AppLogger.debug('GPBinaryヘッダー: あり（SRS ID: $srsId）');

    if (wkb.length > 8) {
      final wkbPart = wkb.sublist(8);
      if (wkbPart.length >= 5) {
        final geomType = ByteData.sublistView(
          wkbPart,
          1,
          5,
        ).getUint32(0, Endian.little);
        AppLogger.debug('ジオメトリタイプ: $geomType');
      }
    }
  } else {
    AppLogger.debug('GPBinaryヘッダー: なし');
    if (wkb.length >= 5) {
      final geomType = ByteData.sublistView(
        wkb,
        1,
        5,
      ).getUint32(0, Endian.little);
      AppLogger.debug('ジオメトリタイプ: $geomType');
    }
  }
  AppLogger.debug('妥当性: ${validateWkbData(wkb) ? "OK" : "NG"}');
  AppLogger.debug('==============================');
}

