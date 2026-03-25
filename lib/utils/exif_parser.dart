// K-MAPS: EXIF解析ユーティリティ
// 画像ファイルからGPS座標やメタデータを抽出する共通処理
// ImageNodeとGlobalImageNodeで使用

import 'dart:io';
import 'dart:typed_data';
import 'package:exif/exif.dart';
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
/// exifパッケージを使用してGPS座標やメタデータを抽出する静的メソッドを提供
/// 高速化のため、ファイル先頭部分（1MB）のみを読み込む
class ExifParser {
  ExifParser._();

  /// 画像ファイルからEXIFデータを抽出
  /// GPS座標が含まれていない場合はnullを返す
  static Future<ExifImageData?> extractFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final stats = await file.stat();

      // 電子小黒板等のメタデータが大きい画像にも対応するため1MBまで読む
      final bytes = await _readFileHeader(filePath, 1024 * 1024);
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) return null;

      final location = _extractGpsLocation(tags);
      if (location == null) return null;

      return ExifImageData(
        location: location,
        takenAt: _extractDateTime(tags),
        metadata: ImageMetadata(
          fileSize: stats.size,
          width: _extractInt(tags, 'EXIF ExifImageWidth') ??
              _extractInt(tags, 'Image ImageWidth'),
          height: _extractInt(tags, 'EXIF ExifImageLength') ??
              _extractInt(tags, 'Image ImageLength'),
          camera: _extractCamera(tags),
        ),
        direction: _extractGpsDirection(tags),
      );
    } catch (e) {
      AppLogger.debug('[ERROR] ExifParser.extractFromFile: $e');
      return null;
    }
  }

  static Future<Uint8List> _readFileHeader(String filePath, int maxBytes) async {
    final file = File(filePath);
    final fileSize = await file.length();
    final bytesToRead = fileSize < maxBytes ? fileSize : maxBytes;

    final raf = await file.open(mode: FileMode.read);
    try {
      return Uint8List.fromList(await raf.read(bytesToRead));
    } finally {
      await raf.close();
    }
  }

  static LatLng? _extractGpsLocation(Map<String, IfdTag> tags) {
    final latTag = tags['GPS GPSLatitude'];
    final latRefTag = tags['GPS GPSLatitudeRef'];
    final lngTag = tags['GPS GPSLongitude'];
    final lngRefTag = tags['GPS GPSLongitudeRef'];
    if (latTag == null || latRefTag == null || lngTag == null || lngRefTag == null) return null;

    final latValues = latTag.values;
    final lngValues = lngTag.values;
    if (latValues is! IfdRatios || lngValues is! IfdRatios) return null;
    if (latValues.ratios.length < 3 || lngValues.ratios.length < 3) return null;

    final lat = _ratiosDmsToDecimal(latValues.ratios) * (latRefTag.printable == 'S' ? -1 : 1);
    final lng = _ratiosDmsToDecimal(lngValues.ratios) * (lngRefTag.printable == 'W' ? -1 : 1);
    return LatLng(lat, lng);
  }

  static double _ratiosDmsToDecimal(List<Ratio> dms) {
    return dms[0].toDouble() + (dms[1].toDouble() / 60.0) + (dms[2].toDouble() / 3600.0);
  }

  static double? _extractGpsDirection(Map<String, IfdTag> tags) {
    final tag = tags['GPS GPSImgDirection'];
    if (tag == null) return null;
    final values = tag.values;
    if (values is IfdRatios && values.ratios.isNotEmpty) {
      return values.ratios[0].toDouble();
    }
    return null;
  }

  static DateTime? _extractDateTime(Map<String, IfdTag> tags) {
    final tag = tags['EXIF DateTimeOriginal'] ?? tags['Image DateTime'];
    if (tag == null) return null;
    try {
      final parts = tag.printable.split(RegExp(r'[\s:]'));
      if (parts.length >= 6) {
        return DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]),
          int.parse(parts[3]), int.parse(parts[4]), int.parse(parts[5]),
        );
      }
    } catch (_) {}
    return null;
  }

  static int? _extractInt(Map<String, IfdTag> tags, String key) {
    final tag = tags[key];
    if (tag == null) return null;
    try {
      return tag.values.firstAsInt();
    } catch (_) {
      return null;
    }
  }

  static String? _extractCamera(Map<String, IfdTag> tags) {
    final make = tags['Image Make']?.printable;
    final model = tags['Image Model']?.printable;
    if (make == null && model == null) return null;
    if (make != null && model != null) {
      return model.startsWith(make) ? model : '$make $model';
    }
    return make ?? model;
  }

  /// DMS（度分秒）を十進度に変換
  static double dmsToDecimal(List<double> dms) {
    if (dms.length < 3) return 0.0;
    return dms[0] + (dms[1] / 60.0) + (dms[2] / 3600.0);
  }
}
