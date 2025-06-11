/// K-MAPS: レイヤ構造Drawerウィジェット
/// プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示し、
/// 可視切り替え・リネーム・削除などの操作を提供するUI。
library;

import 'dart:io';
import 'dart:convert'; // JSON処理のため追加
import 'package:flutter/material.dart';
import 'package:k_maps/utils/global_config.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
// import '../utils/meta_data.dart' as meta_util;
import 'package:collection/collection.dart';
import '../models/layer_tree_node.dart';
import '../models/geopackage_file.dart';
import '../models/geometry_type.dart'; // ジオメトリタイプenumをインポート
import '../utils/metadata_parser.dart'; // メタデータパーサーをインポート

/// レイヤ構造Drawer（最小構成＋レイヤ追加・削除）
/// GeoPackageノードはタップでレイヤリストをトグル展開
class LayerDrawer extends StatefulWidget {
  final LayerTreeNode? currentNode;
  final void Function(LayerTreeNode? newNode) onDirChanged;
  final void Function(void Function()) setStateCallback;

  /// 地図ジャンプ用コールバック（中心座標に移動）
  final void Function(LatLng latLng)? onJumpTo;

  /// LayerDrawerコンストラクタ
  const LayerDrawer({
    super.key,
    required this.currentNode,
    required this.onDirChanged,
    required this.setStateCallback,
    this.onJumpTo,
  });

  @override
  State<LayerDrawer> createState() => _LayerDrawerState();
}

class _LayerDrawerState extends State<LayerDrawer> {
  /// 展開中のGeoPackageノードのファイルパスを保持
  final Set<String> expandedGpkgPaths = {};

  // 属性テーブル表示中かどうか・どのLayerNodeか
  LayerNode? attributeTableLayerNode;

  /// 初回の自動展開が完了したかを追跡
  bool _hasPerformedInitialExpansion = false;

  /// ユーザーが明示的に閉じたGeoPackageノードのパスを記録
  final Set<String> _userClosedGpkgPaths = {};

  @override
  void initState() {
    super.initState();
    // デフォルトで全gpkgノードを展開状態に
    _expandAllGeoPackageNodes();
    _hasPerformedInitialExpansion = true;
  }

  @override
  void didUpdateWidget(LayerDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // currentNodeが変更された場合のみ自動展開（新しいディレクトリに移動した場合）
    if (oldWidget.currentNode != widget.currentNode) {
      _userClosedGpkgPaths.clear(); // 新しいディレクトリでは閉じた履歴をリセット
      _expandAllGeoPackageNodes();
      _hasPerformedInitialExpansion = true;
    }
  }

  /// 現在のノードの全GeoPackage子ノードを展開状態に設定
  void _expandAllGeoPackageNodes() {
    final node = widget.currentNode;
    if (node != null) {
      for (final child in node.children) {
        if (child is GeoPackageNode) {
          final absPath = child.geoPackageFile.getAbsolutePath();
          if (absPath != null) expandedGpkgPaths.add(absPath);
        }
      }
    }
  }

