/// K-MAPS: LayerDrawer用インポート/エクスポート機能
library;

import 'package:flutter/material.dart';
import '../../services/import_export_service.dart';

/// インポート/エクスポート機能を提供するミックスイン
mixin LayerDrawerImportExport {
  /// ImportExportServiceのインスタンス
  ImportExportService get importExportService => ImportExportService();

  /// インポート成功メッセージを表示
  void showImportSuccess(BuildContext context, ImportExportResult result) {
    String message = 'Import completed successfully!';
    if (result.metadata != null) {
      final metadata = result.metadata!;
      if (metadata['layerName'] != null) {
        message += '\nLayer: ${metadata['layerName']}';
      }
      if (metadata['featureCount'] != null) {
        message += '\nFeatures: ${metadata['featureCount']}';
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// インポートエラーメッセージを表示
  void showImportError(BuildContext context, String errorMessage) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Import failed: $errorMessage'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }
}
