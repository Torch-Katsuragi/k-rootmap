// K-MAPS: 属性テーブル用ダイアログ
// カラム追加、フィルタ複製、フィールド計算機、カラム操作など

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/app_notification.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/geometry_type.dart';
import '../../providers/notification_providers.dart';
import '../../utils/app_logger.dart';
import '../../utils/qgis_expression_filter.dart';

void _notify(WidgetRef? ref, String title, NotificationLevel level) {
  ref
      ?.read(notificationCenterProvider.notifier)
      .add(title: title, level: level);
}

/// カラム追加ダイアログを表示
Future<void> showAddColumnDialog(
  BuildContext context,
  LayerNode layer,
  VoidCallback onColumnAdded, {
  WidgetRef? ref,
}) async {
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
                    _notify(ref, 'カラム名を入力してください', NotificationLevel.warning);
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
      _notify(ref, 'カラム「$columnName」を追加しました', NotificationLevel.success);
    } catch (e) {
      AppLogger.debug('[AttributeTableDialogs] カラム追加エラー: $e');
      _notify(ref, 'カラム追加に失敗しました: $e', NotificationLevel.error);
    }
  }
}

/// フィルタ結果のフィーチャ複製ダイアログ
Future<void> showDuplicateFilteredDialog(
  BuildContext context,
  LayerNode layer,
  String filterSql,
  VoidCallback onDuplicated, {
  WidgetRef? ref,
}) async {
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
                _notify(ref, 'レイヤ名を入力してください', NotificationLevel.warning);
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

      await gpkgFile.addLayer(result, geomType ?? GeometryType.point);

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

      final copiedCount = await gpkgFile.duplicateFilteredFeatures(
        layer.layerName,
        result,
        filterSql,
      );

      onDuplicated();
      _notify(
        ref,
        '$copiedCount件を「$result」にコピーしました',
        NotificationLevel.success,
      );
    } catch (e) {
      AppLogger.debug('[AttributeTableDialogs] フィルタ複製エラー: $e');
      _notify(ref, '複製に失敗しました: $e', NotificationLevel.error);
    }
  }
}

/// フィールド計算機ダイアログ
Future<void> showFieldCalculatorDialog(
  BuildContext context,
  LayerNode layer,
  List<String> columnNames,
  VoidCallback onUpdated, {
  WidgetRef? ref,
}) async {
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

      final validation = QgisExpressionFilter.toSqlWhere(expression);
      if (validation is FilterResultError) {
        _notify(ref, '式エラー: ${validation.message}', NotificationLevel.error);
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
      _notify(ref, '$updatedCount件を更新しました（$target）', NotificationLevel.success);
    } catch (e) {
      AppLogger.debug('[FieldCalculator] エラー: $e');
      _notify(ref, 'フィールド計算エラー: $e', NotificationLevel.error);
    }
  }
}

/// カラムリネームダイアログ
Future<void> showRenameColumnDialog(
  BuildContext context,
  LayerNode layer,
  String currentName,
  VoidCallback onRenamed, {
  WidgetRef? ref,
}) async {
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
      _notify(
        ref,
        'カラム名を「$currentName」→「$newName」に変更しました',
        NotificationLevel.success,
      );
    } catch (e) {
      AppLogger.debug('[RenameColumn] エラー: $e');
      _notify(ref, 'カラム名変更エラー: $e', NotificationLevel.error);
    }
  }
}

/// カラム削除確認ダイアログ
Future<void> showDeleteColumnDialog(
  BuildContext context,
  LayerNode layer,
  String columnName,
  VoidCallback onDeleted, {
  WidgetRef? ref,
}) async {
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
      _notify(ref, 'カラム「$columnName」を削除しました', NotificationLevel.success);
    } catch (e) {
      AppLogger.debug('[DeleteColumn] エラー: $e');
      _notify(ref, 'カラム削除エラー: $e', NotificationLevel.error);
    }
  }
}
