/// K-MAPS: レイヤ構造Drawerウィジェット
/// プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示し、
/// 可視切り替え・リネーム・削除などの操作を提供するUI。
library;

import 'dart:io';
import 'dart:convert'; // JSON処理のため追加
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // クリップボード機能のため追加
import 'package:k_maps/utils/global_config.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
// import '../utils/meta_data.dart' as meta_util;
import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../models/layer_tree_node.dart';
import '../models/geopackage_file.dart';
import '../models/geometry_type.dart'; // ジオメトリタイプenumをインポート
import '../utils/metadata_parser.dart'; // メタデータパーサーをインポート
import '../utils/global_drawing_state.dart'; // 追記機能のため追加
import '../utils/feature_calc_utils.dart'; // ポリゴン合成機能のため追加
import '../services/import_export_service.dart'; // インポート機能用
import '../converters/feature_converter.dart'; // フィーチャエクスポート機能用
import '../converters/base_converter.dart'; // ConversionResultとパラメータクラス用
import 'dialog_manager.dart'; // ダイアログ管理用
import 'attribute_table_widget.dart'; // PlutoGrid属性テーブル用

/// レイヤ構造Drawer（最小構成＋レイヤ追加・削除）
/// GeoPackageノードはタップでレイヤリストをトグル展開
class LayerDrawer extends StatefulWidget {
  final LayerTreeNode? currentNode;
  final void Function(LayerTreeNode? newNode) onDirChanged;
  final void Function(void Function()) setStateCallback;

  /// 地図ジャンプ用コールバック（中心座標に移動）
  final void Function(LatLng latLng)? onJumpTo;

  /// 追記モード開始用コールバック（ツール切り替えとレイヤー選択）
  final void Function(FeatureNode feature)? onStartAppendMode;

