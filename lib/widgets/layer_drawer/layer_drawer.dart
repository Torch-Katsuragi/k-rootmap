/// K-MAPS: レイヤ構造Drawerウィジェット（メインファイル）
/// プロジェクトフォルダ・サブフォルダ・GeoPackage・レイヤの階層構造をファイルエクスプローラ風に1階層のみリスト表示し、
/// 可視切り替え・リネーム・削除などの操作を提供するUI。
library;

import 'dart:io'; // Debug logging + file operations
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:latlong2/latlong.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/feature_node.dart'; // FeatureNodeをインポート
import '../../models/nodes/image_node.dart';
import '../../models/nodes/global_folder_node.dart'; // グローバルフォルダ
import '../../models/geopackage/geopackage_file.dart';
import 'layer_drawer_title_bar.dart';
import 'layer_drawer_tiles.dart';
import 'layer_drawer_utils.dart';
import 'layer_drawer_import_export.dart';

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

class _LayerDrawerState extends State<LayerDrawer>
    with LayerDrawerTiles, LayerDrawerUtils, LayerDrawerImportExport {
  /// 展開中のGeoPackageノードのファイルパスを保持
  @override
  final Set<String> expandedGpkgPaths = {};

  /// ユーザーが明示的に閉じたGeoPackageノードのパスを記録
  final Set<String> _userClosedGpkgPaths = {};

  /// ドラッグ中のファイル管理
  bool _isDragging = false;
  GeoPackageNode? _dragTargetGeoPackageNode;

  @override
  void Function(void Function()) get setStateCallback =>
      widget.setStateCallback;

  @override
  void Function(LatLng latLng)? get onJumpTo => widget.onJumpTo;

  @override
  void Function(FeatureNode feature)? get onStartAppendMode =>
      widget.onStartAppendMode;

  @override
  bool get isDragging => _isDragging;

  @override
  set isDragging(bool value) {
    setState(() {
      _isDragging = value;
    });
  }

  @override
  GeoPackageNode? get dragTargetGeoPackageNode => _dragTargetGeoPackageNode;

  @override
  set dragTargetGeoPackageNode(GeoPackageNode? node) {
    setState(() {
      _dragTargetGeoPackageNode = node;
    });
  }

  @override
  Set<String> get userClosedGpkgPaths => _userClosedGpkgPaths;

  @override
  LayerTreeNode? get currentNode => widget.currentNode;

  @override
  void initState() {
    super.initState();
    // デフォルトで全gpkgノードを展開状態に
    expandAllGeoPackageNodes(widget.currentNode, expandedGpkgPaths);
  }

  @override
  void didUpdateWidget(LayerDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // currentNodeが変更された場合のみ自動展開（新しいディレクトリに移動した場合）
    if (oldWidget.currentNode != widget.currentNode) {
      _userClosedGpkgPaths.clear(); // 新しいディレクトリでは閉じた履歴をリセット
      expandAllGeoPackageNodes(widget.currentNode, expandedGpkgPaths);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.currentNode == null) {
      return const Center(child: Text('ディレクトリが見つかりません'));
    }

    // 新しいGeoPackageノードが追加されていれば自動展開（ユーザーが閉じたものは除く）
    expandNewGeoPackageNodesOnly(
      widget.currentNode,
      expandedGpkgPaths,
      _userClosedGpkgPaths,
    );

    return Container(
      decoration:
          _isDragging
              ? BoxDecoration(
                border: Border.all(color: Colors.blue, width: 2),
                borderRadius: BorderRadius.circular(8),
                color: Colors.blue.withValues(alpha: 0.1),
              )
              : null,
      child: Column(
        children: [
          LayerDrawerTitleBar(
            title: widget.currentNode!.name,
            currentNode: widget.currentNode!,
            onAddFolder:
                widget.currentNode is FolderNode
                    ? () => _addFolder(context)
                    : null,
            onAddGeoPackage:
                widget.currentNode is FolderNode
                    ? () => _addGeoPackage(context)
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
                color: Colors.blue.withValues(alpha: 0.2),
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
                    return buildFolderTile(
                      context,
                      node,
                      () => widget.onDirChanged(node),
                    );
                  } else if (node is ImageNode) {
                    return buildPhotoTile(
                      context,
                      node,
                      onRename: () => _renamePhoto(context, node),
                    );
                  } else if (node is GeoPackageNode) {
                    return buildGeoPackageTile(
                      context,
                      node,
                      onRename: () => _renameGeoPackage(context, node),
                    );
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

  /// 写真のリネーム処理
  Future<void> _renamePhoto(BuildContext context, ImageNode node) async {
    AppLogger.debug('[DEBUG] _renamePhoto: 開始 - ${node.name}');
    String input = p.basenameWithoutExtension(node.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('写真のリネーム'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: '新しいファイル名'),
            controller: TextEditingController(text: input),
            onChanged: (v) => input = v,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.pop(context, value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, input),
              child: const Text('変更'),
            ),
          ],
        );
      },
    );

    AppLogger.debug('[DEBUG] _renamePhoto: ダイアログ結果 = $result');

    if (result != null && result.isNotEmpty && result != p.basenameWithoutExtension(node.name)) {
      try {
        final newName = result;
        AppLogger.debug('[DEBUG] _renamePhoto: rename呼び出し - $newName');
        await node.rename(newName);
        AppLogger.debug('[DEBUG] _renamePhoto: rename完了');
        
        // 親フォルダの再スキャンを確実に行うために
        // node.rename() 内で parent.updateChildren() が呼ばれているが
        // ここでも明示的に呼び、UI更新コールバックを実行する
        if (node.parent != null) {
          await node.parent!.updateChildren();
        }
        
        widget.setStateCallback(() {});
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('写真をリネームしました: $newName')),
          );
        }
      } catch (e) {
        AppLogger.debug('[ERROR] _renamePhoto: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('リネームに失敗しました: $e')),
          );
        }
      }
    }
  }

  /// GeoPackageのリネーム処理
  Future<void> _renameGeoPackage(BuildContext context, GeoPackageNode node) async {
    String input = p.basenameWithoutExtension(node.name);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('GeoPackageのリネーム'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: '新しいファイル名'),
            controller: TextEditingController(text: input),
            onChanged: (v) => input = v,
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.pop(context, value.trim());
              }
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, input),
              child: const Text('変更'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty && result != p.basenameWithoutExtension(node.name)) {
      try {
        // リネーム前のパスと展開状態を保持
        final oldPath = node.geoPackageFile.getAbsolutePath();
        final wasExpanded = oldPath != null && expandedGpkgPaths.contains(oldPath);
        final parentNode = node.parent;
        
        // リネーム実行（新しいファイル名が返される）
        final newFileName = await node.rename(result);
        
        // 親フォルダの再スキャンを実行（新しいノードが生成される）
        if (parentNode != null) {
          await parentNode.updateChildren();
        }
        
        // 展開状態を新しいパスに引き継ぐ
        if (oldPath != null && wasExpanded) {
          expandedGpkgPaths.remove(oldPath);
          final parentPath = p.dirname(oldPath);
          final newPath = p.join(parentPath, newFileName);
          expandedGpkgPaths.add(newPath);
          
          // 新しいノードを探してレイヤー情報をロード
          if (parentNode != null) {
            for (final child in parentNode.children) {
              if (child is GeoPackageNode) {
                final childPath = child.geoPackageFile.getAbsolutePath();
                if (childPath == newPath) {
                  await child.updateChildren();
                  break;
                }
              }
            }
          }
        }
        
        widget.setStateCallback(() {});
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('GeoPackageをリネームしました: $newFileName')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('リネームに失敗しました: $e')),
          );
        }
      }
    }
  }

  /// フォルダ追加処理
  Future<void> _addFolder(BuildContext context) async {
    String input = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新規サブフォルダ'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'フォルダ名'),
            onChanged: (v) => input = v,
            onSubmitted: (value) {
              // Enterキーが押された場合、フォルダ名が空でなければ作成処理を実行
              if (value.trim().isNotEmpty) {
                Navigator.pop(context, value.trim());
              }
            },
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
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('同名のフォルダが既に存在します')));
        }
        return;
      }
      Directory(path).createSync();
      
      // グローバルフォルダ内の場合はGlobalSubFolderNodeとして作成
      if (folderNode is GlobalFolderNode) {
        folderNode.addChild(
          GlobalSubFolderNode(
            result,
            basePath: folderNode.globalPath,
            visible: true,
            parent: folderNode,
          ),
        );
      } else if (folderNode is GlobalSubFolderNode) {
        folderNode.addChild(
          GlobalSubFolderNode(
            result,
            basePath: folderNode.basePath,
            visible: true,
            parent: folderNode,
          ),
        );
      } else {
        folderNode.addChild(
          FolderNode(result, visible: true, parent: folderNode),
        );
      }
      widget.setStateCallback(() {});
    }
  }

  /// GeoPackage追加処理
  Future<void> _addGeoPackage(BuildContext context) async {
    String input = '';
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('新規GeoPackageファイル'),
          content: TextField(
            autofocus: true,
            decoration: const InputDecoration(labelText: 'ファイル名（.gpkg）'),
            onChanged: (v) => input = v,
            onSubmitted: (value) {
              // Enterキーが押された場合、ファイル名が空でなければ作成処理を実行
              if (value.trim().isNotEmpty) {
                Navigator.pop(context, value.trim());
              }
            },
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
      AppLogger.debug('[LayerDrawer] GeoPackage作成開始: $result');

      final folderNode = widget.currentNode as FolderNode;
      final dir = folderNode.getAbsoluteFilePath();
      final fileName = result.endsWith('.gpkg') ? result : '$result.gpkg';
      final path = p.join(dir ?? '', fileName);

      AppLogger.debug('[LayerDrawer] 作成予定パス: $path');
      AppLogger.debug('[LayerDrawer] 親ディレクトリ: $dir');

      if (File(path).existsSync()) {
        AppLogger.debug('[LayerDrawer] 同名ファイルが既に存在します');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('同名のGeoPackageファイルが既に存在します')),
          );
        }
        return;
      }

      AppLogger.debug('[LayerDrawer] GeoPackageNodeを作成中...');
      final parentNode = widget.currentNode as FolderNode;
      
      // グローバルフォルダ内の場合は絶対パスモードでGeoPackageを作成
      final bool isGlobalFolder = parentNode is GlobalFolderNode || parentNode is GlobalSubFolderNode;
      final GeoPackageFile gpkgFile;
      final GeoPackageNode newNode;
      
      if (isGlobalFolder) {
        // グローバルフォルダ内：絶対パスモード
        gpkgFile = GeoPackageFile([fileName], absolutePath: path);
        newNode = GlobalGeoPackageNode(
          gpkgFile,
          absolutePath: path,
          visible: true,
          parent: folderNode,
        );
        AppLogger.debug('[LayerDrawer] GlobalGeoPackageFile作成: absolutePath=$path');
      } else {
        // 通常フォルダ：相対パスモード
        final parentPath = parentNode.getAbsolutePathSegments();
        final fileNameList = [fileName];
        gpkgFile = GeoPackageFile([...parentPath, ...fileNameList]);
        newNode = GeoPackageNode(
          gpkgFile,
          visible: true,
          parent: folderNode,
        );
        AppLogger.debug('[LayerDrawer] GeoPackageFile作成: pathList=${gpkgFile.pathList}');
      }

      folderNode.addChild(newNode);

      // 空のGeoPackageファイルを即座に作成
      AppLogger.debug('[LayerDrawer] 空のGeoPackageファイル作成中...');
      final createSuccess = await gpkgFile.createEmptyDatabase();
      if (!createSuccess) {
        AppLogger.debug('[LayerDrawer] 空のGeoPackageファイル作成失敗');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('GeoPackageファイルの作成に失敗しました')),
          );
        }
        // 作成失敗時はノードを削除
        folderNode.removeChild(newNode);
        return;
      }

      // 新規作成されたGeoPackageを自動展開
      final newAbsPath = gpkgFile.getAbsolutePath();
      AppLogger.debug('[LayerDrawer] 新規GeoPackage絶対パス: $newAbsPath');
      if (newAbsPath != null) {
        expandedGpkgPaths.add(newAbsPath);
      }

      AppLogger.debug('[LayerDrawer] UI更新中...');
      widget.setStateCallback(() {});
      AppLogger.debug('[LayerDrawer] GeoPackage作成完了');
    }
  }
}

