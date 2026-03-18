// K-MAPS: 属性テーブル用ダイアログ
// カラム追加ダイアログ、フィルタ複製ダイアログなど

import 'package:flutter/material.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/geometry_type.dart';
import '../../utils/app_logger.dart';

/// カラム追加ダイアログを表示
Future<void> showAddColumnDialog(
  BuildContext context,
  LayerNode layer,
  VoidCallback onColumnAdded,
) async {
  final columnNameController = TextEditingController();
  String selectedType = 'TEXT';

  final result = await showDialog<Map<String, String>>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.add_box, color: Colors.blue),
                SizedBox(width: 8),
                Text('カラム追加'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: columnNameController,
                  decoration: const InputDecoration(
                    labelText: 'カラム名',
                    hintText: '例: 備考, 数量, 日付',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'データ型',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'TEXT', child: Text('テキスト (TEXT)')),
                    DropdownMenuItem(value: 'INTEGER', child: Text('整数 (INTEGER)')),
                    DropdownMenuItem(value: 'REAL', child: Text('小数 (REAL)')),
                    DropdownMenuItem(value: 'BLOB', child: Text('バイナリ (BLOB)')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedType = value);
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final columnName = columnNameController.text.trim();
                  if (columnName.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('カラム名を入力してください'),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }
                  Navigator.of(dialogContext).pop({
                    'name': columnName,
                    'type': selectedType,
                  });
                },
                icon: const Icon(Icons.check),
                label: const Text('追加'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null && context.mounted) {
    final columnName = result['name']!;
    final columnType = result['type']!;

    try {
      await layer.geoPackageFile.addAttributeColumn(
        layer.layerName,
        columnName,
        columnType,
      );
      layer.clearColumnNamesCache();
      onColumnAdded();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カラム「$columnName」を追加しました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[AttributeTableDialogs] カラム追加エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カラム追加に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

/// フィルタ結果のフィーチャ複製ダイアログ
Future<void> showDuplicateFilteredDialog(
  BuildContext context,
  LayerNode layer,
  String filterSql,
  VoidCallback onDuplicated,
) async {
  final layerNameController = TextEditingController(
    text: '${layer.layerName}_filtered',
  );

  final matchCount = await layer.geoPackageFile.countFilteredFeatures(
    layer.layerName,
    filterSql,
  );

  if (!context.mounted) return;

  final result = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.copy_all, color: Colors.green),
            SizedBox(width: 8),
            Text('フィルタ結果を複製'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$matchCount件のフィーチャを新しいレイヤにコピーします。',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              'フィルタ: $filterSql',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: layerNameController,
              decoration: const InputDecoration(
                labelText: '新しいレイヤ名',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('キャンセル'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              final name = layerNameController.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('レイヤ名を入力してください'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop(name);
            },
            icon: const Icon(Icons.copy_all),
            label: const Text('複製'),
          ),
        ],
      );
    },
  );

  if (result != null && context.mounted) {
    try {
      final gpkgFile = layer.geoPackageFile;
      final geomType = await gpkgFile.getGeometryType(layer.layerName);

      // 新レイヤ作成
      await gpkgFile.addLayer(result, geomType ?? GeometryType.point);

      // 属性スキーマを移植
      final sourceColumns = await gpkgFile.getAttributeColumnInfo(
        layer.layerName,
        includeBuiltIn: false,
      );
      for (final col in sourceColumns) {
        final name = col['name'] as String;
        final type = col['type'] as String;
        if (name.toLowerCase() != 'geom' &&
            name.toLowerCase() != 'fid' &&
            name.toLowerCase() != 'id') {
          await gpkgFile.addAttributeColumn(result, name, type);
        }
      }

      // フィルタ結果を複製
      final copiedCount = await gpkgFile.duplicateFilteredFeatures(
        layer.layerName,
        result,
        filterSql,
      );

      onDuplicated();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$copiedCount件を「$result」にコピーしました'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[AttributeTableDialogs] フィルタ複製エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('複製に失敗しました: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
