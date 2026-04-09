// フィーチャ詳細パネルウィジェット
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../i18n/strings.g.dart';
import 'dart:io';
import '../models/nodes/feature_node.dart';
import '../models/nodes/image_node.dart';
import '../providers/project_providers.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/feature_editor/feature_editor_screen.dart';
import '../widgets/feature_editor/actions/simplify_action.dart';
import '../widgets/feature_editor/actions/trim_action.dart';

class FeatureDetailPanel extends ConsumerWidget {
  final dynamic feature;
  const FeatureDetailPanel({super.key, required this.feature});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (feature == null) return const SizedBox.shrink();

    // ImageNode用の詳細パネル
    if (feature is ImageNode) {
      final photo = feature as ImageNode;

      // プロジェクトルートからの相対パスを計算
      final projectRoot = ref.read(projectRootDirProvider);
      String displayPath = photo.filePath;
      if (projectRoot != null && photo.filePath.startsWith(projectRoot)) {
        displayPath = photo.filePath.substring(projectRoot.length);
        if (displayPath.startsWith('\\') || displayPath.startsWith('/')) {
          displayPath = displayPath.substring(1);
        }
      }

      return _buildPanel(
        context,
        title: "📸 写真ファイル",
        children: [
          // 画像プレビューを追加（タップでフルスクリーン表示）
          GestureDetector(
            onTap: () {
              showPhotoViewer(
                context,
                imagePath: photo.filePath,
              );
            },
            child: Container(
              width: double.infinity,
              height: 120,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // 画像
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(photo.filePath),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey.shade100,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image, color: Colors.grey, size: 24),
                              const SizedBox(height: 4),
                              Text(
                                t.featureDetail.imageError,
                                style: TextStyle(color: Colors.grey, fontSize: 10),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  // 拡大アイコン（ホバーヒント）
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Icon(
                        Icons.zoom_in,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 詳細情報
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.featureDetail.nameLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: Text(photo.name)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.featureDetail.pathLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(displayPath, style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.featureDetail.coordLabel, style: const TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(
                  photo.hasLocation
                      ? '${photo.location!.latitude.toStringAsFixed(6)}, ${photo.location!.longitude.toStringAsFixed(6)}'
                      : t.featureDetail.noLocation,
                  style: TextStyle(
                    fontSize: 11,
                    color: photo.hasLocation ? null : Colors.grey,
                    fontStyle: photo.hasLocation ? null : FontStyle.italic,
                  ),
                ),
              ),
            ],
          ),
          if (photo.takenAt != null) ...[
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.featureDetail.dateLabel,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(
                  child: Text(
                    '${photo.takenAt}',
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.featureDetail.sizeLabel,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: Text(
                  '${(photo.metadata.fileSize / (1024 * 1024)).toStringAsFixed(1)} MB',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ],
      );
    }

    // 既存のFeatureNode用の処理
    if (feature is FeatureNode) {
      final infoMap = feature.infoMap;
      const hiddenKeys = {'geom', 'sub_table'};
      final filteredEntries =
          infoMap.entries
              .where((entry) =>
                  !entry.key.toLowerCase().contains('metadata') &&
                  !hiddenKeys.contains(entry.key))
              .toList();

      final children = <Widget>[
        for (final entry in filteredEntries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.key}: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Expanded(child: Text(entry.value)),
              ],
            ),
          ),
      ];

      // Line/Polygonの場合は「編集」ボタンを追加
      if (feature is LineFeatureNode || feature is PolygonFeatureNode) {
        children.addAll([
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openFeatureEditor(context, feature),
              icon: const Icon(Icons.edit, size: 16),
              label: Text(t.featureDetail.edit),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue.shade700,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ]);
      }

      // タイトルをシンプルに（PointFeatureNode → Point等）
      String displayTitle = 'Feature';
      if (feature is PointFeatureNode) {
        displayTitle = 'Point';
      } else if (feature is LineFeatureNode) {
        displayTitle = 'Line';
      } else if (feature is PolygonFeatureNode) {
        displayTitle = 'Polygon';
      }
      
      return _buildPanel(
        context,
        title: displayTitle,
        children: children,
      );
    }
    return const SizedBox.shrink();
  }

  /// フィーチャ編集画面に遷移
  void _openFeatureEditor(BuildContext context, FeatureNode feature) {
    Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FeatureEditorScreen(
          feature: feature,
          actions: [
            SimplifyAction(),
            TrimAction(),
          ],
        ),
      ),
    );
  }

  /// パネルウィジェットビルダー
  Widget _buildPanel(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(12),
      color: Colors.white.withValues(alpha: 0.8),
      child: Container(
        width: 220,
        constraints: const BoxConstraints(
          maxHeight: 300,
        ),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            // スクロール可能にしつつ、内容に応じて縮小
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

