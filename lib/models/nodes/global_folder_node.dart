// K-MAPS: グローバルフォルダノードクラス
// どのプロジェクトを開いても表示される共有フォルダ
// 実体はアプリケーションのDocumentsディレクトリに存在

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import 'package:k_maps/utils/app_logger.dart';
import 'layer_tree_node.dart';
import 'folder_node.dart';
import 'geopackage_node.dart';
import 'image_node.dart';
import '../geopackage/geopackage_file.dart';

/// グローバルフォルダノード
/// - どのプロジェクトを開いてもルートフォルダ直下に表示される
/// - 実体は getApplicationDocumentsDirectory()/k_maps_global に存在
/// - 青色アイコンで通常フォルダと差別化
class GlobalFolderNode extends FolderNode {
  /// グローバルフォルダの実体パス
  final String globalPath;

  GlobalFolderNode(
    super.name, {
    required this.globalPath,
    super.visible,
    super.parent,
    super.children,
  });

  /// グローバルノードフラグ
  @override
  bool get isGlobalNode => true;

  /// 青色アイコンで差別化
  @override
  Color get baseIconColor => Colors.blue;

  /// グローバルフォルダ自体の絶対パスを返す
  @override
  String? getAbsoluteFilePath() {
    return globalPath;
  }

  /// グローバルフォルダの子ノードを更新
  /// 通常のFolderNodeと同様だが、子フォルダはGlobalSubFolderNodeとして生成
  @override
  Future<void> updateChildren() async {
    // ディレクトリが存在しなければ作成
    final dir = Directory(globalPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
      AppLogger.debug('[GlobalFolderNode] Created global folder: $globalPath');
    }

    // サブフォルダを読み込み
    final folderNodes = await _loadGlobalSubFolders();
    // GeoPackageを読み込み
    final gpkgNodes = await _loadGeoPackageNodes();
    // 画像ファイルを読み込み
    final photoNodes = await _loadImageNodes();

    // 現在のファイルシステムに存在するノード名のセットを作成
    final currentFolderNames = folderNodes.map((n) => n.name).toSet();
    final currentGpkgNames = gpkgNodes.map((n) => n.name).toSet();
    final currentPhotoNames = photoNodes.map((n) => n.name).toSet();
    final allCurrentNames = {
      ...currentFolderNames,
      ...currentGpkgNames,
      ...currentPhotoNames,
    };

    // 既存の子ノードで、ファイルシステムに存在しないものを削除
    children.removeWhere((child) {
      final shouldRemove = !allCurrentNames.contains(child.name);
      if (shouldRemove) {
        AppLogger.debug(
          '[GlobalFolderNode] Removing ${child.name} (no longer exists)',
        );
        child.parent = null;
      }
      return shouldRemove;
    });

    // 新しいノードを追加（既存ノードは再利用）
    for (final node in folderNodes) {
      addChildIfNotExists(node);
    }
    for (final node in gpkgNodes) {
      addChildIfNotExists(node);
    }
    for (final node in photoNodes) {
      addChildIfNotExists(node);
    }

    AppLogger.debug(
      '[GlobalFolderNode] ${children.length} children after update',
    );
  }