  /// 新規追加されたGeoPackageノードのみを自動展開（ユーザーが閉じたものは除く）
  void _expandNewGeoPackageNodesOnly() {
    final node = widget.currentNode;
    if (node != null) {
      for (final child in node.children) {
        if (child is GeoPackageNode) {
          final absPath = child.geoPackageFile.getAbsolutePath();
          // まだ展開状態の管理対象になっていない かつ ユーザーが閉じていないノードのみ展開
          if (absPath != null &&
              !expandedGpkgPaths.contains(absPath) &&
              !_userClosedGpkgPaths.contains(absPath)) {
            expandedGpkgPaths.add(absPath);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentNode == null) {
      return const Center(child: Text('ディレクトリが見つかりません'));
    }

    // 新しいGeoPackageノードが追加されていれば自動展開（ユーザーが閉じたものは除く）
    _expandNewGeoPackageNodesOnly();

    // 属性テーブル表示中ならそちらを表示
    if (attributeTableLayerNode != null) {
      return AttributeTablePanel(
        layerNode: attributeTableLayerNode!,
        onBack: () {
          setState(() {
            attributeTableLayerNode = null;
          });
        },
        onJumpTo: widget.onJumpTo,
      );
    }
    return Column(
      children: [
        LayerDrawerTitleBar(
          title: widget.currentNode!.name,
          currentNode: widget.currentNode!,
          onAddFolder:
              widget.currentNode is FolderNode
                  ? () async {
                    String input = '';
                    final result = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('新規サブフォルダ'),
                          content: TextField(
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'フォルダ名',
                            ),
                            onChanged: (v) => input = v,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, input),
                              child: const Text('作成'),
                            ),
                          ],
                        );
                      },
                    );
                    if (result != null && result.isNotEmpty) {
                      final folderNode = widget.currentNode as FolderNode;
                      final dir = folderNode.getAbsoluteFilePath();
                      final path = p.join(dir ?? '', result);
                      if (Directory(path).existsSync()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('同名のフォルダが既に存在します')),
                        );
                        return;
                      }
                      Directory(path).createSync();
                      folderNode.addChild(
                        FolderNode(result, visible: true, parent: folderNode),
                      );
                      widget.setStateCallback(() {});
                    }
                  }
                  : null,
          onAddGeoPackage:
              widget.currentNode is FolderNode
                  ? () async {
                    String input = '';
                    final result = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return AlertDialog(
                          title: const Text('新規GeoPackageファイル'),
                          content: TextField(
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: 'ファイル名（.gpkg）',
                            ),
                            onChanged: (v) => input = v,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, null),
                              child: const Text('キャンセル'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, input),
                              child: const Text('作成'),
                            ),
                          ],
                        );
                      },
                    );
                    if (result != null && result.isNotEmpty) {
                      print('[LayerDrawer] GeoPackage作成開始: $result');

                      final folderNode = widget.currentNode as FolderNode;
                      final dir = folderNode.getAbsoluteFilePath();
                      final fileName =
                          result.endsWith('.gpkg') ? result : '$result.gpkg';
                      final path = p.join(dir ?? '', fileName);

                      print('[LayerDrawer] 作成予定パス: $path');
                      print('[LayerDrawer] 親ディレクトリ: $dir');

                      if (File(path).existsSync()) {
                        print('[LayerDrawer] 同名ファイルが既に存在します');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('同名のGeoPackageファイルが既に存在します')),
                        );
                        return;
                      }

                      print('[LayerDrawer] GeoPackageNodeを作成中...');
                      final parentNode = widget.currentNode as FolderNode;
                      final parentPath = parentNode.getAbsolutePathSegments();
                      final fileNameList = [fileName];
                      final gpkgFile = GeoPackageFile([
                        ...parentPath,
                        ...fileNameList,
                      ]);

                      print(
                        '[LayerDrawer] GeoPackageFile作成: pathList=${gpkgFile.pathList}',
                      );

                      final newNode = GeoPackageNode(
                        gpkgFile,
                        visible: true,
                        parent: folderNode,
                      );
                      folderNode.addChild(newNode);

                      // 空のGeoPackageファイルを即座に作成
                      print('[LayerDrawer] 空のGeoPackageファイル作成中...');
                      final createSuccess =
                          await gpkgFile.createEmptyDatabase();
                      if (!createSuccess) {
                        print('[LayerDrawer] 空のGeoPackageファイル作成失敗');
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('GeoPackageファイルの作成に失敗しました')),
                        );
                        // 作成失敗時はノードを削除
                        folderNode.removeChild(newNode);
                        return;
                      }

                      // 新規作成されたGeoPackageを自動展開
                      final newAbsPath = gpkgFile.getAbsolutePath();
                      print('[LayerDrawer] 新規GeoPackage絶対パス: $newAbsPath');
                      if (newAbsPath != null) {
                        expandedGpkgPaths.add(newAbsPath);
                      }

                      print('[LayerDrawer] UI更新中...');
                      widget.setStateCallback(() {});
                      print('[LayerDrawer] GeoPackage作成完了');
                    }
                  }
                  : null,
          onBack:
              widget.currentNode!.parent != null
                  ? () => widget.onDirChanged(widget.currentNode!.parent)
                  : null,
        ),
        Expanded(
          child: ListView(
            children: [
              ...widget.currentNode!.children.map((node) {
                if (node is FolderNode) {
                  return _buildFolderTile(context, node);
                } else if (node is GeoPackageNode) {
                  return _buildGeoPackageTile(context, node);
                }
                // LayerNodeはここで描画しない
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFolderTile(BuildContext context, FolderNode node) => ListTile(
    leading: _buildIconWithVisibility(node),
    title: Text(node.name),
    onTap: () => widget.onDirChanged(node),
  );

  /// GeoPackageノードのタイル。タップでレイヤリストをトグル展開
  Widget _buildGeoPackageTile(BuildContext context, GeoPackageNode node) {
    final absPath = node.geoPackageFile.getAbsolutePath();
    final isExpanded = absPath != null && expandedGpkgPaths.contains(absPath);
    return Column(
      children: [
        ListTile(
          leading: _buildIconWithVisibility(node),
          title: Text(node.name),
          onTap: () {
            setState(() {
              if (isExpanded) {
                // 閉じる場合：展開リストから削除し、ユーザーが閉じたことを記録
                expandedGpkgPaths.remove(absPath);
                _userClosedGpkgPaths.add(absPath);
              } else {
                // 展開する場合：展開リストに追加し、ユーザーが閉じた記録を削除
                if (absPath != null) {
                  expandedGpkgPaths.add(absPath);
                  _userClosedGpkgPaths.remove(absPath);
                }
              }
            });
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // GeoPackageノードの右側に…メニュー（削除操作）を追加
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder:
                          (context) => AlertDialog(
                            title: const Text('GeoPackage削除'),
                            content: Text(
                              '${node.name} を本当に削除しますか？\nファイルも完全に削除されます。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('キャンセル'),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('削除'),
                              ),
                            ],
                          ),
                    );
                    if (confirm == true) {
                      try {
                        // geopackageノード削除（ファイルも含めて削除）
                        await node.dispose();
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('${node.name} を削除しました')),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('削除に失敗しました: $e')),
                        );
                      }
                    }
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(value: 'delete', child: Text('削除')),
                    ],
              ),
            ],
          ),
        ),
        if (isExpanded) ...[
          ...node.children.map(
            (layerNode) => _buildLayerTile(layerNode as LayerNode),
          ),
          // レイヤリストの最下部にレイヤ追加ボタンを表示
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
              child: _buildAddLayerButton(context, node),
            ),
          ),
        ],
      ],
    );
  }

  /// レイヤタイル（可視切り替え・選択・削除）
  Widget _buildLayerTile(LayerNode node) {
    final isSelected = GlobalConfig.instance.selectedLayerNode == node;
    return ListTile(
      // GeoPackageノード配下のレイヤはインデントして階層感を出す
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: GestureDetector(
        onTap: () {
          node.visible = !node.visible;
          // フィーチャ表示を更新
          if (GlobalConfig.instance.mapState != null) {
            GlobalConfig.instance.mapState.refreshFeatures();
          }
          widget.setStateCallback(() {});
        },
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color:
                    isSelected
                        ? Colors.blue.withOpacity(0.15)
                        : Colors.transparent,
              ),
              padding: const EdgeInsets.all(4),
              child: Icon(
                node.baseIcon,
                color:
                    isSelected
                        ? Colors.blue
                        : (node.isVisibleRecursive()
                            ? node.baseIconColor
                            : Colors.grey),
              ),
            ),
            if (!node.visible)
              Transform.rotate(
                angle: -0.7,
                child: Container(width: 32, height: 4, color: Colors.grey),
              ),
          ],
        ),
      ),
      title: Text(
        node.name,
        style: TextStyle(
          color:
              isSelected
                  ? Colors.blue
                  : (node.isVisibleRecursive() ? null : Colors.grey),
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () {
        GlobalConfig.instance.selectedLayerNode = node;
        widget.setStateCallback(() {});
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('レイヤ削除'),
                    content: Text('${node.name} を本当に削除しますか？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('キャンセル'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('削除'),
                      ),
                    ],
                  ),
            );
            if (confirm == true) {
              node.dispose();
              widget.setStateCallback(() {});
            }
          } else if (value == 'attributes') {
            setState(() {
              attributeTableLayerNode = node;
            });
          }
        },
        itemBuilder:
            (context) => [
              const PopupMenuItem(value: 'attributes', child: Text('属性テーブル')),
              const PopupMenuItem(value: 'delete', child: Text('削除')),
            ],
      ),
    );
  }

  /// 可視性アイコン（タップで可視切り替え）
  Widget _buildIconWithVisibility(LayerTreeNode node) => GestureDetector(
    onTap: () {
      node.visible = !node.visible;
      // フィーチャ表示を更新
      if (GlobalConfig.instance.mapState != null) {
        GlobalConfig.instance.mapState.refreshFeatures();
      }
      widget.setStateCallback(() {});
    },
    child: Stack(
      alignment: Alignment.center,
      children: [
        Icon(
          node.baseIcon,
          color: node.isVisibleRecursive() ? node.baseIconColor : Colors.grey,
        ),
        if (!node.visible)
          Transform.rotate(
            angle: -0.7,
            child: Container(width: 32, height: 4, color: Colors.grey),
          ),
      ],
    ),
  );

  /// レイヤ追加ボタン
  Widget _buildAddLayerButton(
    BuildContext context,
    GeoPackageNode node,
  ) => GestureDetector(
    onTap: () async {
      final result = await showDialog<Map<String, String>>(
        context: context,
        builder: (context) {
          String input = '';
          GeometryType geomType = GeometryType.point;
          return AlertDialog(
            title: const Text('新規レイヤ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'レイヤ名'),
                  onChanged: (v) => input = v,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<GeometryType>(
                  value: geomType,
                  decoration: const InputDecoration(labelText: 'ジオメトリタイプ'),
                  items: [
                    DropdownMenuItem(
                      value: GeometryType.point,
                      child: Text(GeometryType.point.displayName),
                    ),
                    DropdownMenuItem(
                      value: GeometryType.linestring,
                      child: Text(GeometryType.linestring.displayName),
                    ),
                    DropdownMenuItem(
                      value: GeometryType.polygon,
                      child: Text(GeometryType.polygon.displayName),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) geomType = v;
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed:
                    () => Navigator.pop(context, {
                      'name': input,
                      'geomType': geomType.value,
                    }),
                child: const Text('作成'),
              ),
            ],
          );
        },
      );
      if (result != null &&
          result['name'] != null &&
          result['name']!.isNotEmpty) {
        print(
          '[LayerDrawer] レイヤ作成開始: ${result['name']}, タイプ: ${result['geomType']}',
        );

        // ジオメトリタイプに応じて適切なLayerNodeサブクラスを生成
        LayerTreeNode? newLayerNode;
        final geomTypeString = result['geomType']!;
        final geomType = GeometryType.fromString(geomTypeString);

        print('[LayerDrawer] ジオメトリタイプ解析: $geomTypeString -> $geomType');

        try {
          switch (geomType) {
            case GeometryType.point:
              print('[LayerDrawer] PointLayerNode作成中...');
              newLayerNode = await PointLayerNode.createIn(
                node,
                result['name']!,
              );
              break;
            case GeometryType.linestring:
              print('[LayerDrawer] LineLayerNode作成中...');
              newLayerNode = await LineLayerNode.createIn(
                node,
                result['name']!,
              );
              break;
            case GeometryType.polygon:
              print('[LayerDrawer] PolygonLayerNode作成中...');
              newLayerNode = await PolygonLayerNode.createIn(
                node,
                result['name']!,
              );
              break;
            case null:
              print('[LayerDrawer] 不明なジオメトリタイプです');
              break;
          }

          if (newLayerNode != null) {
            print('[LayerDrawer] レイヤ作成成功、UI更新中...');
            // 追加成功時のみUI更新
            widget.setStateCallback(() {});
            // 地図本体も即時再描画
            if (GlobalConfig.instance.mapState != null) {
              GlobalConfig.instance.mapState.setState(() {});
            }
            print('[LayerDrawer] レイヤ作成完了');
          } else {
            print('[LayerDrawer] レイヤ作成失敗: newLayerNodeがnull');
          }
        } catch (e, stack) {
          print('[LayerDrawer] レイヤ作成エラー: $e');
          print('[LayerDrawer] スタックトレース: $stack');
        }
      }
    },
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: const [
        Icon(Icons.add, size: 24),
        SizedBox(width: 8),
        Text(
          'Add Layer',
          style: TextStyle(fontSize: 16, color: Colors.black87),
        ),
      ],
    ),
  );
}

