// K-MAPS: WKBユーティリティ
// ジオメトリのWKBエンコード・デコード関数群
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';

/// WKB(Point)生成ユーティリティ
Uint8List createWkbPoint(double lon, double lat) {
  // リトルエンディアン: 0x01
  // ジオメトリタイプ: 1 (POINT)
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x01, 0x00, 0x00, 0x00]); // type=1 (POINT)
  final bdata = ByteData(16);
  bdata.setFloat64(0, lon, Endian.little); // X=lon
  bdata.setFloat64(8, lat, Endian.little); // Y=lat
  bytes.add(bdata.buffer.asUint8List());
  return bytes.toBytes();
}

/// WKB(LineString)生成ユーティリティ
Uint8List createWkbLineString(List<LatLng> line) {
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
  return bytes.toBytes();
}

/// WKB(Polygon)生成ユーティリティ
Uint8List createWkbPolygon(List<List<LatLng>> rings) {
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
  return bytes.toBytes();
}

/// WKB(LineString)デコードユーティリティ
List<LatLng> parseWkbLineString(Uint8List wkb) {
  if (wkb.length < 9) return [];
  final n = ByteData.sublistView(wkb, 5, 9).getUint32(0, Endian.little);
  final pts = <LatLng>[];
  for (int i = 0; i < n; i++) {
    final offset = 9 + i * 16;
    if (offset + 16 > wkb.length) break;
    final lon = ByteData.sublistView(
      wkb,
      offset,
      offset + 8,
    ).getFloat64(0, Endian.little);
    final lat = ByteData.sublistView(
      wkb,
      offset + 8,
      offset + 16,
    ).getFloat64(0, Endian.little);
    pts.add(LatLng(lat, lon));
  }
  return pts;
}

/// WKB(Polygon)デコードユーティリティ
List<List<LatLng>> parseWkbPolygon(Uint8List wkb) {
  if (wkb.length < 9) return [];
  final nRings = ByteData.sublistView(wkb, 5, 9).getUint32(0, Endian.little);
  int offset = 9;
  final rings = <List<LatLng>>[];
  for (int r = 0; r < nRings; r++) {
    if (offset + 4 > wkb.length) break;
    final nPts = ByteData.sublistView(
      wkb,
      offset,
      offset + 4,
    ).getUint32(0, Endian.little);
    offset += 4;
    final ring = <LatLng>[];
    for (int i = 0; i < nPts; i++) {
      if (offset + 16 > wkb.length) break;
      final lon = ByteData.sublistView(
        wkb,
        offset,
        offset + 8,
      ).getFloat64(0, Endian.little);
      final lat = ByteData.sublistView(
        wkb,
        offset + 8,
        offset + 16,
      ).getFloat64(0, Endian.little);
      ring.add(LatLng(lat, lon));
      offset += 16;
    }
    rings.add(ring);
  }
  return rings;
}

/// WKB(MultiLineString)生成ユーティリティ
Uint8List createWkbMultiLineString(List<List<LatLng>> lines) {
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x05, 0x00, 0x00, 0x00]); // type=5 (MULTILINESTRING)
  final n = lines.length;
  final nBytes = ByteData(4)..setUint32(0, n, Endian.little);
  bytes.add(nBytes.buffer.asUint8List());
  for (final line in lines) {
    // 各LineStringをWKBで追加
    final lineWkb = createWkbLineString(line);
    bytes.add(lineWkb);
  }
  return bytes.toBytes();
}

/// WKB(MultiPolygon)生成ユーティリティ
Uint8List createWkbMultiPolygon(List<List<List<LatLng>>> polygons) {
  final bytes = BytesBuilder();
  bytes.addByte(0x01); // little endian
  bytes.add([0x06, 0x00, 0x00, 0x00]); // type=6 (MULTIPOLYGON)
  final n = polygons.length;
  final nBytes = ByteData(4)..setUint32(0, n, Endian.little);
  bytes.add(nBytes.buffer.asUint8List());
  for (final poly in polygons) {
    // 各PolygonをWKBで追加
    final polyWkb = createWkbPolygon(poly);
    bytes.add(polyWkb);
  }
  return bytes.toBytes();
}

/// WKB(MultiLineString)デコードユーティリティ
List<List<LatLng>> parseWkbMultiLineString(Uint8List wkb) {
  if (wkb.length < 9) return [];
  final n = ByteData.sublistView(wkb, 5, 9).getUint32(0, Endian.little);
  int offset = 9;
  final lines = <List<LatLng>>[];
  for (int i = 0; i < n; i++) {
    // 各LineStringのWKBをパース
    if (offset + 5 > wkb.length) break;
    final type = ByteData.sublistView(
      wkb,
      offset + 1,
      offset + 5,
    ).getUint32(0, Endian.little);
    if (type != 2) break; // LINESTRING
    final nPts = ByteData.sublistView(
      wkb,
      offset + 5,
      offset + 9,
    ).getUint32(0, Endian.little);
    final line = <LatLng>[];
    for (int j = 0; j < nPts; j++) {
      final ptOffset = offset + 9 + j * 16;
      if (ptOffset + 16 > wkb.length) break;
      final lon = ByteData.sublistView(
        wkb,
        ptOffset,
        ptOffset + 8,
      ).getFloat64(0, Endian.little);
      final lat = ByteData.sublistView(
        wkb,
        ptOffset + 8,
        ptOffset + 16,
      ).getFloat64(0, Endian.little);
      line.add(LatLng(lat, lon));
    }
    lines.add(line);
    offset += 9 + nPts * 16;
  }
  return lines;
}

/// WKB(MultiPolygon)デコードユーティリティ
List<List<List<LatLng>>> parseWkbMultiPolygon(Uint8List wkb) {
  if (wkb.length < 9) return [];
  final n = ByteData.sublistView(wkb, 5, 9).getUint32(0, Endian.little);
  int offset = 9;
  final polygons = <List<List<LatLng>>>[];
  for (int i = 0; i < n; i++) {
    // 各PolygonのWKBをパース
    if (offset + 5 > wkb.length) break;
    final type = ByteData.sublistView(
      wkb,
      offset + 1,
      offset + 5,
    ).getUint32(0, Endian.little);
    if (type != 3) break; // POLYGON
    final nRings = ByteData.sublistView(
      wkb,
      offset + 5,
      offset + 9,
    ).getUint32(0, Endian.little);
    int ringOffset = offset + 9;
    final rings = <List<LatLng>>[];
    for (int r = 0; r < nRings; r++) {
      if (ringOffset + 4 > wkb.length) break;
      final nPts = ByteData.sublistView(
        wkb,
        ringOffset,
        ringOffset + 4,
      ).getUint32(0, Endian.little);
      ringOffset += 4;
      final ring = <LatLng>[];
      for (int j = 0; j < nPts; j++) {
        if (ringOffset + 16 > wkb.length) break;
        final lon = ByteData.sublistView(
          wkb,
          ringOffset,
          ringOffset + 8,
        ).getFloat64(0, Endian.little);
        final lat = ByteData.sublistView(
          wkb,
          ringOffset + 8,
          ringOffset + 16,
        ).getFloat64(0, Endian.little);
        ring.add(LatLng(lat, lon));
        ringOffset += 16;
      }
      rings.add(ring);
    }
    polygons.add(rings);
    offset = ringOffset;
  }
  return polygons;
}
