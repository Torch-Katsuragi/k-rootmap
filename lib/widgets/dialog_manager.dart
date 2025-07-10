// K-MAPS: Dialog Manager
// ダイアログとコンバーターを統合管理するマネージャー
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:file_picker/file_picker.dart';
import '../converters/base_converter.dart';
import '../converters/layer_converter.dart';
import '../converters/feature_converter.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/folder_node.dart';
import '../models/nodes/geopackage_node.dart';
import '../models/nodes/layer_node.dart';
import '../models/nodes/feature_node.dart';
import '../models/nodes/photo_node.dart';
import '../services/import_export_service.dart';

/// ダイアログ管理機能を提供するマネージャークラス
class DialogManager {
  static final DialogManager _instance = DialogManager._internal();
  factory DialogManager() => _instance;
  DialogManager._internal();

  /// クロスプラットフォーム対応のファイル選択
  /// file_selectorがWindowsで失敗した場合、file_pickerにフォールバック
  static Future<String?> _selectFileForOpen() async {
    try {
      // まずfile_selectorを試行
      const XTypeGroup geoTypeGroup = XTypeGroup(
        label: 'Geographic Files',
        extensions: <String>['shp', 'geojson', 'json', 'kml', 'csv', 'gpx'],
      );

      final XFile? file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[geoTypeGroup],
      );

      return file?.path;
    } catch (e) {
      print(
        '[DialogManager] file_selector failed, falling back to file_picker: $e',
      );

      // file_selectorが失敗した場合、file_pickerにフォールバック
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['shp', 'geojson', 'json', 'kml', 'csv', 'gpx'],
          allowMultiple: false,
        );

        return result?.files.first.path;
      } catch (fallbackError) {
        print('[DialogManager] file_picker also failed: $fallbackError');
        return null;
      }
    }
  }

  /// クロスプラットフォーム対応のファイル保存場所選択
  /// file_selectorがWindowsで失敗した場合、file_pickerにフォールバック
  static Future<String?> _selectLocationForSave(
    String suggestedName,
    String extension,
  ) async {
    try {
      // まずfile_selectorを試行
      final FileSaveLocation? result = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
        ],
      );

      return result?.path;
    } catch (e) {
      print(
        '[DialogManager] file_selector save failed, falling back to file_picker: $e',
      );

      // file_selectorが失敗した場合、file_pickerにフォールバック
      try {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Save File',
          fileName: suggestedName,
          type: FileType.custom,
          allowedExtensions: [extension],
        );

        return result;
      } catch (fallbackError) {
        print('[DialogManager] file_picker save also failed: $fallbackError');
        return null;
      }
    }
  }

  /// レイヤーインポートダイアログを表示
  static Future<void> showLayerImportDialog(
    BuildContext context, {
    LayerTreeNode? targetLayer,
  }) async {
    final result = await showDialog<ConversionResult>(
      context: context,
      builder: (context) => _LayerImportDialog(targetLayer: targetLayer),
    );

    if (result != null && result.success) {
      _showSuccessSnackBar(context, 'Layer imported successfully!');
    } else if (result != null && !result.success) {
      _showErrorSnackBar(context, result.errorMessage ?? 'Import failed');
    }
  }

  /// レイヤーエクスポートダイアログを表示
  static Future<void> showLayerExportDialog(
    BuildContext context, {
    required LayerNode sourceLayer,
  }) async {
    final result = await showDialog<ConversionResult>(
      context: context,
      builder: (context) => _LayerExportDialog(sourceLayer: sourceLayer),
    );

    if (result != null && result.success) {
      _showSuccessSnackBar(context, 'Layer exported successfully!');
    } else if (result != null && !result.success) {
      _showErrorSnackBar(context, result.errorMessage ?? 'Export failed');
    }
  }

  /// フィーチャインポートダイアログを表示
  static Future<void> showFeatureImportDialog(
    BuildContext context, {
    required LayerNode targetLayer,
    List<Map<String, dynamic>>? features,
  }) async {
    final result = await showDialog<ConversionResult>(
      context: context,
      builder:
          (context) => _FeatureImportDialog(
            targetLayer: targetLayer,
            features: features,
          ),
    );

    if (result != null && result.success) {
      final metadata = result.metadata;
      final count = metadata?['successfulImports'] ?? 0;
      _showSuccessSnackBar(context, '$count features imported successfully!');
    } else if (result != null && !result.success) {
      _showErrorSnackBar(context, result.errorMessage ?? 'Import failed');
    }
  }

  /// フィーチャエクスポートダイアログを表示
  static Future<void> showFeatureExportDialog(
    BuildContext context, {
    required List<Map<String, dynamic>> features,
    List<int>? selectedFeatureIds,
  }) async {
    final result = await showDialog<ConversionResult>(
      context: context,
      builder:
          (context) => _FeatureExportDialog(
            features: features,
            selectedFeatureIds: selectedFeatureIds,
          ),
    );

    if (result != null && result.success) {
      final metadata = result.metadata;
      final count = metadata?['featureCount'] ?? 0;
      _showSuccessSnackBar(context, '$count features exported successfully!');
    } else if (result != null && !result.success) {
      _showErrorSnackBar(context, result.errorMessage ?? 'Export failed');
    }
  }

  /// 成功メッセージを表示
  static void _showSuccessSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// エラーメッセージを表示
  static void _showErrorSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  /// ファイル形式から拡張子を取得
  static String _getFileExtension(FileFormat format) {
    switch (format) {
      case FileFormat.shapefile:
        return 'shp';
      case FileFormat.geojson:
        return 'geojson';
      case FileFormat.kml:
        return 'kml';
      case FileFormat.csv:
        return 'csv';
      case FileFormat.gpx:
        return 'gpx';
      default:
        return 'dat';
    }
  }
}

