// K-MAPS: 画像ノードクラス
// 位置情報付き画像ファイルに対応するレイヤツリーノード

import 'dart:io';
import 'dart:typed_data';
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import 'layer_tree_node.dart';
import 'folder_node.dart';

/// 画像ファイルノード（位置情報付き画像ファイル管理）
/// EXIFデータから緯度経度を取得し、位置情報がある画像のみを管理する
class ImageNode extends LayerTreeNode {
  /// 画像ファイルの絶対パス
  final String filePath;

  /// 画像の撮影位置（EXIFから取得）
  final LatLng location;

  /// 撮影日時（EXIFから取得、nullable）
  final DateTime? takenAt;

  /// 画像ファイルの詳細情報
  final ImageMetadata metadata;

  /// コンストラクタ
  ImageNode(
    this.filePath,
    this.location,
    this.metadata, {
    this.takenAt,
    bool visible = true,
    LayerTreeNode? parent,
    bool isPhoto = true,
  }) : super(
         p.basename(filePath),
         visible: visible,
         parent: parent,
         nodeType: "image",
       );

  /// ノード種別ごとのベースアイコン（UI用）
  @override
  IconData get baseIcon => Icons.photo_camera;
  @override
  Color get baseIconColor => Colors.purple;

  /// 詳細情報（項目名と値のペア、順序付き）
  List<MapEntry<String, String>> get detailEntries => [
    MapEntry('name', name),
    MapEntry('file_path', filePath),
    MapEntry('latitude', location.latitude.toStringAsFixed(6)),
    MapEntry('longitude', location.longitude.toStringAsFixed(6)),
    if (takenAt != null) MapEntry('taken_at', takenAt!.toLocal().toString()),
    MapEntry('file_size', _formatFileSize(metadata.fileSize)),
    if (metadata.width != null && metadata.height != null)
      MapEntry('dimensions', '${metadata.width} x ${metadata.height}'),
    if (metadata.camera != null) MapEntry('camera', metadata.camera!),
  ];

  /// ファイルサイズを読みやすい形式に変換
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 画像ファイルが存在するかチェック
  bool get fileExists => File(filePath).existsSync();

