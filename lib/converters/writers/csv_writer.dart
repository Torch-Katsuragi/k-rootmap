// Copyright (C) 2024-2026 Torch-Katsuragi
//
// This program is free software; you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation; either version 2 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program; if not, write to the Free Software Foundation, Inc.,
// 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
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
