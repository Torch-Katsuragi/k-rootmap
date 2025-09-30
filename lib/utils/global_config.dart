/// プロジェクト全体のグローバル変数・設定を管理する最小クラス
/// 例: プロジェクトのルートディレクトリパスなど
library;

import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/layer_node.dart';
import '../tools/map_tool.dart';
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../tools/gps_tool.dart';
import '../services/basemap_service.dart';
import 'global_drawing_state.dart';

class GlobalConfig {
  // シングルトンインスタンス
  static final GlobalConfig instance = GlobalConfig._internal();
  factory GlobalConfig() => instance;
  GlobalConfig._internal() : currentTool = PanTool();

  /// プロジェクトのルートディレクトリパス
  String? projectRootDir;

  /// レイヤツリーのルートノード
  LayerTreeNode? folderTree;

  /// 現在選択中のLayerNode（地図編集・描画用）
  LayerNode? selectedLayerNode;

  /// 地図操作ツールのグローバルインスタンス
  final PanTool panTool = PanTool();
  final PenTool penTool = PenTool();
  final SelectTool selectTool = SelectTool();
  final GpsTool gpsTool = GpsTool();

  /// 現在選択中の地図操作ツール
  MapTool currentTool;

  /// 選択中フィーチャのリスト（今後利用予定）
  /// 例: 地物IDやFeatureインスタンス等を格納
  List<dynamic> selectedFeatures = [];

  /// 地図画面のStateインスタンス（グローバル参照用）
  dynamic mapState;

  /// 左下フロートボタンの押下状態（true: 押下中, false: 通常）
  bool isFabActive = false;
  
  /// 選択されたフィーチャを削除（統一処理）
  /// pen_tool、AttributeTableなど全ての削除処理で使用
  Future<void> disposeSelectedFeatures({dynamic mapState}) async {
    final selectedFeaturesToDispose = List.from(selectedFeatures);
    print('[GlobalConfig] 削除処理開始: ${selectedFeaturesToDispose.length}個のフィーチャ');
    
    if (selectedFeaturesToDispose.isEmpty) {
      print('[GlobalConfig] 削除するフィーチャがありません');
      return;
    }
    
    // 即座に選択状態をクリア（UI更新優先）
    selectedFeatures.clear();
    print('[GlobalConfig] 選択状態をクリアしました');
    
    // 即座にUI更新（選択表示を確実にクリア）
    if (mapState != null) {
      mapState.setState(() {});
      mapState.refreshFeatures();
      print('[GlobalConfig] UI更新をトリガーしました');
    }
    
    // 各フィーチャーを非同期で削除（並行処理）
    final disposeFutures = selectedFeaturesToDispose.map((feature) async {
      try {
        print('[GlobalConfig] フィーチャ削除中: ${feature.name} (ID: ${feature.rowId})');
        await feature.dispose();
        print('[GlobalConfig] フィーチャ削除完了: ${feature.name}');
      } catch (e) {
        print('[ERROR] GlobalConfig: フィーチャ削除失敗 ${feature.name}: $e');
      }
    }).toList();
    
    // バックグラウンドで削除処理完了を待機（UIには影響しない）
    await Future.wait(disposeFutures).then((_) {
      print('[GlobalConfig] 全${selectedFeaturesToDispose.length}個のフィーチャ削除完了');
      // 削除完了後に最終的なUI更新
      if (mapState != null) {
        mapState.refreshFeatures();
      }
    }).catchError((e) {
      print('[ERROR] GlobalConfig: バッチ削除エラー: $e');
    });
  }

  /// 背景地図管理サービス
  final BaseMapService baseMapService = BaseMapService();

  /// グローバル描画状態管理
  final GlobalDrawingState drawingState = GlobalDrawingState.instance;

  /// GPS関連の設定
  String? preferredGpsSourceType; // 'internal' または 'external'
  String? selectedGnssDeviceAddress; // 外部GNSS機器のBluetoothアドレス
  String? selectedGnssDeviceName; // 外部GNSS機器の名前

  // 必要に応じて他のグローバル設定も追加
  // String? userName;
  // int? someGlobalFlag;
}

extension LayerTreeNodeUtils on LayerTreeNode {
  /// isVisibleRecursive==trueな全LayerNodeを再帰的に取得
  List<LayerNode> getVisibleLayerNodes() {
    final result = <LayerNode>[];
    void collect(LayerTreeNode node) {
      if (node is LayerNode && node.isVisibleRecursive()) {
        result.add(node);
      }
      for (final child in node.children) {
        collect(child);
      }
    }

    collect(this);
    return result;
  }
}
