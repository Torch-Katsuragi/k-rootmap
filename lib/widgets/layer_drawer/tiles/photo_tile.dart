/// K-MAPS: 写真タイルウィジェット
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:image/image.dart' as img;
import '../../../i18n/strings.g.dart';
import '../../../models/nodes/image_node.dart';
import '../../../models/nodes/overlay_image_node.dart';
import '../../../models/kmeta.dart';
import '../../../providers/selection_providers.dart';
import '../../../providers/ui_state_providers.dart';
import '../../../services/kmeta_service.dart';
import '../../../utils/app_logger.dart';
import '../common_dialogs.dart';
import 'node_visibility_icon.dart';

/// 写真ノード用の ListTile ウィジェット
class PhotoTile extends ConsumerWidget {
  final ImageNode node;
  final VoidCallback? onRename;
  final void Function(LatLng)? onJumpTo;

  const PhotoTile({
    super.key,
    required this.node,
    this.onRename,
    this.onJumpTo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOverlay = node is OverlayImageNode;

    return ListTile(
      leading: NodeVisibilityIcon(node: node),
      title: Text(node.name),
      subtitle: isOverlay
          ? Text(t.layerDrawer.photo.overlay, style: const TextStyle(fontSize: 11, color: Colors.teal))
          : node.hasLocation
              ? null
              : Text(t.layerDrawer.photo.noLocation, style: const TextStyle(fontSize: 11)),
      onTap: () {
        ref.read(selectedFeaturesProvider.notifier).set([node]);
        if (node.hasLocation && onJumpTo != null) {
          onJumpTo!(node.location!);
        }
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          switch (value) {
            case 'rename':
              onRename?.call();
              break;
            case 'delete':
              await _handleDelete(context, ref);
              break;
            case 'convert_to_overlay':
              await _handleConvertToOverlay(context, ref);
              break;
            case 'convert_to_normal':
              await _handleConvertToNormal(context, ref);
              break;
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'rename', child: Text(t.layerDrawer.photo.changeName)),
          if (!isOverlay)
            PopupMenuItem(
              value: 'convert_to_overlay',
              child: Text(t.layerDrawer.photo.convertToOverlay),
            ),
          if (isOverlay)
            PopupMenuItem(
              value: 'convert_to_normal',
              child: Text(t.layerDrawer.photo.convertToNormal),
            ),
          PopupMenuItem(value: 'delete', child: Text(t.layerDrawer.photo.deletePhoto)),
        ],
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    await confirmAndExecute(
      context,
      ref: ref,
      title: t.layerDrawer.photo.deleteTitle,
      content: Text(t.layerDrawer.photo.deleteConfirm(name: node.name)),
      confirmLabel: t.common.delete,
      confirmColor: Colors.red,
      successMessage: t.layerDrawer.photo.photoDeleted(name: node.name),
      execute: () async {
        ref.read(selectedFeaturesProvider.notifier).remove(node);
        await node.dispose();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
    );
  }

  /// 通常のImageNode → OverlayImageNodeに変換
  /// カメラ中心に配置、画像サイズからデフォルトパラメータを生成
  Future<void> _handleConvertToOverlay(BuildContext context, WidgetRef ref) async {
    final absPath = node.getAbsoluteFilePath();
    if (absPath == null) return;

    final folderPath = p.dirname(absPath);
    final fileName = p.basename(absPath);

    // 画像サイズを取得
    int imageWidth = 1920;
    int imageHeight = 1080;
    try {
      final file = File(absPath);
      final imageBytes = await file.readAsBytes();
      final decoded = img.decodeImage(imageBytes);
      if (decoded != null) {
        imageWidth = decoded.width;
        imageHeight = decoded.height;
      }
    } catch (e) {
      AppLogger.debug('[PhotoTile] Failed to read image size: $e');
    }

    // カメラ中心座標を取得（現在表示中のマップ中心に配置）
    double centerLng = 139.767;
    double centerLat = 35.681;
    final mapController = ref.read(mapControllerHolderProvider);
    if (mapController?.raw != null) {
      final cameraCenter = mapController!.camera.center;
      centerLng = cameraCenter.longitude;
      centerLat = cameraCenter.latitude;
    } else if (node.hasLocation) {
      // マップコントローラ未初期化時はEXIF位置をフォールバック
      centerLng = node.location!.longitude;
      centerLat = node.location!.latitude;
    }

    final overlay = KMetaImageOverlay(
      centerLng: centerLng,
      centerLat: centerLat,
      scale: 1.0,  // 1 m/px
      rotation: 0.0,
      opacity: 0.7,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );

    final success = await KMetaService.instance.setImageOverlay(
      folderPath, fileName, overlay,
    );
    if (success) {
      AppLogger.debug('[PhotoTile] Converted to overlay: $fileName');
      if (node.parent != null) {
        await node.parent!.updateChildren();
      }
      if (context.mounted) {
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      }
    }
  }

  /// OverlayImageNode → 通常のImageNodeに戻す
  Future<void> _handleConvertToNormal(BuildContext context, WidgetRef ref) async {
    final absPath = node.getAbsoluteFilePath();
    if (absPath == null) return;

    final folderPath = p.dirname(absPath);
    final fileName = p.basename(absPath);

    final success = await KMetaService.instance.removeImageOverlay(
      folderPath, fileName,
    );
    if (success) {
      AppLogger.debug('[PhotoTile] Converted to normal: $fileName');
      if (node.parent != null) {
        await node.parent!.updateChildren();
      }
      if (context.mounted) {
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      }
    }
  }
}
