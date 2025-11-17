// K-MAPS: 写真ノードクラス
// 位置情報付き画像ファイルに対応するレイヤツリーノード

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import 'layer_tree_node.dart';
import 'folder_node.dart';

/// 画像ファイルノード（位置情報付き画像ファイル管理）
/// EXIFデータから緯度経度を取得し、位置情報がある画像のみを管理する
class PhotoNode extends LayerTreeNode {
  /// 画像ファイルの絶対パス
  final String filePath;

  /// 画像の撮影位置（EXIFから取得）
  final LatLng location;

  /// 撮影日時（EXIFから取得、nullable）
  final DateTime? takenAt;

  /// 画像ファイルの詳細情報
  final PhotoMetadata metadata;

  /// コンストラクタ
  PhotoNode(
    this.filePath,
    this.location,
    this.metadata, {
    this.takenAt,
    bool visible = true,
    LayerTreeNode? parent,
  }) : super(
         p.basename(filePath),
         visible: visible,
         parent: parent,
         nodeType: "photo",
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
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// 画像ファイルが存在するかチェック
  bool get fileExists => File(filePath).existsSync();

  /// 画像ファイルのサムネイル取得（将来的に実装）
  // Future<Uint8List?> getThumbnail() async {
  //   // 画像リサイズライブラリを使用してサムネイル生成
  //   return null;
  // }

  /// 指定したフォルダ内の画像ファイルをスキャンし、位置情報付きのPhotoNodeリストを返す
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    print('[DEBUG] PhotoNode.loadNodes: called with parent=${parent?.name}');
    final nodes = <LayerTreeNode>[];
    if (parent is! FolderNode) return nodes;

    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) {
      print(
        '[DEBUG] PhotoNode.loadNodes: absPath is null for parent ${parent.name}',
      );
      return nodes;
    }

    final dir = Directory(absPath);
    if (!dir.existsSync()) {
      print('[DEBUG] PhotoNode.loadNodes: directory does not exist: $absPath');
      return nodes;
    }

    print('[DEBUG] PhotoNode.loadNodes: scanning directory: $absPath');
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
      print('[DEBUG] PhotoNode.loadNodes: found image file: $fileName');