  /// 指定したフォルダ内の画像ファイルをスキャンし、位置情報付きのImageNodeリストを返す
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    AppLogger.debug('[DEBUG] ImageNode.loadNodes: called with parent=${parent?.name}');
    final nodes = <LayerTreeNode>[];
    if (parent is! FolderNode) return nodes;

    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) {
      AppLogger.debug(
        '[DEBUG] ImageNode.loadNodes: absPath is null for parent ${parent.name}',
      );
      return nodes;
    }

    final dir = Directory(absPath);
    if (!dir.existsSync()) {
      AppLogger.debug('[DEBUG] ImageNode.loadNodes: directory does not exist: $absPath');
      return nodes;
    }

    AppLogger.debug('[DEBUG] ImageNode.loadNodes: scanning directory: $absPath');
    // ディレクトリ内の画像ファイルをスキャンして名前順にソート
    final supportedExtensions = {'.jpg', '.jpeg', '.png', '.tiff', '.tif'};
    
    final imageFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => supportedExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in imageFiles) {
      final fileName = p.basename(entity.path);
      AppLogger.debug('[DEBUG] ImageNode.loadNodes: found image file: $fileName');

      try {
        // EXIFデータから位置情報を抽出
        final exifData = await _extractExifData(entity.path);
        if (exifData != null) {
          final imageNode = ImageNode(
            entity.path,
            exifData.location,
            exifData.metadata,
            takenAt: exifData.takenAt,
            visible: true,
            parent: parent,
          );
          nodes.add(imageNode);
          AppLogger.debug(
            '[DEBUG] ImageNode.loadNodes: created ImageNode for $fileName at ${exifData.location}',
          );
        } else {
          AppLogger.debug(
            '[DEBUG] ImageNode.loadNodes: no GPS data found in $fileName, skipping',
          );
        }
      } catch (e) {
        AppLogger.debug(
          '[ERROR] ImageNode.loadNodes: failed to process $fileName: $e',
        );
      }
    }

    AppLogger.debug(
      '[DEBUG] ImageNode.loadNodes: found ${nodes.length} images with GPS data, returning',
    );
    return nodes;
  }

  /// EXIFデータから位置情報と撮影情報を抽出
  /// 位置情報がない場合はnullを返す
  /// 
  /// パフォーマンス最適化: ファイル全体ではなくヘッダー部分のみを読み込む
  static Future<ExifImageData?> _extractExifData(String filePath) async {
    try {
      // ファイルサイズを取得
      final file = File(filePath);
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
      );
    } catch (e) {
      AppLogger.debug('[ERROR] ImageNode._extractExifData: $e');
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
        AppLogger.debug('[DEBUG] ImageNode._parseBasicExif: not a JPEG file');
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

      AppLogger.debug('[DEBUG] ImageNode._parseBasicExif: no EXIF data found');
      return null;
    } catch (e) {
      AppLogger.debug('[ERROR] ImageNode._parseBasicExif: $e');
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
        AppLogger.debug('[DEBUG] ImageNode._parseTiffExif: invalid TIFF header');
        return null;
      }

      final tiffId =
          isLittleEndian
              ? bytes[start + 2] | (bytes[start + 3] << 8)
              : (bytes[start + 2] << 8) | bytes[start + 3];
      if (tiffId != 42) {
        AppLogger.debug('[DEBUG] ImageNode._parseTiffExif: invalid TIFF identifier');
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
      AppLogger.debug('[ERROR] ImageNode._parseTiffExif: $e');
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
      AppLogger.debug('[ERROR] ImageNode._parseIFD: $e');
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
          case 1:
            if (type == 2 && count == 2) {
              latRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 2:
            if (type == 5 && count == 3) {
              latDms = _parseRationalArray(
                bytes,
                tiffStart + valueOffset,
                3,
                isLittleEndian,
              );
            }
            break;
          case 3:
            if (type == 2 && count == 2) {
              lngRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 4:
            if (type == 5 && count == 3) {
              lngDms = _parseRationalArray(
                bytes,
                tiffStart + valueOffset,
                3,
                isLittleEndian,
              );
            }
            break;
        }

        offset += 12;
      }

      if (latRef != null &&
          lngRef != null &&
          latDms != null &&
          lngDms != null) {
        final lat = _dmsToDecimal(latDms) * (latRef == 'S' ? -1 : 1);
        final lng = _dmsToDecimal(lngDms) * (lngRef == 'W' ? -1 : 1);

        AppLogger.debug(
          '[DEBUG] ImageNode._parseGpsIFD: GPS coordinates found: $lat, $lng',
        );
        return {'lat': lat, 'lng': lng};
      }

      return null;
    } catch (e) {
      AppLogger.debug('[ERROR] ImageNode._parseGpsIFD: $e');
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
      AppLogger.debug('[ERROR] ImageNode._parseRationalArray: $e');
      return null;
    }
  }

  /// DMS（度分秒）を十進度に変換
  static double _dmsToDecimal(List<double> dms) {
    if (dms.length < 3) return 0.0;
    return dms[0] + (dms[1] / 60.0) + (dms[2] / 3600.0);
  }

  /// リネーム処理
  Future<void> rename(String newName) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('ファイルが存在しません: $filePath');
      }

      final directory = p.dirname(filePath);
      final extension = p.extension(filePath);
      final newFileName = newName.endsWith(extension) ? newName : '$newName$extension';
      final newPath = p.join(directory, newFileName);

      if (File(newPath).existsSync()) {
        throw Exception('同名のファイルが既に存在します: $newFileName');
      }

      await file.rename(newPath);
      
      if (parent != null) {
        await parent!.updateChildren();
      }
      
    } catch (e) {
      AppLogger.debug('[ERROR] ImageNode.rename: $e');
      rethrow;
    }
  }

  @override
  Future<void> updateChildren() async {
    children.clear();
  }

  @override
  Future<void> dispose() async {
    AppLogger.debug('[DEBUG] ImageNode.dispose: disposing image $name');
    
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        AppLogger.debug('[DEBUG] ImageNode.dispose: deleted file $filePath');
      } else {
        AppLogger.debug('[DEBUG] ImageNode.dispose: file not found $filePath');
      }
    } catch (e) {
      AppLogger.debug('[ERROR] ImageNode.dispose: failed to delete file $filePath: $e');
      rethrow;
    }
    
    await super.dispose();
  }
}

/// 画像のEXIFデータから抽出した情報
class ExifImageData {
  final LatLng location;
  final DateTime? takenAt;
  final ImageMetadata metadata;

  ExifImageData({required this.location, this.takenAt, required this.metadata});
}

/// 画像ファイルのメタデータ
class ImageMetadata {
  final int fileSize;
  final int? width;
  final int? height;
  final String? camera;

  ImageMetadata({required this.fileSize, this.width, this.height, this.camera});
}

