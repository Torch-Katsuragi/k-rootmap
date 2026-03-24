// K-MAPS: ギャラリーインポート
// file_picker で画像を選択し、プロジェクトフォルダにコピー（EXIF完全保持）

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import '../models/nodes/folder_node.dart';
import '../models/nodes/image_node.dart';
import '../models/app_notification.dart';
import '../providers/notification_providers.dart';
import '../utils/app_logger.dart';
import '../utils/exif_parser.dart';

/// ギャラリーからプロジェクトフォルダに写真をインポートするユーティリティ
class GalleryImporter {
  GalleryImporter._();

  /// ファイルピッカーで画像を選択し、targetFolder にインポートする。
  /// file_picker は ACTION_OPEN_DOCUMENT を使用するため EXIF が完全保持される。
  static Future<bool> pickAndImport(
    BuildContext context,
    FolderNode targetFolder, {
    WidgetRef? ref,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return false;

    final folderPath = targetFolder.getAbsoluteFilePath();
    if (folderPath == null) {
      if (ref != null) {
        ref.read(notificationCenterProvider.notifier).add(
          title: 'Failed to resolve folder path',
          level: NotificationLevel.error,
        );
      }
      return false;
    }

    int imported = 0;
    for (final file in result.files) {
      final srcPath = file.path;
      if (srcPath == null) continue;

      try {
        final ext = p.extension(srcPath).toLowerCase();
        if (ext.isEmpty) continue;

        final baseName = p.basenameWithoutExtension(file.name);
        final destPath = _uniquePath(folderPath, baseName, ext);

        await File(srcPath).copy(destPath);

        final node = await _createImageNode(destPath, targetFolder);
        targetFolder.addChild(node);
        imported++;
      } catch (e) {
        AppLogger.debug('[GalleryImport] Error importing ${file.name}: $e');
      }
    }

    if (imported > 0 && ref != null) {
      ref.read(notificationCenterProvider.notifier).add(
        title: 'Imported $imported photo${imported != 1 ? 's' : ''}',
        level: NotificationLevel.success,
      );
    }
    return imported > 0;
  }

  /// EXIF から位置情報・メタデータを読み取って ImageNode を生成
  static Future<ImageNode> _createImageNode(
    String destPath,
    FolderNode parent,
  ) async {
    LatLng? location;
    DateTime? takenAt;
    double? direction;
    int? width;
    int? height;

    final exif = await ExifParser.extractFromFile(destPath);
    if (exif != null) {
      location = exif.location;
      takenAt = exif.takenAt;
      direction = exif.direction;
      width = exif.metadata.width;
      height = exif.metadata.height;
    }

    final stats = await File(destPath).stat();
    return ImageNode(
      destPath,
      location,
      ImageMetadata(
        fileSize: stats.size,
        width: width,
        height: height,
        camera: null,
      ),
      takenAt: takenAt,
      direction: direction,
      visible: true,
      parent: parent,
      isPhoto: true,
    );
  }

  static String _uniquePath(String dir, String baseName, String ext) {
    var path = p.join(dir, '$baseName$ext');
    var i = 1;
    while (File(path).existsSync()) {
      path = p.join(dir, '${baseName}_$i$ext');
      i++;
    }
    return path;
  }
}
