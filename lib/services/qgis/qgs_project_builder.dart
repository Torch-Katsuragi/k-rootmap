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
/// レイヤツリーを辿って [QgsProject] を組み立て、`.qgs` として書き出す。
///
/// > [!IMPORTANT] 書き出す単位は「dir」
/// > Drive連携は**プロジェクト単位ではなくフォルダ単位**なので、
/// > `.qgs` も連携dirごとに置く。そのdirを単体で渡された人が、
/// > そのdirだけで開けるべきだから。パスも相対で書く。
///
/// > [!WARNING] root外は書かない
/// > 相対パスで外に出るデータソースは、渡された相手の環境には無い。
/// > 対象は「このdirの下にある `.gpkg`」だけ。
library;

import 'package:path/path.dart' as p;

import '../../core/fs/k_file_system.dart';
import '../../models/geometry_type.dart';
import '../../models/kmeta.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/view_node.dart';
import '../../utils/app_logger.dart';
import '../coordinate/gpkg_crs_resolver.dart';
import 'qgs_model.dart';
import 'qgs_writer.dart';

class QgsProjectBuilder {
  const QgsProjectBuilder();

  /// [root] 以下を `.qgs` の内容に組み立てる。
  ///
  /// [root] 自身はグループにしない（プロジェクトのルートそのものなので）。
  Future<QgsProject> build(FolderNode root) async {
    final rootPath = root.getAbsoluteFilePath();
    final skipped = <String>[];

    final children = <QgsTreeNode>[];
    for (final child in root.children) {
      final node = await _convert(child, rootPath, skipped);
      if (node != null) children.add(node);
    }

    return QgsProject(name: _projectName(root, rootPath), root: children, skipped: skipped);
  }

  /// プロジェクト名。
  ///
  /// ⚠ ルートの [FolderNode.name] は "Home" 固定なので使えない。
  /// 実際のフォルダ名（パスの末尾）を採る。
  String _projectName(FolderNode root, String? rootPath) {
    if (rootPath == null) return root.name;
    final base = p.basename(p.normalize(rootPath));
    return base.isEmpty ? root.name : base;
  }

  /// [root] のフォルダに `project.qgs` を書く。
  ///
  /// [project] を渡さなければその場で組み立てる。
  /// 呼び出し側が除外リストを見たい場合は、先に [build] して渡すこと。
  ///
  /// 戻り値は書いたファイルのパス。書けなければ null。
  Future<String?> writeTo(FolderNode root, {QgsProject? project}) async {
    final rootPath = root.getAbsoluteFilePath();
    if (rootPath == null) {
      AppLogger.debug('[QgsProjectBuilder] ルートのパスを解決できない');
      return null;
    }

    final built = project ?? await build(root);
    final xml = const QgsWriter().build(built);
    final path = p.join(rootPath, kQgsFileName);
    await fs.writeAsString(path, xml);
    AppLogger.debug(
      '[QgsProjectBuilder] $path に ${built.layers.length} レイヤを書いた'
      '（除外 ${built.skipped.length} 件）',
    );
    return path;
  }

  // =============================================
  // ノードの変換
  // =============================================

  Future<QgsTreeNode?> _convert(
    LayerTreeNode node,
    String? rootPath,
    List<String> skipped,
  ) async {
    if (node is FolderNode) return _convertFolder(node, rootPath, skipped);
    if (node is GeoPackageNode) {
      return _convertGeoPackage(node, rootPath, skipped);
    }

    // 画像・オーバーレイは QGIS のラスタレイヤに落とせるが、まだ対応していない。
    // 黙って落とさず、必ず報告する。
    skipped.add('${node.name}（${node.nodeType.displayName}は未対応）');
    return null;
  }

  Future<QgsTreeNode?> _convertFolder(
    FolderNode folder,
    String? rootPath,
    List<String> skipped,
  ) async {
    final children = <QgsTreeNode>[];
    for (final child in folder.children) {
      final converted = await _convert(child, rootPath, skipped);
      if (converted != null) children.add(converted);
    }
    if (children.isEmpty) return null;
    return QgsGroup(
      name: folder.name,
      children: children,
      visible: folder.visible,
    );
  }

  Future<QgsTreeNode?> _convertGeoPackage(
    GeoPackageNode gpkg,
    String? rootPath,
    List<String> skipped,
  ) async {
    final absPath = gpkg.geoPackageFile.getAbsolutePath();
    final relPath = _relativeTo(rootPath, absPath);
    if (relPath == null) {
      // root外を指すgpkg。渡された相手の環境には無いので書かない。
      skipped.add('${gpkg.name}（プロジェクトフォルダの外を参照している）');
      return null;
    }

    final groups = <QgsTreeNode>[];
    for (final layer in gpkg.children.whereType<LayerNode>()) {
      final group = await _convertLayer(layer, relPath, skipped);
      if (group != null) groups.add(group);
    }
    if (groups.isEmpty) return null;

    return QgsGroup(
      name: gpkg.name,
      children: groups,
      visible: gpkg.visible,
    );
  }