  /// グローバルフォルダ直下のサブフォルダを読み込み
  Future<List<LayerTreeNode>> _loadGlobalSubFolders() async {
    final nodes = <LayerTreeNode>[];
    final dir = Directory(globalPath);
    if (!dir.existsSync()) return nodes;

    final directories = dir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in directories) {
      final name = p.basename(entity.path);
      nodes.add(
        GlobalSubFolderNode(
          name,
          basePath: globalPath,
          visible: true,
          parent: this,
          children: [],
        ),
      );
    }
    return nodes;
  }

  /// グローバルフォルダ直下のGeoPackageノードを読み込み
  Future<List<LayerTreeNode>> _loadGeoPackageNodes() async {
    final nodes = <LayerTreeNode>[];
    final dir = Directory(globalPath);
    if (!dir.existsSync()) return nodes;

    final gpkgFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gpkg'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in gpkgFiles) {
      final fileName = p.basename(entity.path);
      // 絶対パスモードでGeoPackageFileを作成
      final gpkgFile = GeoPackageFile([fileName], absolutePath: entity.path);
      nodes.add(
        GlobalGeoPackageNode(gpkgFile, absolutePath: entity.path, parent: this),
      );
      AppLogger.debug('[GlobalFolderNode] Found GeoPackage: $fileName');
    }
    return nodes;
  }

  /// グローバルフォルダ直下の画像ノードを読み込み
  Future<List<LayerTreeNode>> _loadImageNodes() async {
    final nodes = <LayerTreeNode>[];
    final dir = Directory(globalPath);
    if (!dir.existsSync()) return nodes;

    const supportedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.tiff', '.tif'];
    final imageFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return supportedExtensions.contains(ext);
        })
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in imageFiles) {
      final node = await GlobalImageNode.fromPath(entity.path, parent: this);
      if (node != null) {
        nodes.add(node);
      }
    }
    return nodes;
  }

  /// グローバルフォルダ内に新しいフォルダを作成
  static GlobalSubFolderNode? createIn(GlobalFolderNode parent, String name) {
    final newDir = Directory(p.join(parent.globalPath, name));
    if (!newDir.existsSync()) {
      newDir.createSync();
    }
    final node = GlobalSubFolderNode(
      name,
      basePath: parent.globalPath,
      parent: parent,
    );
    parent.addChild(node);
    return node;
  }
}

/// グローバルフォルダ内のサブフォルダノード
/// 青色アイコン＆グローバルフォルダベースのパス解決
class GlobalSubFolderNode extends FolderNode {
  /// グローバルフォルダのベースパス
  final String basePath;

  GlobalSubFolderNode(
    super.name, {
    required this.basePath,
    super.visible,
    super.parent,
    super.children,
  });

  /// グローバルノードフラグ
  @override
  bool get isGlobalNode => true;

  /// 青色アイコンで差別化
  @override
  Color get baseIconColor => Colors.blue;

  /// グローバルフォルダベースの絶対パスを返す
  @override
  String? getAbsoluteFilePath() {
    // 親をたどってパスセグメントを構築
    final segments = <String>[];
    LayerTreeNode? current = this;
    while (current != null && current is! GlobalFolderNode) {
      segments.insert(0, current.name);
      current = current.parent;
    }
    return p.joinAll([basePath, ...segments]);
  }

  /// 子ノードを更新（サブフォルダ・GeoPackage・画像）
  @override
  Future<void> updateChildren() async {
    final absPath = getAbsoluteFilePath();
    if (absPath == null) return;

    final dir = Directory(absPath);
    if (!dir.existsSync()) return;

    // サブフォルダを読み込み
    final folderNodes = await _loadSubFolders(absPath);
    // GeoPackageを読み込み
    final gpkgNodes = await _loadGeoPackageNodes(absPath);
    // 画像ファイルを読み込み
    final photoNodes = await _loadImageNodes(absPath);

    // 現在のファイルシステムに存在するノード名のセットを作成
    final allCurrentNames = {
      ...folderNodes.map((n) => n.name),
      ...gpkgNodes.map((n) => n.name),
      ...photoNodes.map((n) => n.name),
    };

    // 既存の子ノードで、ファイルシステムに存在しないものを削除
    children.removeWhere((child) {
      final shouldRemove = !allCurrentNames.contains(child.name);
      if (shouldRemove) {
        child.parent = null;
      }
      return shouldRemove;
    });

    // 新しいノードを追加
    for (final node in folderNodes) {
      addChildIfNotExists(node);
    }
    for (final node in gpkgNodes) {
      addChildIfNotExists(node);
    }
    for (final node in photoNodes) {
      addChildIfNotExists(node);
    }
  }

