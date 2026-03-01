/// K-MAPS: 写真タイル構築ミックスイン
library;

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../models/nodes/layer_tree_node.dart';
import '../../../models/nodes/image_node.dart';
import '../../../providers/selection_providers.dart';
import '../layer_drawer.dart';

mixin PhotoTileBuilder on ConsumerState<LayerDrawer> {
  void Function(LatLng latLng)? get onJumpTo;
  void triggerMapRefresh();
  Widget buildIconWithVisibility(LayerTreeNode node);

  /// 写真タイルを構築（画像ファイル）
  Widget buildPhotoTile(
    BuildContext context,
    ImageNode node, {
    VoidCallback? onRename,
  }) {
    return ListTile(
      leading: buildIconWithVisibility(node),
      title: Text(
        node.name,
        style: node.hasLocation ? null : const TextStyle(fontStyle: FontStyle.italic),
      ),
      subtitle: node.hasLocation ? null : const Text('位置情報なし', style: TextStyle(fontSize: 11)),
      onTap: () {
        ref.read(selectedFeaturesProvider.notifier).set([node]);

        if (node.hasLocation && onJumpTo != null) {
          onJumpTo!(node.location!);
        }

        setState(() {});
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            if (onRename != null) onRename();
          } else if (value == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('写真削除'),
                    content: Text(
                      '${node.name} を本当に削除しますか？\nファイルも完全に削除されます。',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('キャンセル'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('削除'),
                      ),
                    ],
                  ),
            );
            if (confirm == true) {
              try {
                ref.read(selectedFeaturesProvider.notifier).remove(node);

                await node.dispose();

                triggerMapRefresh();

                setState(() {});
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('写真を削除しました: ${node.name}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('写真の削除に失敗しました: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          }
        },
        itemBuilder: (context) {
          AppLogger.debug('[DEBUG] buildPhotoTile: itemBuilder called');
          return [
            const PopupMenuItem(value: 'rename', child: Text('名前の変更')),
            const PopupMenuItem(value: 'delete', child: Text('削除')),
          ];
        },
      ),
    );
  }
}
