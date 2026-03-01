import 'dart:io';
import 'base_converter.dart';
import '../services/import_export/import_export_service.dart';
import 'writers/geojson_writer.dart';
import 'writers/csv_writer.dart';
import 'writers/kml_writer.dart';
import 'writers/shapefile_writer.dart';

/// フィーチャエクスポート用コンバーター
class FeatureExportConverter
    extends BaseConverter<FeatureConversionParams, String> {
  final FileFormat exportFormat;
  final String outputPath;
  final bool convertToPointCloud;

  FeatureExportConverter({
    required this.exportFormat,
    required this.outputPath,
    this.convertToPointCloud = true,
  });

  @override
  Future<bool> validate(FeatureConversionParams input) async {
    try {
      if (input.features.isEmpty) {
        return false;
      }

      final outputDir = Directory(File(outputPath).parent.path);

      if (!await outputDir.exists()) {
        return false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  Future<ConversionResult> convert(FeatureConversionParams input) async {
    try {
      notifyProgress(0.1, 'Validating features...');

      final featuresToExport =
          input.selectedFeatureIds != null
              ? input.features.where((feature) {
                final id = feature['id'] as int?;
                return id != null && input.selectedFeatureIds!.contains(id);
              }).toList()
              : input.features;

      if (featuresToExport.isEmpty) {
        return ConversionResult.error('No features selected for export');
      }

      notifyProgress(0.6, 'Converting to ${exportFormat.value} format...');

      switch (exportFormat) {
        case FileFormat.geojson:
          return await GeoJsonWriter().write(
            featuresToExport,
            outputPath,
            notifyProgress,
          );
        case FileFormat.csv:
          return await CsvWriter().write(
            featuresToExport,
            outputPath,
            notifyProgress,
          );
        case FileFormat.kml:
          return await KmlWriter().write(
            featuresToExport,
            outputPath,
            notifyProgress,
          );
        case FileFormat.shapefile:
          return await ShapefileWriter(
            convertToPointCloud: convertToPointCloud,
          ).write(featuresToExport, outputPath, notifyProgress);
        default:
          return ConversionResult.error(
            'Unsupported export format: ${exportFormat.value}',
          );
      }
    } catch (e) {
      return ConversionResult.error('Feature export failed: $e');
    }
  }
}

/// フィーチャ変換・処理用コンバーター
class FeatureTransformConverter
    extends BaseConverter<FeatureConversionParams, List<Map<String, dynamic>>> {
  final String Function(Map<String, dynamic>) transformFunction;

  FeatureTransformConverter({required this.transformFunction});

  @override
  Future<ConversionResult> convert(FeatureConversionParams input) async {
    try {
      notifyProgress(0.4, 'Transforming features...');

      final transformedFeatures = <Map<String, dynamic>>[];

      for (int i = 0; i < input.features.length; i++) {
        try {
          final feature = input.features[i];

          final progress = 0.4 + (0.5 * (i / input.features.length));
          notifyProgress(
            progress,
            'Transforming feature ${i + 1}/${input.features.length}...',
          );

          final transformedFeature = Map<String, dynamic>.from(feature);
          final transformResult = transformFunction(transformedFeature);

          if (transformResult.isNotEmpty) {
            transformedFeature['transformed'] = transformResult;
          }

          transformedFeatures.add(transformedFeature);
        } catch (e) {
          transformedFeatures.add(input.features[i]);
        }
      }

      return ConversionResult.success(
        data: transformedFeatures,
        metadata: {
          'originalCount': input.features.length,
          'transformedCount': transformedFeatures.length,
        },
      );
    } catch (e) {
      return ConversionResult.error('Feature transformation failed: $e');
    }
  }
}

/// フィーチャバリデーションコンバーター
class FeatureValidationConverter
    extends BaseConverter<List<Map<String, dynamic>>, Map<String, dynamic>> {
  @override
  Future<ConversionResult> convert(List<Map<String, dynamic>> input) async {
    try {
      notifyProgress(0.4, 'Validating features...');

      final validationResults = {
        'totalFeatures': input.length,
        'validFeatures': 0,
        'invalidFeatures': 0,
        'errors': <Map<String, dynamic>>[],
      };

      for (int i = 0; i < input.length; i++) {
        try {
          final feature = input[i];
          final progress = 0.4 + (0.5 * (i / input.length));
          notifyProgress(
            progress,
            'Validating feature ${i + 1}/${input.length}...',
          );

          final isValid = _validateFeature(feature);
          if (isValid) {
            validationResults['validFeatures'] =
                (validationResults['validFeatures'] as int) + 1;
          } else {
            validationResults['invalidFeatures'] =
                (validationResults['invalidFeatures'] as int) + 1;
            (validationResults['errors'] as List).add({
              'featureIndex': i,
              'featureId': feature['id'],
              'error': 'Invalid feature structure',
            });
          }
        } catch (e) {
          validationResults['invalidFeatures'] =
              (validationResults['invalidFeatures'] as int) + 1;
          (validationResults['errors'] as List).add({
            'featureIndex': i,
            'error': e.toString(),
          });
        }
      }

      return ConversionResult.success(
        data: validationResults,
        metadata: {
          'validationCompleted': true,
          'successRate':
              (validationResults['validFeatures'] as int) / input.length,
        },
      );
    } catch (e) {
      return ConversionResult.error('Feature validation failed: $e');
    }
  }

  bool _validateFeature(Map<String, dynamic> feature) {
    if (!feature.containsKey('id')) return false;
    if (!feature.containsKey('geometry')) return false;

    final geometry = feature['geometry'] as Map<String, dynamic>?;
    if (geometry == null) return false;
    if (!geometry.containsKey('type')) return false;
    if (!geometry.containsKey('coordinates')) return false;

    return true;
  }
}