  Future<List<LayerTreeNode>> _loadSubFolders(String absPath) async {
    final nodes = <LayerTreeNode>[];
    final dir = Directory(absPath);

    final directories = dir
        .listSync()
        .whereType<Directory>()
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in directories) {
      nodes.add(
        GlobalSubFolderNode(
          p.basename(entity.path),
          basePath: basePath,
          visible: true,
          parent: this,
          children: [],
        ),
      );
    }
    return nodes;
  }

  Future<List<LayerTreeNode>> _loadGeoPackageNodes(String absPath) async {
    final nodes = <LayerTreeNode>[];
    final dir = Directory(absPath);

    final gpkgFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.gpkg'))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in gpkgFiles) {
      final fileName = p.basename(entity.path);
      // 絶対パスモードでGeoPackageFileを作成
      final gpkgFile = GeoPackageFile([fileName], absolutePath: entity.path);
      nodes.add(
        GlobalGeoPackageNode(gpkgFile, absolutePath: entity.path, parent: this),
      );
    }
    return nodes;
  }

  Future<List<LayerTreeNode>> _loadImageNodes(String absPath) async {
    final nodes = <LayerTreeNode>[];
    final dir = Directory(absPath);

    const supportedExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.tiff', '.tif'];
    final imageFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final ext = p.extension(f.path).toLowerCase();
          return supportedExtensions.contains(ext);
        })
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in imageFiles) {
      final node = await GlobalImageNode.fromPath(entity.path, parent: this);
      if (node != null) {
        nodes.add(node);
      }
    }
    return nodes;
  }

  /// サブフォルダ内に新しいフォルダを作成
  static GlobalSubFolderNode? createIn(GlobalSubFolderNode parent, String name) {
    final parentPath = parent.getAbsoluteFilePath();
    if (parentPath == null) return null;
    
    final newDir = Directory(p.join(parentPath, name));
    if (!newDir.existsSync()) {
      newDir.createSync();
    }
    final node = GlobalSubFolderNode(
      name,
      basePath: parent.basePath,
      parent: parent,
    );
    parent.addChild(node);
    return node;
  }
}

/// グローバルフォルダ用のGeoPackageノード
/// 絶対パスを使用してパス解決
class GlobalGeoPackageNode extends GeoPackageNode {
  /// ファイルの絶対パス
  final String absolutePath;

  GlobalGeoPackageNode(
    super.geoPackageFile, {
    required this.absolutePath,
    super.visible,
    super.parent,
  });

  /// グローバルノードフラグ
  @override
  bool get isGlobalNode => true;

  /// 青色系のアイコン色で差別化
  @override
  Color get baseIconColor => Colors.blue.shade700;
}

/// グローバルフォルダ用の画像ノード
class GlobalImageNode extends ImageNode {
  GlobalImageNode._(
    super.filePath,
    super.location,
    super.metadata, {
    super.takenAt,
    super.visible,
    super.parent,
  });

  /// グローバルノードフラグ
  @override
  bool get isGlobalNode => true;

  /// 絶対パスからGlobalImageNodeを作成
  static Future<GlobalImageNode?> fromPath(
    String absolutePath, {
    LayerTreeNode? parent,
  }) async {
    final file = File(absolutePath);
    if (!file.existsSync()) return null;

    try {
      // ファイル情報を取得
      final stats = await file.stat();
      
      // EXIFデータから位置情報を抽出（ImageNodeの内部メソッドと同様のロジック）
      final exifData = await _extractExifDataFromPath(absolutePath, stats.size);
      
      if (exifData != null) {
        return GlobalImageNode._(
          absolutePath,
          exifData.location,
          exifData.metadata,
          takenAt: exifData.takenAt,
          visible: true,
          parent: parent,
        );
      } else {
        // 位置情報がない画像も表示（デフォルト座標）
        return GlobalImageNode._(
          absolutePath,
          const LatLng(0, 0),
          ImageMetadata(fileSize: stats.size),
          visible: true,
          parent: parent,
        );
      }
    } catch (e) {
      AppLogger.debug('[GlobalImageNode] Error loading image: $e');
      return null;
    }
  }

