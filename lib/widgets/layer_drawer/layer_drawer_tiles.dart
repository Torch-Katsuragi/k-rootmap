/// K-MAPS: LayerDrawer用各種タイル描画ロジック
library;

import 'dart:io' show Directory, Platform;
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/image_node.dart';
import '../../models/nodes/drive_folder_node.dart';
import '../../models/nodes/global_folder_node.dart';
import '../../models/geometry_type.dart';
import '../../utils/global_config.dart';
import '../../services/google_drive/index.dart';
import '../../services/kmeta_service.dart';
import '../../utils/feature_calc_utils.dart';
import '../../services/import_export_service.dart';
import '../../services/geometry_conversion_service.dart';
import '../../widgets/dialog_manager.dart';
import '../../widgets/geometry_conversion_dialogs.dart';
import '../../screens/layer_style_settings_screen.dart';
import '../../presentation/node_presenter.dart';
import 'sync_merge_dialog.dart';

/// 各種タイル描画機能を提供するミックスイン
mixin LayerDrawerTiles {
  /// 現在選択されているレイヤノード

  /// 状態更新コールバック
  void Function(void Function()) get setStateCallback;

  /// 地図ジャンプ用コールバック
  void Function(LatLng latLng)? get onJumpTo;

  /// 追記モード開始用コールバック
  void Function(FeatureNode feature)? get onStartAppendMode;

  /// ドラッグ関連状態
  bool get isDragging;
  set isDragging(bool value);

  GeoPackageNode? get dragTargetGeoPackageNode;
  set dragTargetGeoPackageNode(GeoPackageNode? node);

  /// 展開状態管理
  Set<String> get expandedGpkgPaths;
  Set<String> get userClosedGpkgPaths;

  /// ImportExportService
  ImportExportService get importExportService;

  /// マップの強制更新をトリガー
  void triggerMapRefresh();

  /// 現在開いているノード（フォルダ）
  LayerTreeNode? get currentNode;

  /// モバイルかどうか（Drive連携機能はモバイル専用）
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// フォルダタイルを構築
  Widget buildFolderTile(
    BuildContext context,
    FolderNode node,
    VoidCallback onTap,
  ) {
    // DriveFolderNodeの場合は同期メニュー付き（モバイルのみ）
    if (node is DriveFolderNode && _isMobile) {
      return ListTile(
        leading: _buildDriveFolderIcon(node),
        title: Text(node.name),
        subtitle: _buildDriveFolderSubtitle(node),
        onTap: onTap,
        trailing: _buildDriveFolderMenu(context, node),
      );
    }

    // DriveFolderNodeだがPC版の場合はアイコンのみ変更（同期メニューなし）
    if (node is DriveFolderNode && !_isMobile) {
      return ListTile(
        leading: Icon(Icons.cloud, color: Colors.blue.shade600),
        title: Text(node.name),
        subtitle: const Text('PC版では同期不可（Google Drive Desktop使用）',
            style: TextStyle(fontSize: 10, color: Colors.grey)),
        onTap: onTap,
      );
    }

    // 通常のフォルダ
    return ListTile(
      leading: _buildIconWithVisibility(node),
      title: Text(node.name),
      onTap: onTap,
    );
  }

  /// Drive連携フォルダのアイコンを構築
  Widget _buildDriveFolderIcon(DriveFolderNode node) {
    return NodePresenter.buildIconWithSyncOverlay(
      node,
      size: 24,
      syncStatus: node.syncStatus,
    );
  }

  /// Drive連携フォルダのサブタイトルを構築
  Widget? _buildDriveFolderSubtitle(DriveFolderNode node) {
    String statusText;
    Color statusColor;
    
    switch (node.syncStatus) {
      case SyncStatus.synced:
        statusText = '同期済み';
        statusColor = Colors.green;
        break;
      case SyncStatus.localChanges:
        statusText = 'ローカル変更あり';
        statusColor = Colors.orange;
        break;
      case SyncStatus.remoteChanges:
        statusText = 'Drive変更あり';
        statusColor = Colors.blue;
        break;
      case SyncStatus.conflict:
        statusText = '競合あり';
        statusColor = Colors.red;
        break;
      case SyncStatus.syncing:
        statusText = '同期中...';
        statusColor = Colors.blue;
        break;
      case SyncStatus.error:
        statusText = 'エラー';
        statusColor = Colors.red;
        break;
      case SyncStatus.unknown:
        statusText = node.isReadOnly ? '読み取り専用' : 'Drive連携';
        statusColor = Colors.grey;
        break;
    }
    
    return Text(
      statusText,
      style: TextStyle(fontSize: 12, color: statusColor),
    );
  }

  /// Drive連携フォルダのメニューを構築
  Widget _buildDriveFolderMenu(BuildContext context, DriveFolderNode node) {
    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'upload':
            await _openSyncMergeDialog(context, node, mode: SyncMode.upload);
            break;
          case 'download':
            await _openSyncMergeDialog(context, node, mode: SyncMode.download);
            break;
          case 'refresh':
            await _refreshSyncStatus(node);
            break;
          case 'unlink':
            await _unlinkDriveFolder(context, node);
            break;
          case 'delete':
            await _deleteDriveFolder(context, node);
            break;
        }
      },
      itemBuilder: (context) => [
        if (!node.isReadOnly)
          const PopupMenuItem(
            value: 'upload',
            child: ListTile(
              leading: Icon(Icons.cloud_upload, color: Colors.orange),
              title: Text('アップロード'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem(
          value: 'download',
          child: ListTile(
            leading: Icon(Icons.cloud_download, color: Colors.green),
            title: Text('ダウンロード'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'refresh',
          child: ListTile(
            leading: Icon(Icons.refresh, color: Colors.blue),
            title: Text('状態を更新'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'unlink',
          child: ListTile(
            leading: Icon(Icons.link_off, color: Colors.red),
            title: Text('Drive連携を解除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text('フォルダごと削除'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  /// 同期状態を更新（UIのみ、ダイアログなし）
  Future<void> _refreshSyncStatus(DriveFolderNode node) async {
    final localPath = node.getAbsoluteFilePath();
    if (localPath == null) return;

    node.syncStatus = SyncStatus.syncing;
    setStateCallback(() {});

    try {
      final syncEngine = SyncEngine();
      final detail = await syncEngine.checkSyncStatusDetail(localPath);
      _updateNodeSyncStatus(node, detail.status);
    } catch (e) {
      node.syncStatus = SyncStatus.error;
    }

    setStateCallback(() {});
  }

  /// 子ノードを再帰的に更新（フォルダ・GeoPackage両方）
  Future<void> _updateChildrenRecursive(LayerTreeNode node) async {
    await node.updateChildren();
    for (final child in node.children) {
      if (child is FolderNode) {
        await _updateChildrenRecursive(child);
      } else if (child is GeoPackageNode) {
        await child.updateChildren();
      }
    }
  }

  /// Drive操作前の認証チェック
  /// 未認証の場合はサインインを試みる
  /// トークン期限切れの場合はリフレッシュを試みる
  Future<bool> _ensureDriveAuthenticated(BuildContext context) async {
    final driveService = GoogleDriveService();
    
    // 既に認証済みならOK
    if (driveService.isDriveApiAvailable) {
      // トークンをリフレッシュして最新状態に
      await driveService.refreshToken();
      return true;
    }
    
    // サイレントサインインを試行（initialize内で実行される）
    await driveService.initialize();
    if (driveService.isDriveApiAvailable) {
      return true;
    }
    
    // 明示的なサインインを試行
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Driveにログインしています...'),
        duration: Duration(seconds: 3),
      ),
    );
    
    final signInResult = await driveService.signIn();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    
    if (signInResult) {
      return true;
    }
    
    // サインイン失敗
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Google Driveへのログインに失敗しました'),
        backgroundColor: Colors.red,
      ),
    );
    return false;
  }

  /// 同期マージダイアログを開く
  Future<void> _openSyncMergeDialog(
    BuildContext context,
    DriveFolderNode node, {
    required SyncMode mode,
  }) async {
    final localPath = node.getAbsoluteFilePath();
    if (localPath == null) return;

    // 認証チェック
    if (!await _ensureDriveAuthenticated(context)) return;

    try {
      node.syncStatus = SyncStatus.syncing;
      setStateCallback(() {});

      // ローディングダイアログを即座に表示
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('変更を確認しています...'),
            ],
          ),
        ),
      );

      final syncEngine = SyncEngine();
      final entries = await syncEngine.getMergeEntries(localPath);

      // ローディングダイアログを閉じる
      if (context.mounted) Navigator.of(context).pop();

      if (!context.mounted) return;

      // 変更がない場合
      if (entries.isEmpty) {
        node.syncStatus = SyncStatus.synced;
        setStateCallback(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('変更はありません'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      // マージダイアログを表示
      final decisions = await SyncMergeDialog.show(
        context,
        folderName: node.name,
        entries: entries,
        mode: mode,
      );

      if (decisions == null || decisions.isEmpty) {
        // キャンセルされた場合は状態を再確認
        final detail = await syncEngine.checkSyncStatusDetail(localPath);
        _updateNodeSyncStatus(node, detail.status);
        setStateCallback(() {});
        return;
      }

      // マージを実行
      node.syncStatus = SyncStatus.syncing;
      setStateCallback(() {});

      final result = await syncEngine.executeMerge(localPath, decisions);

      if (result.success) {
        node.syncStatus = SyncStatus.synced;
        
        // ローカルファイル変更があった場合は子ノードを再帰的に再読み込み
        if (result.downloadedCount > 0 || result.deletedCount > 0) {
          await _updateChildrenRecursive(node);
          triggerMapRefresh();
          setStateCallback(() {});
        }
        
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '同期完了: ${result.uploadedCount}アップロード, '
                '${result.downloadedCount}ダウンロード, '
                '${result.deletedCount}削除',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        node.syncStatus = SyncStatus.error;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('エラー: ${result.errorMessage}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      node.syncStatus = SyncStatus.error;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('エラー: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setStateCallback(() {});
  }

  /// ノードの同期状態を更新
  void _updateNodeSyncStatus(DriveFolderNode node, FolderSyncStatus status) {
    switch (status) {
      case FolderSyncStatus.synced:
        node.syncStatus = SyncStatus.synced;
        break;
      case FolderSyncStatus.localChanges:
        node.syncStatus = SyncStatus.localChanges;
        break;
      case FolderSyncStatus.remoteChanges:
        node.syncStatus = SyncStatus.remoteChanges;
        break;
      case FolderSyncStatus.conflict:
        node.syncStatus = SyncStatus.conflict;
        break;
      case FolderSyncStatus.notLinked:
      case FolderSyncStatus.error:
        node.syncStatus = SyncStatus.error;
        break;
    }
  }

  /// Drive連携を解除
  Future<void> _unlinkDriveFolder(BuildContext context, DriveFolderNode node) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Drive連携を解除'),
        content: Text(
          '${node.name} のDrive連携を解除しますか？\n\nローカルファイルは削除されません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('解除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final folderPath = node.getAbsoluteFilePath();
    if (folderPath == null) return;

    // .kmeta.jsonからDrive連携情報をクリア
    await KMetaService.instance.unlinkDrive(folderPath);

    // DriveFolderNodeを通常のFolderNode（またはGlobalSubFolderNode）に置換
    final parentNode = node.parent;
    if (parentNode != null) {
      final index = parentNode.children.indexOf(node);
      if (index >= 0) {
        LayerTreeNode replacement;
        if (parentNode is GlobalFolderNode) {
          replacement = GlobalSubFolderNode(
            node.name,
            basePath: parentNode.globalPath,
            visible: node.visible,
            parent: parentNode,
            children: [],
          );
        } else if (parentNode is GlobalSubFolderNode) {
          replacement = GlobalSubFolderNode(
            node.name,
            basePath: parentNode.basePath,
            visible: node.visible,
            parent: parentNode,
            children: [],
          );
        } else {
          replacement = FolderNode(
            node.name,
            visible: node.visible,
            parent: parentNode,
            children: [],
          );
        }
        parentNode.children[index] = replacement;
        node.parent = null;
      }
    }

    setStateCallback(() {});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Drive連携を解除しました')),
      );
    }
  }

  /// Drive連携フォルダをローカルから完全削除
  Future<void> _deleteDriveFolder(BuildContext context, DriveFolderNode node) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('フォルダ削除'),
        content: Text(
          '${node.name} をローカルから完全に削除しますか？\n\n'
          'フォルダ内のすべてのファイルが削除されます。\n'
          'Drive上のデータには影響しません。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final folderPath = node.getAbsoluteFilePath();
    if (folderPath == null) return;

    try {
      final dir = Directory(folderPath);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
      node.parent?.removeChild(node);
      setStateCallback(() {});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${node.name} を削除しました')),
        );
      }
    } catch (e) {
      AppLogger.error('[LayerDrawerTiles] フォルダ削除エラー: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
      }
    }
  }

  /// 写真タイルを構築（画像ファイル）
  Widget buildPhotoTile(
    BuildContext context,
    ImageNode node, {
    VoidCallback? onRename,
  }) {
    return ListTile(
      leading: _buildIconWithVisibility(node),
      title: Text(
        node.name,
        style: node.hasLocation ? null : const TextStyle(fontStyle: FontStyle.italic),
      ),
      subtitle: node.hasLocation ? null : const Text('位置情報なし', style: TextStyle(fontSize: 11)),
      onTap: () {
        GlobalConfig.instance.selectedFeatures.clear();
        GlobalConfig.instance.selectedFeatures.add(node);

        if (node.hasLocation && onJumpTo != null) {
          onJumpTo!(node.location!);
        }

        setStateCallback(() {});
      },
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            // リネーム処理（onRenameコールバックを実行）
            if (onRename != null) onRename();
          } else if (value == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder:
                  (context) => AlertDialog(
                    title: const Text('写真削除'),
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
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('削除'),
                      ),
                    ],
                  ),
            );
            if (confirm == true) {
              try {
                // 削除されるImageNodeが選択されている場合は選択状態をクリア
                GlobalConfig.instance.selectedFeatures.remove(node);

                await node.dispose();

                // マップのフィーチャキャッシュを更新
                triggerMapRefresh();

                setStateCallback(() {});
                
                // 成功メッセージを表示
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('写真を削除しました: ${node.name}'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                // エラーメッセージを表示
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('写真の削除に失敗しました: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            }
          }
        },
        itemBuilder: (context) {
          AppLogger.debug('[DEBUG] buildPhotoTile: itemBuilder called');
          return [
            const PopupMenuItem(value: 'rename', child: Text('名前の変更')),
            const PopupMenuItem(value: 'delete', child: Text('削除')),
          ];
        },
      ),
    );
  }

  /// GeoPackageタイルを構築
  Widget buildGeoPackageTile(
    BuildContext context,
    GeoPackageNode node, {
    VoidCallback? onRename,
  }) {
    final absPath = node.geoPackageFile.getAbsolutePath();
    final isExpanded = absPath != null && expandedGpkgPaths.contains(absPath);
    final isDropTarget = isDragging && dragTargetGeoPackageNode == node;

    // レイヤドロップターゲットの内容を構築
    final geoPackageContent = Column(
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
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'DROP LAYER HERE',
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
            if (isExpanded) {
              // 閉じる場合：展開リストから削除し、ユーザーが閉じたことを記録
              expandedGpkgPaths.remove(absPath);
              userClosedGpkgPaths.add(absPath);
            } else {
              // 展開する場合：展開リストに追加し、ユーザーが閉じた記録を削除
              if (absPath != null) {
                expandedGpkgPaths.add(absPath);
                userClosedGpkgPaths.remove(absPath);
              }
            }
            setStateCallback(() {});
          },
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'rename') {
                    if (onRename != null) onRename();
                  } else if (value == 'delete') {
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
                          GlobalConfig.instance.selectedFeatures.removeWhere((
                            feature,
                          ) {
                            if (feature is FeatureNode) {
                              return feature.parent == layer;
                            }
                            return false;
                          });
                        }

                        // geopackageノード削除（ファイルも含めて削除）
                        await node.dispose();

                        // マップのフィーチャキャッシュを更新
                        triggerMapRefresh();

                        setStateCallback(() {});
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${node.name} を削除しました')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('削除に失敗しました: $e')),
                          );
                        }
                      }
                    }
                  }
                },
                itemBuilder:
                    (context) => [
                      const PopupMenuItem(value: 'rename', child: Text('名前の変更')),
                      const PopupMenuItem(value: 'delete', child: Text('削除')),
                    ],
              ),
            ],
          ),
        ),
        if (isExpanded) ...[
          ...node.children.map(
            (layerNode) => buildLayerTile(context, layerNode as LayerNode),
          ),
          // レイヤリストの最下部にレイヤ追加ボタンを表示
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 32, top: 4, bottom: 4),
              child: buildAddLayerButton(context, node),
            ),
          ),
        ],
      ],
    );

    // レイヤドロップ対応のDragTargetでラップ
    final layerDragTarget = DragTarget<LayerNode>(
      onAcceptWithDetails: (details) async {
        final sourceLayer = details.data;
        await _handleLayerDrop(context, sourceLayer, node);

        // ドロップ完了後にフラグをリセット
        isDragging = false;
        dragTargetGeoPackageNode = null;
        setStateCallback(() {});
      },
      onWillAcceptWithDetails: (details) {
        // レイヤドロップを受け入れるかどうかの判定
        final sourceLayer = details.data;

        // 自分自身の親GeoPackageには移植できない
        if (sourceLayer.geoPackageNode == node) {
          return false;
        }

        return true;
      },
      onMove: (details) {
        // ドラッグがこのターゲット上に移動した時
        if (!isDragging || dragTargetGeoPackageNode != node) {
          isDragging = true;
          dragTargetGeoPackageNode = node;
          setStateCallback(() {});
        }
      },
      onLeave: (data) {
        // ドラッグがこのターゲットから離れた時
        if (dragTargetGeoPackageNode == node) {
          dragTargetGeoPackageNode = null;
          setStateCallback(() {});
        }
      },
      builder: (context, candidateData, rejectedData) {
        return Container(
          decoration:
              isDropTarget
                  ? BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 2),
                    borderRadius: BorderRadius.circular(4),
                    color: Colors.blue.withValues(alpha: 0.1),
                  )
                  : null,
          child: geoPackageContent,
        );
      },
    );

    // ファイルドロップ対応のDropTargetでラップ（外側）
    return DropTarget(
      onDragEntered: (details) {
        // ファイルドラッグの場合のみ処理
        if (!isDragging || dragTargetGeoPackageNode != node) {
          isDragging = true;
          dragTargetGeoPackageNode = node;
          setStateCallback(() {});
        }
      },
      onDragExited: (details) {
        if (dragTargetGeoPackageNode == node) {
          dragTargetGeoPackageNode = null;
          isDragging = false;
          setStateCallback(() {});
        }
      },
      onDragDone: (details) async {
        if (details.files.isNotEmpty) {
          // 複数ファイルのドロップに対応
          for (final file in details.files) {
            await _handleSpecificGeoPackageDrop(file.path, node);
          }

          // 処理完了後にフラグをリセット
          isDragging = false;
          dragTargetGeoPackageNode = null;
          setStateCallback(() {});
        }
      },
      child: layerDragTarget,
    );
  }

  /// レイヤタイルを構築（可視切り替え・選択・削除・ドラッグアンドドロップ）
  Widget buildLayerTile(BuildContext context, LayerNode node) {
    final isSelected = GlobalConfig.instance.selectedLayerNode == node;

    // レイヤタイルの内容を構築（GestureDetectorでonTap/onDoubleTapを制御）
    final layerTileContent = GestureDetector(
      onTap: () {
        GlobalConfig.instance.selectedLayerNode = node;
        setStateCallback(() {});
      },
      onDoubleTap: () {
        final coords = node.getAllCoordinates();
        if (coords.isEmpty) return;
        final mapController = GlobalConfig.instance.mapState?.mapController;
        if (mapController == null) return;
        mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: coords,
            padding: const EdgeInsets.all(50),
          ),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 32, right: 16),
        leading: GestureDetector(
          onTap: () {
            node.visible = !node.visible;
            node.persistVisibility();
            GlobalConfig.instance.mapState?.refreshFeatures();
            setStateCallback(() {});
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color:
                      isSelected
                          ? Colors.blue.withValues(alpha: 0.15)
                          : Colors.transparent,
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  NodePresenter.getIcon(node),
                  color:
                      isSelected
                          ? Colors.blue
                          : (node.isVisibleRecursive()
                              ? NodePresenter.getColor(node)
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
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'rename') {
            // レイヤー名変更ダイアログ
            await _showRenameLayerDialog(context, node);
          } else if (value == 'style') {
            // スタイル設定画面を開く
            await _openLayerStyleSettings(context, node);
          } else if (value == 'delete') {
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
              triggerMapRefresh();

              // UI更新
              setStateCallback(() {});
            }
          } else if (value == 'export') {
            // DialogManagerを使用してレイヤーエクスポートダイアログを表示
            await DialogManager.showLayerExportDialog(
              context,
              sourceLayer: node,
            );
          } else if (value == 'convert_to_line' && node is PointLayerNode) {
            await _convertPointsToLine(context, node);
          } else if (value == 'merge' && node is PolygonLayerNode) {
            await _mergePolygonsInLayer(context, node);
          } else if (value == 'absorb') {
            await _absorbMatchingLayers(context, node);
          }
        },
        itemBuilder:
            (context) => [
              // リネーム
              const PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit, size: 16),
                    SizedBox(width: 8),
                    Text('Rename'),
                  ],
                ),
              ),
              // スタイル設定
              const PopupMenuItem(
                value: 'style',
                child: Row(
                  children: [
                    Icon(Icons.palette, size: 16),
                    SizedBox(width: 8),
                    Text('Style'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
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
              // PointLayerNodeの場合のみ変換メニューを表示
              if (node is PointLayerNode)
                const PopupMenuItem(
                  value: 'convert_to_line',
                  child: Row(
                    children: [
                      Icon(Icons.transform, size: 16),
                      SizedBox(width: 8),
                      Text('ライン/ポリゴンに変換'),
                    ],
                  ),
                ),
              // PolygonLayerNodeの場合のみ合成メニューを表示
              if (node is PolygonLayerNode)
                const PopupMenuItem(value: 'merge', child: Text('合成')),
              // 同一GeoPackage内のカラム一致レイヤーを吸収
              const PopupMenuItem(
                value: 'absorb',
                child: Row(
                  children: [
                    Icon(Icons.merge_type, size: 16),
                    SizedBox(width: 8),
                    Text('同構造レイヤを吸収'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'delete', child: Text('削除')),
            ],
      ),
      ),
    );

    // LongPressDraggableでラップしてドラッグ機能を追加
    return LongPressDraggable<LayerNode>(
      data: node,
      dragAnchorStrategy:
          (draggable, context, position) => const Offset(0, 0), // ドラッグ開始位置を調整
      feedback: Material(
        elevation: 8.0,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 280, // フィードバックの幅を固定
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                NodePresenter.buildIcon(node),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.drag_indicator, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
      childWhenDragging: Container(
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Opacity(opacity: 0.5, child: layerTileContent),
      ),
      onDragStarted: () {
        AppLogger.debug('[LayerDrawer] レイヤドラッグ開始: ${node.name}');
        // ドラッグ状態をONにして視覚的フィードバックを開始
        isDragging = true;
        setStateCallback(() {});
      },
      onDragEnd: (details) {
        AppLogger.debug('[LayerDrawer] レイヤドラッグ終了: ${node.name}');
        // ドラッグ状態をOFFにする
        isDragging = false;
        dragTargetGeoPackageNode = null;
        setStateCallback(() {});
      },
      child: layerTileContent,
    );
  }

  /// レイヤ追加ボタンを構築
  Widget buildAddLayerButton(BuildContext context, GeoPackageNode node) {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog<Map<String, String>>(
          context: context,
          builder: (context) => _NewLayerDialog(),
        );
        if (result != null &&
            result['name'] != null) {
          AppLogger.debug(
            '[LayerDrawer] レイヤ作成開始: ${result['name']}, タイプ: ${result['geomType']}',
          );

          // ジオメトリタイプに応じて適切なLayerNodeサブクラスを生成
          LayerTreeNode? newLayerNode;
          final geomTypeString = result['geomType']!;
          final geomType = GeometryType.fromString(geomTypeString);

          AppLogger.debug('[LayerDrawer] ジオメトリタイプ解析: $geomTypeString -> $geomType');

          try {
            switch (geomType) {
              case GeometryType.point:
                AppLogger.debug('[LayerDrawer] PointLayerNode作成中...');
                newLayerNode = await PointLayerNode.createIn(
                  node,
                  result['name']!,
                );
                break;
              case GeometryType.linestring:
                AppLogger.debug('[LayerDrawer] LineLayerNode作成中...');
                newLayerNode = await LineLayerNode.createIn(
                  node,
                  result['name']!,
                );
                break;
              case GeometryType.polygon:
                AppLogger.debug('[LayerDrawer] PolygonLayerNode作成中...');
                newLayerNode = await PolygonLayerNode.createIn(
                  node,
                  result['name']!,
                );
                break;
              case null:
                AppLogger.debug('[LayerDrawer] 不明なジオメトリタイプです');
                break;
            }

            if (newLayerNode != null) {
              AppLogger.debug('[LayerDrawer] レイヤ作成成功、UI更新中...');
              // 追加成功時のみUI更新
              setStateCallback(() {});
              // 地図本体も即時再描画
              GlobalConfig.instance.mapState?.setState(() {});
              AppLogger.debug('[LayerDrawer] レイヤ作成完了');
            } else {
              AppLogger.debug('[LayerDrawer] レイヤ作成失敗: newLayerNodeがnull');
            }
          } catch (e, stack) {
            AppLogger.debug('[LayerDrawer] レイヤ作成エラー: $e');
            AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
          }
        }
      },
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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

  /// 可視性アイコンを構築（タップで可視切り替え）
  Widget _buildIconWithVisibility(LayerTreeNode node) {
    return GestureDetector(
      onTap: () {
        node.visible = !node.visible;
        node.persistVisibility();
        GlobalConfig.instance.mapState?.refreshFeatures();
        setStateCallback(() {});
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            NodePresenter.getIcon(node),
            color: node.isVisibleRecursive() ? NodePresenter.getColor(node) : Colors.grey,
          ),
          if (!node.visible)
            Transform.rotate(
              angle: -0.7,
              child: Container(width: 32, height: 4, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  /// 写真の詳細情報を表示するダイアログ

  /// レイヤー名変更ダイアログ
  Future<void> _showRenameLayerDialog(
    BuildContext context,
    LayerNode node,
  ) async {
    final controller = TextEditingController(text: node.layerName);
    final formKey = GlobalKey<FormState>();

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename Layer'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Layer Name',
              hintText: 'Enter new layer name',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Name cannot be empty';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState?.validate() ?? false) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );

    if (newName != null && newName != node.layerName) {
      try {
        // レイヤー名を変更（DBテーブル名変更）
        await node.geoPackageFile.renameLayer(node.layerName, newName);
        // 親のGeoPackageNodeを更新
        await node.geoPackageNode.updateChildren();
        // マップを更新
        triggerMapRefresh();
        setStateCallback(() {});
        AppLogger.debug('[LayerDrawer] Layer renamed: ${node.layerName} -> $newName');
      } catch (e) {
        AppLogger.debug('[LayerDrawer] Rename failed: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rename failed: $e')),
          );
        }
      }
    }
  }

  /// スタイル設定画面を開く
  Future<void> _openLayerStyleSettings(
    BuildContext context,
    LayerNode node,
  ) async {
    // 親フォルダのパスを取得
    final folderNode = node.folderNode;
    final folderPath = folderNode?.getAbsoluteFilePath();

    if (folderPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not determine folder path')),
      );
      return;
    }

    // スタイル設定画面を開く
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LayerStyleSettingsScreen(
          targetLayer: node,
          folderPath: folderPath,
        ),
      ),
    );

    // 画面から戻ったらマップを更新
    triggerMapRefresh();
    setStateCallback(() {});
  }

  /// ポイントレイヤーをライン/ポリゴンに変換
  Future<void> _convertPointsToLine(
    BuildContext context,
    PointLayerNode sourceLayer,
  ) async {
    try {
      // ポイントレイヤー内の全フィーチャを取得
      final features = sourceLayer.features;
      
      if (features.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ポイントが存在しないため変換できません')),
        );
        return;
      }

      // カレントディレクトリ直下のGeoPackage内のライン/ポリゴンレイヤーを検索
      final targetLayers = GeometryConversionService.findTargetLayersForPoints(currentNode);
      
      if (targetLayers.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('カレントディレクトリ直下にライン/ポリゴンレイヤーが見つかりません。\n先にレイヤーを作成してください。')),
          );
        }
        return;
      }
      
      // ダイアログを表示
      final targetLayer = await showDialog<LayerNode>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          return ConvertPointsToGeometryDialog(
            sourceLayer: sourceLayer,
            availableLayers: targetLayers,
          );
        },
      );

      if (targetLayer == null) {
        return;
      }

      // 名前入力ダイアログを表示（ペンツールと同じパターン）
      String? featureName = await showDialog<String>(
        context: context,
        builder: (context) {
          String text = '';
          final typeLabel = targetLayer is LineLayerNode ? 'ライン' : 'ポリゴン';
          return AlertDialog(
            title: Text('$typeLabel フィーチャ名の入力'),
            content: TextField(
              autofocus: true,
              decoration: const InputDecoration(labelText: '名前（任意）'),
              onChanged: (v) => text = v,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('キャンセル'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, text),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

      // キャンセルされた場合は処理を中断
      if (featureName == null) {
        return;
      }

      // 変換サービスを使用してフィーチャを作成（入力された名前を渡す）
      final createdFeature = await GeometryConversionService.convertPointsToGeometry(
        sourceLayer: sourceLayer,
        targetLayer: targetLayer,
        name: featureName.isNotEmpty ? featureName : null, // 空の場合はnullを渡してデフォルト名を使用
      );

      if (createdFeature != null) {
        // UI更新とマップ反映
        await targetLayer.updateChildren();
        setStateCallback(() {});
        
        // マップの強制更新
        triggerMapRefresh();
        GlobalConfig.instance.mapState?.refreshFeatures();

        final typeLabel = targetLayer is LineLayerNode ? 'ライン' : 'ポリゴン';
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ポイントを$typeLabel に変換しました (${features.length}個の点)'),
            ),
          );
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('フィーチャの作成に失敗しました')));
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] ポイント変換エラー: $e');
      AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('変換処理中にエラーが発生しました: $e')));
      }
    }
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
                '${layerNode.name} 内の $mergeableCount 個のポリゴンを合成しますか？\n\n'
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
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ポリゴンの合成に失敗しました')));
        }
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
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('新しいレイヤーの作成に失敗しました')));
        }
        return;
      }

      // 合成されたポリゴンを新しいレイヤーに追加
      final mergedFeature = await PolygonFeatureNode.createIn(
        newLayerNode,
        mergedPolygon,
        'merged_polygon',
        '${layerNode.name}の$mergeableCount個のポリゴンを合成',
        metadata: {
          'source_layer': layerNode.name,
          'merged_count': mergeableCount,
          'created_at': DateTime.now().toIso8601String(),
        },
      );

      if (mergedFeature != null) {
        // UI更新
        setStateCallback(() {});
        GlobalConfig.instance.mapState?.setState(() {});

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ポリゴンを合成しました。新しいレイヤー「$newLayerName」に保存されました。'),
            ),
          );
        }

        AppLogger.debug('[LayerDrawer] ポリゴン合成完了: $newLayerName');
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('合成ポリゴンの保存に失敗しました')));
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] ポリゴン合成エラー: $e');
      AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('合成処理中にエラーが発生しました: $e')));
      }
    }
  }

  /// 同一GeoPackage内のカラム名が完全一致するレイヤーを吸収
  Future<void> _absorbMatchingLayers(
    BuildContext context,
    LayerNode targetNode,
  ) async {
    try {
      // 親のGeoPackageノードを取得
      final parentGpkg = targetNode.parent;
      if (parentGpkg is! GeoPackageNode) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('GeoPackage内のレイヤーではありません')),
        );
        return;
      }

      // ターゲットレイヤのカラム構造を取得
      final targetColumns = await parentGpkg.geoPackageFile.getTableColumns(targetNode.name);
      if (targetColumns.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レイヤーのカラム情報を取得できませんでした')),
        );
        return;
      }

      // 同一GeoPackage内の同じ型の他レイヤーを検索
      final siblingLayers = parentGpkg.children
          .whereType<LayerNode>()
          .where((layer) => layer != targetNode && layer.runtimeType == targetNode.runtimeType)
          .toList();

      if (siblingLayers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('同じ型の他のレイヤーがありません')),
        );
        return;
      }

      // カラム名が完全一致するレイヤーを検索
      final matchingLayers = <LayerNode>[];
      for (final layer in siblingLayers) {
        final layerColumns = await parentGpkg.geoPackageFile.getTableColumns(layer.name);
        // カラム名のセットが完全一致するか確認（順序は問わない）
        if (_columnsMatch(targetColumns, layerColumns)) {
          matchingLayers.add(layer);
        }
      }

      if (matchingLayers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('カラム構造が一致するレイヤーが見つかりません')),
        );
        return;
      }

      // 確認ダイアログを表示
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('レイヤー吸収'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('以下の ${matchingLayers.length} 件のレイヤーを「${targetNode.name}」に吸収しますか？\n'),
              ...matchingLayers.map((l) => Text('  • ${l.name}')),
              const SizedBox(height: 12),
              const Text('※吸収されたレイヤーは削除されます', style: TextStyle(color: Colors.red)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('吸収'),
            ),
          ],
        ),
      );

      if (confirm != true) return;

      // 吸収処理を実行
      int absorbedCount = 0;
      for (final sourceLayer in matchingLayers) {
        try {
          // ソースレイヤーのフィーチャをターゲットレイヤーにコピー
          final copied = await parentGpkg.geoPackageFile.copyFeaturesBetweenLayers(
            sourceLayer.name,
            targetNode.name,
          );
          
          if (copied > 0) {
            absorbedCount += copied;
            
            // ソースレイヤーを削除
            sourceLayer.dispose();
            
            AppLogger.debug('[LayerDrawer] レイヤー吸収完了: ${sourceLayer.name} -> ${targetNode.name} ($copied features)');
          }
        } catch (e) {
          AppLogger.debug('[LayerDrawer] レイヤー吸収エラー: ${sourceLayer.name} - $e');
        }
      }

      // ターゲットレイヤーのフィーチャを更新
      await targetNode.updateChildren();

      // UI更新
      triggerMapRefresh();
      setStateCallback(() {});

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$absorbedCount 件のフィーチャを吸収しました')),
        );
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] レイヤー吸収エラー: $e');
      AppLogger.debug('[LayerDrawer] スタックトレース: $stack');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('吸収処理中にエラーが発生しました: $e')),
        );
      }
    }
  }

  /// カラム構造が一致するか確認（geomカラムを除く属性カラムのみ比較）
  bool _columnsMatch(List<String> columns1, List<String> columns2) {
    // システムカラム（id, geom, fid等）を除外して比較
    final systemColumns = {'id', 'fid', 'geom', 'geometry', 'ROWID'};
    final attrs1 = columns1.where((c) => !systemColumns.contains(c.toLowerCase())).toSet();
    final attrs2 = columns2.where((c) => !systemColumns.contains(c.toLowerCase())).toSet();
    return attrs1.length == attrs2.length && attrs1.containsAll(attrs2);
  }

  /// 特定のGeoPackageノードへのファイルドロップを処理
  Future<void> _handleSpecificGeoPackageDrop(
    String filePath,
    GeoPackageNode targetNode,
  ) async {
    try {
      AppLogger.debug(
        '[LayerDrawer] GeoPackageドロップ処理開始: $filePath -> ${targetNode.name}',
      );

      // インポート実行
      final result = await importExportService.importFile(filePath, targetNode);

      if (result.success) {
        // 成功：レイヤーツリーを更新
        await targetNode.updateChildren();

        // 作成されたレイヤーノードもFeatureNodeを更新
        if (result.createdLayer != null) {
          AppLogger.debug(
            '[LayerDrawer] 作成されたレイヤーのフィーチャ更新: ${result.createdLayer!.layerName}',
          );
          await result.createdLayer!.updateChildren();

          // デバッグ：フィーチャが正しく読み込まれたかを確認
          final features = result.createdLayer!.features;
          AppLogger.debug(
            '[LayerDrawer] レイヤー「${result.createdLayer!.layerName}」のフィーチャ数: ${features.length}',
          );

          // デバッグ：最初のフィーチャの詳細
          if (features.isNotEmpty) {
            final firstFeature = features.first;
            AppLogger.debug(
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
        setStateCallback(() {});

        // マップページのフィーチャデータを強制更新
        triggerMapRefresh();

        // 追加の確実な更新（少し遅延させて実行）
        Future.delayed(const Duration(milliseconds: 500), () {
          triggerMapRefresh();
        });

        _showImportSuccess(result);

        AppLogger.debug('[LayerDrawer] GeoPackageドロップ処理完了');
      } else {
        _showImportError(result.errorMessage ?? 'Import failed');
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] GeoPackageドロップエラー: $e');
      AppLogger.debug('スタックトレース: $stack');
      _showImportError('Unexpected error during import: $e');
    }
  }

  /// インポート成功メッセージを表示
  void _showImportSuccess(ImportExportResult result) {
    // ScaffoldMessengerを使用するにはBuildContextが必要
    // このメソッドは呼び出し側でcontextを渡すように変更する必要がある
    AppLogger.debug('[LayerDrawer] インポート成功: ${result.metadata}');
  }

  /// インポートエラーメッセージを表示
  void _showImportError(String errorMessage) {
    // ScaffoldMessengerを使用するにはBuildContextが必要
    // このメソッドは呼び出し側でcontextを渡すように変更する必要がある
  }

  /// レイヤドロップ処理
  Future<void> _handleLayerDrop(
    BuildContext context,
    LayerNode sourceLayer,
    GeoPackageNode targetGeoPackage,
  ) async {
    try {
      AppLogger.debug(
        '[LayerDrawer] レイヤドロップ処理開始: ${sourceLayer.name} → ${targetGeoPackage.name}',
      );

      // ユーザーに移植確認を表示
      final confirm = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('レイヤ移植'),
              content: Text(
                '「${sourceLayer.name}」を「${targetGeoPackage.name}」に移植しますか？\n\n'
                '移植により、元のGeoPackageからこのレイヤは削除されます。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('移植'),
                ),
              ],
            ),
      );

      if (confirm != true) {
        AppLogger.debug('[LayerDrawer] レイヤ移植がキャンセルされました');
        return;
      }

      // 移植処理を実行
      AppLogger.debug('[LayerDrawer] レイヤ移植実行中...');
      final migratedLayer = await sourceLayer.migrateToGeoPackage(
        targetGeoPackage,
        moveLayer: true, // 移動モード
      );

      if (migratedLayer != null) {
        // 移植成功
        AppLogger.debug('[LayerDrawer] レイヤ移植成功: ${migratedLayer.name}');

        // UI更新
        triggerMapRefresh();
        setStateCallback(() {});

        // 移植されたレイヤを選択状態にする
        GlobalConfig.instance.selectedLayerNode = migratedLayer;

        // 成功メッセージを表示
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '「${sourceLayer.name}」を「${targetGeoPackage.name}」に移植しました',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // 移植失敗
        AppLogger.debug('[LayerDrawer] レイヤ移植失敗');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('レイヤ移植に失敗しました'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[LayerDrawer] レイヤドロップ処理エラー: $e');
      AppLogger.debug('スタックトレース: $stack');

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('レイヤ移植中にエラーが発生しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// レイヤ新規作成ダイアログ
class _NewLayerDialog extends StatefulWidget {
  @override
  _NewLayerDialogState createState() => _NewLayerDialogState();
}

class _NewLayerDialogState extends State<_NewLayerDialog> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  GeometryType _geomType = GeometryType.point;
  bool _isUserInput = false; // ユーザーが手動で入力したかを追跡

  @override
  void initState() {
    super.initState();
    // 初期状態ではデフォルト名を設定
    _controller = TextEditingController(text: _geomType.defaultLayerName);
    _focusNode = FocusNode();
    
    // フォーカス取得時に全選択するためのリスナーを追加
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _selectAllText();
      }
    });
    
    // 初期表示時に全選択
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectAllText();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// テキストを全選択する
  void _selectAllText() {
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  /// レイヤ名を取得（空欄の場合はデフォルト名を返す）
  String _getLayerName() {
    final input = _controller.text.trim();
    return input.isEmpty ? _geomType.defaultLayerName : input;
  }

  /// ダイアログを閉じてレイヤ作成を実行
  void _createLayer() {
    Navigator.pop(context, {
      'name': _getLayerName(),
      'geomType': _geomType.value,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新規レイヤ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'レイヤ名',
              hintText: _geomType.defaultLayerName, // プレースホルダとしてデフォルト名を表示
            ),
            onTap: () {
              // タップ時にも全選択を実行
              _selectAllText();
            },
            onChanged: (value) {
              // ユーザーが入力した場合のフラグを立てる
              // ただし、デフォルト名と同じ場合はユーザー入力とみなさない
              _isUserInput = value.isNotEmpty && value != _geomType.defaultLayerName;
            },
            onSubmitted: (value) {
              // Enterキーが押された場合、常に作成処理を実行
              _createLayer();
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<GeometryType>(
            initialValue: _geomType,
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
              if (v != null) {
                setState(() {
                  _geomType = v;
                  // ユーザーが手動入力していない場合は、デフォルト名を更新
                  if (!_isUserInput) {
                    _controller.text = _geomType.defaultLayerName;
                    // テキストを全選択状態にする
                    _selectAllText();
                  }
                });
              }
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
          onPressed: _createLayer,
          child: const Text('作成'),
        ),
      ],
    );
  }
}
