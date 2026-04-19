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
/// フィーチャ編集アクションの抽象インタフェース
///
/// 各ジオメトリ操作（簡略化・切り取り等）はこのクラスを実装する。
/// FeatureEditorScreen はこのインタフェースだけに依存し、
/// 具象アクション / 具象FeatureNode型を知らなくてよい。
library;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../models/nodes/feature_node.dart';

/// アクションが地図上に表示するポリラインデータ
class PreviewLines {
  final List<LatLng> backgroundLine;
  final List<LatLng> foregroundLine;
  const PreviewLines({
    required this.backgroundLine,
    required this.foregroundLine,
  });

  static const empty = PreviewLines(backgroundLine: [], foregroundLine: []);
}

abstract class FeatureEditAction {
  /// タブに表示するラベル
  String get label;

  /// タブに表示するアイコン
  IconData get icon;

  /// このアクションが対象フィーチャに適用可能か
  bool canApplyTo(FeatureNode feature);

  /// コントロールUIのみを構築（プレビュー地図は Screen 側で表示）
  /// [previewLines] を更新すると地図上のポリラインが変わる
  Widget buildControls(
    BuildContext context,
    FeatureNode feature,
    ValueNotifier<PreviewLines> previewLines,
  );
}
