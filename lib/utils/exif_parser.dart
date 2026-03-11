// K-MAPS: EXIF解析ユーティリティ
// 画像ファイルからGPS座標やメタデータを抽出する共通処理
// ImageNodeとGlobalImageNodeで使用

import 'dart:io';
import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import 'app_logger.dart';

/// 画像のEXIFデータから抽出した情報
class ExifImageData {
  final LatLng location;
  final DateTime? takenAt;
  final ImageMetadata metadata;

  /// 撮影方向（真北基準、0-360度）。EXIFのGPSImgDirectionから取得
  final double? direction;

  ExifImageData({required this.location, this.takenAt, required this.metadata, this.direction});
}

/// 画像ファイルのメタデータ
class ImageMetadata {
  final int fileSize;
  final int? width;
  final int? height;
  final String? camera;

  ImageMetadata({required this.fileSize, this.width, this.height, this.camera});
}

/// EXIF解析ユーティリティクラス
/// 
/// JPEG画像からGPS座標やメタデータを抽出する静的メソッドを提供
/// 高速化のため、ファイル先頭部分（256KB）のみを読み込む
class ExifParser {
  ExifParser._();
  
  /// 画像ファイルからEXIFデータを抽出
  /// GPS座標が含まれていない場合はnullを返す
  static Future<ExifImageData?> extractFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      
      final stats = await file.stat();
      
      // EXIF情報はファイルの先頭部分にあるため、最大256KBまで読み込む
      // 大量の画像がある場合、これにより読み込み速度が大幅に向上
      final bytes = await _readFileHeader(filePath, 256 * 1024);
      final exifResult = _parseBasicExif(bytes);
      if (exifResult == null) return null;

      final metadata = ImageMetadata(
        fileSize: stats.size,
        width: exifResult['width'] as int?,
        height: exifResult['height'] as int?,
        camera: exifResult['camera'] as String?,
      );