/// レイヤーインポート用ダイアログ
class _LayerImportDialog extends StatefulWidget {
  final LayerTreeNode? targetLayer;

  const _LayerImportDialog({this.targetLayer});

  @override
  State<_LayerImportDialog> createState() => _LayerImportDialogState();
}

class _LayerImportDialogState extends State<_LayerImportDialog> {
  final LayerImportConverter _converter = LayerImportConverter();
  bool _isProcessing = false;
  double _progress = 0.0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    _converter.setProgressCallback(_onProgressUpdate);
  }

  void _onProgressUpdate(double progress, String message) {
    if (mounted) {
      setState(() {
        _progress = progress;
        _progressMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Layer'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.targetLayer != null) ...[
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text('Target: ${widget.targetLayer!.name}'),
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (_isProcessing) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_progressMessage),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _handleImport,
                icon: const Icon(Icons.file_upload),
                label: const Text('Select File to Import'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _handleImport() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // ファイル選択ダイアログを表示
      final filePath = await DialogManager._selectFileForOpen();

      if (filePath == null) {
        // ユーザーがキャンセルした場合
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final fileExtension = filePath.split('.').last.toLowerCase();
      final sourceFormat = _getFileFormatFromExtension(fileExtension);

      final params = FileConversionParams(
        filePath: filePath,
        sourceFormat: sourceFormat,
        targetFormat: FileFormat.shapefile,
      );

      final result = await _converter.execute(params);

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(ConversionResult.error(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  /// ファイル拡張子からFileFormatを取得
  FileFormat _getFileFormatFromExtension(String extension) {
    switch (extension) {
      case 'shp':
        return FileFormat.shapefile;
      case 'geojson':
      case 'json':
        return FileFormat.geojson;
      case 'kml':
        return FileFormat.kml;
      case 'csv':
        return FileFormat.csv;
      case 'gpx':
        return FileFormat.gpx;
      default:
        return FileFormat.unknown;
    }
  }
}

/// レイヤーエクスポート用ダイアログ
class _LayerExportDialog extends StatefulWidget {
  final LayerNode sourceLayer;

  const _LayerExportDialog({required this.sourceLayer});

  @override
  State<_LayerExportDialog> createState() => _LayerExportDialogState();
}

class _LayerExportDialogState extends State<_LayerExportDialog> {
  final LayerExportConverter _converter = LayerExportConverter();
  FileFormat _selectedFormat = FileFormat.shapefile;
  bool _isProcessing = false;
  double _progress = 0.0;
  String _progressMessage = '';

  @override
  void initState() {
    super.initState();
    _converter.setProgressCallback(_onProgressUpdate);
  }

  void _onProgressUpdate(double progress, String message) {
    if (mounted) {
      setState(() {
        _progress = progress;
        _progressMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Export Layer'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text('Source: ${widget.sourceLayer.layerName}'),
              ),
            ),
            const SizedBox(height: 16),

            if (_isProcessing) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_progressMessage),
            ] else ...[
              DropdownButtonFormField<FileFormat>(
                value: _selectedFormat,
                decoration: const InputDecoration(
                  labelText: 'Export Format',
                  border: OutlineInputBorder(),
                ),
                items:
                    [
                          FileFormat.shapefile,
                          FileFormat.geojson,
                          FileFormat.kml,
                          FileFormat.csv,
                        ]
                        .map(
                          (format) => DropdownMenuItem(
                            value: format,
                            child: Text(format.value.toUpperCase()),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _selectedFormat = value!),
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _handleExport,
                icon: const Icon(Icons.file_download),
                label: const Text('Export Layer'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _handleExport() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // ファイル保存先選択ダイアログを表示
      final String suggestedName =
          '${widget.sourceLayer.layerName}_export.${DialogManager._getFileExtension(_selectedFormat)}';

      final outputPath = await DialogManager._selectLocationForSave(
        suggestedName,
        DialogManager._getFileExtension(_selectedFormat),
      );

      if (outputPath == null) {
        // ユーザーがキャンセルした場合
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final params = LayerConversionParams(
        sourceLayer: widget.sourceLayer,
        outputPath: outputPath,
        targetFormat: _selectedFormat,
        options: {}, // convertToPointCloudオプションを削除
      );

      final result_conversion = await _converter.execute(params);

      if (mounted) {
        Navigator.of(context).pop(result_conversion);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(ConversionResult.error(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}

/// フィーチャインポート用ダイアログ
class _FeatureImportDialog extends StatefulWidget {
  final LayerNode targetLayer;
  final List<Map<String, dynamic>>? features;

  const _FeatureImportDialog({required this.targetLayer, this.features});

  @override
  State<_FeatureImportDialog> createState() => _FeatureImportDialogState();
}

class _FeatureImportDialogState extends State<_FeatureImportDialog> {
  final FeatureImportConverter _converter = FeatureImportConverter();
  bool _isProcessing = false;
  double _progress = 0.0;
  String _progressMessage = '';
  int _maxFeatures = 50;

  @override
  void initState() {
    super.initState();
    _converter.setProgressCallback(_onProgressUpdate);
  }

  void _onProgressUpdate(double progress, String message) {
    if (mounted) {
      setState(() {
        _progress = progress;
        _progressMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import Features'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text('Target: ${widget.targetLayer.layerName}'),
              ),
            ),
            const SizedBox(height: 16),

            if (_isProcessing) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_progressMessage),
            ] else ...[
              TextFormField(
                initialValue: _maxFeatures.toString(),
                decoration: const InputDecoration(
                  labelText: 'Max Features',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => _maxFeatures = int.tryParse(value) ?? 50,
              ),
              const SizedBox(height: 12),

              ElevatedButton.icon(
                onPressed: _handleImport,
                icon: const Icon(Icons.upload),
                label: const Text('Import Features'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _handleImport() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      final features = widget.features ?? <Map<String, dynamic>>[];

      final params = FeatureConversionParams(
        targetLayer: widget.targetLayer,
        features: features,
        options: {'maxFeatures': _maxFeatures},
      );

      final result = await _converter.execute(params);

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(ConversionResult.error(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}

/// フィーチャエクスポート用ダイアログ
class _FeatureExportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> features;
  final List<int>? selectedFeatureIds;

  const _FeatureExportDialog({required this.features, this.selectedFeatureIds});

  @override
  State<_FeatureExportDialog> createState() => _FeatureExportDialogState();
}

class _FeatureExportDialogState extends State<_FeatureExportDialog> {
  bool _isProcessing = false;
  double _progress = 0.0;
  String _progressMessage = '';
  FileFormat _selectedFormat = FileFormat.geojson;
  bool _convertToPointCloud = false; // Point cloudオプションを追加

  void _onProgressUpdate(double progress, String message) {
    if (mounted) {
      setState(() {
        _progress = progress;
        _progressMessage = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final featureCount =
        widget.selectedFeatureIds?.length ?? widget.features.length;

    return AlertDialog(
      title: const Text('Export Features'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Text('Features to export: $featureCount'),
              ),
            ),
            const SizedBox(height: 16),

            if (_isProcessing) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(_progressMessage),
            ] else ...[
              DropdownButtonFormField<FileFormat>(
                value: _selectedFormat,
                decoration: const InputDecoration(
                  labelText: 'Export Format',
                  border: OutlineInputBorder(),
                ),
                items:
                    [
                          FileFormat.geojson,
                          FileFormat.csv,
                          FileFormat.kml,
                          FileFormat.shapefile,
                        ]
                        .map(
                          (format) => DropdownMenuItem(
                            value: format,
                            child: Text(format.value.toUpperCase()),
                          ),
                        )
                        .toList(),
                onChanged: (value) => setState(() => _selectedFormat = value!),
              ),
              const SizedBox(height: 12),

              // Point cloudオプション（Shapefileの場合のみ表示）
              if (_selectedFormat == FileFormat.shapefile) ...[
                CheckboxListTile(
                  title: const Text('Convert to Point Cloud'),
                  subtitle: const Text(
                    'Convert polygons/lines to individual points',
                  ),
                  value: _convertToPointCloud,
                  onChanged:
                      (value) =>
                          setState(() => _convertToPointCloud = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 12),
              ],

              ElevatedButton.icon(
                onPressed: _handleExport,
                icon: const Icon(Icons.file_download),
                label: const Text('Export Features'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Future<void> _handleExport() async {
    setState(() {
      _isProcessing = true;
    });

    try {
      // ファイル保存先選択ダイアログを表示
      final featureCount =
          widget.selectedFeatureIds?.length ?? widget.features.length;
      final String suggestedName =
          'features_${featureCount}_export.${DialogManager._getFileExtension(_selectedFormat)}';

      final outputPath = await DialogManager._selectLocationForSave(
        suggestedName,
        DialogManager._getFileExtension(_selectedFormat),
      );

      if (outputPath == null) {
        // ユーザーがキャンセルした場合
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final converter = FeatureExportConverter(
        exportFormat: _selectedFormat,
        outputPath: outputPath,
        convertToPointCloud:
            _selectedFormat == FileFormat.shapefile
                ? _convertToPointCloud
                : false, // Shapefileの場合のみオプションを適用
      );

      converter.setProgressCallback(_onProgressUpdate);

      final params = FeatureConversionParams(
        targetLayer: null, // エクスポート処理では不要
        features: widget.features,
        selectedFeatureIds: widget.selectedFeatureIds,
      );

      final result_conversion = await converter.execute(params);

      if (mounted) {
        Navigator.of(context).pop(result_conversion);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(ConversionResult.error(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }
}
