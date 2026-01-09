// K-MAPS: 属性テーブル用ダイアログ
// カラム追加ダイアログなど

import 'package:flutter/material.dart';
import '../../models/nodes/layer_node.dart';
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
