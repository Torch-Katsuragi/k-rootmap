// lib/tools/pen_tool.dart
// ペンツール（レイヤ描画）
import 'map_tool.dart';
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../utils/global_drawing_state.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import 'package:latlong2/latlong.dart';
import 'pan_tool.dart';
import 'select_tool.dart';
import 'dart:async';
import '../interfaces/map_state_interface.dart';
import '../providers/tool_providers.dart';
import '../providers/selection_providers.dart';
import '../providers/ui_state_providers.dart';
import '../providers/drawing_provider.dart';

/// ペンツール（レイヤ描画）
class PenTool extends MapTool {
  final Ref _ref;
  PenTool(this._ref);

  /// てのひらツールのグローバルインスタンス（2本指パン・回転用）
  PanTool get panTool => _ref.read(panToolProvider);

  /// グローバル描画状態への参照
  GlobalDrawingState get drawingState => _ref.read(drawingStateProvider);

  @override
  String get name => 'Pen';

  @override
  IconData get icon => Icons.edit;

  /// UI更新デバウンス用タイマー
  Timer? _uiUpdateTimer;

  bool _isDrawing = false;
  int _pointerCount = 0;

  /// プレビュー用の点座標（外部参照用getter）
  /// グローバル描画状態から取得
  LatLng? get pointPreview => drawingState.pointPreview;

  /// 線の描画点列（グローバル描画状態から取得）
  List<LatLng> get drawingLine => drawingState.drawingLine;

  /// ポリゴンの描画点列（グローバル描画状態から取得）
  List<LatLng> get drawingPolygon => drawingState.drawingPolygon;

  /// タップイベント
  @override
  void onTap(TapUpDetails details, IMapState mapState) {
    AppLogger.debug('[DEBUG] PenTool.onTap: タップイベント開始');

    // フロートボタン押下時は消しゴム動作
    if (_ref.read(isFabActiveProvider)) {
      final latlng = mapState.offsetToLatLng(details.localPosition);
      AppLogger.debug(
        '[DEBUG] PenTool.onTap: eraser mode - selecting feature at $latlng',
      );

      SelectTool.selectFeatureAtLatLng(tapLatLng: latlng, mapState: mapState, ref: _ref);
      AppLogger.debug(
        '[DEBUG] PenTool.onTap: selected features count: ${_ref.read(selectedFeaturesProvider).length}',
      );

      if (_ref.read(selectedFeaturesProvider).isNotEmpty) {
        _disposeSelectedFeatures(mapState);
      } else {
        AppLogger.debug('[DEBUG] PenTool.onTap: no features selected for deletion');
      }
      return;
    }

    // 通常は描画
    final selected = _ref.read(selectedLayerNodeProvider);
    if (selected == null) {
      AppLogger.debug('[DEBUG] PenTool.onTap: 選択されたレイヤーがありません');
      return;
    }

    if (!selected.isVisibleRecursive()) {
      AppLogger.debug('[DEBUG] PenTool.onTap: レイヤーが不可視のため処理中止');
      // 警告ポップアップ
      ScaffoldMessenger.of(
        mapState.context,
      ).showSnackBar(const SnackBar(content: Text('このレイヤは不可視のため編集できません')));
      return;
    }

    final latlng = mapState.offsetToLatLng(details.localPosition);
    AppLogger.debug('[DEBUG] PenTool.onTap: 座標取得完了 $latlng');

    if (selected is PointLayerNode) {
      AppLogger.debug('[DEBUG] PenTool.onTap: ポイントレイヤー処理');
      PointFeatureNode.createIn(selected, latlng, '', '').then((_) {
        // フィーチャー作成完了後にUI更新
        mapState.refreshFeatures();
      });
      mapState.setState(() {});
    } else if (selected is LineLayerNode) {
      AppLogger.debug('[DEBUG] PenTool.onTap: ラインレイヤー処理');

      drawingState.addLinePoint(latlng, null);
      mapState.setState(() {});
    } else if (selected is PolygonLayerNode) {
      AppLogger.debug(
        '[DEBUG] PenTool.onTap: ポリゴンレイヤー処理開始 - 現在の点数: ${drawingPolygon.length}',
      );

      // タップ時のポリゴン描画
      try {
        drawingState.addPolygonPoint(latlng, null);

        // デバウンス機能：50ms後にUI更新を実行
        _uiUpdateTimer?.cancel();
        _uiUpdateTimer = Timer(Duration(milliseconds: 50), () {
          mapState.setState(() {});
        });

        AppLogger.debug(
          '[DEBUG] PenTool.onTap: ポリゴン点追加完了 - 新しい点数: ${drawingPolygon.length}',
        );
      } catch (e) {
        AppLogger.debug('[ERROR] PenTool.onTap: ポリゴン点追加エラー: $e');
      }
    }

    AppLogger.debug('[DEBUG] PenTool.onTap: タップイベント完了');
  }

