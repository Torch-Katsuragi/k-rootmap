import 'base_converter.dart';

/// フィーチャインポート用コンバーター
class FeatureImportConverter
    extends BaseConverter<FeatureConversionParams, List<Map<String, dynamic>>> {
  @override
  Future<bool> validate(FeatureConversionParams input) async {
    try {
      if (input.targetLayer == null) {
        return false;
      }

      if (input.features.isEmpty) {
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
      notifyProgress(0.4, 'Processing features...');

      final successfulImports = <Map<String, dynamic>>[];
      final errors = <String>[];

      final maxFeatures =
          input.options['maxFeatures'] as int? ?? input.features.length;
      final featuresToProcess = input.features.take(maxFeatures).toList();

      for (int i = 0; i < featuresToProcess.length; i++) {
        try {
          final feature = featuresToProcess[i];

          final progress = 0.4 + (0.5 * (i / featuresToProcess.length));
          notifyProgress(
            progress,
            'Importing feature ${i + 1}/${featuresToProcess.length}...',
          );

          await input.targetLayer!.geoPackageFile.addFeatureWithAttributes(
            input.targetLayer!.layerName,
            feature['geometry'],
            feature['metadata'] ?? {},
          );

          successfulImports.add(feature);
        } catch (e) {
          errors.add('Feature ${i + 1}: $e');
        }
      }

      final metadata = {
        'totalFeatures': featuresToProcess.length,
        'successfulImports': successfulImports.length,
        'errors': errors.length,
        'targetLayer': input.targetLayer!.layerName,
      };

      if (errors.isNotEmpty) {
        metadata['errorDetails'] = errors;
      }

      return ConversionResult.success(
        data: successfulImports,
        metadata: metadata,
      );
    } catch (e) {
      return ConversionResult.error('Feature import failed: $e');
    }
  }
}