      return ExifImageData(
        location: LatLng(
          exifResult['lat'] as double,
          exifResult['lng'] as double,
        ),
        takenAt: exifResult['datetime'] as DateTime?,
        metadata: metadata,
        direction: exifResult['direction'] as double?,
      );
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser.extractFromFile: $e');
      return null;
    }
  }

  /// ファイルの先頭部分のみを読み込む（EXIF解析用）
  static Future<Uint8List> _readFileHeader(String filePath, int maxBytes) async {
    final file = File(filePath);
    final fileSize = await file.length();
    final bytesToRead = fileSize < maxBytes ? fileSize : maxBytes;
    
    final randomAccessFile = await file.open(mode: FileMode.read);
    try {
      final bytes = await randomAccessFile.read(bytesToRead);
      return Uint8List.fromList(bytes);
    } finally {
      await randomAccessFile.close();
    }
  }

  /// 基本的なEXIF解析（JPEG対応）
  static Map<String, dynamic>? _parseBasicExif(Uint8List bytes) {
    try {
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        return null;
      }

      int offset = 2;
      while (offset < bytes.length - 1) {
        if (bytes[offset] != 0xFF) break;

        final marker = bytes[offset + 1];
        offset += 2;

        if (marker == 0xE1) {
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          offset += 2;

          if (offset + 6 < bytes.length &&
              bytes[offset] == 0x45 &&
              bytes[offset + 1] == 0x78 &&
              bytes[offset + 2] == 0x69 &&
              bytes[offset + 3] == 0x66 &&
              bytes[offset + 4] == 0x00 &&
              bytes[offset + 5] == 0x00) {
            final tiffStart = offset + 6;
            return _parseTiffExif(bytes, tiffStart, segmentLength - 6);
          }
        } else if (marker == 0xDA) {
          break;
        } else {
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          offset += segmentLength;
        }
      }

      return null;
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser._parseBasicExif: $e');
      return null;
    }
  }

  /// TIFFフォーマットのEXIFデータを解析
  static Map<String, dynamic>? _parseTiffExif(
    Uint8List bytes,
    int start,
    int length,
  ) {
    try {
      if (start + 8 > bytes.length) return null;

      final isLittleEndian = bytes[start] == 0x49 && bytes[start + 1] == 0x49;
      if (!isLittleEndian &&
          !(bytes[start] == 0x4D && bytes[start + 1] == 0x4D)) {
        return null;
      }

      final tiffId =
          isLittleEndian
              ? bytes[start + 2] | (bytes[start + 3] << 8)
              : (bytes[start + 2] << 8) | bytes[start + 3];
      if (tiffId != 42) {
        return null;
      }

      final ifdOffset =
          isLittleEndian
              ? bytes[start + 4] |
                  (bytes[start + 5] << 8) |
                  (bytes[start + 6] << 16) |
                  (bytes[start + 7] << 24)
              : (bytes[start + 4] << 24) |
                  (bytes[start + 5] << 16) |
                  (bytes[start + 6] << 8) |
                  bytes[start + 7];

      return _parseIFD(bytes, start, start + ifdOffset, isLittleEndian);
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser._parseTiffExif: $e');
      return null;
    }
  }

  /// IFD（Image File Directory）を解析
  static Map<String, dynamic>? _parseIFD(
    Uint8List bytes,
    int tiffStart,
    int ifdStart,
    bool isLittleEndian,
  ) {
    try {
      if (ifdStart + 2 > bytes.length) return null;

      final entryCount =
          isLittleEndian
              ? bytes[ifdStart] | (bytes[ifdStart + 1] << 8)
              : (bytes[ifdStart] << 8) | bytes[ifdStart + 1];

      int offset = ifdStart + 2;
      int? gpsIfdOffset;

      for (int i = 0; i < entryCount; i++) {
        if (offset + 12 > bytes.length) break;

        final tag =
            isLittleEndian
                ? bytes[offset] | (bytes[offset + 1] << 8)
                : (bytes[offset] << 8) | bytes[offset + 1];

        final valueOffset =
            isLittleEndian
                ? bytes[offset + 8] |
                    (bytes[offset + 9] << 8) |
                    (bytes[offset + 10] << 16) |
                    (bytes[offset + 11] << 24)
                : (bytes[offset + 8] << 24) |
                    (bytes[offset + 9] << 16) |
                    (bytes[offset + 10] << 8) |
                    bytes[offset + 11];

        if (tag == 0x8825) {
          gpsIfdOffset = tiffStart + valueOffset;
        }

        offset += 12;
      }

      if (gpsIfdOffset != null && gpsIfdOffset < bytes.length) {
        return _parseGpsIFD(bytes, tiffStart, gpsIfdOffset, isLittleEndian);
      }

      if (offset + 4 <= bytes.length) {
        final nextIfdOffset =
            isLittleEndian
                ? bytes[offset] |
                    (bytes[offset + 1] << 8) |
                    (bytes[offset + 2] << 16) |
                    (bytes[offset + 3] << 24)
                : (bytes[offset] << 24) |
                    (bytes[offset + 1] << 16) |
                    (bytes[offset + 2] << 8) |
                    bytes[offset + 3];

        if (nextIfdOffset != 0) {
          return _parseIFD(
            bytes,
            tiffStart,
            tiffStart + nextIfdOffset,
            isLittleEndian,
          );
        }
      }

      return null;
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser._parseIFD: $e');
      return null;
    }
  }

  /// GPS IFDを解析して緯度経度を取得
  static Map<String, dynamic>? _parseGpsIFD(
    Uint8List bytes,
    int tiffStart,
    int gpsIfdStart,
    bool isLittleEndian,
  ) {
    try {
      if (gpsIfdStart + 2 > bytes.length) return null;

      final entryCount =
          isLittleEndian
              ? bytes[gpsIfdStart] | (bytes[gpsIfdStart + 1] << 8)
              : (bytes[gpsIfdStart] << 8) | bytes[gpsIfdStart + 1];

      int offset = gpsIfdStart + 2;
      String? latRef, lngRef;
      List<double>? latDms, lngDms;
      double? imgDirection;

      for (int i = 0; i < entryCount; i++) {
        if (offset + 12 > bytes.length) break;

        final tag =
            isLittleEndian
                ? bytes[offset] | (bytes[offset + 1] << 8)
                : (bytes[offset] << 8) | bytes[offset + 1];

        final type =
            isLittleEndian
                ? bytes[offset + 2] | (bytes[offset + 3] << 8)
                : (bytes[offset + 2] << 8) | bytes[offset + 3];

        final count =
            isLittleEndian
                ? bytes[offset + 4] |
                    (bytes[offset + 5] << 8) |
                    (bytes[offset + 6] << 16) |
                    (bytes[offset + 7] << 24)
                : (bytes[offset + 4] << 24) |
                    (bytes[offset + 5] << 16) |
                    (bytes[offset + 6] << 8) |
                    bytes[offset + 7];

        final valueOffset =
            isLittleEndian
                ? bytes[offset + 8] |
                    (bytes[offset + 9] << 8) |
                    (bytes[offset + 10] << 16) |
                    (bytes[offset + 11] << 24)
                : (bytes[offset + 8] << 24) |
                    (bytes[offset + 9] << 16) |
                    (bytes[offset + 10] << 8) |
                    bytes[offset + 11];

        switch (tag) {
          case 1: // GPSLatitudeRef
            if (type == 2 && count == 2) {
              latRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 2: // GPSLatitude
            if (type == 5 && count == 3) {
              latDms = _parseRationalArray(
                bytes,
                tiffStart + valueOffset,
                3,
                isLittleEndian,
              );
            }
            break;
          case 3: // GPSLongitudeRef
            if (type == 2 && count == 2) {
              lngRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 4: // GPSLongitude
            if (type == 5 && count == 3) {
              lngDms = _parseRationalArray(
                bytes,
                tiffStart + valueOffset,
                3,
                isLittleEndian,
              );
            }
            break;
          case 0x11: // GPSImgDirection（撮影方向、RATIONAL型）
            if (type == 5 && count == 1) {
              final dirValues = _parseRationalArray(
                bytes,
                tiffStart + valueOffset,
                1,
                isLittleEndian,
              );
              if (dirValues != null && dirValues.isNotEmpty) {
                imgDirection = dirValues[0];
              }
            }
            break;
        }

        offset += 12;
      }

      if (latRef != null &&
          lngRef != null &&
          latDms != null &&
          lngDms != null) {
        final lat = dmsToDecimal(latDms) * (latRef == 'S' ? -1 : 1);
        final lng = dmsToDecimal(lngDms) * (lngRef == 'W' ? -1 : 1);

        return {
          'lat': lat,
          'lng': lng,
          if (imgDirection != null) 'direction': imgDirection,
        };
      }

      return null;
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser._parseGpsIFD: $e');
      return null;
    }
  }

  /// RATIONAL配列を解析
  static List<double>? _parseRationalArray(
    Uint8List bytes,
    int start,
    int count,
    bool isLittleEndian,
  ) {
    try {
      if (start + count * 8 > bytes.length) return null;

      final result = <double>[];
      for (int i = 0; i < count; i++) {
        final offset = start + i * 8;

        final numerator =
            isLittleEndian
                ? bytes[offset] |
                    (bytes[offset + 1] << 8) |
                    (bytes[offset + 2] << 16) |
                    (bytes[offset + 3] << 24)
                : (bytes[offset] << 24) |
                    (bytes[offset + 1] << 16) |
                    (bytes[offset + 2] << 8) |
                    bytes[offset + 3];

        final denominator =
            isLittleEndian
                ? bytes[offset + 4] |
                    (bytes[offset + 5] << 8) |
                    (bytes[offset + 6] << 16) |
                    (bytes[offset + 7] << 24)
                : (bytes[offset + 4] << 24) |
                    (bytes[offset + 5] << 16) |
                    (bytes[offset + 6] << 8) |
                    bytes[offset + 7];

        if (denominator != 0) {
          result.add(numerator / denominator);
        } else {
          result.add(0.0);
        }
      }

      return result;
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser._parseRationalArray: $e');
      return null;
    }
  }

  /// DMS（度分秒）を十進度に変換
  /// 外部からも使用可能なユーティリティメソッド
  static double dmsToDecimal(List<double> dms) {
    if (dms.length < 3) return 0.0;
    return dms[0] + (dms[1] / 60.0) + (dms[2] / 3600.0);
  }
}