/// 青いタイトルパネル（currentNodeの名前を表示＋右側に追加ボタン）
class LayerDrawerTitleBar extends StatelessWidget {
  final String title;
  final LayerTreeNode currentNode;
  final void Function()? onAddFolder;
  final void Function()? onAddGeoPackage;
  final void Function()? onBack;
  const LayerDrawerTitleBar({
    super.key,
    required this.title,
    required this.currentNode,
    this.onAddFolder,
    this.onAddGeoPackage,
    this.onBack,
  });

  /// アイコン右上に緑の+を合成するWidget（再利用可）
  static Widget buildAddIconOverlay(IconData baseIcon, Color baseColor) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(baseIcon, color: baseColor, size: 28),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add_circle, color: Colors.green, size: 16),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      color: Colors.blue,
      child: Row(
        children: [
          if (onBack != null)
            Padding(
              padding: const EdgeInsets.only(right: 8, left: 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.white,
                    size: 20,
                  ),
                  tooltip: '一つ上の階層に戻る',
                  onPressed: onBack,
                  padding: EdgeInsets.zero,
                  constraints: BoxConstraints(),
                ),
              ),
            ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (currentNode is FolderNode) ...[
            IconButton(
              tooltip: 'サブフォルダ追加',
              icon: buildAddIconOverlay(Icons.folder, Colors.amber),
              onPressed: onAddFolder,
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'GeoPackage追加',
              icon: buildAddIconOverlay(Icons.storage, Color(0xFFCFD8DC)),
              onPressed: onAddGeoPackage,
            ),
          ],
        ],
      ),
    );
  }
}

