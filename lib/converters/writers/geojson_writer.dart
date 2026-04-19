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