  /// EXIFデータから位置情報を抽出（ImageNode._extractExifDataと同様のロジック）
  static Future<ExifImageData?> _extractExifDataFromPath(String filePath, int fileSize) async {
    try {
      final file = File(filePath);
      // EXIF情報はファイルの先頭部分にあるため、最大256KBまで読み込む
      final randomAccessFile = await file.open(mode: FileMode.read);
      try {
        final bytesToRead = fileSize < 256 * 1024 ? fileSize : 256 * 1024;
        final bytes = await randomAccessFile.read(bytesToRead);
        
        // JPEG形式かチェック
        if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
          return null; // Not JPEG
        }

        // 簡易的なEXIF解析でGPS座標を取得
        final gpsData = _parseGpsFromBytes(bytes);
        if (gpsData == null) return null;

        final metadata = ImageMetadata(
          fileSize: fileSize,
          width: gpsData['width'] as int?,
          height: gpsData['height'] as int?,
          camera: gpsData['camera'] as String?,
        );

        return ExifImageData(
          location: LatLng(
            gpsData['lat'] as double,
            gpsData['lng'] as double,
          ),
          takenAt: gpsData['datetime'] as DateTime?,
          metadata: metadata,
        );
      } finally {
        await randomAccessFile.close();
      }
    } catch (e) {
      AppLogger.debug('[GlobalImageNode] EXIF extraction error: $e');
      return null;
    }
  }

  /// バイト配列からGPS情報を解析
  static Map<String, dynamic>? _parseGpsFromBytes(List<int> bytes) {
    try {
      int offset = 2;
      while (offset < bytes.length - 1) {
        if (bytes[offset] != 0xFF) break;

        final marker = bytes[offset + 1];
        offset += 2;

        if (marker == 0xE1) {
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          offset += 2;

          if (offset + 6 < bytes.length &&
              bytes[offset] == 0x45 && // 'E'
              bytes[offset + 1] == 0x78 && // 'x'
              bytes[offset + 2] == 0x69 && // 'i'
              bytes[offset + 3] == 0x66 && // 'f'
              bytes[offset + 4] == 0x00 &&
              bytes[offset + 5] == 0x00) {
            final tiffStart = offset + 6;
            return _parseTiffExif(bytes, tiffStart, segmentLength - 6);
          }
        } else if (marker == 0xDA) {
          break; // Start of scan data
        } else {
          final segmentLength = (bytes[offset] << 8) | bytes[offset + 1];
          offset += segmentLength;
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// TIFFフォーマットのEXIFデータを解析
  static Map<String, dynamic>? _parseTiffExif(List<int> bytes, int start, int length) {
    try {
      if (start + 8 > bytes.length) return null;

      final isLittleEndian = bytes[start] == 0x49 && bytes[start + 1] == 0x49;
      if (!isLittleEndian && !(bytes[start] == 0x4D && bytes[start + 1] == 0x4D)) {
        return null;
      }

      final tiffId = isLittleEndian
          ? bytes[start + 2] | (bytes[start + 3] << 8)
          : (bytes[start + 2] << 8) | bytes[start + 3];
      if (tiffId != 42) return null;

      final ifdOffset = isLittleEndian
          ? bytes[start + 4] | (bytes[start + 5] << 8) | (bytes[start + 6] << 16) | (bytes[start + 7] << 24)
          : (bytes[start + 4] << 24) | (bytes[start + 5] << 16) | (bytes[start + 6] << 8) | bytes[start + 7];

      return _parseIFD(bytes, start, start + ifdOffset, isLittleEndian);
    } catch (e) {
      return null;
    }
  }

  /// IFD（Image File Directory）を解析
  static Map<String, dynamic>? _parseIFD(List<int> bytes, int tiffStart, int ifdStart, bool isLittleEndian) {
    try {
      if (ifdStart + 2 > bytes.length) return null;

      final entryCount = isLittleEndian
          ? bytes[ifdStart] | (bytes[ifdStart + 1] << 8)
          : (bytes[ifdStart] << 8) | bytes[ifdStart + 1];

      int offset = ifdStart + 2;
      int? gpsIfdOffset;

      for (int i = 0; i < entryCount; i++) {
        if (offset + 12 > bytes.length) break;

        final tag = isLittleEndian
            ? bytes[offset] | (bytes[offset + 1] << 8)
            : (bytes[offset] << 8) | bytes[offset + 1];

        final valueOffset = isLittleEndian
            ? bytes[offset + 8] | (bytes[offset + 9] << 8) | (bytes[offset + 10] << 16) | (bytes[offset + 11] << 24)
            : (bytes[offset + 8] << 24) | (bytes[offset + 9] << 16) | (bytes[offset + 10] << 8) | bytes[offset + 11];

        if (tag == 0x8825) { // GPS IFD pointer
          gpsIfdOffset = tiffStart + valueOffset;
        }

        offset += 12;
      }

      if (gpsIfdOffset != null && gpsIfdOffset < bytes.length) {
        return _parseGpsIFD(bytes, tiffStart, gpsIfdOffset, isLittleEndian);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// GPS IFDを解析して緯度経度を取得
  static Map<String, dynamic>? _parseGpsIFD(List<int> bytes, int tiffStart, int gpsIfdStart, bool isLittleEndian) {
    try {
      if (gpsIfdStart + 2 > bytes.length) return null;

      final entryCount = isLittleEndian
          ? bytes[gpsIfdStart] | (bytes[gpsIfdStart + 1] << 8)
          : (bytes[gpsIfdStart] << 8) | bytes[gpsIfdStart + 1];

      int offset = gpsIfdStart + 2;
      String? latRef, lngRef;
      List<double>? latDms, lngDms;

      for (int i = 0; i < entryCount; i++) {
        if (offset + 12 > bytes.length) break;

        final tag = isLittleEndian
            ? bytes[offset] | (bytes[offset + 1] << 8)
            : (bytes[offset] << 8) | bytes[offset + 1];

        final type = isLittleEndian
            ? bytes[offset + 2] | (bytes[offset + 3] << 8)
            : (bytes[offset + 2] << 8) | bytes[offset + 3];

        final count = isLittleEndian
            ? bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24)
            : (bytes[offset + 4] << 24) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7];

        final valueOffset = isLittleEndian
            ? bytes[offset + 8] | (bytes[offset + 9] << 8) | (bytes[offset + 10] << 16) | (bytes[offset + 11] << 24)
            : (bytes[offset + 8] << 24) | (bytes[offset + 9] << 16) | (bytes[offset + 10] << 8) | bytes[offset + 11];

        switch (tag) {
          case 1: // GPS Latitude Ref
            if (type == 2 && count == 2) {
              latRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 2: // GPS Latitude
            if (type == 5 && count == 3) {
              latDms = _parseRationalArray(bytes, tiffStart + valueOffset, 3, isLittleEndian);
            }
            break;
          case 3: // GPS Longitude Ref
            if (type == 2 && count == 2) {
              lngRef = String.fromCharCode(bytes[offset + 8]);
            }
            break;
          case 4: // GPS Longitude
            if (type == 5 && count == 3) {
              lngDms = _parseRationalArray(bytes, tiffStart + valueOffset, 3, isLittleEndian);
            }
            break;
        }

        offset += 12;
      }

      if (latRef != null && lngRef != null && latDms != null && lngDms != null) {
        final lat = _dmsToDecimal(latDms) * (latRef == 'S' ? -1 : 1);
        final lng = _dmsToDecimal(lngDms) * (lngRef == 'W' ? -1 : 1);
        return {'lat': lat, 'lng': lng};
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// RATIONAL配列を解析
  static List<double>? _parseRationalArray(List<int> bytes, int start, int count, bool isLittleEndian) {
    try {
      if (start + count * 8 > bytes.length) return null;

      final result = <double>[];
      for (int i = 0; i < count; i++) {
        final offset = start + i * 8;

        final numerator = isLittleEndian
            ? bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24)
            : (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];

        final denominator = isLittleEndian
            ? bytes[offset + 4] | (bytes[offset + 5] << 8) | (bytes[offset + 6] << 16) | (bytes[offset + 7] << 24)
            : (bytes[offset + 4] << 24) | (bytes[offset + 5] << 16) | (bytes[offset + 6] << 8) | bytes[offset + 7];

        if (denominator != 0) {
          result.add(numerator / denominator);
        } else {
          result.add(0.0);
        }
      }
      return result;
    } catch (e) {
      return null;
    }
  }

  /// DMS（度分秒）を十進度に変換
  static double _dmsToDecimal(List<double> dms) {
    if (dms.length < 3) return 0.0;
    return dms[0] + (dms[1] / 60.0) + (dms[2] / 3600.0);
  }

  /// 青色系のアイコン色で差別化
  @override
  Color get baseIconColor => Colors.blue.shade300;
}