/// メタデータ表示ダイアログ
class MetadataTableDialog extends StatelessWidget {
  final MetadataTableData tableData;

  const MetadataTableDialog({super.key, required this.tableData});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tableData.title),
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
                  tableData.headers
                      .map((header) => DataColumn(label: Text(header)))
                      .toList(),
              rows:
                  tableData.rows
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
          child: const Text('閉じる'),
        ),
      ],
    );
  }
}

// GeoPackageFileの絶対パス取得用メソッドを追加
extension GeoPackageFilePathExt on GeoPackageFile {
  /// projectRootDir + pathList で絶対パスを返す
  String? getAbsolutePath() {
    final root = GlobalConfig.instance.projectRootDir;
    if (root == null) return null;
    return p.joinAll([root, ...pathList]);
  }
}

// 属性テーブル表示用パネルWidgetを追加
class AttributeTablePanel extends StatefulWidget {
  final LayerNode layerNode;
  final VoidCallback onBack;

  /// 地図ジャンプ用コールバック
  final void Function(LatLng latLng)? onJumpTo;
  const AttributeTablePanel({
    super.key,
    required this.layerNode,
    required this.onBack,
    this.onJumpTo,
  });

  @override
  State<AttributeTablePanel> createState() => _AttributeTablePanelState();
}

