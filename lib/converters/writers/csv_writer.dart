import 'dart:io';
import '../base_converter.dart';

/// CSV形式のフィーチャ書き出しクラス
class CsvWriter {
  Future<ConversionResult> write(
    List<Map<String, dynamic>> features,
    String outputPath,
    void Function(double, String) notifyProgress,
  ) async {
    if (features.isEmpty) {
      return ConversionResult.error('No features to export');
    }

    final csvLines = <String>[];

    final headers = <String>{'id', 'geometry_type'};
    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      headers.addAll(metadata.keys.cast<String>());
    }
    csvLines.add(headers.join(','));

    for (final feature in features) {
      final row = <String>[];
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};

      for (final header in headers) {
        String value;
        switch (header) {
          case 'id':
            value = (feature['id'] ?? '').toString();
            break;
          case 'geometry_type':
            value = _getGeometryType(feature['geometry']).toString();
            break;
          default:
            value = (metadata[header] ?? '').toString();
            break;
        }
        if (value.contains(',') ||
            value.contains('"') ||
            value.contains('\n')) {
          value = '"${value.replaceAll('"', '""')}"';
        }
        row.add(value);
      }
      csvLines.add(row.join(','));
    }

    final exportData = csvLines.join('\n');

    notifyProgress(0.8, 'Writing file...');
    final file = File(outputPath);
    await file.writeAsString(exportData);

    return ConversionResult.success(
      data: outputPath,
      metadata: {
        'exportFormat': 'CSV',
        'featureCount': features.length,
        'outputPath': outputPath,
      },
    );
  }

  String _getGeometryType(Map<String, dynamic>? geometry) {
    if (geometry == null) return 'Unknown';
    return geometry['type']?.toString() ?? 'Unknown';
  }
}