      try {
        // EXIFデータから位置情報を抽出
        final exifData = await _extractExifData(entity.path);
        if (exifData != null) {
          final photoNode = PhotoNode(
            entity.path,
            exifData.location,
            exifData.metadata,
            takenAt: exifData.takenAt,
            visible: true,
            parent: parent,
          );
          nodes.add(photoNode);
          print(
            '[DEBUG] PhotoNode.loadNodes: created PhotoNode for $fileName at ${exifData.location}',
          );
        } else {
          print(
            '[DEBUG] PhotoNode.loadNodes: no GPS data found in $fileName, skipping',
          );
        }
      } catch (e) {
        print(
          '[ERROR] PhotoNode.loadNodes: failed to process $fileName: $e',
        );
      }
    }

    print(
      '[DEBUG] PhotoNode.loadNodes: found ${nodes.length} photos with GPS data, returning',
    );
    return nodes;
  }

  /// EXIFデータから位置情報と撮影情報を抽出
  /// 位置情報がない場合はnullを返す
  static Future<ExifPhotoData?> _extractExifData(String filePath) async {
    try {
      // 基本的なEXIF解析（JPEG対応）
      /// GPS情報がある場合のみ座標データを返す
      final bytes = await File(filePath).readAsBytes();
      final exifResult = _parseBasicExif(bytes);
      if (exifResult == null) return null;

      final stats = await File(filePath).stat();
      final metadata = PhotoMetadata(
        fileSize: stats.size,
        width: exifResult['width'] as int?,
        height: exifResult['height'] as int?,
        camera: exifResult['camera'] as String?,
      );

      return ExifPhotoData(
        location: LatLng(
          exifResult['lat'] as double,
          exifResult['lng'] as double,
        ),
        takenAt: exifResult['datetime'] as DateTime?,
        metadata: metadata,
      );
    } catch (e) {
      print('[ERROR] PhotoNode._extractExifData: $e');
      return null;
    }
  }

  /// 基本的なEXIF解析（JPEG対応）
  /// GPS情報がある場合のみ座標データを返す
  static Map<String, dynamic>? _parseBasicExif(Uint8List bytes) {
    try {
      // JPEGファイルかチェック（SOI: 0xFFD8で開始）
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        print('[DEBUG] PhotoNode._parseBasicExif: not a JPEG file');
        return null;
      }

      // APP1セグメント（EXIF）を探す
      int offset = 2;
      while (offset < bytes.length - 1) {
        if (bytes[offset] != 0xFF) break;

        final marker = bytes[offset + 1];
        offset += 2;

        if (marker == 0xE1) {
          // APP1セグメント（EXIF）
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          offset += 2;

          // "Exif\0\0" ヘッダをチェック
          if (offset + 6 < bytes.length &&
              bytes[offset] == 0x45 &&
              bytes[offset + 1] == 0x78 &&
              bytes[offset + 2] == 0x69 &&
              bytes[offset + 3] == 0x66 &&
              bytes[offset + 4] == 0x00 &&
              bytes[offset + 5] == 0x00) {
            // TIFFヘッダの開始位置
            final tiffStart = offset + 6;
            return _parseTiffExif(bytes, tiffStart, segmentLength - 6);
          }
        } else if (marker == 0xDA) {
          // SOS（Start of Scan）
          break; // 画像データ開始、EXIFはない
        } else {
          // 他のセグメントをスキップ
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          offset += segmentLength;
        }
      }

      print('[DEBUG] PhotoNode._parseBasicExif: no EXIF data found');
      return null;
    } catch (e) {
      print('[ERROR] PhotoNode._parseBasicExif: $e');
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

      // エンディアンをチェック（"II" = little-endian, "MM" = big-endian）
      final isLittleEndian = bytes[start] == 0x49 && bytes[start + 1] == 0x49;
      if (!isLittleEndian &&
          !(bytes[start] == 0x4D && bytes[start + 1] == 0x4D)) {
        print('[DEBUG] PhotoNode._parseTiffExif: invalid TIFF header');
        return null;
      }

      // TIFF識別子（42）をチェック
      final tiffId =
          isLittleEndian
              ? bytes[start + 2] | (bytes[start + 3] << 8)
              : (bytes[start + 2] << 8) | bytes[start + 3];
      if (tiffId != 42) {
        print('[DEBUG] PhotoNode._parseTiffExif: invalid TIFF identifier');
        return null;
      }

      // 最初のIFDのオフセット
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

      // IFDを解析してGPS情報を探す
      return _parseIFD(bytes, start, start + ifdOffset, isLittleEndian);
    } catch (e) {
      print('[ERROR] PhotoNode._parseTiffExif: $e');
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

      // エントリ数を取得
      final entryCount =
          isLittleEndian
              ? bytes[ifdStart] | (bytes[ifdStart + 1] << 8)
              : (bytes[ifdStart] << 8) | bytes[ifdStart + 1];

      int offset = ifdStart + 2;
      int? gpsIfdOffset;

      // 各エントリを処理
      for (int i = 0; i < entryCount; i++) {
        if (offset + 12 > bytes.length) break;

        // タグID
        final tag =
            isLittleEndian
                ? bytes[offset] | (bytes[offset + 1] << 8)
                : (bytes[offset] << 8) | bytes[offset + 1];

        // 値のオフセット/値
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

        // GPS IFDポインタ（タグ 0x8825）
        if (tag == 0x8825) {
          gpsIfdOffset = tiffStart + valueOffset;
        }

        offset += 12;
      }

      // GPS IFDがあれば解析
      if (gpsIfdOffset != null && gpsIfdOffset < bytes.length) {
        return _parseGpsIFD(bytes, tiffStart, gpsIfdOffset, isLittleEndian);
      }

      // 次のIFDがあれば処理（GPS情報が見つからない場合）
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
      print('[ERROR] PhotoNode._parseIFD: $e');
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

      // エントリ数を取得
      final entryCount =
          isLittleEndian
              ? bytes[gpsIfdStart] | (bytes[gpsIfdStart + 1] << 8)
              : (bytes[gpsIfdStart] << 8) | bytes[gpsIfdStart + 1];

      int offset = gpsIfdStart + 2;
      String? latRef, lngRef;
      List<double>? latDms, lngDms;

      // 各GPSエントリを処理
      for (int i = 0; i < entryCount; i++) {
        if (offset + 12 > bytes.length) break;

        // タグID
        final tag =
            isLittleEndian
                ? bytes[offset] | (bytes[offset + 1] << 8)
                : (bytes[offset] << 8) | bytes[offset + 1];

        // データ型
        final type =
            isLittleEndian
                ? bytes[offset + 2] | (bytes[offset + 3] << 8)
                : (bytes[offset + 2] << 8) | bytes[offset + 3];

        // データ数
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

        // 値のオフセット/値
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
              // ASCII string
              latRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 2: // GPSLatitude
            if (type == 5 && count == 3) {
              // RATIONAL
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
              // ASCII string
              lngRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 4: // GPSLongitude
            if (type == 5 && count == 3) {
              // RATIONAL
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

      // 緯度経度が揃っていれば座標を計算
      if (latRef != null &&
          lngRef != null &&
          latDms != null &&
          lngDms != null) {
        final lat = _dmsToDecimal(latDms) * (latRef == 'S' ? -1 : 1);
        final lng = _dmsToDecimal(lngDms) * (lngRef == 'W' ? -1 : 1);

        print(
          '[DEBUG] PhotoNode._parseGpsIFD: GPS coordinates found: $lat, $lng',
        );
        return {'lat': lat, 'lng': lng};
      }

      return null;
    } catch (e) {
      print('[ERROR] PhotoNode._parseGpsIFD: $e');
      return null;
    }
  }

  /// RATIONAL配列（分数の配列）を解析
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
      print('[ERROR] PhotoNode._parseRationalArray: $e');
      return null;
    }
  }

  /// DMS（度分秒）を十進度に変換
  static double _dmsToDecimal(List<double> dms) {
    if (dms.length < 3) return 0.0;
    return dms[0] + (dms[1] / 60.0) + (dms[2] / 3600.0);
  }

  @override
  Future<void> updateChildren() async {
    // PhotoNodeは子ノードを持たない
    children.clear();
  }

  @override
  Future<void> dispose() async {
    print('[DEBUG] PhotoNode.dispose: disposing photo ${name}');
    
    // 画像ファイルを削除
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        print('[DEBUG] PhotoNode.dispose: deleted file ${filePath}');
      } else {
        print('[DEBUG] PhotoNode.dispose: file not found ${filePath}');
      }
    } catch (e) {
      print('[ERROR] PhotoNode.dispose: failed to delete file ${filePath}: $e');
      // エラーを再throwして、呼び出し元で処理できるようにする
      rethrow;
    }
    
    await super.dispose();
  }
}

/// 写真のEXIFデータから抽出した情報
class ExifPhotoData {
  final LatLng location;
  final DateTime? takenAt;
  final PhotoMetadata metadata;

  ExifPhotoData({required this.location, this.takenAt, required this.metadata});
}

/// 写真ファイルのメタデータ
class PhotoMetadata {
  final int fileSize;
  final int? width;
  final int? height;
  final String? camera;

  PhotoMetadata({required this.fileSize, this.width, this.height, this.camera});
}
