// K-MAPS: Base Exporter
// エクスポーターの抽象基底クラス
import '../import_export_models.dart';
import '../../../models/nodes/layer_node.dart';

/// エクスポーターの抽象基底クラス
abstract class BaseExporter {
  /// サポートするファイル形式
  FileFormat get format;

  /// レイヤをファイルにエクスポート
  /// [layer] エクスポート対象のレイヤ
  /// [outputPath] 出力先ファイルパス
  Future<ImportExportResult> export(LayerNode layer, String outputPath);
}

