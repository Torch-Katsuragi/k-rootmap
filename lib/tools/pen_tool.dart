// lib/tools/pen_tool.dart
// ペンツール（レイヤ描画）
import 'package:flutter/widgets.dart';
import 'map_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../utils/global_config.dart';
import '../models/layer_tree_node.dart';
import 'package:latlong2/latlong.dart';
import 'pan_tool.dart'; // てのひらツールを利用
import 'select_tool.dart';
import 'dart:async'; // デバウンス機能用

/// ペンツール（レイヤ描画）
class PenTool extends MapTool {
  /// てのひらツールのグローバルインスタンス（2本指パン・回転用）
  PanTool get panTool => GlobalConfig.instance.panTool;

  @override
  String get name => 'Pen';

  @override
  IconData get icon => Icons.edit;

  final List<Offset> _currentPath = [];

  /// 線の描画点列
  final List<LatLng> drawingLine = [];

  /// ポリゴンの描画点列
  final List<LatLng> drawingPolygon = [];

  /// ポリゴンプレビュー用キャッシュ（パフォーマンス最適化）
  List<LatLng>? _cachedPolygonPreview;
  int _lastPolygonUpdateCount = -1;

  /// UI更新デバウンス用タイマー
  Timer? _uiUpdateTimer;

  Offset? _lastFingerPosition;
  bool _isDrawing = false;
  int _pointerCount = 0;
  LatLng? _pointPreview;

  /// プレビュー用の点座標（外部参照用getter）
  LatLng? get pointPreview => _pointPreview;

  /// ポリゴンプレビュー取得（キャッシュ機能付き・パフォーマンス最適化）
  List<LatLng>? getPolygonPreview(
    List<LatLng> Function(List<LatLng>) closeRing,
  ) {
    if (drawingPolygon.length < 2) return null;

    // キャッシュが有効かチェック
    if (_lastPolygonUpdateCount == drawingPolygon.length &&
        _cachedPolygonPreview != null) {
      return _cachedPolygonPreview;
    }

    // 2点の場合は線として扱い、closeRingは呼び出さない
    if (drawingPolygon.length == 2) {
      _cachedPolygonPreview = List<LatLng>.from(drawingPolygon);
      _lastPolygonUpdateCount = drawingPolygon.length;

      print(
        '[DEBUG] PenTool.getPolygonPreview: 線プレビュー - 点数: ${drawingPolygon.length}',
      );
      return _cachedPolygonPreview;
    }

    // 3点以上の場合は新しい計算を実行してキャッシュ
    _cachedPolygonPreview = closeRing(drawingPolygon);
    _lastPolygonUpdateCount = drawingPolygon.length;

    print(
      '[DEBUG] PenTool.getPolygonPreview: キャッシュ更新 - 点数: ${drawingPolygon.length}',
    );
    return _cachedPolygonPreview;
  }

