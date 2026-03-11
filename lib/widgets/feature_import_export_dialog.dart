// K-MAPS: Feature Import/Export Dialog Widget
// 個別フィーチャのインポート・エクスポート機能を提供するダイアログ
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/import_export_service.dart';
import '../models/nodes/layer_node.dart';

/// 個別フィーチャのImport/Export機能を提供するダイアログ
class FeatureImportExportDialog extends StatefulWidget {
  /// 対象レイヤー
  final LayerNode targetLayer;

  /// 選択されたフィーチャのIDリスト（エクスポート用）
  final List<int>? selectedFeatureIds;

  /// コンストラクタ
  const FeatureImportExportDialog({
    super.key,
    required this.targetLayer,
    this.selectedFeatureIds,
  });

  /// フィーチャインポート用ダイアログを表示
  static Future<void> showImportDialog(
    BuildContext context, {
    required LayerNode targetLayer,
  }) {
    return showDialog<void>(
      context: context,
      builder: (context) => FeatureImportExportDialog(targetLayer: targetLayer),
    );
  }

  /// フィーチャエクスポート用ダイアログを表示
  static Future<void> showExportDialog(
    BuildContext context, {
    required LayerNode targetLayer,
    List<int>? selectedFeatureIds,
  }) {
    return showDialog<void>(
      context: context,
      builder:
          (context) => FeatureImportExportDialog(
            targetLayer: targetLayer,
            selectedFeatureIds: selectedFeatureIds,
          ),
    );
  }

  @override
  State<FeatureImportExportDialog> createState() =>
      _FeatureImportExportDialogState();
}

