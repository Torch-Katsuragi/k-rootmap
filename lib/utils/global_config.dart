/// プロジェクト全体のグローバル変数・設定を管理する最小クラス
/// 例: プロジェクトのルートディレクトリパスなど
library;

import '../models/layer_tree_node.dart';
import '../tools/map_tool.dart';
import '../tools/pan_tool.dart';
import '../tools/pen_tool.dart';
import '../tools/select_tool.dart';
import '../tools/gps_tool.dart';
import '../services/basemap_service.dart';

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

  /// 背景地図管理サービス
  final BaseMapService baseMapService = BaseMapService();

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
