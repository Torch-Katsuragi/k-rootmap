// K-MAPS: Base Importer
// インポーターの抽象基底クラス
import '../import_export_models.dart';
import '../../../models/nodes/geopackage_node.dart';

/// インポーターの抽象基底クラス
abstract class BaseImporter {
  /// この形式のファイルを処理できるか判定
  bool canHandle(String extension);

  /// サポートするファイル形式
  FileFormat get format;

  /// ファイルをインポート
  /// [filePath] インポート対象のファイルパス
  /// [targetGeoPackage] インポート先のGeoPackageNode
  /// [layerName] 作成するレイヤ名（省略時はファイル名から自動生成）
  Future<ImportExportResult> import(
    String filePath,
    GeoPackageNode targetGeoPackage, {
    String? layerName,
  });
}