  /// Layer は**グループ**になり、その下の View が QGIS のレイヤになる。
  Future<QgsTreeNode?> _convertLayer(
    LayerNode layer,
    String gpkgRelPath,
    List<String> skipped,
  ) async {
    final geometryType = _geometryTypeOf(layer);
    if (geometryType == null) {
      skipped.add('${layer.layerName}（ジオメトリ種別が分からない）');
      return null;
    }

    if (layer.views.isEmpty) await layer.loadViews();
    final crs = await _crsOf(layer);
    final layerStyle = await layer.getKmetaStyle();

    final qgsLayers = <QgsTreeNode>[
      for (final view in layer.views)
        QgsLayer(
          id: _layerId(view),
          name: view.name,
          dataSourcePath: gpkgRelPath,
          tableName: layer.layerName,
          geometryType: geometryType,
          crs: crs,
          subset: view.filter,
          // View に指定が無ければレイヤのスタイルに落ちる
          style: _toQgsStyle(view.style ?? layerStyle),
          visible: view.visible,
        ),
    ];
    if (qgsLayers.isEmpty) return null;

    return QgsGroup(
      name: layer.layerName,
      children: qgsLayers,
      visible: layer.visible,
    );
  }

  // =============================================
  // 部品
  // =============================================

  /// `.qgs` から見た相対パス。root外を指していたら null。
  ///
  /// ⚠ 判定は**正規化した絶対パス**で行う。`../shared/kyoyu.gpkg` のように
  /// 相対で外に出るケースが林業では現実にありそうなので、素朴な文字列比較では足りない。
  String? _relativeTo(String? rootPath, String? absPath) {
    if (rootPath == null || absPath == null) return null;
    final root = p.normalize(rootPath);
    final target = p.normalize(absPath);
    final rel = p.relative(target, from: root);
    if (rel.startsWith('..') || p.isAbsolute(rel)) return null;
    // QGIS は `./` 始まりを相対パスとして扱う。区切りは常に `/`
    return './${rel.replaceAll(r'\', '/')}';
  }

  /// View の一意ID。
  ///
  /// **決定的に作る。** 生成のたびに変わると `.qgs` の差分が毎回出て、
  /// Drive同期が無駄に動く。QGIS は中身を問わず「一意な文字列」としか見ない。
  String _layerId(ViewNode view) {
    final sanitized = view.viewKey.replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    // 非ASCIIを潰すと衝突しうるので、元のキーのハッシュを添える
    final hash = view.viewKey.hashCode.toUnsigned(32).toRadixString(16);
    return '${sanitized}_$hash';
  }

  GeometryType? _geometryTypeOf(LayerNode layer) {
    if (layer is PointLayerNode) return GeometryType.point;
    if (layer is LineLayerNode) return GeometryType.linestring;
    if (layer is PolygonLayerNode) return GeometryType.polygon;
    return null;
  }

  Future<QgsCrs> _crsOf(LayerNode layer) async {
    try {
      final db = await layer.geoPackageFile.getDatabase();
      final crs = await GpkgCrsResolver.instance.resolveLayerCrs(
        db,
        layer.layerName,
      );
      return QgsCrs(
        authId: crs.epsgCode,
        srid: crs.srsId,
        description: crs.name,
        wkt: crs.definitionWkt,
        proj4: crs.proj4String,
        isGeographic: crs.isWgs84,
      );
    } catch (e) {
      // 解決できなければWGS84として書く。gpkg側に正しい定義があるので
      // QGIS は開いた時点で直せる（間違ったsrsidを書き込むよりまし）。
      AppLogger.debug('[QgsProjectBuilder] CRSを解決できない: $e');
      return QgsCrs.wgs84;
    }
  }

  QgsStyle? _toQgsStyle(KMetaLayerStyle? style) {
    if (style == null) return null;
    final converted = QgsStyle(
      pointColor: style.pointColor,
      pointSizePx: style.pointSize,
      lineColor: style.lineColor,
      lineWidthPx: style.lineWidth,
      fillColor: style.polygonFillColor,
      fillOpacity: style.polygonFillOpacity,
      strokeColor: style.polygonBorderColor,
      strokeWidthPx: style.polygonBorderWidth,
      strokeOpacity: style.polygonBorderOpacity,
    );
    return converted.isEmpty ? null : converted;
  }
}
