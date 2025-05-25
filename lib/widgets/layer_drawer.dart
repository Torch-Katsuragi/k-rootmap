/// K-MAPS: レイヤ構造Drawerウィジェット
/// プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示し、
/// 可視切り替え・リネーム・削除などの操作を提供するUI。
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:k_maps/utils/global_config.dart';
import 'package:path/path.dart' as p;
// import '../utils/meta_data.dart' as meta_util;
import 'package:collection/collection.dart';
import '../models/layer_tree_node.dart';
import '../models/geopackage_file.dart';

/// レイヤ構造Drawer（最小構成＋レイヤ追加・削除）
/// GeoPackageノードはタップでレイヤリストをトグル展開
class LayerDrawer extends StatefulWidget {
  final LayerTreeNode? currentNode;
  final void Function(LayerTreeNode? newNode) onDirChanged;
  final void Function(void Function()) setStateCallback;

  /// LayerDrawerコンストラクタ
  const LayerDrawer({
    super.key,
    required this.currentNode,
    required this.onDirChanged,
    required this.setStateCallback,
  });

  @override
  State<LayerDrawer> createState() => _LayerDrawerState();
}

class _LayerDrawerState extends State<LayerDrawer> {
  /// 展開中のGeoPackageノードのファイルパスを保持
  final Set<String> expandedGpkgPaths = {};

  // 属性テーブル表示中かどうか・どのLayerNodeか
  LayerNode? attributeTableLayerNode;

  @override
  void initState() {
    super.initState();
    // デフォルトで全gpkgノードを展開状態に
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

  @override
  Widget build(BuildContext context) {
    if (widget.currentNode == null) {
      return const Center(child: Text('ディレクトリが見つかりません'));
    }
    // 属性テーブル表示中ならそちらを表示
    if (attributeTableLayerNode != null) {
      return AttributeTablePanel(
        layerNode: attributeTableLayerNode!,
        onBack: () {
          setState(() {
            attributeTableLayerNode = null;
          });
        },
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
                      final folderNode = widget.currentNode as FolderNode;
                      final dir = folderNode.getAbsoluteFilePath();
                      final fileName =
                          result.endsWith('.gpkg') ? result : '$result.gpkg';
                      final path = p.join(dir ?? '', fileName);
                      if (File(path).existsSync()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('同名のGeoPackageファイルが既に存在します')),
                        );
                        return;
                      }
                      final parentNode = widget.currentNode as FolderNode;
                      final parentPath = parentNode.getAbsolutePathSegments();
                      final fileNameList = [fileName];
                      final gpkgFile = GeoPackageFile([
                        ...parentPath,
                        ...fileNameList,
                      ]);
                      final newNode = GeoPackageNode(
                        gpkgFile,
                        visible: true,
                        parent: folderNode,
                      );
                      folderNode.addChild(newNode);
                      widget.setStateCallback(() {});
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
                if (absPath != null) expandedGpkgPaths.remove(absPath);
              } else {
                if (absPath != null) expandedGpkgPaths.add(absPath);
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
                        // geopakcageノード削除
                        node.dispose();
                        setState(() {});
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
      leading: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              isSelected ? Colors.blue.withOpacity(0.15) : Colors.transparent,
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
          String geomType = 'MULTIPOINT';
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
                DropdownButtonFormField<String>(
                  value: geomType,
                  decoration: const InputDecoration(labelText: 'ジオメトリタイプ'),
                  items: const [
                    DropdownMenuItem(
                      value: 'MULTIPOINT',
                      child: Text('MULTIPOINT'),
                    ),
                    DropdownMenuItem(
                      value: 'MULTILINESTRING',
                      child: Text('MULTILINESTRING'),
                    ),
                    DropdownMenuItem(
                      value: 'MULTIPOLYGON',
                      child: Text('MULTIPOLYGON'),
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
                      'geomType': geomType,
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
        // node.geoPackageFile.addLayer(result['name']!, result['geomType']!);
        // ジオメトリタイプに応じて適切なLayerNodeサブクラスを生成
        LayerTreeNode? newLayerNode;
        switch (result['geomType']) {
          case 'MULTIPOINT':
            newLayerNode = PointLayerNode.createIn(node, result['name']!);
            break;
          case 'MULTILINESTRING':
            newLayerNode = LineLayerNode.createIn(node, result['name']!);
            break;
          case 'MULTIPOLYGON':
            newLayerNode = PolygonLayerNode.createIn(node, result['name']!);
            break;
        }
        if (newLayerNode != null) {
          // 追加成功時のみUI更新
          widget.setStateCallback(() {});
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
  const AttributeTablePanel({
    super.key,
    required this.layerNode,
    required this.onBack,
  });

  @override
  State<AttributeTablePanel> createState() => _AttributeTablePanelState();
}

class _AttributeTablePanelState extends State<AttributeTablePanel> {
  // 編集中セル: rowId, カラム名
  int? editingRowId;
  String? editingColumn;
  String editingValue = '';

  @override
  Widget build(BuildContext context) {
    final columns = widget.layerNode.getAttributeNames();
    final features = widget.layerNode.features;
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
                  '${widget.layerNode.name} の属性テーブル',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                border: TableBorder.all(color: Colors.grey.shade300, width: 1),
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
                                      // 今後feature選択等に拡張予定
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
                                Text('${feature.getAttributeValue(col) ?? ''}'),
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
                                      feature.editAttribute(col, editingValue);
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
                                  onTap: () {
                                    setState(() {
                                      editingRowId = feature.rowId;
                                      editingColumn = col;
                                      editingValue =
                                          '${feature.getAttributeValue(col) ?? ''}';
                                    });
                                  },
                                  child: Container(
                                    alignment: Alignment.centerLeft,
                                    constraints: const BoxConstraints(
                                      minWidth: 80,
                                      minHeight: 40,
                                    ),
                                    child: Text(
                                      '${feature.getAttributeValue(col) ?? ''}',
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
