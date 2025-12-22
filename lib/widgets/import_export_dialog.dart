// K-MAPS: Import/Export Dialog Widget (DEPRECATED)
// ファイルのインポート・エクスポート機能を提供するダイアログ
//
// ⚠️ DEPRECATED: このダイアログは非推奨です
// 代わりに以下を使用してください:
// - LayerImportExportDialog: レイヤー全体の操作用
// - FeatureImportExportDialog: 個別フィーチャの操作用
import 'dart:io';
import 'package:k_maps/utils/app_logger.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import '../services/import_export_service.dart';
import '../models/nodes/layer_tree_node.dart';
import '../models/nodes/layer_node.dart';
import '../utils/global_config.dart';

/// Import/Export機能を提供するダイアログ
class ImportExportDialog extends StatefulWidget {
  /// 現在選択されているレイヤー（インポート先の特定に使用）
  final LayerTreeNode? currentLayer;

  /// コンストラクタ
  const ImportExportDialog({super.key, this.currentLayer});

  /// ダイアログを表示するヘルパーメソッド
  static Future<void> show(
    BuildContext context, {
    LayerTreeNode? currentLayer,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => ImportExportDialog(currentLayer: currentLayer),
    );
  }

  @override
  State<ImportExportDialog> createState() => _ImportExportDialogState();
}

class _ImportExportDialogState extends State<ImportExportDialog> {
  final ImportExportService _importExportService = ImportExportService();
  bool _isProcessing = false;
  String? _statusMessage;
  ImportExportResult? _lastResult;
  double _progressValue = 0.0;
  String _progressMessage = '';

  // ファイル情報
  String? _selectedFilePath;
  String? _selectedFileName;
  int? _selectedFileSize;

  // ドラッグ&ドロップ状態
  bool _isDragging = false;

