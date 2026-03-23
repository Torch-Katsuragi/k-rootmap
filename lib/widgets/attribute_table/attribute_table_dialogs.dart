// K-MAPS: 属性テーブル用ダイアログ
// カラム追加、フィルタ複製、フィールド計算機、カラム操作など

import 'package:flutter/material.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/geometry_type.dart';
import '../../utils/app_logger.dart';
import '../../utils/qgis_expression_filter.dart';

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
                    DropdownMenuItem(
                      value: 'INTEGER',
                      child: Text('整数 (INTEGER)'),
                    ),
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
                  Navigator.of(
                    dialogContext,
                  ).pop({'name': columnName, 'type': selectedType});
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

/// フィールド計算機ダイアログ
Future<void> showFieldCalculatorDialog(
  BuildContext context,
  LayerNode layer,
  List<String> columnNames,
  VoidCallback onUpdated,
) async {
  final expressionController = TextEditingController();
  String? selectedColumn;
  bool createNew = false;
  final newColumnController = TextEditingController();
  String newColumnType = 'TEXT';

  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (BuildContext dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.calculate, color: Colors.deepPurple),
                SizedBox(width: 8),
                Text('フィールド計算機'),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: createNew,
                        onChanged:
                            (v) => setState(() => createNew = v ?? false),
                      ),
                      const Text('新規カラムを作成', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                  if (createNew) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newColumnController,
                            decoration: const InputDecoration(
                              labelText: '新規カラム名',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            initialValue: newColumnType,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'TEXT',
                                child: Text('TEXT'),
                              ),
                              DropdownMenuItem(
                                value: 'INTEGER',
                                child: Text('INTEGER'),
                              ),
                              DropdownMenuItem(
                                value: 'REAL',
                                child: Text('REAL'),
                              ),
                            ],
                            onChanged: (v) {
                              if (v != null) setState(() => newColumnType = v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: selectedColumn,
                      decoration: const InputDecoration(
                        labelText: '更新対象カラム',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items:
                          columnNames
                              .where((c) => !c.startsWith('_'))
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                      onChanged: (v) => setState(() => selectedColumn = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  TextField(
                    controller: expressionController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'SQL式',
                      hintText: '例: upper("name")  |  "qty" * 2  |  \'固定値\'',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'カラム参照は "カラム名"、文字列は \'値\' で囲んでください。\n'
                    'SQLite関数が使えます: upper, lower, length, round, substr, etc.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('キャンセル'),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  final expr = expressionController.text.trim();
                  if (expr.isEmpty) return;

                  final target =
                      createNew
                          ? newColumnController.text.trim()
                          : selectedColumn;
                  if (target == null || target.isEmpty) return;

                  Navigator.of(dialogContext).pop({
                    'target': target,
                    'expression': expr,
                    'createNew': createNew,
                    'newType': newColumnType,
                  });
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('実行'),
              ),
            ],
          );
        },
      );
    },
  );

  if (result != null && context.mounted) {
    try {
      final target = result['target'] as String;
      final expression = result['expression'] as String;
      final isNew = result['createNew'] as bool;

      // 式の安全性チェック（SELECT用のバリデーションを流用）
      final validation = QgisExpressionFilter.toSqlWhere(expression);
      if (validation is FilterResultError) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('式エラー: ${validation.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      if (isNew) {
        final newType = result['newType'] as String;
        await layer.geoPackageFile.addAttributeColumn(
          layer.layerName,
          target,
          newType,
        );
        layer.clearColumnNamesCache();
      }

      final updatedCount = await layer.geoPackageFile
          .updateColumnWithExpression(layer.layerName, target, expression);

      onUpdated();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$updatedCount件を更新しました（$target）'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[FieldCalculator] エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('フィールド計算エラー: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}

/// カラムリネームダイアログ
Future<void> showRenameColumnDialog(
  BuildContext context,
  LayerNode layer,
  String currentName,
  VoidCallback onRenamed,
) async {
  final controller = TextEditingController(text: currentName);

  final newName = await showDialog<String>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Text('カラム名変更'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: '新しいカラム名',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = controller.text.trim();
                if (name.isNotEmpty && name != currentName) {
                  Navigator.of(ctx).pop(name);
                }
              },
              child: const Text('変更'),
            ),
          ],
        ),
  );

  if (newName != null && context.mounted) {
    try {
      await layer.geoPackageFile.renameColumn(
        layer.layerName,
        currentName,
        newName,
      );
      layer.clearColumnNamesCache();
      onRenamed();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カラム名を「$currentName」→「$newName」に変更しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[RenameColumn] エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('カラム名変更エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

/// カラム削除確認ダイアログ
Future<void> showDeleteColumnDialog(
  BuildContext context,
  LayerNode layer,
  String columnName,
  VoidCallback onDeleted,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder:
        (ctx) => AlertDialog(
          title: const Text('カラム削除'),
          content: Text('カラム「$columnName」を削除しますか？\nこの操作は元に戻せません。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('削除', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
  );

  if (confirmed == true && context.mounted) {
    try {
      await layer.geoPackageFile.dropColumn(layer.layerName, columnName);
      layer.clearColumnNamesCache();
      onDeleted();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('カラム「$columnName」を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      AppLogger.debug('[DeleteColumn] エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('カラム削除エラー: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