  /// タップイベント
  @override
  void onTap(TapUpDetails details, dynamic mapState) {
    print('[DEBUG] PenTool.onTap: タップイベント開始');

    // フロートボタン押下時は消しゴム動作
    if (GlobalConfig.instance.isFabActive) {
      final latlng = mapState.offsetToLatLng(details.localPosition);
      print(
        '[DEBUG] PenTool.onTap: eraser mode - selecting feature at $latlng',
      );

      // フィーチャーを選択
      SelectTool.selectFeatureAtLatLng(tapLatLng: latlng, mapState: mapState);
      print(
        '[DEBUG] PenTool.onTap: selected features count: ${GlobalConfig.instance.selectedFeatures.length}',
      );

      // 選択されたフィーチャーがある場合のみ削除
      if (GlobalConfig.instance.selectedFeatures.isNotEmpty) {
        _disposeSelectedFeatures(mapState);
      } else {
        print('[DEBUG] PenTool.onTap: no features selected for deletion');
      }
      return;
    }

    // 通常は描画
    final selected = GlobalConfig.instance.selectedLayerNode;
    if (selected == null) {
      print('[DEBUG] PenTool.onTap: 選択されたレイヤーがありません');
      return;
    }

    if (!selected.isVisibleRecursive()) {
      print('[DEBUG] PenTool.onTap: レイヤーが不可視のため処理中止');
      // 警告ポップアップ
      final context = mapState.context;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('このレイヤは不可視のため編集できません')));
      return;
    }

    final latlng = mapState.offsetToLatLng(details.localPosition);
    print('[DEBUG] PenTool.onTap: 座標取得完了 $latlng');

    if (selected is PointLayerNode) {
      print('[DEBUG] PenTool.onTap: ポイントレイヤー処理');
      PointFeatureNode.createIn(selected, latlng, '', '').then((_) {
        // フィーチャー作成完了後にUI更新
        mapState.refreshFeatures();
      });
      mapState.setState(() {});
    } else if (selected is LineLayerNode) {
      print('[DEBUG] PenTool.onTap: ラインレイヤー処理');
      addDrawingLinePoint(latlng, mapState.setState);
    } else if (selected is PolygonLayerNode) {
      print(
        '[DEBUG] PenTool.onTap: ポリゴンレイヤー処理開始 - 現在の点数: ${drawingPolygon.length}',
      );

      // タップ時のポリゴン描画の最適化（UI更新頻度を抑制）
      try {
        addDrawingPolygonPointOptimized(latlng, mapState.setState);
        print(
          '[DEBUG] PenTool.onTap: ポリゴン点追加完了 - 新しい点数: ${drawingPolygon.length}',
        );
      } catch (e) {
        print('[ERROR] PenTool.onTap: ポリゴン点追加エラー: $e');
      }
    }

    print('[DEBUG] PenTool.onTap: タップイベント完了');
  }

  /// スケール開始イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleStart(ScaleStartDetails details, dynamic mapState) {
    final selected = GlobalConfig.instance.selectedLayerNode;

    if (_pointerCount == 2) {
      //2本指を離すとき高確率で残った方の指でdetails.pointerCount=1としてonscalestartが呼ばれるので、その場合は一回スキップ(0にするとupdateとendで何もしなくなる)
      _pointerCount = 0;
      return;
    }
    _pointerCount = details.pointerCount ?? 1;

    // 2本指の場合は、選択レイヤーに関係なくパン操作を許可
    if (_pointerCount == 2) {
      panTool.onScaleStart(details, mapState);
      return;
    }

    // 1本指の場合のみレイヤー選択チェック
    if (selected == null || !selected.isVisibleRecursive()) {
      if (selected != null && !selected.isVisibleRecursive()) {
        final context = mapState.context;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('このレイヤは不可視のため編集できません')));
      }
      return;
    }
    if (_pointerCount == 1) {
      if (GlobalConfig.instance.isFabActive) {
        return;
      }
      // Pointerバッファがあれば最初に反映
      if (pointerBuffer.isNotEmpty) {
        if (selected is LineLayerNode) {
          drawingLine.clear();
          for (final offset in pointerBuffer) {
            final latlng = mapState.offsetToLatLng(offset);
            addDrawingLinePoint(latlng, mapState.setState);
          }
        } else if (selected is PolygonLayerNode) {
          drawingPolygon.clear();
          for (final offset in pointerBuffer) {
            final latlng = mapState.offsetToLatLng(offset);
            addDrawingPolygonPoint(latlng, mapState.setState);
          }
        }
        clearPointerBuffer();
      }
      final latlng = mapState.offsetToLatLng(details.localFocalPoint);
      if (selected is PointLayerNode) {
        _pointPreview = latlng;
        mapState.setState(() {});
      } else if (selected is LineLayerNode) {
        if (drawingLine.isEmpty) {
          addDrawingLinePoint(latlng, mapState.setState);
        }
        _isDrawing = true;
      } else if (selected is PolygonLayerNode) {
        if (drawingPolygon.isEmpty) {
          addDrawingPolygonPoint(latlng, mapState.setState);
        }
        _isDrawing = true;
      }
    }
  }

  /// スケール更新イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleUpdate(ScaleUpdateDetails details, dynamic mapState) {
    final selected = GlobalConfig.instance.selectedLayerNode;

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
      if (GlobalConfig.instance.isFabActive) {
        final latlng = mapState.offsetToLatLng(details.localFocalPoint);
        print(
          '[DEBUG] PenTool.onScaleUpdate: eraser mode - selecting feature at $latlng',
        );

        // フィーチャーを選択
        SelectTool.selectFeatureAtLatLng(tapLatLng: latlng, mapState: mapState);
        print(
          '[DEBUG] PenTool.onScaleUpdate: selected features count: ${GlobalConfig.instance.selectedFeatures.length}',
        );

        // 選択されたフィーチャーがある場合のみ削除
        if (GlobalConfig.instance.selectedFeatures.isNotEmpty) {
          _disposeSelectedFeatures(mapState);
        } else {
          print(
            '[DEBUG] PenTool.onScaleUpdate: no features selected for deletion',
          );
        }
        return;
      }
      final latlng = mapState.offsetToLatLng(details.localFocalPoint);
      if (selected is PointLayerNode) {
        _pointPreview = latlng;
        mapState.setState(() {});
      } else if (selected is LineLayerNode && _isDrawing) {
        addDrawingLinePoint(latlng, mapState.setState);
      } else if (selected is PolygonLayerNode && _isDrawing) {
        addDrawingPolygonPoint(latlng, mapState.setState);
      }
    }
  }

  /// スケール終了イベント
  /// 1本指: ペン描画, 2本指: パンツール処理
  @override
  void onScaleEnd(ScaleEndDetails details, dynamic mapState) {
    final selected = GlobalConfig.instance.selectedLayerNode;

    // 2本指の場合は、選択レイヤーに関係なくパン操作を許可
    if (_pointerCount == 2) {
      panTool.onScaleEnd(details, mapState);
      // _pointerCount = 0;
      return;
    }

    // 1本指の場合のみレイヤー選択チェック
    if (selected == null || !selected.isVisibleRecursive()) return;
    if (_pointerCount == 1) {
      if (selected is PointLayerNode && _pointPreview != null) {
        PointFeatureNode.createIn(
          selected,
          _pointPreview!,
          'FreeHandPoint',
          '',
        ).then((_) {
          // フィーチャー作成完了後にUI更新
          mapState.refreshFeatures();
        });
        _pointPreview = null;
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
        drawingLine.clear();
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
        drawingPolygon.clear();
        _isDrawing = false;
        mapState.setState(() {});
      }
    }
    _pointerCount = 0;
  }

  /// 線の描画点を追加
  void addDrawingLinePoint(
    LatLng latlng,
    void Function(void Function()) setState,
  ) {
    setState(() {
      drawingLine.add(latlng);
    });
  }

  /// ポリゴンの描画点を追加
  void addDrawingPolygonPoint(
    LatLng latlng,
    void Function(void Function()) setState,
  ) {
    setState(() {
      drawingPolygon.add(latlng);
    });
  }

  /// ポリゴンの描画点を追加（最適化版：デバウンス機能付き）
  void addDrawingPolygonPointOptimized(
    LatLng latlng,
    void Function(void Function()) setState,
  ) {
    print('[DEBUG] addDrawingPolygonPointOptimized: 開始 - 座標: $latlng');

    // まず座標をリストに追加
    drawingPolygon.add(latlng);

    // キャッシュを無効化
    _cachedPolygonPreview = null;
    _lastPolygonUpdateCount = -1;

    print(
      '[DEBUG] addDrawingPolygonPointOptimized: 座標追加完了 - 現在の点数: ${drawingPolygon.length}',
    );

    // 既存のタイマーをキャンセル
    _uiUpdateTimer?.cancel();

    // デバウンス機能：50ms後にUI更新を実行
    _uiUpdateTimer = Timer(Duration(milliseconds: 50), () {
      try {
        setState(() {
          print('[DEBUG] addDrawingPolygonPointOptimized: デバウンス後UI更新実行');
        });
        print('[DEBUG] addDrawingPolygonPointOptimized: UI更新完了');
      } catch (e) {
        print('[ERROR] addDrawingPolygonPointOptimized: UI更新エラー: $e');
      }
    });

    print('[DEBUG] addDrawingPolygonPointOptimized: 完了');
  }

  /// 1つ取り消し
  void undo(void Function(void Function()) setState, {required bool isLine}) {
    setState(() {
      if (isLine && drawingLine.isNotEmpty) {
        drawingLine.removeLast();
      } else if (!isLine && drawingPolygon.isNotEmpty) {
        drawingPolygon.removeLast();
      }
    });
  }

  /// キャンセル（全消去）
  void cancel(void Function(void Function()) setState, {required bool isLine}) {
    setState(() {
      if (isLine) {
        drawingLine.clear();
      } else {
        drawingPolygon.clear();
      }
    });
  }

  /// リソースのクリーンアップ
  void dispose() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer = null;
    _cachedPolygonPreview = null;
  }

  /// 確定処理（属性入力ダイアログはUI側で呼ぶこと）
  void confirm({
    required LayerNode selected,
    required String name,
    required String description,
    required void Function(void Function()) setState,
    required List<LatLng> Function(List<LatLng>) closeRing,
  }) {
    if (selected is LineLayerNode && drawingLine.length >= 2) {
      LineFeatureNode.createIn(
        selected,
        List<LatLng>.from(drawingLine),
        name,
        description,
      ).then((_) {
        // フィーチャ表示を更新（mapStateが利用可能なら）
        if (GlobalConfig.instance.mapState != null) {
          GlobalConfig.instance.mapState.refreshFeatures();
        }
      });
      setState(() {
        drawingLine.clear();
      });
    } else if (selected is PolygonLayerNode && drawingPolygon.length >= 3) {
      final closed = closeRing(drawingPolygon);
      PolygonFeatureNode.createIn(
        selected,
        List<List<LatLng>>.from([closed]),
        name,
        description,
      ).then((_) {
        // フィーチャ表示を更新（mapStateが利用可能なら）
        if (GlobalConfig.instance.mapState != null) {
          GlobalConfig.instance.mapState.refreshFeatures();
        }
      });
      setState(() {
        drawingPolygon.clear();
      });
    }
  }

  /// 選択されたフィーチャーを効率的に削除（最適化・UI更新修正）
  void _disposeSelectedFeatures(dynamic mapState) async {
    final selectedFeatures = List.from(GlobalConfig.instance.selectedFeatures);
    print(
      '[DEBUG] PenTool._disposeSelectedFeatures: disposing ${selectedFeatures.length} features',
    );

    if (selectedFeatures.isEmpty) {
      print('[DEBUG] PenTool._disposeSelectedFeatures: no features to dispose');
      return;
    }

    // 即座に選択状態をクリア（UI更新優先）
    GlobalConfig.instance.selectedFeatures.clear();
    print(
      '[DEBUG] PenTool._disposeSelectedFeatures: cleared selected features',
    );

    // 即座にUI更新（選択表示を確実にクリア）
    mapState.setState(() {});
    mapState.refreshFeatures();
    print('[DEBUG] PenTool._disposeSelectedFeatures: triggered UI update');

    // 各フィーチャーを非同期で削除（並行処理）
    final disposeFutures =
        selectedFeatures.map((feature) async {
          try {
            print(
              '[DEBUG] PenTool._disposeSelectedFeatures: disposing feature ${feature.name}',
            );
            await feature.dispose();
            print(
              '[DEBUG] PenTool._disposeSelectedFeatures: disposed feature ${feature.name}',
            );
          } catch (e) {
            print(
              '[ERROR] PenTool._disposeSelectedFeatures: failed to dispose ${feature.name}: $e',
            );
          }
        }).toList();

    // バックグラウンドで削除処理完了を待機（UIには影響しない）
    Future.wait(disposeFutures)
        .then((_) {
          print(
            '[DEBUG] PenTool._disposeSelectedFeatures: all ${selectedFeatures.length} features disposed',
          );
          // 削除完了後に最終的なUI更新
          mapState.refreshFeatures();
        })
        .catchError((e) {
          print(
            '[ERROR] PenTool._disposeSelectedFeatures: error during batch disposal: $e',
          );
        });
  }
}