  /// スケール開始イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleStart(ScaleStartDetails details, IMapState mapState) {
    // 中ボタンドラッグ中は何もしない（意図しない描画を防ぐ）
    if (panTool.isMiddleButtonDragging) return;

    final selected = _ref.read(selectedLayerNodeProvider);

    if (_pointerCount == 2) {
      //2本指を離すとき高確率で残った方の指でdetails.pointerCount=1としてonscalestartが呼ばれるので、その場合は一回スキップ(0にするとupdateとendで何もしなくなる)
      _pointerCount = 0;
      return;
    }
    _pointerCount = details.pointerCount;

    // 2本指の場合は、選択レイヤーに関係なくパン操作を許可
    if (_pointerCount == 2) {
      panTool.onScaleStart(details, mapState);
      return;
    }

    // 1本指の場合のみレイヤー選択チェック
    if (selected == null || !selected.isVisibleRecursive()) {
      if (selected != null && !selected.isVisibleRecursive()) {
        ScaffoldMessenger.of(
          mapState.context,
        ).showSnackBar(const SnackBar(content: Text('このレイヤは不可視のため編集できません')));
      }
      return;
    }
    if (_pointerCount == 1) {
      if (_ref.read(isFabActiveProvider)) {
        return;
      }
      // Pointerバッファがあれば最初に反映
      if (pointerBuffer.isNotEmpty) {
        if (selected is LineLayerNode) {
          drawingState.clearLine();
          for (final offset in pointerBuffer) {
            final latlng = mapState.offsetToLatLng(offset);
            drawingState.addLinePoint(latlng, null);
          }
        } else if (selected is PolygonLayerNode) {
          drawingState.clearPolygon();
          for (final offset in pointerBuffer) {
            final latlng = mapState.offsetToLatLng(offset);
            drawingState.addPolygonPoint(latlng, null);
          }
        }
        clearPointerBuffer();
      }
      final latlng = mapState.offsetToLatLng(details.localFocalPoint);
      if (selected is PointLayerNode) {
        drawingState.setPointPreview(latlng);
        mapState.setState(() {});
      } else if (selected is LineLayerNode) {
        if (drawingLine.isEmpty) {
          drawingState.addLinePoint(latlng, null);
          mapState.setState(() {});
        }
        _isDrawing = true;
      } else if (selected is PolygonLayerNode) {
        if (drawingPolygon.isEmpty) {
          drawingState.addPolygonPoint(latlng, null);
          mapState.setState(() {});
        }
        _isDrawing = true;
      }
    }
  }

  /// スケール更新イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleUpdate(ScaleUpdateDetails details, IMapState mapState) {
    // 中ボタンドラッグ中は何もしない（意図しない描画を防ぐ）
    if (panTool.isMiddleButtonDragging) return;

    final selected = _ref.read(selectedLayerNodeProvider);

    // 2本指の場合は、選択レイヤーに関係なくパン操作を許可
    if (_pointerCount == 2) {
      panTool.onScaleUpdate(details, mapState);
      // 2本指終了時に1本指状態で呼ばれるので、_pointercount=2のままにしておく(スキップフラグとして利用)
      return;
    }

    // 1本指の場合のみレイヤー選択チェック
    if (selected == null || !selected.isVisibleRecursive()) return;
    if (_pointerCount == 1) {
      // フロートボタン押下時は消しゴム動作
      if (_ref.read(isFabActiveProvider)) {
        final latlng = mapState.offsetToLatLng(details.localFocalPoint);
        AppLogger.debug(
          '[DEBUG] PenTool.onScaleUpdate: eraser mode - selecting feature at $latlng',
        );

        SelectTool.selectFeatureAtLatLng(tapLatLng: latlng, mapState: mapState, ref: _ref);
        AppLogger.debug(
          '[DEBUG] PenTool.onScaleUpdate: selected features count: ${_ref.read(selectedFeaturesProvider).length}',
        );

        if (_ref.read(selectedFeaturesProvider).isNotEmpty) {
          _disposeSelectedFeatures(mapState);
        } else {
          AppLogger.debug(
            '[DEBUG] PenTool.onScaleUpdate: no features selected for deletion',
          );
        }
        return;
      }
      final latlng = mapState.offsetToLatLng(details.localFocalPoint);
      if (selected is PointLayerNode) {
        drawingState.setPointPreview(latlng);
        mapState.setState(() {});
      } else if (selected is LineLayerNode && _isDrawing) {
        drawingState.addLinePoint(latlng, null);
        mapState.setState(() {});
      } else if (selected is PolygonLayerNode && _isDrawing) {
        drawingState.addPolygonPoint(latlng, null);
        mapState.setState(() {});
      }
    }
  }

  /// スケール終了イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleEnd(ScaleEndDetails details, IMapState mapState) {
    // 中ボタンドラッグ中は何もしない（意図しない描画を防ぐ）
    if (panTool.isMiddleButtonDragging) return;

    final selected = _ref.read(selectedLayerNodeProvider);

    // 2本指の場合は、選択レイヤーに関係なくパン操作を許可
    if (_pointerCount == 2) {
      panTool.onScaleEnd(details, mapState);
      // _pointerCount = 0;
      return;
    }

    // 1本指の場合のみレイヤー選択チェック
    if (selected == null || !selected.isVisibleRecursive()) return;
    if (_pointerCount == 1) {
      if (selected is PointLayerNode && pointPreview != null) {
        PointFeatureNode.createIn(
          selected,
          pointPreview!,
          'FreeHandPoint',
          '',
        ).then((_) {
          // フィーチャー作成完了後にUI更新
          mapState.refreshFeatures();
        });
        drawingState.setPointPreview(null);
        mapState.setState(() {});
      } else if (selected is LineLayerNode && drawingLine.length >= 2) {
        LineFeatureNode.createIn(
          selected,
          List<LatLng>.from(drawingLine),
          'FreeHandLine',
          '',
        ).then((_) {
          // フィーチャー作成完了後にUI更新
          mapState.refreshFeatures();
        });
        drawingState.clearLine();
        _isDrawing = false;
        mapState.setState(() {});
      } else if (selected is PolygonLayerNode && drawingPolygon.length >= 3) {
        final closed = mapState.closeRing(drawingPolygon);
        PolygonFeatureNode.createIn(
          selected,
          List<List<LatLng>>.from([closed]),
          'FreeHandPolygon',
          '',
        ).then((_) {
          // フィーチャー作成完了後にUI更新
          mapState.refreshFeatures();
        });
        drawingState.clearPolygon();
        _isDrawing = false;
        mapState.setState(() {});
      }
    }
    _pointerCount = 0;
  }

  /// リソースのクリーンアップ
  void cleanUp() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
  }

  /// 選択されたフィーチャーを削除（GlobalConfig統一処理を使用）
  void _disposeSelectedFeatures(IMapState mapState) async {
    AppLogger.debug('[DEBUG] PenTool._disposeSelectedFeatures: using SelectedFeatures provider deletion');
    
    await _ref.read(selectedFeaturesProvider.notifier).disposeSelectedFeatures();
  }

  /// マウスホイールスクロールイベント（ズーム機能）
  /// PanToolの統一処理を呼び出し
  @override
  void onPointerSignal(PointerEvent event, IMapState mapState) {
    if (event is PointerScrollEvent) {
      panTool.handleMouseWheelZoom(event, mapState);
    }
  }

  @override
  void onMiddleButtonDown(PointerDownEvent event, IMapState mapState) {
    panTool.onMiddleButtonDown(event, mapState);
  }

  @override
  void onMiddleButtonMove(PointerMoveEvent event, IMapState mapState) {
    panTool.onMiddleButtonMove(event, mapState);
  }

  @override
  void onMiddleButtonUp(PointerUpEvent event, IMapState mapState) {
    panTool.onMiddleButtonUp(event, mapState);
  }
}
