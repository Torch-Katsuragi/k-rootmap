// Root Maps: ギャラリーインポート
// file_picker で画像を選択し、プロジェクトフォルダにコピー（EXIF完全保持）
//
// Android の Photo Picker は content URI 経由でキャッシュコピーを返す際に
// EXIF GPS データをプライバシー保護のため除去してしまう。
// そこで file_picker の identifier (content URI) を MethodChannel 経由で
// Kotlin 側に渡し、MediaStore から実ファイルパスを解決して直接コピーすることで
// EXIF メタデータを完全保持する。

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const _channel = MethodChannel('com.k_root.k_maps/media_copy');

  /// ファイルピッカーで画像を選択し、targetFolder にインポートする。
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
      try {
        // 拡張子を name から取得（identifier 経由だと srcPath が無い場合がある）
        final ext = p.extension(file.name).toLowerCase();
        if (ext.isEmpty) continue;

        final baseName = p.basenameWithoutExtension(file.name);
        final destPath = _uniquePath(folderPath, baseName, ext);

        // Android: content URI からネイティブ側で実ファイルを直接コピー（EXIF 保持）
        // 非 Android: 従来の File.copy フォールバック
        final copied = await _copyFile(file, destPath);
        if (!copied) {
          AppLogger.debug('[GalleryImport] Failed to copy ${file.name}');
          continue;
        }

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

  /// ファイルをコピーする。
  /// Android では MethodChannel 経由で content URI から実ファイルを直接コピーし、
  /// EXIF メタデータを完全保持する。
  /// 非 Android や identifier が無い場合は File.copy でフォールバック。
  static Future<bool> _copyFile(PlatformFile file, String destPath) async {
    // Android: content URI が取れればネイティブ側で実ファイルコピー
    if (Platform.isAndroid && file.identifier != null) {
      try {
        final success = await _channel.invokeMethod<bool>('copyOriginal', {
          'uri': file.identifier,
          'destPath': destPath,
        });
        if (success == true) return true;
      } catch (e) {
        AppLogger.debug('[GalleryImport] Native copy failed, falling back: $e');
      }
    }

    // フォールバック: file_picker のキャッシュパスからコピー
    final srcPath = file.path;
    if (srcPath == null) return false;
    await File(srcPath).copy(destPath);
    return true;
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
