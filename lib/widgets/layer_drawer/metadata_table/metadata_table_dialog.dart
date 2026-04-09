/// K-MAPS: メタデータテーブル表示ダイアログ
library;

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import '../../../i18n/strings.g.dart';
import '../../../models/app_notification.dart';
import '../../../providers/notification_providers.dart';
import '../../../providers/project_providers.dart';
import '../../../utils/metadata_parser.dart';

class MetadataTableDialog extends ConsumerStatefulWidget {
  final MetadataTableData tableData;
  final String gpkgName;
  final String layerName;
  final String featureName;
  final LatLng? featureLatLng;

  const MetadataTableDialog({
    super.key,
    required this.tableData,
    required this.gpkgName,
    required this.layerName,
    required this.featureName,
    this.featureLatLng,
  });

  @override
  ConsumerState<MetadataTableDialog> createState() => _MetadataTableDialogState();
}

class _MetadataTableDialogState extends ConsumerState<MetadataTableDialog> {
  late MetadataTableData currentTableData;

  @override
  void initState() {
    super.initState();
    currentTableData = widget.tableData;
  }

  /// 座標系を変更
  Future<void> _changeCoordinateSystem(String newEpsgCode) async {
    if (widget.featureLatLng == null) return;

    try {
      final newTableData = await MetadataParser.recalculateXYCoordinates(
        currentTableData,
        widget.featureLatLng!,
        newEpsgCode,
      );

      setState(() {
        currentTableData = newTableData;
      });
    } catch (e) {
      if (mounted) {
        ref.read(notificationCenterProvider.notifier).add(
          title: t.metadata.coordinateChangeFailed(error: '$e'),
          level: NotificationLevel.error,
        );
      }
    }
  }

  /// メタデータテーブルのTSVエクスポート処理
  Future<void> _exportMetadataToTSV(BuildContext context) async {
    try {
      // プロジェクトルートディレクトリを取得
      final projectRoot = ref.read(projectRootDirProvider);
      if (projectRoot == null) {
        ref.read(notificationCenterProvider.notifier).add(
          title: t.metadata.projectRootNotFound,
          level: NotificationLevel.error,
        );
        return;
      }

      // ファイル名を生成（指定された形式に変更）
      final safeGpkgName = widget.gpkgName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '_',
      );
      final safeLayerName = widget.layerName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '_',
      );
      final safeFeatureName = widget.featureName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '_',
      );
      final tsvFileName =
          '${safeGpkgName}_${safeLayerName}_${safeFeatureName}_metadata_table.tsv';
      final tsvPath = p.join(projectRoot, tsvFileName);

      // TSVファイルを作成
      final tsvFile = File(tsvPath);
      final sink = tsvFile.openWrite();

      // ヘッダー行を書き込み
      final headerLine = currentTableData.headers
          .map(_escapeTsvField)
          .join('\t');
      sink.writeln(headerLine);

      // データ行を書き込み
      for (final row in currentTableData.rows) {
        final escapedRow = row.map(_escapeTsvField).join('\t');
        sink.writeln(escapedRow);
      }

      await sink.close();

      ref.read(notificationCenterProvider.notifier).add(
        title: t.metadata.tsvExported(name: tsvFileName),
        level: NotificationLevel.success,
      );
    } catch (e) {
      ref.read(notificationCenterProvider.notifier).add(
        title: t.metadata.tsvExportFailed(error: '$e'),
        level: NotificationLevel.error,
      );
    }
  }

  /// TSV用フィールドエスケープ処理
  String _escapeTsvField(String field) {
    // タブ、改行、復帰文字を置換してエスケープ
    return field
        .replaceAll('\t', ' ') // タブをスペースに置換
        .replaceAll('\n', ' ') // 改行をスペースに置換
        .replaceAll('\r', ' '); // 復帰文字をスペースに置換
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(currentTableData.title)),
          // 座標系選択ドロップダウン（座標系選択肢がある場合のみ表示）
          if (currentTableData.coordinateSystemOptions != null &&
              currentTableData.coordinateSystemOptions!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: DropdownButton<String>(
                value: currentTableData.selectedCoordinateSystem,
                hint: Text(t.metadata.coordinateSystem),
                items:
                    currentTableData.coordinateSystemOptions!.entries
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(
                              entry.value,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        )
                        .toList(),
                onChanged: (String? newValue) {
                  if (newValue != null &&
                      newValue != currentTableData.selectedCoordinateSystem) {
                    _changeCoordinateSystem(newValue);
                  }
                },
              ),
            ),
          IconButton(
            icon: const Icon(Icons.file_download),
            tooltip: t.metadata.tsvExport,
            onPressed: () => _exportMetadataToTSV(context),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              border: TableBorder.all(color: Colors.grey.shade300, width: 1),
              columns:
                  currentTableData.headers
                      .map((header) => DataColumn(label: Text(header)))
                      .toList(),
              rows:
                  currentTableData.rows
                      .map(
                        (row) => DataRow(
                          cells:
                              row
                                  .map(
                                    (cell) => DataCell(
                                      SelectableText(
                                        cell,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  )
                                  .toList(),
                        ),
                      )
                      .toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(t.common.close),
        ),
      ],
    );
  }
}

