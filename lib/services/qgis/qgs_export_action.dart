// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
/// 「QGISプロジェクトを書き出す」を呼ぶ側の共通処理。
///
/// UI からは複数箇所（フォルダのメニュー・地図の ≡ メニュー）から呼ばれるので、
/// 通知の出し方をここに1つだけ置く。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/strings.g.dart';
import '../../models/app_notification.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../providers/notification_providers.dart';
import '../../providers/ui_state_providers.dart';
import '../../utils/app_logger.dart';
import '../../core/fs/k_file_system.dart';
import 'qgs_importer.dart';
import 'qgs_project_builder.dart';
import 'qgs_writer.dart';

/// [node]（フォルダ）以下を `project.qgs` として書き出し、結果を通知する。
///
/// > [!IMPORTANT] 捨てたものは必ず報告する
/// > 画像レイヤやフォルダ外を参照する `.gpkg` は `.qgs` に書けない。
/// > 黙って落とすと「QGISで開いたら何か足りない」になるので、必ず出す。
Future<void> exportQgsProject(WidgetRef ref, LayerTreeNode? node) async {
  final notifier = ref.read(notificationCenterProvider.notifier);

  // ルートは必ずフォルダ。プロジェクト未オープンなら null が来る。
  if (node is! FolderNode) {
    notifier.add(title: t.qgis.noProject, level: NotificationLevel.warning);
    return;
  }
  final root = node;

  notifier.add(title: t.qgis.writing, level: NotificationLevel.info);

  try {
    const builder = QgsProjectBuilder();
    final project = await builder.build(root);
    final path = await builder.writeTo(root, project: project);
    if (path == null) {
      notifier.add(
        title: t.qgis.writeFailed,
        level: NotificationLevel.error,
      );
      return;
    }

    notifier.add(
      title: t.qgis.written(count: project.layers.length),
      level: NotificationLevel.success,
    );

    if (project.skipped.isNotEmpty) {
      notifier.add(
        title: t.qgis.skipped(
          count: project.skipped.length,
          names: project.skipped.join(' / '),
        ),
        level: NotificationLevel.warning,
      );
    }
  } catch (e) {
    AppLogger.debug('[QGIS] 書き出しに失敗: $e');
    notifier.add(
      title: '${t.qgis.writeFailed}: $e',
      level: NotificationLevel.error,
    );
  }
}

/// [node]（フォルダ）の中の `.qgs` を読み、View として取り込む。
///
/// ファイル選択ダイアログは出さない。**共有の単位は dir** なので、
/// 「このフォルダの中の `.qgs`」だけを相手にすればよい。
/// 複数あれば `project.qgs` を優先し、無ければ名前順の先頭を使う。
Future<void> importQgsProject(WidgetRef ref, LayerTreeNode? node) async {
  final notifier = ref.read(notificationCenterProvider.notifier);

  if (node is! FolderNode) {
    notifier.add(title: t.qgis.noProject, level: NotificationLevel.warning);
    return;
  }
  final folderPath = node.getAbsoluteFilePath();
  if (folderPath == null) {
    notifier.add(title: t.qgis.noProject, level: NotificationLevel.warning);
    return;
  }

  try {
    final candidates =
        (await fs.list(folderPath))
            .where((e) => !e.isDirectory && e.name.toLowerCase().endsWith('.qgs'))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    if (candidates.isEmpty) {
      notifier.add(title: t.qgis.notFound, level: NotificationLevel.warning);
      return;
    }
    final target = candidates.firstWhere(
      (e) => e.name == kQgsFileName,
      orElse: () => candidates.first,
    );

    notifier.add(title: t.qgis.importing, level: NotificationLevel.info);

    final result = await const QgsImporter().import(target.path, node);

    if (result.isEmpty) {
      notifier.add(
        title: t.qgis.importedNothing(file: target.name),
        level: NotificationLevel.warning,
      );
    } else {
      notifier.add(
        title: t.qgis.imported(
          file: target.name,
          count: result.importedViewCount,
        ),
        level: NotificationLevel.success,
      );
      ref.read(featureRefreshTriggerProvider.notifier).trigger();
    }

    // ⚠ 捨てたものは必ず出す。黙って落とすと
    //    「QGISでは見えていたのに」になって、原因を追えなくなる
    if (result.discarded.isNotEmpty) {
      notifier.add(
        title: t.qgis.discarded(
          count: result.discarded.length,
          names: result.discarded.join(' / '),
        ),
        level: NotificationLevel.warning,
      );
    }
  } catch (e) {
    AppLogger.debug('[QGIS] 読み込みに失敗: $e');
    notifier.add(
      title: '${t.qgis.importFailed}: $e',
      level: NotificationLevel.error,
    );
  }
}