  // インポート設定オプション
  bool _showImportOptions = false;
  bool _createNewGeoPackage = false;
  int _maxFeaturesToImport = 50; // デフォルトで50個まで

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import/Export'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 現在のレイヤー情報
            Card(
              color: Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Layer Context',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.currentLayer != null
                          ? 'Layer: ${widget.currentLayer!.name} (${widget.currentLayer!.nodeType})'
                          : 'No layer selected',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // サポートされている形式
            Text(
              'Supported Import Formats:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children:
                  _importExportService
                      .getSupportedImportExtensions()
                      .map(
                        (ext) => Chip(
                          label: Text(ext),
                          backgroundColor: Colors.green[100],
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 16),

            // ドラッグ&ドロップエリア
            DropTarget(
              onDragDone: _handleDrop,
              onDragEntered: (_) => setState(() => _isDragging = true),
              onDragExited: (_) => setState(() => _isDragging = false),
              child: Container(
                width: double.infinity,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _isDragging ? Colors.blue : Colors.grey[400]!,
                    width: _isDragging ? 2 : 1,
                    style: BorderStyle.solid,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  color: _isDragging ? Colors.blue[50] : Colors.grey[50],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      size: 40,
                      color: _isDragging ? Colors.blue : Colors.grey[600],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isDragging ? 'Drop file here' : 'Drag & Drop file here',
                      style: TextStyle(
                        color: _isDragging ? Colors.blue : Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'or',
                      style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ファイル選択ボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _handleFileSelection,
                icon: const Icon(Icons.folder_open),
                label: const Text('Select File'),
              ),
            ),
            const SizedBox(height: 8),

            // 選択されたファイル情報
            if (_selectedFilePath != null) ...[
              Card(
                color: Colors.blue[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selected File:',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Name: $_selectedFileName',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_selectedFileSize != null)
                        Text(
                          'Size: ${(_selectedFileSize! / 1024).toStringAsFixed(1)} KB',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // インポート設定オプション
            if (_selectedFilePath != null) ...[
              Card(
                color: Colors.grey[50],
                child: ExpansionTile(
                  leading: const Icon(Icons.settings),
                  title: const Text('Import Options'),
                  initiallyExpanded: _showImportOptions,
                  onExpansionChanged:
                      (expanded) =>
                          setState(() => _showImportOptions = expanded),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 最大フィーチャ数
                          Row(
                            children: [
                              const Text('Max Features: '),
                              Expanded(
                                child: Slider(
                                  value: _maxFeaturesToImport.toDouble(),
                                  min: 10,
                                  max: 100,
                                  divisions: 9,
                                  label: _maxFeaturesToImport.toString(),
                                  onChanged:
                                      (value) => setState(
                                        () =>
                                            _maxFeaturesToImport =
                                                value.toInt(),
                                      ),
                                ),
                              ),
                              Text('$_maxFeaturesToImport'),
                            ],
                          ),

                          // 新しいGeoPackage作成オプション
                          CheckboxListTile(
                            title: const Text('Create new GeoPackage'),
                            subtitle: const Text(
                              'Create a separate .gpkg file for this import',
                            ),
                            value: _createNewGeoPackage,
                            onChanged:
                                (value) => setState(
                                  () => _createNewGeoPackage = value ?? false,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],

            // インポートボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    (_isProcessing || _selectedFilePath == null)
                        ? null
                        : _handleImport,
                icon:
                    _isProcessing
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.file_upload),
                label: Text(_isProcessing ? 'Processing...' : 'Import File'),
              ),
            ),

            // 進行状況表示
            if (_isProcessing) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.orange[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Import Progress',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: _progressValue,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).primaryColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _progressMessage,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${(_progressValue * 100).toInt()}% completed',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),

            // エクスポートボタン
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed:
                    widget.currentLayer != null && !_isProcessing
                        ? _handleExport
                        : null,
                icon: const Icon(Icons.file_download),
                label: const Text('Export Layer as Point Cloud Shapefile'),
              ),
            ),
            const SizedBox(height: 16),

            // ステータス表示
            if (_statusMessage != null) ...[
              Card(
                color:
                    _lastResult?.success == true
                        ? Colors.green[50]
                        : Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _lastResult?.success == true
                                ? Icons.check_circle
                                : Icons.error,
                            color:
                                _lastResult?.success == true
                                    ? Colors.green
                                    : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _lastResult?.success == true ? 'Success' : 'Error',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _statusMessage!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (_lastResult?.metadata != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Details:',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        ...(_lastResult!.metadata!.entries.map(
                          (e) => Text(
                            '• ${e.key}: ${e.value}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  /// ファイル選択処理
  Future<void> _handleFileSelection() async {
    try {
      // ファイル選択ダイアログを表示
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            _importExportService
                .getSupportedImportExtensions()
                .map((ext) => ext.substring(1)) // "."を除去
                .toList(),
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return; // キャンセルされた場合
      }

      final filePath = result.files.first.path;
      final file = result.files.first;

      if (filePath == null) {
        setState(() {
          _statusMessage = 'Invalid file path';
        });
        return;
      }

      // ファイル情報を取得
      // final fileInfo = File(filePath);

      setState(() {
        _selectedFilePath = filePath;
        _selectedFileName = file.name;
        _selectedFileSize = file.size;
        _statusMessage = null;
        _lastResult = null;
      });

      AppLogger.debug(
        '[ImportExportDialog] Selected file: $filePath (${file.size} bytes)',
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'File selection failed: $e';
      });
    }
  }

  /// 進行状況を更新
  void _updateProgress(double value, String message) {
    if (mounted) {
      setState(() {
        _progressValue = value;
        _progressMessage = message;
      });
    }
  }

  /// ドラッグ&ドロップ処理
  Future<void> _handleDrop(DropDoneDetails details) async {
    setState(() => _isDragging = false);

    if (details.files.isEmpty) return;

    final droppedFile = details.files.first;
    final filePath = droppedFile.path;

    AppLogger.debug('[ImportExportDialog] Dropped file: $filePath');

    // ファイル拡張子をチェック
    final supportedExtensions =
        _importExportService.getSupportedImportExtensions();
    final fileExtension = '.${filePath.split('.').last.toLowerCase()}';

    if (!supportedExtensions.contains(fileExtension)) {
      setState(() {
        _statusMessage = 'Unsupported file format: $fileExtension';
      });
      return;
    }

    try {
      // ファイル情報を取得
      final fileStat = await File(filePath).stat();

      setState(() {
        _selectedFilePath = filePath;
        _selectedFileName = filePath.split('/').last.split('\\').last;
        _selectedFileSize = fileStat.size;
        _statusMessage = null;
        _lastResult = null;
      });

      AppLogger.debug(
        '[ImportExportDialog] File dropped and selected: $_selectedFileName (${fileStat.size} bytes)',
      );
    } catch (e) {
      setState(() {
        _statusMessage = 'Failed to process dropped file: $e';
      });
    }
  }

  /// ファイルインポート処理
  Future<void> _handleImport() async {
    if (_selectedFilePath == null) {
      setState(() {
        _statusMessage = 'No file selected';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
      _lastResult = null;
      _progressValue = 0.0;
      _progressMessage = 'Starting import...';
    });

    try {
      // 進行状況の段階的更新
      _updateProgress(0.1, 'Validating file...');
      await Future.delayed(const Duration(milliseconds: 200));

      _updateProgress(0.2, 'Reading file structure...');
      await Future.delayed(const Duration(milliseconds: 300));

      _updateProgress(0.4, 'Analyzing geometry data...');
      await Future.delayed(const Duration(milliseconds: 400));

      _updateProgress(0.6, 'Creating layer...');

      // インポート実行
      final importResult = await _importExportService
          .importFileFromCurrentLayer(_selectedFilePath!, widget.currentLayer);

      _updateProgress(0.8, 'Finalizing import...');
      await Future.delayed(const Duration(milliseconds: 300));

      _updateProgress(1.0, 'Import completed!');

      setState(() {
        _isProcessing = false;
        _lastResult = importResult;
        _statusMessage =
            importResult.success
                ? 'Import completed successfully!'
                : importResult.errorMessage ?? 'Import failed';
      });

      // インポート成功時はマップのフィーチャ更新をトリガー
      if (importResult.success) {
        _triggerMapRefresh();

        // 少し遅延させて再度更新（確実性のため）
        Future.delayed(Duration(milliseconds: 500), () {
          _triggerMapRefresh();
        });
      }

      // 成功時はダイアログを自動で閉じる（オプション）
      if (importResult.success && mounted) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[ImportExportDialog] Import error: $e');
      AppLogger.debug('Stack trace: $stack');

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Import failed: $e';
        _lastResult = ImportExportResult.error(e.toString());
      });
    }
  }

  /// マップページのフィーチャ更新をトリガー
  void _triggerMapRefresh() {
    try {
      // GlobalConfigを通じてマップページの更新をトリガー（型安全）
      final mapState = GlobalConfig.instance.mapState;
      if (mapState != null && mapState.mounted) {
        mapState.refreshFeatures();
        AppLogger.debug('[ImportExportDialog] マップフィーチャ更新をトリガーしました');
      } else {
        AppLogger.debug('[ImportExportDialog] マップページが見つからないか、マウントされていません');
      }
    } catch (e) {
      AppLogger.debug('[ImportExportDialog] マップ更新エラー: $e');
    }
  }

  /// レイヤーエクスポート処理
  Future<void> _handleExport() async {
    if (widget.currentLayer == null) {
      setState(() {
        _statusMessage = 'No layer selected for export';
      });
      return;
    }

    try {
      // 保存先ファイル選択
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Layer as Shapefile',
        fileName: '${widget.currentLayer!.name}_pointcloud.shp',
        type: FileType.custom,
        allowedExtensions: ['shp'],
      );

      if (result == null) {
        return; // キャンセルされた場合
      }

      setState(() {
        _isProcessing = true;
        _statusMessage = null;
        _lastResult = null;
        _progressValue = 0.0;
        _progressMessage = 'Starting export...';
      });

      // 進行状況の段階的更新
      _updateProgress(0.1, 'Analyzing layer data...');
      await Future.delayed(const Duration(milliseconds: 200));

      _updateProgress(0.3, 'Converting features to point cloud...');
      await Future.delayed(const Duration(milliseconds: 300));

      _updateProgress(0.5, 'Creating Shapefile...');

      // LayerTreeNodeからLayerNodeへのキャスト確認
      if (widget.currentLayer is! LayerNode) {
        setState(() {
          _statusMessage = 'Selected item is not a layer that can be exported';
        });
        return;
      }

      // エクスポート実行
      final exportResult = await _importExportService.exportLayer(
        widget.currentLayer! as LayerNode,
        result,
        FileFormat.shapefile,
      );

      _updateProgress(0.8, 'Finalizing export...');
      await Future.delayed(const Duration(milliseconds: 300));

      _updateProgress(1.0, 'Export completed!');

      setState(() {
        _isProcessing = false;
        _lastResult = exportResult;
        _statusMessage =
            exportResult.success
                ? 'Export completed successfully!'
                : exportResult.errorMessage ?? 'Export failed';
      });

      // 成功時はダイアログを自動で閉じる（オプション）
      if (exportResult.success && mounted) {
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) {
          Navigator.of(context).pop();
        }
      }
    } catch (e, stack) {
      AppLogger.debug('[ImportExportDialog] Export error: $e');
      AppLogger.debug('Stack trace: $stack');

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Export failed: $e';
        _lastResult = ImportExportResult.error(e.toString());
      });
    }
  }
}

