/// K-MAPS: LayerDrawer用各種タイル描画ロジック
library;

import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import 'package:latlong2/latlong.dart';
import '../../models/nodes/layer_tree_node.dart';
import '../../models/nodes/folder_node.dart';
import '../../models/nodes/geopackage_node.dart';
import '../../models/nodes/layer_node.dart';
import '../../models/nodes/feature_node.dart';
import '../../models/nodes/photo_node.dart';
import '../../models/geometry_type.dart';
import '../../utils/global_config.dart';
import '../../utils/feature_calc_utils.dart';
import '../../services/import_export_service.dart';
import '../../services/geometry_conversion_service.dart';
import '../../widgets/dialog_manager.dart';
import '../../widgets/geometry_conversion_dialogs.dart';

import 'layer_drawer_extensions.dart';

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

  /// フォルダタイルを構築
  Widget buildFolderTile(
    BuildContext context,
    FolderNode node,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: _buildIconWithVisibility(node),
      title: Text(node.name),
      onTap: onTap,
    );
  }

  /// 写真タイルを構築（位置情報付き画像ファイル）
  Widget buildPhotoTile(
    BuildContext context,
    PhotoNode node, {
    VoidCallback? onRename,
  }) {
    return ListTile(
      leading: _buildIconWithVisibility(node),
      title: Text(node.name),
      onTap: () {
        // PhotoNode選択処理（地図上でハイライト表示）
        GlobalConfig.instance.selectedFeatures.clear();
        GlobalConfig.instance.selectedFeatures.add(node);

        // 地図の中心を写真の位置に移動
        if (onJumpTo != null) {
          onJumpTo!(node.location);
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
                // 削除されるPhotoNodeが選択されている場合は選択状態をクリア
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
        itemBuilder:
            (context) => [
              const PopupMenuItem(value: 'rename', child: Text('名前の変更')),
              const PopupMenuItem(value: 'delete', child: Text('削除')),
            ],
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

    // レイヤタイルの内容を構築
    final layerTileContent = ListTile(
      // GeoPackageノード配下のレイヤはインデントして階層感を出す
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: GestureDetector(
        onTap: () {
          node.visible = !node.visible;
          // フィーチャ表示を更新
          if (GlobalConfig.instance.mapState != null) {
            GlobalConfig.instance.mapState.refreshFeatures();
          }
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
        setStateCallback(() {});
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
          }
        },
        itemBuilder:
            (context) => [
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
              const PopupMenuItem(value: 'delete', child: Text('削除')),
            ],
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
                Icon(node.baseIcon, color: node.baseIconColor),
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
              if (GlobalConfig.instance.mapState != null) {
                GlobalConfig.instance.mapState.setState(() {});
              }
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
        // フィーチャ表示を更新
        if (GlobalConfig.instance.mapState != null) {
          GlobalConfig.instance.mapState.refreshFeatures();
        }
        setStateCallback(() {});
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
  }

  /// 写真の詳細情報を表示するダイアログ

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
        
        if (GlobalConfig.instance.mapState != null) {
          GlobalConfig.instance.mapState.refreshFeatures();
        }

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
        if (GlobalConfig.instance.mapState != null) {
          GlobalConfig.instance.mapState.setState(() {});
        }

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
