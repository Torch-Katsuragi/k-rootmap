/// K-MAPS: 写真タイルウィジェット
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../../../models/nodes/image_node.dart';
import '../../../providers/selection_providers.dart';
import '../../../providers/ui_state_providers.dart';
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
    return ListTile(
      leading: NodeVisibilityIcon(node: node),
      title: Text(
        node.name,
        style: node.hasLocation
            ? null
            : const TextStyle(fontStyle: FontStyle.italic),
      ),
      subtitle: node.hasLocation
          ? null
          : const Text('位置情報なし', style: TextStyle(fontSize: 11)),
      onTap: () {
        ref.read(selectedFeaturesProvider.notifier).set([node]);
        if (node.hasLocation && onJumpTo != null) {
          onJumpTo!(node.location!);
        }
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            onRename?.call();
          } else if (value == 'delete') {
            await _handleDelete(context, ref);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('名前の変更')),
          PopupMenuItem(value: 'delete', child: Text('削除')),
        ],
      ),
    );
  }

  Future<void> _handleDelete(BuildContext context, WidgetRef ref) async {
    await confirmAndExecute(
      context,
      ref: ref,
      title: '写真削除',
      content: Text('${node.name} を本当に削除しますか？\nファイルも完全に削除されます。'),
      confirmLabel: '削除',
      confirmColor: Colors.red,
      successMessage: '写真を削除しました: ${node.name}',
      execute: () async {
        ref.read(selectedFeaturesProvider.notifier).remove(node);
        await node.dispose();
        ref.read(featureRefreshTriggerProvider.notifier).trigger();
      },
    );
  }
}
