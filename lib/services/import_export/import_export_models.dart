// K-MAPS: Import/Export Models
// ファイル形式定義とインポート/エクスポート結果クラス
import '../../../models/nodes/layer_node.dart';

/// ファイル形式の種類
enum FileFormat {
  shapefile,
  geojson,
  kml,
  csv,
  gpx,
  unknown;

  /// 各形式の表示名を取得
  String get value {
    switch (this) {
      case FileFormat.shapefile:
        return 'Shapefile';
      case FileFormat.geojson:
        return 'GeoJSON';
      case FileFormat.kml:
        return 'KML';
      case FileFormat.csv:
        return 'CSV';
      case FileFormat.gpx:
        return 'GPX';
      case FileFormat.unknown:
        return 'Unknown';
    }
  }

  /// ファイル拡張子から形式を判定
  static FileFormat fromExtension(String extension) {
    switch (extension.toLowerCase()) {
      case '.shp':
        return FileFormat.shapefile;
      case '.geojson':
      case '.json':
        return FileFormat.geojson;
      case '.kml':
        return FileFormat.kml;
      case '.csv':
        return FileFormat.csv;
      case '.gpx':
        return FileFormat.gpx;
      default:
        return FileFormat.unknown;
    }
  }

  /// 読み込み対応の判定
  bool get isImportSupported {
    switch (this) {
      case FileFormat.shapefile:
        return true;
      case FileFormat.geojson:
        return true;
      case FileFormat.kml:
      case FileFormat.csv:
      case FileFormat.gpx:
        return false; // 将来実装予定
      case FileFormat.unknown:
        return false;
    }
  }

  /// エクスポート対応の判定
  bool get isExportSupported {
    switch (this) {
      case FileFormat.shapefile:
        return true;
      case FileFormat.geojson:
        return true;
      case FileFormat.kml:
        return true;
      case FileFormat.csv:
        return true;
      case FileFormat.gpx:
        return false; // 将来実装予定
      case FileFormat.unknown:
        return false;
    }
  }

  /// 形式に対応する拡張子を取得
  String get extension {
    switch (this) {
      case FileFormat.shapefile:
        return '.shp';
      case FileFormat.geojson:
        return '.geojson';
      case FileFormat.kml:
        return '.kml';
      case FileFormat.csv:
        return '.csv';
      case FileFormat.gpx:
        return '.gpx';
      case FileFormat.unknown:
        return '';
    }
  }
}

/// Import/Export結果の情報
class ImportExportResult {
  final bool success;
  final String? errorMessage;
  final LayerNode? createdLayer;
  final Map<String, dynamic>? metadata;

  ImportExportResult({
    required this.success,
    this.errorMessage,
    this.createdLayer,
    this.metadata,
  });

  factory ImportExportResult.success({
    LayerNode? createdLayer,
    Map<String, dynamic>? metadata,
  }) {
    return ImportExportResult(
      success: true,
      createdLayer: createdLayer,
      metadata: metadata,
    );
  }

  factory ImportExportResult.error(String message) {
    return ImportExportResult(success: false, errorMessage: message);
  }
}

