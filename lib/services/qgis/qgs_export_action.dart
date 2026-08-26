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
import '../../utils/app_logger.dart';
import 'qgs_project_builder.dart';

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
