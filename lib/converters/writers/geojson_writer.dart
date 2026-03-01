import 'dart:convert';
import 'dart:io';
import '../base_converter.dart';

/// GeoJSON形式のフィーチャ書き出しクラス
class GeoJsonWriter {
  Future<ConversionResult> write(
    List<Map<String, dynamic>> features,
    String outputPath,
    void Function(double, String) notifyProgress,
  ) async {
    final geojsonFeatures =
        features.map((feature) {
          return {
            'type': 'Feature',
            'properties': feature['metadata'] ?? {},
            'geometry': feature['geometry'],
          };
        }).toList();

    final geojson = {'type': 'FeatureCollection', 'features': geojsonFeatures};
    final exportData = jsonEncode(geojson);

    notifyProgress(0.8, 'Writing file...');
    final file = File(outputPath);
    await file.writeAsString(exportData);

    return ConversionResult.success(
      data: outputPath,
      metadata: {
        'exportFormat': 'GeoJSON',
        'featureCount': features.length,
        'outputPath': outputPath,
      },
    );
  }
}
