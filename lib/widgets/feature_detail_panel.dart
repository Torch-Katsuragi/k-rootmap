// フィーチャ詳細パネルウィジェット
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'dart:io';
import '../models/nodes/feature_node.dart';
import '../models/nodes/image_node.dart';
import '../models/nodes/layer_node.dart'; // PointLayerNode用
import '../utils/global_config.dart';
import '../widgets/line_simplification_dialog.dart';
import '../widgets/geometry_conversion_dialogs.dart';
import '../widgets/photo_viewer.dart';
import '../services/geometry_conversion_service.dart';

/// フィーチャ詳細パネル
class FeatureDetailPanel extends StatelessWidget {
  final dynamic feature;
  const FeatureDetailPanel({super.key, required this.feature});

  @override
  Widget build(BuildContext context) {
    if (feature == null) return const SizedBox.shrink();

    // ImageNode用の詳細パネル
    if (feature is ImageNode) {
      final photo = feature as ImageNode;

      // プロジェクトルートからの相対パスを計算
      final projectRoot = GlobalConfig.instance.projectRootDir;
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
                              Icon(Icons.broken_image, color: Colors.grey, size: 24),
                              const SizedBox(height: 4),
                              Text(
                                '画像エラー',
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
              const Text('名前: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(child: Text(photo.name)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('パス: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(displayPath, style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('座標: ', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(
                  photo.hasLocation
                      ? '${photo.location!.latitude.toStringAsFixed(6)}, ${photo.location!.longitude.toStringAsFixed(6)}'
                      : '位置情報なし',
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
                const Text(
                  '撮影日時: ',
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
              const Text(
                'サイズ: ',
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
      // metadataを含む属性名の項目を除外
      final filteredEntries =
          infoMap.entries
              .where((entry) => !entry.key.toLowerCase().contains('metadata'))
              .toList();

      final children = <Widget>[
        for (final entry in filteredEntries)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${entry.key}: ',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(child: Text(entry.value)),
            ],
          ),
      ];

      // LineFeatureNodeの場合は簡略化ボタンとポイント変換ボタンを追加
      if (feature is LineFeatureNode) {
        children.addAll([
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showLineSimplificationDialog(context, feature),
              icon: const Icon(Icons.timeline, size: 16),
              label: const Text('ライン簡略化'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue.shade700,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showConvertToPointsDialog(context, feature),
              icon: const Icon(Icons.scatter_plot, size: 16),
              label: const Text('ポイントに変換'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade50,
                foregroundColor: Colors.green.shade700,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ]);
      }

      // PolygonFeatureNodeの場合はポイント変換ボタンを追加
      if (feature is PolygonFeatureNode) {
        children.addAll([
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _showConvertToPointsDialog(context, feature),
              icon: const Icon(Icons.scatter_plot, size: 16),
              label: const Text('ポイントに変換'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade50,
                foregroundColor: Colors.green.shade700,
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

  /// ライン簡略化ダイアログを表示
  Future<void> _showLineSimplificationDialog(
    BuildContext context,
    LineFeatureNode lineFeature,
  ) async {
    final result = await showDialog<List<LatLng>?>(
      context: context,
      builder: (context) => LineSimplificationDialog(lineFeature: lineFeature),
    );

    if (result != null && result.isNotEmpty) {
      // 簡略化を適用
      try {
        // LineFeatureNodeのupdateLineメソッドを使用してDBまで確実に保存
        final success = await lineFeature.updateLine(result);

        if (!success) {
          throw Exception('ジオメトリの更新に失敗しました');
        }

        AppLogger.debug('[LineSimplification] 簡略化適用完了: ${lineFeature.name}');
        AppLogger.debug('[LineSimplification] 点数: ${result.length}点');

        // マップを更新
        if (context.mounted) {
          final mapState = GlobalConfig.instance.mapState;
          if (mapState != null) {
            mapState.refreshFeatures();
            mapState.setState(() {});
          }
        }

        // 成功メッセージ
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ライン簡略化が適用されました')));
        }
      } catch (e) {
        AppLogger.debug('[ERROR] ライン簡略化適用失敗: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('ライン簡略化の適用に失敗しました: $e')));
        }
      }
    }
  }

  /// ライン/ポリゴン→ポイント変換ダイアログを表示
  Future<void> _showConvertToPointsDialog(
    BuildContext context,
    FeatureNode feature,
  ) async {
    // 座標リストを取得（カウント用）
    int pointCount = 0;
    if (feature is LineFeatureNode) {
      pointCount = feature.line.length;
    } else if (feature is PolygonFeatureNode) {
      final geometry = feature.geometry as List<List<LatLng>>?;
      if (geometry != null && geometry.isNotEmpty) {
        final outerRing = geometry.first;
        // 閉じたポリゴンなら最後の座標を除外してカウント
        if (outerRing.length >= 2) {
          final first = outerRing.first;
          final last = outerRing.last;
          pointCount = (first.latitude == last.latitude && first.longitude == last.longitude)
              ? outerRing.length - 1
              : outerRing.length;
        } else {
          pointCount = outerRing.length;
        }
      }
    }

    if (pointCount == 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('座標データが見つかりません')),
        );
      }
      return;
    }

    // カレントディレクトリ直下のポイントレイヤーを検索
    final pointLayers = GeometryConversionService.findTargetLayersForGeometry(
      GlobalConfig.instance.folderTree,
    );

    if (pointLayers.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カレントディレクトリ直下にポイントレイヤーが見つかりません。\n先にポイントレイヤーを作成してください。')),
        );
      }
      return;
    }

    // ダイアログを表示
    final targetLayer = await showDialog<PointLayerNode>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return ConvertGeometryToPointsDialog(
          sourceFeature: feature,
          availableLayers: pointLayers,
          pointCount: pointCount,
        );
      },
    );

    if (targetLayer == null) {
      return;
    }

    // 変換サービスを使用してポイントを作成
    try {
      final createdFeatures = await GeometryConversionService.convertGeometryToPoints(
        sourceFeature: feature,
        targetLayer: targetLayer,
      );

      if (createdFeatures.isNotEmpty) {
        // マップを更新
        final mapState = GlobalConfig.instance.mapState;
        if (mapState != null) {
          mapState.refreshFeatures();
          mapState.setState(() {});
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${createdFeatures.length}個のポイントを作成しました'),
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.debug('[ERROR] ポイント変換失敗: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ポイント変換に失敗しました: $e')),
        );
      }
    }
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
      color: Colors.white,
      child: Container(
        width: 220,
        constraints: const BoxConstraints(
          maxHeight: 300, // 最大高さを300pxに制限
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


