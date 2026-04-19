// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
// Root Maps: 画像ノードクラス
// 位置情報付き画像ファイルに対応するレイヤツリーノード

import 'dart:io';
import 'package:root_maps/utils/app_logger.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import 'layer_tree_node.dart';
import 'folder_node.dart';
import '../../core/node_types.dart';
import '../../i18n/strings.g.dart';
import '../../models/kmeta.dart';
import '../../services/geotiff_service.dart';
import '../../services/kmeta_service.dart';
import '../../utils/exif_parser.dart';
import 'overlay_image_node.dart';

// ExifParserからクラスを再エクスポート（後方互換性のため）
export '../../utils/exif_parser.dart' show ExifImageData, ImageMetadata;

/// 画像ファイルノード（画像ファイル管理）
/// EXIFデータから緯度経度を取得できる場合は位置情報も保持する
class ImageNode extends LayerTreeNode {
  /// 画像ファイルの絶対パス
  final String filePath;

  /// 画像の撮影位置（EXIFから取得、位置情報なしの場合はnull）
  final LatLng? location;

  /// 撮影日時（EXIFから取得、nullable）
  final DateTime? takenAt;

  /// 画像ファイルの詳細情報
  final ImageMetadata metadata;

  /// 撮影方向（真北基準、0-360度）。EXIFのGPSImgDirectionから取得
  final double? direction;

  /// 位置情報を持っているか
  bool get hasLocation => location != null;

  /// コンストラクタ
  ImageNode(
    this.filePath,
    this.location,
    this.metadata, {
    this.takenAt,
    this.direction,
    bool visible = true,
    LayerTreeNode? parent,
    bool isPhoto = true,
  }) : super(
         p.basename(filePath),
         visible: visible,
         parent: parent,
         nodeType: NodeType.image,
       );
  
  // UI関連（baseIcon, baseIconColor）はNodePresenterに移動

  @override
  Future<void> persistVisibility() async {
    final parentFolder = parent;
    if (parentFolder is! FolderNode) return;
    final parentPath = parentFolder.getAbsoluteFilePath();
    if (parentPath == null) return;
    await KMetaService.instance.setImageVisibility(parentPath, name, visible);
    parentFolder.invalidateMetaCache();
  }

  /// 詳細情報（項目名と値のペア、順序付き）
  List<MapEntry<String, String>> get detailEntries => [
    MapEntry('name', name),
    MapEntry('file_path', filePath),
    if (hasLocation) ...[
      MapEntry('latitude', location!.latitude.toStringAsFixed(6)),
      MapEntry('longitude', location!.longitude.toStringAsFixed(6)),
    ] else
      MapEntry('location', t.gps.noLocation),
    if (direction != null) MapEntry('direction', '${direction!.toStringAsFixed(1)}°'),
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

  /// 指定したフォルダ内の画像ファイルをスキャンし、ImageNodeリストを返す
  /// GeoTIFFタグ（ModelTransformationTag）を持つ.tifファイルはOverlayImageNodeとして生成
  static Future<List<LayerTreeNode>> loadNodes(LayerTreeNode? parent) async {
    final nodes = <LayerTreeNode>[];
    if (parent is! FolderNode) return nodes;

    final absPath = parent.getAbsoluteFilePath();
    if (absPath == null) return nodes;

    final dir = Directory(absPath);
    if (!dir.existsSync()) return nodes;

    const supportedExtensions = {'.jpg', '.jpeg', '.png', '.tiff', '.tif'};

    final imageFiles = dir
        .listSync()
        .whereType<File>()
        .where((f) => supportedExtensions.contains(p.extension(f.path).toLowerCase()))
        .toList()
      ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));

    for (var entity in imageFiles) {
      try {
        final ext = p.extension(entity.path).toLowerCase();
        final isTiff = ext == '.tif' || ext == '.tiff';

        // GeoTIFFタグの判定（.tifファイルのみ）
        KMetaImageOverlay? overlayParams;
        if (isTiff) {
          final bytes = await entity.readAsBytes();
          overlayParams = GeoTiffService.readGeoTiffParams(bytes);
        }

        if (overlayParams != null) {
          // GeoTIFFタグあり → OverlayImageNode
          nodes.add(OverlayImageNode(
            entity.path,
            LatLng(overlayParams.centerLat, overlayParams.centerLng),
            ImageMetadata(fileSize: entity.lengthSync()),
            overlayParams: overlayParams,
            visible: true,
            parent: parent,
          ));
        } else {
          // 通常画像
          final exifData = await ExifParser.extractFromFile(entity.path);
          final meta = exifData?.metadata ?? ImageMetadata(fileSize: entity.lengthSync());
          nodes.add(ImageNode(
            entity.path,
            exifData?.location,
            meta,
            takenAt: exifData?.takenAt,
            direction: exifData?.direction,
            visible: true,
            parent: parent,
          ));
        }
      } catch (e) {
        AppLogger.debug('[ImageNode] failed: ${p.basename(entity.path)}: $e');
      }
    }

    if (nodes.isNotEmpty) {
      AppLogger.debug('[ImageNode] ${nodes.length} images in ${parent.name}');
    }
    return nodes;
  }

  /// リネーム処理
  Future<void> rename(String newName) async {
    AppLogger.debug('[DEBUG] ImageNode.rename: 開始 - $name → $newName');
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception(t.services.fileNotFound(path: filePath));
      }

      final directory = p.dirname(filePath);
      final extension = p.extension(filePath);
      final newFileName = newName.endsWith(extension) ? newName : '$newName$extension';
      final newPath = p.join(directory, newFileName);

      AppLogger.debug('[DEBUG] ImageNode.rename: $filePath → $newPath');

      if (File(newPath).existsSync()) {
        throw Exception(t.services.fileAlreadyExists(name: newFileName));
      }

      await file.rename(newPath);
      AppLogger.debug('[DEBUG] ImageNode.rename: ファイルリネーム完了');
      
      if (parent != null) {
        AppLogger.debug('[DEBUG] ImageNode.rename: 親ノードのupdateChildren呼び出し');
        await parent!.updateChildren();
        AppLogger.debug('[DEBUG] ImageNode.rename: 親ノードのupdateChildren完了');
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