  /// LayerDrawerコンストラクタ
  const LayerDrawer({
    super.key,
    required this.currentNode,
    required this.onDirChanged,
    required this.setStateCallback,
    this.onJumpTo,
    this.onStartAppendMode,
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

  /// ドラッグ中のファイル管理
  bool _isDragging = false;
  String? _draggedFilePath;
  GeoPackageNode? _dragTargetGeoPackageNode;
  int? _dragInsertIndex;

  /// ImportExportServiceのインスタンス
  ImportExportService get _importExportService => ImportExportService();

  /// PlutoGrid属性テーブルを表示
  void _showPlutoAttributeTable(BuildContext context, LayerNode node) async {
    try {
      // フィーチャデータを取得
      final features = await node.features;

      // フィーチャデータをMap形式に変換
      final featureList = <Map<String, dynamic>>[];
      for (final feature in features) {
        final featureMap = <String, dynamic>{
          'id': feature.rowId,
          'geometry': {
            'type': feature.runtimeType
                .toString()
                .replaceAll('Node', '')
                .replaceAll('Layer', '')
                .replaceAll('Feature', ''),
            'coordinates': [], // 座標は簡略化
          },
          'metadata': feature.metadata,
        };
        featureList.add(featureMap);
      }

      // ダイアログで属性テーブルを表示
      showDialog(
        context: context,
        builder:
            (context) => AttributeTableDialog(
              layer: node,
              features: featureList,
              onFeatureSelected: (feature) {
                // フィーチャが選択された時の処理
                print('Feature selected: ${feature['id']}');
                final featureId = feature['id'] as int;
                final featureNode = features.firstWhere(
                  (f) => f.rowId == featureId,
                  orElse: () => features.first,
                );

                // 地図上でフィーチャを選択状態にする
                GlobalConfig.instance.selectedFeatures = [featureNode];

                // 地図を更新
                if (GlobalConfig.instance.mapState != null) {
                  GlobalConfig.instance.mapState.setState(() {});
                }

                // 地図をフィーチャの位置にジャンプ
                if (widget.onJumpTo != null) {
                  widget.onJumpTo!(featureNode.centroid);
                }
              },
              onAttributeChanged: (feature, field, value) {
                // 属性が変更された時の処理
                print(
                  'Attribute changed: Feature ${feature['id']}, Field: $field, Value: $value',
                );
                // 注意: データベースへの保存は AttributeTableWidget 内で自動実行される
                // ここでは追加的な処理のみ実行
              },
              onFeatureDeleted: (feature) async {
                // フィーチャが削除された時の処理
                print('Feature deleted: ${feature['id']}');
                try {
                  final featureId = feature['id'] as int;
                  FeatureNode? featureNode;
                  try {
                    featureNode = features.firstWhere(
                      (f) => f.rowId == featureId,
                    );
                  } catch (e) {
                    featureNode = null;
                  }

                  if (featureNode != null) {
                    // フィーチャを削除
                    await featureNode.dispose();

                    // レイヤーノードから削除
                    node.children.remove(featureNode);

                    // 地図を更新
                    _triggerMapRefresh();

                    // 成功メッセージ
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('フィーチャが削除されました: ID ${featureId}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  print('Error deleting feature: $e');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('フィーチャの削除に失敗しました: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              onAddFeature: () {
                // 新しいフィーチャを追加する時の処理
                print('Add new feature');
                Navigator.pop(context); // 属性テーブルを閉じる

                // 地図編集モードに切り替え
                if (node is PointLayerNode) {
                  // 点レイヤーの場合 - 地図をタップしてポイントを追加
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('地図上をタップして新しいポイントを追加してください'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                } else if (node is LineLayerNode) {
                  // 線レイヤーの場合 - 線描画モードに切り替え
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('線描画モードに切り替えて新しい線を追加してください'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                } else if (node is PolygonLayerNode) {
                  // 面レイヤーの場合 - 面描画モードに切り替え
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('面描画モードに切り替えて新しい面を追加してください'),
                      duration: Duration(seconds: 3),
                    ),
                  );
                }

                // 選択されたレイヤーを設定
                GlobalConfig.instance.selectedLayerNode = node;
              },
            ),
      );
    } catch (e) {
      print('Error showing pluto attribute table: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('属性テーブルの表示に失敗しました: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// インポート成功メッセージを表示
  void _showImportSuccess(ImportExportResult result) {
    String message = 'Import completed successfully!';
    if (result.metadata != null) {
      final metadata = result.metadata!;
      if (metadata['layerName'] != null) {
        message += '\nLayer: ${metadata['layerName']}';
      }
      if (metadata['featureCount'] != null) {
        message += '\nFeatures: ${metadata['featureCount']}';
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// インポートエラーメッセージを表示
  void _showImportError(String errorMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Import failed: $errorMessage'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// マップページのフィーチャ更新をトリガー
  void _triggerMapRefresh() {
    try {
      // GlobalConfigを通じてマップページの更新をトリガー
      final mapState = GlobalConfig.instance.mapState;
      if (mapState != null && mapState.mounted) {
        // レイヤ削除時は強制的にマップを更新（フィーチャキャッシュクリア）
        (mapState as dynamic).forceMapRefresh();
        print('[LayerDrawer] マップ強制更新をトリガーしました');
      } else {
        print('[LayerDrawer] マップページが見つからないか、マウントされていません');
      }
    } catch (e) {
      print('[LayerDrawer] マップ更新エラー: $e');
    }
  }

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
        onStartAppendMode: widget.onStartAppendMode,
      );
    }

    return Container(
      decoration:
          _isDragging
              ? BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.blue.withOpacity(0.1),
              )
              : null,
      child: Column(
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
                            SnackBar(
                              content: Text('同名のGeoPackageファイルが既に存在します'),
                            ),
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
          if (_isDragging)
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cloud_upload, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'Drop file on GeoPackage to import as layer',
                    style: TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                ...widget.currentNode!.children.map((node) {
                  if (node is FolderNode) {
                    return _buildFolderTile(context, node);
                  } else if (node is GeoPackageNode) {
                    return _buildGeoPackageTile(context, node);
                  } else if (node is PhotoNode) {
                    return _buildPhotoTile(context, node);
                  }
                  // LayerNodeはここで描画しない
                  return const SizedBox.shrink();
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderTile(BuildContext context, FolderNode node) => ListTile(
    leading: _buildIconWithVisibility(node),
    title: Text(node.name),
    onTap: () => widget.onDirChanged(node),
  );

  /// PhotoNodeのタイル（位置情報付き画像ファイル）
  Widget _buildPhotoTile(BuildContext context, PhotoNode node) => ListTile(
    leading: _buildIconWithVisibility(node),
    title: Text(node.name),
    onTap: () {
      // PhotoNode選択処理（地図上でハイライト表示）
      GlobalConfig.instance.selectedFeatures.clear();
      GlobalConfig.instance.selectedFeatures.add(node);

      // 地図の中心を写真の位置に移動
      if (widget.onJumpTo != null) {
        widget.onJumpTo!(node.location);
      }

      widget.setStateCallback(() {});
    },
    trailing: PopupMenuButton<String>(
      onSelected: (value) async {
        if (value == 'delete') {
          final confirm = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text('写真削除'),
                  content: Text('${node.name} をリストから削除しますか？\n（ファイル自体は削除されません）'),
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
            // 削除されるPhotoNodeが選択されている場合は選択状態をクリア
            GlobalConfig.instance.selectedFeatures.remove(node);

            await node.dispose();

            // マップのフィーチャキャッシュを更新
            _triggerMapRefresh();

            widget.setStateCallback(() {});
          }
        } else if (value == 'details') {
          _showPhotoDetails(context, node);
        }
      },
      itemBuilder:
          (context) => [
            const PopupMenuItem(value: 'details', child: Text('詳細情報')),
            const PopupMenuItem(value: 'delete', child: Text('削除')),
          ],
    ),
  );

  /// GeoPackageノードのタイル。タップでレイヤリストをトグル展開
  Widget _buildGeoPackageTile(BuildContext context, GeoPackageNode node) {
    final absPath = node.geoPackageFile.getAbsolutePath();
    final isExpanded = absPath != null && expandedGpkgPaths.contains(absPath);
    final isDropTarget = _isDragging && _dragTargetGeoPackageNode == node;

    return DropTarget(
      onDragEntered: (details) {
        setState(() {
          _isDragging = true;
          _dragTargetGeoPackageNode = node;
        });
      },
      onDragExited: (details) {
        setState(() {
          if (_dragTargetGeoPackageNode == node) {
            _dragTargetGeoPackageNode = null;
            // 他にターゲットがない場合はドラッグ状態をリセット
            _isDragging = false;
          }
        });
      },
      onDragDone: (details) async {
        if (details.files.isNotEmpty) {
          final file = details.files.first;
          await _handleSpecificGeoPackageDrop(file.path, node);

          // 処理完了後にフラグをリセット
          setState(() {
            _isDragging = false;
            _draggedFilePath = null;
            _dragTargetGeoPackageNode = null;
            _dragInsertIndex = null;
          });
        }
      },
      child: Container(
        decoration:
            isDropTarget
                ? BoxDecoration(
                  border: Border.all(color: Colors.green, width: 2),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.green.withOpacity(0.1),
                )
                : null,
        child: Column(
          children: [
            ListTile(
              leading: _buildIconWithVisibility(node),
              title: Row(
                children: [
                  Expanded(child: Text(node.name)),
                  if (isDropTarget)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'DROP HERE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
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
                                    onPressed:
                                        () => Navigator.pop(context, false),
                                    child: const Text('キャンセル'),
                                  ),
                                  TextButton(
                                    onPressed:
                                        () => Navigator.pop(context, true),
                                    child: const Text('削除'),
                                  ),
                                ],
                              ),
                        );
                        if (confirm == true) {
                          try {
                            // GeoPackageが削除されるとそのレイヤも削除される
                            // 削除されるGeoPackageのレイヤが選択されている場合は選択状態をクリア
                            final layersToRemove =
                                node.children.whereType<LayerNode>().toList();
                            for (final layer in layersToRemove) {
                              if (GlobalConfig.instance.selectedLayerNode ==
                                  layer) {
                                GlobalConfig.instance.selectedLayerNode = null;
                              }
                              // そのレイヤのフィーチャが選択されている場合も選択状態をクリア
                              GlobalConfig.instance.selectedFeatures
                                  .removeWhere((feature) {
                                    if (feature is FeatureNode) {
                                      return feature.parent == layer;
                                    }
                                    return false;
                                  });
                            }

                            // geopackageノード削除（ファイルも含めて削除）
                            await node.dispose();

                            // マップのフィーチャキャッシュを更新
                            _triggerMapRefresh();

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
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('削除'),
                          ),
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
        ),
      ),
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
              // 削除されるレイヤが選択されている場合は選択状態をクリア
              if (GlobalConfig.instance.selectedLayerNode == node) {
                GlobalConfig.instance.selectedLayerNode = null;
              }

              // 削除されるレイヤのフィーチャが選択されている場合は選択状態をクリア
              GlobalConfig.instance.selectedFeatures.removeWhere((feature) {
                if (feature is FeatureNode) {
                  return feature.parent == node;
                }
                return false;
              });

              // レイヤを削除
              node.dispose();

              // マップのフィーチャキャッシュを更新
              _triggerMapRefresh();

              // UI更新
              widget.setStateCallback(() {});
            }
          } else if (value == 'attributes') {
            setState(() {
              attributeTableLayerNode = node;
            });
          } else if (value == 'pluto_attributes') {
            _showPlutoAttributeTable(context, node);
          } else if (value == 'export') {
            // DialogManagerを使用してレイヤーエクスポートダイアログを表示
            await DialogManager.showLayerExportDialog(
              context,
              sourceLayer: node,
            );
          } else if (value == 'merge' && node is PolygonLayerNode) {
            _mergePolygonsInLayer(context, node);
          }
        },
        itemBuilder:
            (context) => [
              const PopupMenuItem(value: 'attributes', child: Text('属性テーブル')),
              const PopupMenuItem(
                value: 'pluto_attributes',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, size: 16),
                    SizedBox(width: 8),
                    Text('高機能属性テーブル'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download, size: 16),
                    SizedBox(width: 8),
                    Text('Export Layer'),
                  ],
                ),
              ),
              // PolygonLayerNodeの場合のみ合成メニューを表示
              if (node is PolygonLayerNode)
                const PopupMenuItem(value: 'merge', child: Text('合成')),
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

  /// 写真の詳細情報を表示するダイアログ
  void _showPhotoDetails(BuildContext context, PhotoNode node) {
    // プロジェクトルートからの相対パスを計算
    final projectRoot = GlobalConfig.instance.projectRootDir;
    String displayPath = node.filePath;
    if (projectRoot != null && node.filePath.startsWith(projectRoot)) {
      displayPath = node.filePath.substring(projectRoot.length);
      if (displayPath.startsWith('\\') || displayPath.startsWith('/')) {
        displayPath = displayPath.substring(1);
      }
    }

    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.photo_camera, color: Colors.purple),
                SizedBox(width: 8),
                Text('写真ファイル'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 画像プレビューを追加
                  Container(
                    width: double.infinity,
                    height: 200,
                    margin: EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(node.filePath),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey.shade100,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 48,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  '画像を読み込めません',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  _buildDetailRow('ファイルパス', displayPath),
                  _buildDetailRow('緯度', '${node.location.latitude}'),
                  _buildDetailRow('経度', '${node.location.longitude}'),
                  if (node.takenAt != null)
                    _buildDetailRow('撮影日時', '${node.takenAt}'),
                  if (node.metadata.fileSize != null)
                    _buildDetailRow(
                      'ファイルサイズ',
                      '${(node.metadata.fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB',
                    ),
                  if (node.metadata.width != null &&
                      node.metadata.height != null)
                    _buildDetailRow(
                      '解像度',
                      '${node.metadata.width} × ${node.metadata.height}',
                    ),
                  if (node.metadata.camera != null)
                    _buildDetailRow('カメラ', '${node.metadata.camera}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('閉じる'),
              ),
            ],
          ),
    );
  }

  /// 詳細情報の行を構築
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  /// ポリゴンレイヤー内のポリゴンを合成
  Future<void> _mergePolygonsInLayer(
    BuildContext context,
    PolygonLayerNode layerNode,
  ) async {
    try {
      // レイヤー内の全てのポリゴンFeatureNodeを取得
      final features = layerNode.children.cast<FeatureNode>();

      // 合成可能なポリゴンの数をチェック
      final mergeableCount = PolygonMerge.countMergeablePolygons(features);

      if (mergeableCount < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('合成するには2つ以上の有効なポリゴンが必要です')),
        );
        return;
      }

      // 確認ダイアログを表示
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('ポリゴン合成'),
              content: Text(
                '${layerNode.name} 内の ${mergeableCount} 個のポリゴンを合成しますか？\n\n'
                '最も面積の大きいポリゴンを外形とし、それ以外を穴として扱います。\n'
                '合成後は新しいレイヤー「${layerNode.name}_merged」に保存されます。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('合成'),
                ),
              ],
            ),
      );

      if (confirm != true) return;

      // 合成を実行
      final mergedPolygon = PolygonMerge.mergePolygonFeatures(features);

      if (mergedPolygon.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ポリゴンの合成に失敗しました')));
        return;
      }

      // 新しいレイヤー名を生成
      final newLayerName = '${layerNode.name}_merged';

      // 同じGeoPackageNode内に新しいPolygonLayerNodeを作成
      final parentGpkg = layerNode.parent as GeoPackageNode;
      final newLayerNode = await PolygonLayerNode.createIn(
        parentGpkg,
        newLayerName,
      );

      if (newLayerNode == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('新しいレイヤーの作成に失敗しました')));
        return;
      }

      // 合成されたポリゴンを新しいレイヤーに追加
      final mergedFeature = await PolygonFeatureNode.createIn(
        newLayerNode,
        mergedPolygon,
        'merged_polygon',
        '${layerNode.name}の${mergeableCount}個のポリゴンを合成',
        metadata: {
          'source_layer': layerNode.name,
          'merged_count': mergeableCount,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      if (mergedFeature != null) {
        // UI更新
        widget.setStateCallback(() {});
        if (GlobalConfig.instance.mapState != null) {
          GlobalConfig.instance.mapState.setState(() {});
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ポリゴンを合成しました。新しいレイヤー「$newLayerName」に保存されました。'),
          ),
        );

        print('[LayerDrawer] ポリゴン合成完了: $newLayerName');
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('合成ポリゴンの保存に失敗しました')));
      }
    } catch (e, stack) {
      print('[LayerDrawer] ポリゴン合成エラー: $e');
      print('[LayerDrawer] スタックトレース: $stack');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('合成処理中にエラーが発生しました: $e')));
    }
  }

  /// 特定のGeoPackageノードへのファイルドロップを処理
  Future<void> _handleSpecificGeoPackageDrop(
    String filePath,
    GeoPackageNode targetNode,
  ) async {
    try {
      print(
        '[LayerDrawer] GeoPackageドロップ処理開始: $filePath -> ${targetNode.name}',
      );

      // インポート実行
      final result = await _importExportService.importFile(
        filePath,
        targetNode,
      );

      if (result.success) {
        // 成功：レイヤーツリーを更新
        await targetNode.updateChildren();

        // 作成されたレイヤーノードもFeatureNodeを更新
        if (result.createdLayer != null) {
          print(
            '[LayerDrawer] 作成されたレイヤーのフィーチャ更新: ${result.createdLayer!.layerName}',
          );
          await result.createdLayer!.updateChildren();

          // デバッグ：フィーチャが正しく読み込まれたかを確認
          final features = await result.createdLayer!.features;
          print(
            '[LayerDrawer] レイヤー「${result.createdLayer!.layerName}」のフィーチャ数: ${features.length}',
          );

          // デバッグ：最初のフィーチャの詳細
          if (features.isNotEmpty) {
            final firstFeature = features.first;
            print(
              '[LayerDrawer] 最初のフィーチャ: ${firstFeature.name}, 中心座標: ${firstFeature.centroid}',
            );
          }
        }

        // GeoPackageを自動展開
        final absPath = targetNode.geoPackageFile.getAbsolutePath();
        if (absPath != null) {
          expandedGpkgPaths.add(absPath);
        }

        // UIとマップを強制更新
        widget.setStateCallback(() {});

        // 追加：インポート完了後に状態を確実に更新
        setState(() {});

        // マップページのフィーチャデータを強制更新
        _triggerMapRefresh();

        // 追加の確実な更新（少し遅延させて実行）
        Future.delayed(Duration(milliseconds: 500), () {
          _triggerMapRefresh();
        });

        _showImportSuccess(result);

        print('[LayerDrawer] GeoPackageドロップ処理完了');
      } else {
        _showImportError(result.errorMessage ?? 'Import failed');
      }
    } catch (e, stack) {
      print('[LayerDrawer] GeoPackageドロップエラー: $e');
      print('スタックトレース: $stack');
      _showImportError('Unexpected error during import: $e');
    }
  }
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
class MetadataTableDialog extends StatefulWidget {
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
  State<MetadataTableDialog> createState() => _MetadataTableDialogState();
}