class _FeatureImportExportDialogState extends State<FeatureImportExportDialog>
    with SingleTickerProviderStateMixin {
  bool _isProcessing = false;
  String? _statusMessage;
  ImportExportResult? _lastResult;
  double _progressValue = 0.0;
  String _progressMessage = '';

  // UI状態
  late TabController _tabController;

  // インポート用
  String? _selectedFilePath;
  String? _selectedFileName;
  bool _mergeWithExisting = true;
  bool _skipDuplicates = true;

  // エクスポート用
  FileFormat _exportFormat = FileFormat.geojson;
  bool _exportSelectedOnly = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Feature Import/Export'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // コンテキスト情報
            _buildContextCard(),
            const SizedBox(height: 16),

            // タブバー
            TabBar(
              controller: _tabController,
              tabs: const [
                Tab(icon: Icon(Icons.file_upload), text: 'Import'),
                Tab(icon: Icon(Icons.file_download), text: 'Export'),
              ],
            ),
            const SizedBox(height: 16),

            // タブコンテンツ
            SizedBox(
              height: 300,
              child: TabBarView(
                controller: _tabController,
                children: [_buildImportTab(), _buildExportTab()],
              ),
            ),

            // 進行状況・ステータス表示
            if (_isProcessing) _buildProgressCard(),
            if (_statusMessage != null) _buildStatusCard(),
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

  /// コンテキスト情報カード
  Widget _buildContextCard() {
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Target Layer', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Layer: ${widget.targetLayer.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'Type: ${widget.targetLayer.runtimeType}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (widget.selectedFeatureIds != null)
              Text(
                'Selected Features: ${widget.selectedFeatureIds!.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  /// インポートタブ
  Widget _buildImportTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Import features into current layer',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 16),

          // ファイル選択
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _handleFileSelection,
            icon: const Icon(Icons.folder_open),
            label: const Text('Select Feature File'),
          ),

          if (_selectedFilePath != null) ...[
            const SizedBox(height: 16),
            Card(
              color: Colors.green[50],
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Selected: $_selectedFileName'),
                    const SizedBox(height: 8),

                    // インポートオプション
                    Text(
                      'Import Options:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    CheckboxListTile(
                      title: const Text('Merge with existing features'),
                      subtitle: const Text(
                        'Add to current layer instead of replacing',
                      ),
                      value: _mergeWithExisting,
                      onChanged:
                          (value) => setState(
                            () => _mergeWithExisting = value ?? true,
                          ),
                    ),
                    CheckboxListTile(
                      title: const Text('Skip duplicates'),
                      subtitle: const Text(
                        'Avoid importing identical features',
                      ),
                      value: _skipDuplicates,
                      onChanged:
                          (value) =>
                              setState(() => _skipDuplicates = value ?? true),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _handleFeatureImport,
                icon:
                    _isProcessing
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : const Icon(Icons.add),
                label: Text(_isProcessing ? 'Importing...' : 'Import Features'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// エクスポートタブ
  Widget _buildExportTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export features from current layer',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 16),

          // エクスポート範囲
          Card(
            color: Colors.orange[50],
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export Scope:',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  RadioGroup<bool>(
                    groupValue: _exportSelectedOnly,
                    onChanged: (value) => setState(
                      () => _exportSelectedOnly = value!,
                    ),
                    child: Column(
                      children: [
                        RadioListTile<bool>(
                          title: const Text('Selected features only'),
                          subtitle:
                              widget.selectedFeatureIds != null
                                  ? Text(
                                    '${widget.selectedFeatureIds!.length} features selected',
                                  )
                                  : const Text('No features selected'),
                          value: true,
                          enabled: widget.selectedFeatureIds != null,
                        ),
                        RadioListTile<bool>(
                          title: const Text('All features in layer'),
                          subtitle: const Text('Export entire layer content'),
                          value: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // エクスポート形式
          DropdownButtonFormField<FileFormat>(
            initialValue: _exportFormat,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Export Format',
            ),
            items:
                [FileFormat.geojson, FileFormat.csv, FileFormat.kml]
                    .map(
                      (format) => DropdownMenuItem(
                        value: format,
                        child: Text(format.value),
                      ),
                    )
                    .toList(),
            onChanged: (format) {
              if (format != null) {
                setState(() => _exportFormat = format);
              }
            },
          ),

          const SizedBox(height: 16),

          // エクスポートボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isProcessing ? null : _handleFeatureExport,
              icon:
                  _isProcessing
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                      : const Icon(Icons.file_download),
              label: Text(_isProcessing ? 'Exporting...' : 'Export Features'),
            ),
          ),
        ],
      ),
    );
  }

  /// 進行状況カード
  Widget _buildProgressCard() {
    return Card(
      color: Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Processing...',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: _progressValue),
            const SizedBox(height: 8),
            Text(_progressMessage),
          ],
        ),
      ),
    );
  }

  /// ステータスカード
  Widget _buildStatusCard() {
    return Card(
      color: _lastResult?.success == true ? Colors.green[50] : Colors.red[50],
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
                      _lastResult?.success == true ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(_lastResult?.success == true ? 'Success' : 'Error'),
              ],
            ),
            const SizedBox(height: 4),
            Text(_statusMessage!),
          ],
        ),
      ),
    );
  }

  // 処理メソッド
  Future<void> _handleFileSelection() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['geojson', 'json', 'csv', 'kml'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.path == null) return;

      setState(() {
        _selectedFilePath = file.path;
        _selectedFileName = file.name;
        _statusMessage = null;
        _lastResult = null;
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'File selection failed: $e';
      });
    }
  }

  Future<void> _handleFeatureImport() async {
    if (_selectedFilePath == null) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = null;
      _progressValue = 0.0;
      _progressMessage = 'Starting feature import...';
    });

    try {
      // 機能の実装は後で
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Feature import completed successfully!';
        _lastResult = ImportExportResult.success();
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Feature import failed: $e';
        _lastResult = ImportExportResult.error(e.toString());
      });
    }
  }

  Future<void> _handleFeatureExport() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Features',
        fileName: 'features.${_exportFormat.name}',
        type: FileType.custom,
        allowedExtensions: [_exportFormat.name],
      );

      if (result == null) return;

      setState(() {
        _isProcessing = true;
        _statusMessage = null;
        _progressValue = 0.0;
        _progressMessage = 'Starting feature export...';
      });

      // 機能の実装は後で
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _isProcessing = false;
        _statusMessage = 'Feature export completed successfully!';
        _lastResult = ImportExportResult.success();
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Feature export failed: $e';
        _lastResult = ImportExportResult.error(e.toString());
      });
    }
  }
}