class _AttributeTablePanelState extends State<AttributeTablePanel> {
  // 編集中セル: rowId, カラム名
  int? editingRowId;
  String? editingColumn;
  String editingValue = '';
  bool showAllColumns = false;

  // スクロール位置保持用のコントローラー
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  // データキャッシュ用変数（不必要な再読み込みを防ぐ）
  List<String>? _cachedColumns;
  List<FeatureNode>? _cachedFeatures;
  bool _lastShowAllColumns = false;
  Future<List<dynamic>>? _dataFuture;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  /// メタデータダイアログを表示
  void _showMetadataDialog(BuildContext context, String metadataStr) {
    try {
      // デバッグ出力
      // print('[AttributeTable] メタデータ文字列: $metadataStr');

      // JSONパースを試行
      final metadataJson = jsonDecode(metadataStr) as Map<String, dynamic>;
      // print('[AttributeTable] JSONパース成功: $metadataJson');

      final tableData = MetadataParser.parseMetadata(metadataJson);
      // print('[AttributeTable] パース結果: $tableData');

      if (tableData != null) {
        showDialog(
          context: context,
          builder: (context) => MetadataTableDialog(tableData: tableData),
        );
      } else {
        _showRawMetadataDialog(context, metadataStr);
      }
    } catch (e) {
      print('[AttributeTable] メタデータJSONパースエラー: $e');
      _showRawMetadataDialog(context, metadataStr);
    }
  }

