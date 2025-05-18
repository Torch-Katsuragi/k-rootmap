/// プロジェクト全体のグローバル変数・設定を管理する最小クラス
/// 例: プロジェクトのルートディレクトリパスなど
import '../models/layer_tree_node.dart';

class GlobalConfig {
  // シングルトンインスタンス
  static final GlobalConfig instance = GlobalConfig._internal();
  factory GlobalConfig() => instance;
  GlobalConfig._internal();

  /// プロジェクトのルートディレクトリパス
  String? projectRootDir;

  /// レイヤツリーのルートノード
  LayerTreeNode? folderTree;

  /// 現在選択中のLayerNode（地図編集・描画用）
  LayerNode? selectedLayerNode;

  // 必要に応じて他のグローバル設定も追加
  // String? userName;
  // int? someGlobalFlag;
}