class _MetadataTableDialogState extends State<MetadataTableDialog> {
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
      print('[MetadataTable] 座標系変更エラー: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('座標系の変更に失敗しました: $e')));
    }
  }

  /// メタデータテーブルのTSVエクスポート処理
  Future<void> _exportMetadataToTSV(BuildContext context) async {
    try {
      // プロジェクトルートディレクトリを取得
      final projectRoot = GlobalConfig.instance.projectRootDir;
      if (projectRoot == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('プロジェクトルートディレクトリが見つかりません')),
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

      print('[MetadataTable] TSVエクスポート開始: $tsvPath');

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

      print('[MetadataTable] TSVエクスポート完了: $tsvPath');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('メタデータTSVファイルを出力しました:\n$tsvFileName'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      print('[MetadataTable] TSVエクスポートエラー: $e');
      print('[MetadataTable] スタックトレース: $stackTrace');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('メタデータTSVエクスポートに失敗しました: $e')));
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
                hint: const Text('座標系'),
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
            tooltip: 'TSVエクスポート',
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

  /// 追記モード開始用コールバック（ツール切り替えとレイヤー選択）
  final void Function(FeatureNode feature)? onStartAppendMode;

  const AttributeTablePanel({
    super.key,
    required this.layerNode,
    required this.onBack,
    this.onJumpTo,
    this.onStartAppendMode,
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

  // ページネーション関連
  int _currentPage = 0;
  int _pageSize = 50; // 1ページあたりの表示件数
  int _totalRecords = 0;

  // スクロール位置保持用のコントローラー
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  // データキャッシュ用変数（不必要な再読み込みを防ぐ）
  List<String>? _cachedColumns;
  List<FeatureNode>? _cachedFeatures;
  List<Map<String, dynamic>>? _cachedAttributeData; // 属性データキャッシュ
  bool _lastShowAllColumns = false;
  Future<List<dynamic>>? _dataFuture;

  @override
  void dispose() {
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  /// メタデータダイアログを表示
  void _showMetadataDialog(
    BuildContext context,
    String metadataStr,
    FeatureNode featureNode,
  ) async {
    try {
      // デバッグ出力
      // print('[AttributeTable] メタデータ文字列: $metadataStr');

      // JSONパースを試行
      final metadataJson = jsonDecode(metadataStr) as Map<String, dynamic>;
      // print('[AttributeTable] JSONパース成功: $metadataJson');

      // XY座標付きでメタデータをパース
      final tableData = await MetadataParser.parseMetadataWithCoordinates(
        metadataJson,
        featureNode.centroid,
      );
      // print('[AttributeTable] パース結果: $tableData');

      if (tableData != null) {
        // GeoPackage名とレイヤ名を取得
        final gpkgPath = widget.layerNode.geoPackageFile.getAbsolutePath();
        final gpkgName =
            gpkgPath != null ? p.basenameWithoutExtension(gpkgPath) : 'unknown';
        final layerName = widget.layerNode.layerName;

        // フィーチャ名を取得（FeatureNodeのnameを使用、利用できない場合はID）
        final featureName =
            featureNode.name.isNotEmpty
                ? featureNode.name
                : 'feature_${featureNode.rowId}';

        showDialog(
          context: context,
          builder:
              (context) => MetadataTableDialog(
                tableData: tableData,
                gpkgName: gpkgName,
                layerName: layerName,
                featureName: featureName,
                featureLatLng: featureNode.centroid,
              ),
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
    // showAllColumnsが変更された場合、またはページが変更された場合は再読み込み
    if (_dataFuture == null || _lastShowAllColumns != showAllColumns) {
      _lastShowAllColumns = showAllColumns;
      _dataFuture = _loadTableDataOptimized();
    }
    return _dataFuture!;
  }

  /// 最適化されたテーブルデータ読み込み（一括属性取得）
  Future<List<dynamic>> _loadTableDataOptimized() async {
    try {
      print('[AttributeTable] 最適化データ読み込み開始');

      // カラム名と基本データを並行取得
      final results = await Future.wait([
        widget.layerNode.geoPackageFile.getColumnNames(
          widget.layerNode.layerName,
          getAll: showAllColumns,
        ),
        widget.layerNode.features,
      ]);

      final columns = results[0] as List<String>;
      final features = results[1] as List<FeatureNode>;

      print(
        '[AttributeTable] カラム数: ${columns.length}, フィーチャ数: ${features.length}',
      );

      // 属性データを一括取得
      final attributeData = await widget.layerNode.geoPackageFile
          .getAllFeatureAttributes(
            widget.layerNode.layerName,
            columns: columns,
          );

      print('[AttributeTable] 属性データ一括取得完了: ${attributeData.length}件');

      // 総レコード数を保存（ページネーション用）
      _totalRecords = features.length;

      // データが0件の場合の処理
      if (_totalRecords == 0) {
        print('[AttributeTable] データなし: 0件');
        _cachedColumns = columns;
        _cachedFeatures = features;
        _cachedAttributeData = attributeData;
        return [columns, <FeatureNode>[], <Map<String, dynamic>>[]];
      }

      // ページングされたデータを作成
      final startIndex = _currentPage * _pageSize;
      final endIndex = (startIndex + _pageSize).clamp(
        startIndex,
        features.length,
      );

      final pagedFeatures = features.sublist(startIndex, endIndex);
      final pagedAttributeData =
          attributeData.length > startIndex
              ? attributeData.sublist(
                startIndex,
                endIndex.clamp(startIndex, attributeData.length),
              )
              : <Map<String, dynamic>>[];

      print(
        '[AttributeTable] ページング: ${startIndex}-${endIndex - 1} / $_totalRecords件',
      );

      // キャッシュに保存（全データを保持）
      _cachedColumns = columns;
      _cachedFeatures = features;
      _cachedAttributeData = attributeData;

      return [columns, pagedFeatures, pagedAttributeData];
    } catch (e, stack) {
      print('[AttributeTable] データ読み込みエラー: $e');
      print('[AttributeTable] スタックトレース: $stack');
      return [<String>[], <FeatureNode>[], <Map<String, dynamic>>[]];
    }
  }

  /// TSVエクスポート処理（最適化版）
  Future<void> _exportToTSV(BuildContext context) async {
    try {
      // データを取得（一括取得済みの場合はそれを使用）
      final tableData = await _getTableData();
      final columns = tableData[0] as List<String>;
      final features = tableData[1] as List<FeatureNode>;
      final attributeData = tableData[2] as List<Map<String, dynamic>>;

      // エクスポート先パスを構築
      final gpkgPath = widget.layerNode.geoPackageFile.getAbsolutePath();
      if (gpkgPath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoPackageファイルのパスが見つかりません')),
        );
        return;
      }

      final gpkgDir = p.dirname(gpkgPath);
      final gpkgName = p.basenameWithoutExtension(gpkgPath);
      final layerName = widget.layerNode.layerName;
      final tsvFileName = '${gpkgName}_${layerName}_propety_table.tsv';
      final tsvPath = p.join(gpkgDir, tsvFileName);

      print('[AttributeTable] TSVエクスポート開始: $tsvPath');

      // TSVファイルを作成
      final tsvFile = File(tsvPath);
      final sink = tsvFile.openWrite();

      // ヘッダー行を書き込み（TSVエスケープ付き）
      final headerLine = columns.map(_escapeTsvField).join('\t');
      sink.writeln(headerLine);

      // データ行を書き込み（一括取得した属性データを使用）
      for (int i = 0; i < features.length; i++) {
        final rowValues = <String>[];
        final attributeRow =
            attributeData.length > i ? attributeData[i] : <String, dynamic>{};

        for (final col in columns) {
          if (col == 'geom') {
            // geomカラムは'GEOMETRY'として出力
            rowValues.add(_escapeTsvField('GEOMETRY'));
          } else {
            final value = attributeRow[col];
            rowValues.add(_escapeTsvField(value?.toString() ?? ''));
          }
        }

        final rowLine = rowValues.join('\t');
        sink.writeln(rowLine);
      }

      await sink.close();

      print('[AttributeTable] TSVエクスポート完了: $tsvPath');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('TSVファイルを出力しました:\n$tsvFileName'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e, stackTrace) {
      print('[AttributeTable] TSVエクスポートエラー: $e');
      print('[AttributeTable] スタックトレース: $stackTrace');

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('TSVエクスポートに失敗しました: $e')));
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

  /// 現在のページをリフレッシュ（編集後のデータ更新用）
  void _refreshCurrentPage() {
    _dataFuture = null;
    _cachedAttributeData = null;
    setState(() {
      editingRowId = null;
      editingColumn = null;
    });
  }

  /// 最適化されたDataRowを構築（一括取得した属性データを使用）
  DataRow _buildOptimizedDataRow(
    FeatureNode feature,
    List<String> columns,
    Map<String, dynamic> attributeRow,
  ) {
    return DataRow(
      cells: [
        for (final col in columns)
          col == 'geom'
              ? DataCell(
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapDown: (details) {
                    _showRowContextMenu(
                      context,
                      feature,
                      attributeRow,
                      details.globalPosition,
                    );
                  },
                  child: SizedBox(
                    height: 28,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(40, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                          GlobalConfig.instance.selectedFeatures = [feature];
                          // 地図本体のみ再描画（属性テーブルは再描画しない）
                          if (GlobalConfig.instance.mapState != null) {
                            GlobalConfig.instance.mapState.setState(() {});
                          }
                        }
                      },
                      child: const Text('選択', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                ),
              )
              : col == 'kmaps_metadata'
              ? DataCell(() {
                final metadataStr = attributeRow[col] as String?;
                if (metadataStr == null || metadataStr.isEmpty) {
                  return const Text('');
                }

                return SizedBox(
                  height: 28,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 0,
                      ),
                      minimumSize: const Size(40, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      _showMetadataDialog(context, metadataStr, feature);
                    },
                    child: const Text('表示', style: TextStyle(fontSize: 13)),
                  ),
                );
              }())
              : (editingRowId == feature.rowId && editingColumn == col)
              ? DataCell(
                SizedBox(
                  width: 120,
                  child: TextField(
                    autofocus: true,
                    controller: TextEditingController(text: editingValue)
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
                      // 編集後はキャッシュをクリアして再読み込み（ページは維持）
                      _refreshCurrentPage();
                    },
                    onEditingComplete: () {
                      feature.editAttribute(col, editingValue);
                      // 編集後はキャッシュをクリアして再読み込み（ページは維持）
                      _refreshCurrentPage();
                    },
                  ),
                ),
              )
              : DataCell(
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final value = attributeRow[col];
                    setState(() {
                      editingRowId = feature.rowId;
                      editingColumn = col;
                      editingValue = '${value ?? ''}';
                    });
                  },
                  onSecondaryTapDown: (details) {
                    _showRowContextMenu(
                      context,
                      feature,
                      attributeRow,
                      details.globalPosition,
                    );
                  },
                  child: Container(
                    alignment: Alignment.centerLeft,
                    constraints: const BoxConstraints(
                      minWidth: 80,
                      minHeight: 40,
                    ),
                    child: Text('${attributeRow[col] ?? ''}'),
                  ),
                ),
              ),
        // 追記ボタン用のセルを追加
        _buildAppendCell(feature),
      ],
    );
  }

  /// 行の右クリックメニューを表示
  void _showRowContextMenu(
    BuildContext context,
    FeatureNode feature,
    Map<String, dynamic> attributeRow,
    Offset globalPosition,
  ) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx + 1,
        globalPosition.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: 'export_feature',
          child: const Row(
            children: [
              Icon(Icons.repeat, size: 16),
              SizedBox(width: 8),
              Text('Export Feature'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'copy_coordinates',
          child: const Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('Copy Coordinates'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value != null) {
        _handleContextMenuAction(value, feature, attributeRow);
      }
    });
  }

  /// コンテキストメニューのアクション処理
  void _handleContextMenuAction(
    String action,
    FeatureNode feature,
    Map<String, dynamic> attributeRow,
  ) {
    switch (action) {
      case 'export_feature':
        _exportSingleFeature(feature, attributeRow);
        break;
      case 'copy_coordinates':
        _copyCoordinates(feature);
        break;
    }
  }

  /// 単一フィーチャのエクスポート（ダイアログ表示）
  Future<void> _exportSingleFeature(
    FeatureNode feature,
    Map<String, dynamic> attributeRow,
  ) async {
    try {
      // フィーチャデータを構築
      final featureData = {
        'id': feature.rowId,
        'geometry': _buildGeometryFromFeature(feature),
        'metadata': attributeRow,
      };

      // DialogManagerを使用してフィーチャエクスポートダイアログを表示
      await DialogManager.showFeatureExportDialog(
        context,
        features: [featureData],
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Export failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      print('[AttributeTable] エクスポートエラー: $e');
    }
  }

  /// 座標のコピー
  Future<void> _copyCoordinates(FeatureNode feature) async {
    try {
      final coordinates = feature.centroid;
      final coordText = '${coordinates.latitude}, ${coordinates.longitude}';

      // クリップボードにコピー
      await Clipboard.setData(ClipboardData(text: coordText));
      print('[AttributeTable] 座標コピー: $coordText');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coordinates copied: $coordText'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to copy coordinates: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// フィーチャからジオメトリデータを構築
  Map<String, dynamic> _buildGeometryFromFeature(FeatureNode feature) {
    // 実際の実装では、フィーチャのジオメトリタイプに応じて適切なGeoJSON形式を生成
    if (feature is PointFeatureNode) {
      final coord = feature.centroid;
      return {
        'type': 'Point',
        'coordinates': [coord.longitude, coord.latitude],
      };
    } else if (feature is LineFeatureNode) {
      // 実際の線の座標データが必要
      return {
        'type': 'LineString',
        'coordinates': [], // 実際の座標配列
      };
    } else if (feature is PolygonFeatureNode) {
      // 実際のポリゴンの座標データが必要
      return {
        'type': 'Polygon',
        'coordinates': [[]], // 実際の座標配列
      };
    }

    return {
      'type': 'Point',
      'coordinates': [0.0, 0.0],
    };
  }

  /// 追記ボタン用のDataCellを構築
  /// 線と面のフィーチャの場合のみボタンを表示
  DataCell _buildAppendCell(FeatureNode feature) {
    // 線または面のフィーチャの場合のみ追記ボタンを表示
    if (feature is LineFeatureNode || feature is PolygonFeatureNode) {
      return DataCell(
        SizedBox(
          height: 28,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
              minimumSize: const Size(40, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: Colors.orange.shade100,
            ),
            onPressed: () {
              // GlobalDrawingStateで追記モードを開始
              final drawingState = GlobalDrawingState.instance;
              final success = drawingState.startEditingFeature(feature);

              if (success) {
                // 追記モード開始のコールバックを呼び出し
                widget.onStartAppendMode?.call(feature);

                // 属性テーブルを閉じて地図画面に戻る
                widget.onBack();

                // ユーザーに追記モード開始を通知
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${feature.name}の追記モードを開始しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              } else {
                // エラーメッセージを表示
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('追記モードの開始に失敗しました'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('追記', style: TextStyle(fontSize: 13)),
          ),
        ),
      );
    } else {
      // 点フィーチャの場合は空のセル
      return const DataCell(SizedBox(height: 28, child: Text('')));
    }
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
              IconButton(
                icon: const Icon(Icons.file_download, color: Colors.white),
                tooltip: 'TSVエクスポート',
                onPressed: () => _exportToTSV(context),
              ),
              IconButton(
                icon: const Icon(Icons.transform, color: Colors.white),
                tooltip: 'Feature変換出力',
                onPressed: () => _showFeatureExportDialog(context),
              ),
            ],
          ),
        ),
        // ページネーションコントロール
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(top: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 表示情報
              Text(
                _totalRecords == 0
                    ? '0 / 0 件'
                    : '${_currentPage * _pageSize + 1}-${((_currentPage + 1) * _pageSize).clamp(_currentPage * _pageSize + 1, _totalRecords)} / $_totalRecords 件',
                style: const TextStyle(fontSize: 14),
              ),
              // ページネーションボタン
              Row(
                children: [
                  // ページサイズ選択
                  DropdownButton<int>(
                    value: _pageSize,
                    items:
                        [25, 50, 100, 200]
                            .map(
                              (size) => DropdownMenuItem(
                                value: size,
                                child: Text('$size件'),
                              ),
                            )
                            .toList(),
                    onChanged: (newSize) {
                      if (newSize != null) {
                        setState(() {
                          _pageSize = newSize;
                          _currentPage = 0; // 最初のページに戻る
                          _dataFuture = null; // データ再読み込み
                        });
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  // 前のページボタン
                  IconButton(
                    onPressed:
                        _totalRecords > 0 && _currentPage > 0
                            ? () {
                              setState(() {
                                _currentPage--;
                                _dataFuture = null; // データ再読み込み
                              });
                            }
                            : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  // ページ番号表示
                  Text(
                    _totalRecords == 0
                        ? '0 / 0'
                        : '${_currentPage + 1} / ${((_totalRecords / _pageSize).ceil()).clamp(1, double.infinity).toInt()}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // 次のページボタン
                  IconButton(
                    onPressed:
                        _totalRecords > 0 &&
                                (_currentPage + 1) * _pageSize < _totalRecords
                            ? () {
                              setState(() {
                                _currentPage++;
                                _dataFuture = null; // データ再読み込み
                              });
                            }
                            : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
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
              final attributeData =
                  snapshot.data![2] as List<Map<String, dynamic>>;

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
                      // 追記ボタン用の列を追加
                      const DataColumn(label: Text('追記')),
                    ],
                    rows: [
                      for (int i = 0; i < features.length; i++)
                        _buildOptimizedDataRow(
                          features[i],
                          columns,
                          attributeData.length > i ? attributeData[i] : {},
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

  /// Feature変換出力ダイアログを表示
  Future<void> _showFeatureExportDialog(BuildContext context) async {
    String selectedFormat = 'geojson';
    bool convertToPointCloud = false;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              title: const Text('Feature変換出力'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '出力形式を選択してください：',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: selectedFormat,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'geojson',
                        child: Text('GeoJSON (.geojson)'),
                      ),
                      DropdownMenuItem(value: 'csv', child: Text('CSV (.csv)')),
                      DropdownMenuItem(value: 'kml', child: Text('KML (.kml)')),
                      DropdownMenuItem(
                        value: 'shapefile',
                        child: Text('Shapefile (.shp)'),
                      ),
                    ],
                    onChanged: (String? newValue) {
                      if (newValue != null) {
                        setState(() {
                          selectedFormat = newValue;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('ポイントクラウドに変換'),
                    subtitle: const Text('LineやPolygonを構成点に分解してPoint形式で出力'),
                    value: convertToPointCloud,
                    onChanged: (bool? value) {
                      setState(() {
                        convertToPointCloud = value ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'フィーチャ数: ${_cachedFeatures?.length ?? 0}件',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                ElevatedButton(
                  onPressed:
                      () => Navigator.of(context).pop({
                        'format': selectedFormat,
                        'pointCloud': convertToPointCloud,
                      }),
                  child: const Text('エクスポート'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null) {
      await _executeFeatureExport(
        context,
        result['format'] as String,
        result['pointCloud'] as bool,
      );
    }
  }

  /// Feature変換出力を実行
  Future<void> _executeFeatureExport(
    BuildContext context,
    String format,
    bool convertToPointCloud,
  ) async {
    try {
      // ローディング表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      // エクスポート先パスを構築
      final gpkgPath = widget.layerNode.geoPackageFile.getAbsolutePath();
      if (gpkgPath == null) {
        Navigator.of(context).pop(); // ローディング閉じる
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoPackageファイルのパスが見つかりません')),
        );
        return;
      }

      final gpkgDir = p.dirname(gpkgPath);
      final gpkgName = p.basenameWithoutExtension(gpkgPath);
      final layerName = widget.layerNode.layerName;

      // ファイル拡張子を決定
      final extension = _getFileExtension(format);
      final fileName = '${gpkgName}_${layerName}_features$extension';
      final outputPath = p.join(gpkgDir, fileName);

      print('[AttributeTable] Feature変換出力開始: $outputPath');
      print('[AttributeTable] 形式: $format, ポイントクラウド: $convertToPointCloud');

      // レイヤーエクスポートと同じ処理フローを使用
      // 1. DBから直接フィーチャを取得
      final features = await widget.layerNode.geoPackageFile.getFeatures(
        layerName,
      );
      final geometryType = await widget.layerNode.geoPackageFile
          .getGeometryType(layerName);

      if (features.isEmpty) {
        Navigator.of(context).pop(); // ローディング閉じる
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('エクスポートするフィーチャがありません')));
        return;
      }

      print(
        '[AttributeTable] DBフィーチャ取得完了: ${features.length}個 (タイプ: ${geometryType?.value})',
      );

      // 2. import_export_serviceの統一されたGeoJSON変換を使用
      final importExportService = ImportExportService();
      final geoJsonFeatures = await importExportService
          .convertFeaturesToGeoJson(features, geometryType);

      if (geoJsonFeatures.isEmpty) {
        Navigator.of(context).pop(); // ローディング閉じる
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('フィーチャの変換に失敗しました')));
        return;
      }

      print('[AttributeTable] GeoJSON変換完了: ${geoJsonFeatures.length}個のフィーチャ');

      // 3. FeatureExportConverterを使用（レイヤーエクスポートと同じ）
      final converter = FeatureExportConverter(
        exportFormat: _parseFileFormat(format),
        outputPath: outputPath,
        convertToPointCloud: convertToPointCloud,
      );

      final params = FeatureConversionParams(
        targetLayer: widget.layerNode,
        features: geoJsonFeatures,
        selectedFeatureIds: null, // 全フィーチャをエクスポート
      );

      final result = await converter.convert(params);

      Navigator.of(context).pop(); // ローディング閉じる

      if (result.success) {
        print('[AttributeTable] Feature変換出力完了: $outputPath');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ファイルを出力しました:\n$fileName'),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        print('[AttributeTable] Feature変換出力失敗: ${result.errorMessage}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エクスポートに失敗しました: ${result.errorMessage}')),
        );
      }
    } catch (e, stackTrace) {
      Navigator.of(context).pop(); // ローディング閉じる
      print('[AttributeTable] Feature変換出力エラー: $e');
      print('[AttributeTable] スタックトレース: $stackTrace');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('エクスポートエラー: $e')));
    }
  }

  /// ファイル形式から拡張子を取得
  String _getFileExtension(String format) {
    switch (format) {
      case 'geojson':
        return '.geojson';
      case 'csv':
        return '.csv';
      case 'kml':
        return '.kml';
      case 'shapefile':
        return '.shp';
      default:
        return '.txt';
    }
  }

  /// 文字列からFileFormat enumに変換
  FileFormat _parseFileFormat(String format) {
    switch (format) {
      case 'geojson':
        return FileFormat.geojson;
      case 'csv':
        return FileFormat.csv;
      case 'kml':
        return FileFormat.kml;
      case 'shapefile':
        return FileFormat.shapefile;
      default:
        return FileFormat.geojson;
    }
  }

  // _convertFeatureNodeToGeoJsonメソッドは削除
  // レイヤーエクスポートと同じ処理フローを使用するため不要
}
