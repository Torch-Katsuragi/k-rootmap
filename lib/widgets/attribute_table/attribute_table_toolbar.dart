// K-MAPS: 属性テーブルツールバー
// 座標系選択、各種操作ボタンを提供

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/coordinate/index.dart';
import '../../utils/app_logger.dart';
import 'attribute_table_controller.dart';

/// 属性テーブルツールバー
class AttributeTableToolbar extends StatelessWidget {
  final AttributeTableController controller;
  final VoidCallback? onRefresh;
  final VoidCallback? onCopyTable;
  final VoidCallback? onAddFeature;
  final VoidCallback? onDeleteSelected;
  final VoidCallback? onSave;
  final VoidCallback? onAddColumn;

  const AttributeTableToolbar({
    super.key,
    required this.controller,
    this.onRefresh,
    this.onCopyTable,
    this.onAddFeature,
    this.onDeleteSelected,
    this.onSave,
    this.onAddColumn,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // レイヤー名とフィーチャ数
          Text(
            '${controller.layer.layerName} (${controller.features.length})',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 9,
              height: 1.0,
            ),
          ),

          // Pointレイヤーの場合のみ座標オプション表示
          if (controller.isPointLayer) ...[
            const SizedBox(width: 8),
            _buildWgs84Checkbox(context),
            const SizedBox(width: 8),
            _buildEpsgSelector(context),
          ],

          const Spacer(),

          // 操作ボタン群
          _buildIconButton(Icons.add_box, Colors.blue, onAddColumn, 'カラム追加'),
          _buildIconButton(Icons.refresh, null, onRefresh, '更新'),
          _buildIconButton(Icons.copy, null, onCopyTable, 'テーブルをコピー'),
          if (onAddFeature != null)
            _buildIconButton(Icons.add, null, onAddFeature, 'フィーチャ追加'),
          _buildIconButton(Icons.delete, Colors.red, onDeleteSelected, '選択フィーチャ削除'),
          _buildIconButton(Icons.save, null, onSave, '即座に保存'),
        ],
      ),
    );
  }

  Widget _buildWgs84Checkbox(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: Checkbox(
              value: controller.settings.showWgs84,
              onChanged: (value) {
                controller.updateSettings(
                  controller.settings.copyWith(showWgs84: value ?? true),
                );
              },
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Text('WGS84', style: TextStyle(fontSize: 9)),
        ],
      ),
    );
  }

  Widget _buildEpsgSelector(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 22,
      child: _EpsgAutocomplete(
        initialValue: controller.settings.additionalEpsg,
        onSelected: (epsg) {
          controller.updateSettings(
            controller.settings.copyWith(additionalEpsg: epsg),
          );
        },
        onCleared: () {
          controller.updateSettings(
            controller.settings.copyWith(clearAdditionalEpsg: true),
          );
        },
      ),
    );
  }

  Widget _buildIconButton(
    IconData icon,
    Color? color,
    VoidCallback? onPressed,
    String tooltip,
  ) {
    return SizedBox(
      width: 20,
      height: 20,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 12,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
        tooltip: tooltip,
      ),
    );
  }
}

/// EPSG座標系オートコンプリート
class _EpsgAutocomplete extends StatefulWidget {
  final EpsgDefinition? initialValue;
  final ValueChanged<EpsgDefinition> onSelected;
  final VoidCallback onCleared;

  const _EpsgAutocomplete({
    this.initialValue,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  State<_EpsgAutocomplete> createState() => _EpsgAutocompleteState();
}

class _EpsgAutocompleteState extends State<_EpsgAutocomplete> {
  final _registry = EpsgRegistry.instance;
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue?.displayString ?? '',
    );
  }

  @override
  void didUpdateWidget(_EpsgAutocomplete oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue) {
      _controller.text = widget.initialValue?.displayString ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<EpsgDefinition>(
      initialValue: TextEditingValue(text: _controller.text),
      optionsBuilder: (TextEditingValue value) {
        return _registry.search(value.text);
      },
      displayStringForOption: (option) => option.displayString,
      onSelected: (selection) {
        _controller.text = selection.displayString;
        widget.onSelected(selection);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          style: const TextStyle(fontSize: 8, height: 1.0),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            border: const OutlineInputBorder(),
            isDense: true,
            hintText: 'EPSG (例: 6677, IX系)',
            hintStyle: const TextStyle(fontSize: 8),
            suffixIcon: widget.initialValue != null
                ? GestureDetector(
                    onTap: () {
                      controller.clear();
                      widget.onCleared();
                    },
                    child: const Icon(Icons.clear, size: 12),
                  )
                : null,
          ),
          onSubmitted: (value) {
            final code = value.split(' ').first.trim();
            if (code.isNotEmpty) {
              final epsg = _registry.getByCode(code);
              if (epsg != null) {
                widget.onSelected(epsg);
              }
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 380),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        option.displayString,
                        style: const TextStyle(fontSize: 9),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

/// テーブルをTSV形式でクリップボードにコピー
Future<void> copyTableToClipboard(
  BuildContext context,
  AttributeTableController controller,
) async {
  try {
    final buffer = StringBuffer();

    // ヘッダー行
    final headerNames = controller.columns.map((c) => _escapeTsvValue(c.title)).toList();
    buffer.writeln(headerNames.join('\t'));

    // データ行
    for (final row in controller.rows) {
      final rowValues = <String>[];
      for (final column in controller.columns) {
        final cell = row.cells[column.field];
        final value = cell?.value?.toString() ?? '';
        rowValues.add(_escapeTsvValue(value));
      }
      buffer.writeln(rowValues.join('\t'));
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${controller.rows.length}行をクリップボードにコピーしました'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    AppLogger.debug('[AttributeTableToolbar] クリップボードコピーエラー: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('コピーエラー: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

String _escapeTsvValue(String value) {
  if (value.contains('\n') || value.contains('\t') || value.contains('"')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