  /// 生のメタデータ文字列をダイアログで表示
  void _showRawMetadataDialog(BuildContext context, String metadataStr) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('メタデータ（生データ）'),
            content: SingleChildScrollView(child: Text(metadataStr)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
    );
  }

  /// データを取得または再利用（キャッシュ機能付き）
  Future<List<dynamic>> _getTableData() {
    // showAllColumnsが変更された場合は再読み込み
    if (_dataFuture == null || _lastShowAllColumns != showAllColumns) {
      _lastShowAllColumns = showAllColumns;
      _dataFuture = Future.wait([
        widget.layerNode.geoPackageFile.getColumnNames(
          widget.layerNode.layerName,
          getAll: showAllColumns,
        ),
        widget.layerNode.features,
      ]);
    }
    return _dataFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Colors.blue,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: Colors.white,
                  size: 20,
                ),
                tooltip: '戻る',
                onPressed: widget.onBack,
              ),
              Expanded(
                child: Text(
                  widget.layerNode.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  showAllColumns ? Icons.view_column : Icons.filter_alt,
                  color: Colors.white,
                ),
                tooltip: showAllColumns ? 'supported属性のみ表示' : '全カラム表示',
                onPressed: () {
                  setState(() {
                    showAllColumns = !showAllColumns;
                  });
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: _getTableData(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('エラー: ${snapshot.error}'));
              }
              if (!snapshot.hasData) {
                return const Center(child: Text('データが見つかりません'));
              }

              final columns = snapshot.data![0] as List<String>;
              final features = snapshot.data![1] as List<FeatureNode>;

              return SingleChildScrollView(
                controller: _verticalScrollController,
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  controller: _horizontalScrollController,
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    border: TableBorder.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                    columns: [
                      for (final col in columns) DataColumn(label: Text(col)),
                    ],
                    rows: [
                      for (final feature in features)
                        DataRow(
                          cells: [
                            for (final col in columns)
                              col == 'geom'
                                  ? DataCell(
                                    SizedBox(
                                      height: 28,
                                      child: TextButton(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 0,
                                          ),
                                          minimumSize: const Size(40, 28),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () {
                                          // geom選択時に地図ジャンプ
                                          if (widget.onJumpTo != null) {
                                            widget.onJumpTo!(feature.centroid);
                                          }
                                          // feature選択: selectedFeaturesにセット
                                          final wasSelected = GlobalConfig
                                              .instance
                                              .selectedFeatures
                                              .contains(feature);
                                          if (!wasSelected) {
                                            GlobalConfig
                                                .instance
                                                .selectedFeatures = [feature];
                                            // 地図本体のみ再描画（属性テーブルは再描画しない）
                                            if (GlobalConfig
                                                    .instance
                                                    .mapState !=
                                                null) {
                                              GlobalConfig.instance.mapState
                                                  .setState(() {});
                                            }
                                          }
                                        },
                                        child: const Text(
                                          '選択',
                                          style: TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ),
                                  )
                                  : col == 'id'
                                  ? DataCell(
                                    FutureBuilder<dynamic>(
                                      future: feature.getAttributeValue(col),
                                      builder: (context, attrSnapshot) {
                                        return Text(
                                          '${attrSnapshot.data ?? ''}',
                                        );
                                      },
                                    ),
                                  )
                                  : col == 'kmaps_metadata'
                                  ? DataCell(
                                    FutureBuilder<dynamic>(
                                      future: feature.getAttributeValue(col),
                                      builder: (context, attrSnapshot) {
                                        final metadataStr =
                                            attrSnapshot.data as String?;
                                        if (metadataStr == null ||
                                            metadataStr.isEmpty) {
                                          return const Text('');
                                        }

                                        return SizedBox(
                                          height: 28,
                                          child: TextButton(
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 0,
                                                  ),
                                              minimumSize: const Size(40, 28),
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            onPressed: () {
                                              _showMetadataDialog(
                                                context,
                                                metadataStr,
                                              );
                                            },
                                            child: const Text(
                                              '表示',
                                              style: TextStyle(fontSize: 13),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                  : (editingRowId == feature.rowId &&
                                      editingColumn == col)
                                  ? DataCell(
                                    SizedBox(
                                      width: 120,
                                      child: TextField(
                                        autofocus: true,
                                        controller: TextEditingController(
                                            text: editingValue,
                                          )
                                          ..selection = TextSelection.collapsed(
                                            offset: editingValue.length,
                                          ),
                                        onChanged: (v) {
                                          setState(() {
                                            editingValue = v;
                                          });
                                        },
                                        onSubmitted: (v) {
                                          feature.editAttribute(col, v);
                                          setState(() {
                                            editingRowId = null;
                                            editingColumn = null;
                                          });
                                        },
                                        onEditingComplete: () {
                                          feature.editAttribute(
                                            col,
                                            editingValue,
                                          );
                                          setState(() {
                                            editingRowId = null;
                                            editingColumn = null;
                                          });
                                        },
                                      ),
                                    ),
                                  )
                                  : DataCell(
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () async {
                                        final value = await feature
                                            .getAttributeValue(col);
                                        setState(() {
                                          editingRowId = feature.rowId;
                                          editingColumn = col;
                                          editingValue = '${value ?? ''}';
                                        });
                                      },
                                      child: Container(
                                        alignment: Alignment.centerLeft,
                                        constraints: const BoxConstraints(
                                          minWidth: 80,
                                          minHeight: 40,
                                        ),
                                        child: FutureBuilder<dynamic>(
                                          future: feature.getAttributeValue(
                                            col,
                                          ),
                                          builder: (context, attrSnapshot) {
                                            return Text(
                                              '${attrSnapshot.data ?? ''}',
                                            );
                                          },
                                        ),
                                      ),
                                    ),
                                  ),
                          ],
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
