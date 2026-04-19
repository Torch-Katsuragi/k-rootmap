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

/// KML形式のフィーチャ書き出しクラス
class KmlWriter {
  Future<ConversionResult> write(
    List<Map<String, dynamic>> features,
    String outputPath,
    void Function(double, String) notifyProgress,
  ) async {
    final kmlElements = <String>[];

    for (final feature in features) {
      final metadata = feature['metadata'] as Map<String, dynamic>? ?? {};
      final name = metadata['name'] ?? 'Feature ${feature['id']}';
      final description = metadata['description'] ?? '';

      kmlElements.add(_createKMLPlacemark(feature, name, description));
    }

    final exportData = '''<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Exported Features</name>
    ${kmlElements.join('\n    ')}
  </Document>
</kml>''';

    notifyProgress(0.8, 'Writing file...');
    final file = File(outputPath);
    await file.writeAsString(exportData);

    return ConversionResult.success(
      data: outputPath,
      metadata: {
        'exportFormat': 'KML',
        'featureCount': features.length,
        'outputPath': outputPath,
      },
    );
  }

  String _createKMLPlacemark(
    Map<String, dynamic> feature,
    String name,
    String description,
  ) {
    return '''<Placemark>
      <name>$name</name>
      <description>$description</description>
      <!-- Geometry elements would be added here -->
    </Placemark>''';
  }
}
